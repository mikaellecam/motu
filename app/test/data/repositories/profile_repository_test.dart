import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/local/tables.dart';
import 'package:finance_companion/data/repositories/profile_repository.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:flutter_test/flutter_test.dart';

const first = Profile(
  goal: Goal.longTerm,
  dropReaction: DropReaction.wait,
  knowledge: Knowledge.nothing,
  savings: Savings.livret,
  weeklyTime: WeeklyTime.fifteen,
);

void main() {
  late AppDatabase db;
  late ProfileRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ProfileRepository(db);
  });
  tearDown(() => db.close());

  test('no profile before the first onboarding', () async {
    expect(await repo.load(), isNull);
  });

  test('answers are saved and read back', () async {
    await repo.save(first);
    final read = (await repo.load())!;
    expect(read.goal, Goal.longTerm);
    expect(read.savings, Savings.livret);
    expect(read.weeklyTime, WeeklyTime.fifteen);
  });

  test('a retake replaces the answers and keeps everything else', () async {
    await repo.save(first);
    await db.learningDao.updateProfile(
      const ProfilesCompanion(showAll: Value(true), language: Value('en')),
    );
    await db.learningDao.saveProgress(
      NodeProgressCompanion.insert(
        nodeId: 'ae.fees-toy',
        status: NodeStatus.completed,
      ),
    );
    await db.learningDao.discover('etf', DateTime.utc(2026, 10, 1));

    await repo.save(
      const Profile(
        goal: Goal.discovering,
        dropReaction: DropReaction.buyMore,
        knowledge: Knowledge.alreadyInvesting,
        savings: Savings.invested,
        weeklyTime: WeeklyTime.thirtyPlus,
      ),
    );

    expect((await repo.load())!.knowledge, Knowledge.alreadyInvesting);
    final row = (await db.learningDao.profile())!;
    expect(row.showAll, isTrue);
    expect(row.language, 'en');
    expect(await db.learningDao.progress(), hasLength(1));
    expect(await db.learningDao.discovered(), hasLength(1));
  });

  test(
    'a completed node keeps its first completion and counts attempts',
    () async {
      final first = DateTime.utc(2026, 10, 11, 9);
      await repo.completeNode('ae.apple', answer: 'world', at: first);
      await repo.completeNode(
        'ae.apple',
        answer: 'apple',
        at: first.add(const Duration(hours: 1)),
      );
      await repo.completeNode('ae.fees', at: first);
      expect(await repo.completedNodes(), {'ae.apple', 'ae.fees'});
      final row = (await db.learningDao.progress()).firstWhere(
        (r) => r.nodeId == 'ae.apple',
      );
      expect(
        (row.status, row.attempts, row.lastAnswer, row.completedAt),
        (NodeStatus.completed, 2, 'apple', first),
      );
    },
  );

  test('completions as they happen: each node with its first one', () async {
    final first = DateTime.utc(2026, 10, 11, 9);
    final seen = <Map<String, DateTime>>[];
    final sub = repo.watchCompletions().listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await repo.completeNode('ae.apple', at: first);
    await pumpEventQueue();
    await repo.completeNode('ae.apple', at: first.add(const Duration(days: 1)));
    await repo.completeNode('ae.fees', at: first.add(const Duration(hours: 2)));
    await pumpEventQueue();
    expect(seen.first, isEmpty);
    expect(seen.last, {
      'ae.apple': first,
      'ae.fees': first.add(const Duration(hours: 2)),
    });
  });

  test(
    'settings: defaults, then each one kept, a retake keeping them',
    () async {
      final seen = <AppSettings>[];
      final sub = repo.watchSettings().listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(
        (seen.last.language, seen.last.showAll, seen.last.liveStartingCash),
        (null, false, null),
      );

      const answers = Profile(
        goal: Goal.longTerm,
        dropReaction: DropReaction.wait,
        knowledge: Knowledge.etfs,
        savings: Savings.livret,
        weeklyTime: WeeklyTime.fifteen,
      );
      await repo.save(answers);
      await repo.setLanguage('en');
      await repo.setShowAll(true);
      await repo.setLiveStartingCash(const Money(1000000, Currency.eur));
      // Retaking the questionnaire saves the answers only.
      await repo.save(answers);
      await pumpEventQueue();
      expect(
        (seen.last.language, seen.last.showAll, seen.last.liveStartingCash),
        ('en', true, const Money(1000000, Currency.eur)),
      );
      expect(await repo.showAll(), isTrue);

      await repo.setLanguage(null);
      await pumpEventQueue();
      expect(seen.last.language, isNull);
    },
  );
}
