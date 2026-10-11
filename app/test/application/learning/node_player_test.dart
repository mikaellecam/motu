import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/node_player.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/lesson_pack.dart';

Decimal d(String s) => Decimal.parse(s);
DateTime day(int y, int m, int dd) => DateTime.utc(y, m, dd);
void main() {
  late AppDatabase db;
  late FakeBackend backend;

  ProviderContainer container({String? worldAsset = 'world', Object? choices}) {
    final wall = WallClock(DateTime.utc(2026, 10, 8, 12));
    final c = ProviderContainer(
      // A failure surfaces as is instead of being retried.
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
        contentPackProvider(actionsEtfIsland).overrideWith(
          (ref) async =>
              decodePack(packJson(worldAsset: worldAsset, choices: choices)),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend()
      ..assets.add({...FakeBackend().assets.first, 'id': 'world'})
      ..closes['apple'] = {'2025-10-08': '200', '2026-10-07': '250'}
      ..closes['world'] = {'2025-10-08': '100', '2026-10-07': '110'};
  });
  tearDown(() => db.close());

  group('predict_reveal', () {
    test(
      'the curves start from the amount, with where they come from',
      () async {
        final view = await container().read(
          revealViewProvider('ae.apple').future,
        );
        expect(view.reveal.question.fr, 'Lequel a le plus chuté ?');
        final apple = view.curves.first;
        expect((apple.label.fr, apple.currency), ('Apple', 'USD'));
        expect(apple.points.first.$2, d('1000'));
        expect(apple.points.last.$2.round(scale: 2), d('754.66'));
        expect(apple.change!.round(scale: 4), d('-0.2453'));
        expect(view.curves.last.points.last.$2, d('820'));
        final p = view.provenance;
        expect(
          (p.interval, p.from, p.to, p.currency),
          ('1week', day(2022, 1, 7), day(2022, 12, 30), 'USD'),
        );
        expect(view.hasLiveVariant, isTrue);
      },
    );

    test('no live variant when a curve is not of an asset', () async {
      final view = await container(worldAsset: null)
          .read(revealViewProvider('ae.apple').future);
      expect(view.hasLiveVariant, isFalse);
    });

    test('« Et aujourd\'hui ? »: the same curves over the last year', () async {
      final live = await container().read(
        liveRevealProvider('ae.apple').future,
      );
      expect((live.from, live.to), (day(2025, 10, 8), day(2026, 10, 7)));
      expect(
        [for (final c in live.curves) c.points.last.$2],
        [d('1250'), d('1100')],
      );
      expect(backend.to('/v1/assets/apple/history'), isNotEmpty);
    });

    test('an answer, right or wrong, completes the node', () async {
      final c = container();
      final play = c.read(predictPlayProvider('ae.apple').notifier);
      await play.submit();
      expect(c.read(predictPlayProvider('ae.apple')).submitted, isFalse);

      play.choose('world');
      await play.submit();
      final state = c.read(predictPlayProvider('ae.apple'));
      expect((state.chosen, state.submitted), ('world', true));
      play.choose('apple');
      expect(c.read(predictPlayProvider('ae.apple')).chosen, 'world');

      expect(await c.read(profileRepositoryProvider).completedNodes(), {
        'ae.apple',
      });
      final row = (await db.learningDao.progress()).single;
      expect(
        (row.lastAnswer, row.completedAt),
        ('world', DateTime.utc(2026, 10, 8, 12)),
      );
    });

    test('an unknown node, or a node of another type, is not found', () async {
      final c = container();
      for (final id in ['ae.nope', 'ae.fees']) {
        await expectLater(
          c.read(revealViewProvider(id).future),
          throwsA(isA<NotFoundFailure>()),
          reason: id,
        );
      }
    });

    test('a payload the app cannot play is a server failure', () async {
      final c = container(choices: const []);
      await expectLater(
        c.read(revealViewProvider('ae.apple').future),
        throwsA(isA<ServerFailure>()),
      );
    });
  });

  group('toy', () {
    test('the return starts from the real past average', () async {
      final state = await container().read(toyPlayProvider('ae.fees').future);
      expect(state.value('return').round(scale: 4), d('0.0718'));
      expect(state.returnIsPast, isTrue);
      final past = state.view.past!;
      expect((past.from, past.to), (day(2010, 1, 1), day(2020, 1, 1)));
      final outcome = state.outcome as FeesOutcome;
      expect(outcome.result.low, hasLength(31));
      expect(outcome.result.gap, greaterThan(Decimal.zero));
    });

    test('moving every slider completes the node, once', () async {
      final c = container();
      await c.read(toyPlayProvider('ae.fees').future);
      final play = c.read(toyPlayProvider('ae.fees').notifier);
      for (final (id, value) in [
        ('amount', '20000'),
        ('years', '10'),
        ('return', '0.03'),
        ('fee_low', '0.001'),
      ]) {
        await play.set(id, d(value));
      }
      var state = c.read(toyPlayProvider('ae.fees')).value!;
      expect(state.completed, isFalse);
      expect(state.returnIsPast, isFalse);
      expect((state.outcome as FeesOutcome).result.low, hasLength(11));

      // The 20th step from 0 by 0,1 %: 2 %.
      await play.setStep('fee_high', 20);
      expect(
        c.read(toyPlayProvider('ae.fees')).value!.value('fee_high'),
        d('0.02'),
      );
      await play.setStep('fee_high', 99);
      expect(
        c.read(toyPlayProvider('ae.fees')).value!.value('fee_high'),
        d('0.03'),
        reason: 'kept within the range',
      );
      state = c.read(toyPlayProvider('ae.fees')).value!;
      expect(state.completed, isTrue);
      expect((await db.learningDao.progress()).single.attempts, 1);
    });
  });
}
