import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/glossary.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/remote/frankfurter_api.dart';
import 'package:finance_companion/data/repositories/fx_service.dart';
import 'package:finance_companion/data/repositories/glossary_repository.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/domain/learning/glossary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/fake_frankfurter.dart';
import '../../fakes/glossary_pack.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    final wall = WallClock(DateTime.utc(2026, 10, 8, 12));
    final backend = FakeBackend()
      ..assets.add({
        ...FakeBackend().assets.first,
        'id': 'world',
        'type': 'etf',
      })
      ..closes['apple'] = {
        '2025-10-08': '200',
        '2026-04-01': '150',
        '2026-10-07': '250',
      }
      ..closes['world'] = {'2025-10-08': '100', '2026-10-07': '110'};
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(wall),
        marketRepositoryProvider.overrideWithValue(
          MarketRepository(
            db,
            BackendApi('http://t', adapter: backend),
            wallClock: wall,
          ),
        ),
        fxServiceProvider.overrideWithValue(
          FxService(
            db,
            FrankfurterApi(adapter: FakeFrankfurter()),
            wallClock: wall,
          ),
        ),
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => decodePack(glossaryPackJson())),
      ],
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<GlossaryIndex> index() async {
    c.listen(glossaryIndexProvider('fr'), (_, _) {});
    return c.read(glossaryIndexProvider('fr').future);
  }

  Future<Map<String, TermProgress>> progress() async {
    c.listen(glossaryProgressProvider, (_, _) {});
    return c.read(glossaryProgressProvider.future);
  }

  /// `D: diversification=toDiscover` per letter.
  List<String> shape(GlossaryIndex i) => [
    for (final (letter, rows) in i.groups)
      '$letter: ${[for (final r in rows) '${r.term.id}=${r.status.name}'].join(', ')}',
  ];

  group('index', () {
    test('by first letter, accents aside, with each term\'s status', () async {
      await c
          .read(glossaryRepositoryProvider)
          .discover('indice', DateTime.utc(2026, 10, 1));
      await c
          .read(profileRepositoryProvider)
          .completeNode('ae.fees', at: DateTime.utc(2026, 10, 1));
      final i = await index();
      expect(i.total, 6);
      expect(shape(i), [
        'D: diversification=toDiscover',
        'E: ecart=toDiscover, etf=met',
        'I: indice=discovered',
        'R: risque-de-change=toDiscover',
        'V: volatilite=toDiscover',
      ]);
    });

    test('search ignores case and accents; filters keep or leave', () async {
      await c
          .read(glossaryRepositoryProvider)
          .discover('ecart', DateTime.utc(2026, 10, 1));
      c.read(glossarySearchProvider.notifier).setQuery('ECART');
      expect(shape(await index()), ['E: ecart=discovered']);

      c.read(glossarySearchProvider.notifier)
        ..setQuery('')
        ..setFilter(GlossaryFilter.discovered);
      expect([for (final (l, _) in (await index()).groups) l], ['E']);

      c
          .read(glossarySearchProvider.notifier)
          .setFilter(GlossaryFilter.toDiscover);
      expect(
        [for (final (l, _) in (await index()).groups) l],
        ['D', 'E', 'I', 'R', 'V'],
      );
    });
  });

  group('sheet', () {
    test('the first open discovers the term; the next does not', () async {
      c.listen(termSheetProvider('etf'), (_, _) {});
      final first = await c.read(termSheetProvider('etf').future);
      expect(first.firstOpen, isTrue);
      expect(
        [for (final t in first.related) t.id],
        ['indice', 'diversification'],
      );
      expect(first.term.forYou!.fr, 'Ce que ETF change pour toi.');
      expect((await progress()).keys, contains('etf'));

      c.invalidate(termSheetProvider('etf'));
      expect(
        (await c.read(termSheetProvider('etf').future)).firstOpen,
        isFalse,
      );
    });

    test('an unknown term is not found', () async {
      c.listen(termSheetProvider('nope'), (_, _) {});
      await expectLater(
        c.read(termSheetProvider('nope').future),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('live examples', () {
    test('the asset\'s figure next to the world ETF\'s', () async {
      final perf = await c.read(
        liveExampleProvider(LiveExample.performance, 'apple').future,
      );
      expect(
        (perf.asset.id, perf.figure, perf.world!.id, perf.worldFigure),
        ('apple', d('0.25'), 'world', d('0.1')),
      );
      expect(perf.closes, hasLength(3));
      final drop = await c.read(
        liveExampleProvider(LiveExample.drawdown, 'apple').future,
      );
      expect(drop.figure, d('-0.25'));
    });

    test('opened elsewhere: the world ETF alone', () async {
      final v = await c.read(
        liveExampleProvider(LiveExample.performance, null).future,
      );
      expect((v.asset.id, v.world), ('world', null));
    });

    test(
      'currency: the move of the asset\'s currency against the euro',
      () async {
        final v = await c.read(
          liveExampleProvider(LiveExample.currency, 'apple').future,
        );
        expect(v.figure, isNotNull);
        expect(v.world, isNull, reason: 'nothing to compare');
      },
    );
  });

  group('quiz', () {
    Future<void> play(List<String> answers) async {
      final quiz = c.read(termQuizProvider('etf').notifier);
      for (final a in answers) {
        quiz
          ..choose(a)
          ..check();
        await quiz.next();
      }
    }

    test('all right: passed, and kept', () async {
      await c
          .read(glossaryRepositoryProvider)
          .discover('etf', DateTime.utc(2026, 10, 1));
      await play(['index', 'low']);
      expect(c.read(termQuizProvider('etf')).score, 2);
      expect((await progress())['etf']!.quizPassed, isTrue);
    });

    test('one wrong: not passed; another try starts over', () async {
      await c
          .read(glossaryRepositoryProvider)
          .discover('etf', DateTime.utc(2026, 10, 1));
      await play(['index', 'high']);
      expect(c.read(termQuizProvider('etf')).score, 1);
      expect((await progress())['etf']!.quizPassed, isFalse);
      c.read(termQuizProvider('etf').notifier).retry();
      expect(c.read(termQuizProvider('etf')).index, 0);
      expect(c.read(termQuizProvider('etf')).finished, isFalse);
    });
  });
}
