import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
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
}
