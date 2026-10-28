import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/lesson_play.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/more_lessons.dart';

Decimal d(String s) => Decimal.parse(s);

void main() {
  late AppDatabase db;
  late ProviderContainer c;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(
          WallClock(DateTime.utc(2026, 10, 11, 9)),
        ),
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => decodePack(morePackJson())),
      ],
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<(String, String?)> saved() async {
    final row = (await db.learningDao.progress()).single;
    return (row.nodeId, row.lastAnswer);
  }

  group('decision', () {
    test('the curve splits at the moment; each choice\'s outcome', () async {
      final view = await c.read(decisionViewProvider('ae.march').future);
      expect(view.before.last.$2, d('56'));
      expect(view.after.map((p) => p.$2), [d('56'), d('70'), d('95.2')]);
      expect(view.change, d('0.7'));
      expect(view.outcomes, {
        'hold': d('17000'),
        'half': d('13500'),
        'sell': d('10000'),
      });
    });

    test('a choice completes the node, then shows what happened', () async {
      final play = c.read(decisionPlayProvider('ae.march').notifier);
      await play.submit();
      expect(c.read(decisionPlayProvider('ae.march')).submitted, isFalse);
      play.choose('half');
      await play.submit();
      expect(c.read(decisionPlayProvider('ae.march')).submitted, isTrue);
      expect(await saved(), ('ae.march', 'half'));
    });

    test('another type is not a decision', () async {
      await expectLater(
        c.read(decisionViewProvider('ae.quiz').future),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('sort', () {
    test('real values and the true order', () async {
      final view = await c.read(sortViewProvider('ae.ladder').future);
      expect(view.values['livret'], Decimal.zero);
      expect(view.values['wild']!, greaterThan(view.values['calm']!));
      expect(view.truth, ['livret', 'calm', 'wild']);
    });

    test('moved into place, submitted: how many sit at their rank', () async {
      await c.read(sortPlayProvider('ae.ladder').future);
      final play = c.read(sortPlayProvider('ae.ladder').notifier);
      expect(c.read(sortPlayProvider('ae.ladder')).value!.order, [
        'wild',
        'livret',
        'calm',
      ]);
      // Drag the single stock to the bottom.
      play.move(0, 2);
      expect(c.read(sortPlayProvider('ae.ladder')).value!.order, [
        'livret',
        'calm',
        'wild',
      ]);
      await play.submit();
      expect(c.read(sortPlayProvider('ae.ladder')).value!.placed, 3);
      expect(await saved(), ('ae.ladder', 'livret,calm,wild'));
      // Done: the order no longer moves.
      play.move(0, 2);
      expect(
        c.read(sortPlayProvider('ae.ladder')).value!.order.first,
        'livret',
      );
    });
  });

  test(
    'a Livret item ranks at the rate of the day, offline too (M12-4)',
    () async {
      final wall = WallClock(DateTime.utc(2026, 10, 11, 9));
      final backend = FakeBackend();
      final market = MarketRepository(
        db,
        BackendApi('http://t', adapter: backend),
        wallClock: wall,
      );
      final pack = morePackJson().replaceFirst(
        '"id":"livret","label":{"fr":"Livret A","en":"Livret A"},"value":0',
        '"id":"livret","label":{"fr":"Livret A","en":"Livret A"},"livret":true',
      );
      ProviderContainer container() => ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          databaseProvider.overrideWithValue(db),
          liveClockProvider.overrideWithValue(wall),
          marketRepositoryProvider.overrideWithValue(market),
          contentPackProvider(actionsEtfIsland)
              .overrideWith((ref) async => decodePack(pack)),
        ],
      );
      final online = container();
      addTearDown(online.dispose);
      // The fake backend's Livret: 1,7 % since 1 August 2026.
      expect(
        (await online.read(sortViewProvider('ae.ladder').future))
            .values['livret'],
        d('0.017'),
      );
      backend.offline = true;
      final offline = container();
      addTearDown(offline.dispose);
      expect(
        (await offline.read(sortViewProvider('ae.ladder').future))
            .values['livret'],
        d('0.017'),
        reason: 'the cached history',
      );
    },
  );

  test('a quiz plays as a checkpoint does (M12-4)', () async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        contentPackProvider(actionsEtfIsland).overrideWith(
          (ref) async => decodePack(
            morePackJson().replaceFirst('"type":"checkpoint"', '"type":"quiz"'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final view = await container.read(checkpointViewProvider('ae.quiz').future);
    expect(view.checkpoint.questions, hasLength(2));
  });

  group('build_puzzle', () {
    test('weights are checked by the domain as they change', () async {
      await c.read(puzzlePlayProvider('ae.calm').future);
      final play = c.read(puzzlePlayProvider('ae.calm').notifier);
      var s = c.read(puzzlePlayProvider('ae.calm')).value!;
      expect(
        (s.total, s.volatility, s.check.solved),
        (Decimal.zero, null, false),
      );

      // All in the wild one: too volatile, one asset, one region.
      play.setSteps('ds.wild', 10);
      s = c.read(puzzlePlayProvider('ae.calm')).value!;
      expect(
        (s.check.total, s.check.volatility, s.check.assets),
        (true, false, false),
      );
      await play.submit();
      expect(c.read(puzzlePlayProvider('ae.calm')).value!.completed, isFalse);

      // Half and half in two series moving against each other.
      play
        ..setSteps('ds.wild', 0)
        ..setSteps('ds.calm', 5)
        ..setSteps('ds.counter', 5);
      s = c.read(puzzlePlayProvider('ae.calm')).value!;
      expect(s.volatility!, lessThan(d('0.05')));
      expect(s.check.solved, isTrue);
      await play.submit();
      expect(c.read(puzzlePlayProvider('ae.calm')).value!.completed, isTrue);
      expect(await saved(), ('ae.calm', 'ds.calm=0.5,ds.counter=0.5'));
    });

    test('a weight stays between 0 and 100 %', () async {
      await c.read(puzzlePlayProvider('ae.calm').future);
      final play = c.read(puzzlePlayProvider('ae.calm').notifier)
        ..setSteps('ds.calm', 14);
      expect(
        c.read(puzzlePlayProvider('ae.calm')).value!.weights['ds.calm'],
        Decimal.one,
      );
      play.setSteps('ds.calm', -2);
      expect(
        c.read(puzzlePlayProvider('ae.calm')).value!.weights['ds.calm'],
        Decimal.zero,
      );
    });
  });

  group('checkpoint', () {
    test('one question at a time, then the score, whatever it is', () async {
      await c.read(checkpointViewProvider('ae.quiz').future);
      final play = c.read(checkpointPlayProvider('ae.quiz').notifier);
      play.check();
      expect(c.read(checkpointPlayProvider('ae.quiz')).checked, isFalse);

      play
        ..choose('one')
        ..check();
      var s = c.read(checkpointPlayProvider('ae.quiz'));
      expect((s.index, s.checked), (0, true));
      expect(s.answers, ['one']);
      play.choose('many');
      expect(c.read(checkpointPlayProvider('ae.quiz')).chosen, 'one');

      await play.next();
      s = c.read(checkpointPlayProvider('ae.quiz'));
      expect((s.index, s.checked, s.chosen), (1, false, null));

      play
        ..choose('yes')
        ..check();
      await play.next();
      s = c.read(checkpointPlayProvider('ae.quiz'));
      expect((s.finished, s.score), (true, 1));
      expect(await saved(), ('ae.quiz', '1/2'));
    });
  });
}
