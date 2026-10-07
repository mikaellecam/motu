import 'package:drift/native.dart';
import 'package:finance_companion/application/onboarding/onboarding_controller.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/repositories/profile_repository.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:finance_companion/domain/learning/profile_rules.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails the first [failures] saves.
class FlakyRepository implements ProfileRepository {
  FlakyRepository({this.failures = 0});
  int failures;
  Profile? saved;

  @override
  Future<Profile?> load() async => saved;

  @override
  Future<void> save(Profile profile) async {
    if (failures > 0) {
      failures--;
      throw const StorageFailure();
    }
    saved = profile;
  }
}

const answers = <Enum>[
  Goal.longTerm,
  DropReaction.wait,
  Knowledge.etfs,
  Savings.currentAccount,
  WeeklyTime.fifteen,
];

void main() {
  late ProviderContainer container;
  late AppDatabase db;

  ProviderContainer containerWith(List overrides) {
    final c = ProviderContainer(overrides: [...overrides]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    container = containerWith([databaseProvider.overrideWithValue(db)]);
  });

  Future<OnboardingState> start(ProviderContainer c) =>
      c.read(onboardingControllerProvider.future);
  OnboardingState stateOf(ProviderContainer c) =>
      c.read(onboardingControllerProvider).requireValue;
  OnboardingController controllerOf(ProviderContainer c) =>
      c.read(onboardingControllerProvider.notifier);

  test('starts on the first question with nothing chosen', () async {
    final s = await start(container);
    expect(s.question, 0);
    expect(s.answers, everyElement(isNull));
    expect(s.done, isFalse);
  });

  test('moving on without an answer shows the validation message', () async {
    await start(container);
    await controllerOf(container).next();
    expect(stateOf(container).showError, isTrue);
    expect(stateOf(container).question, 0);

    controllerOf(container).choose(Goal.longTerm);
    expect(stateOf(container).showError, isFalse);
    await controllerOf(container).next();
    expect(stateOf(container).question, 1);
  });

  test('back goes to the previous question, never before the first', () async {
    await start(container);
    final controller = controllerOf(container);
    controller.back();
    expect(stateOf(container).question, 0);
    controller.choose(Goal.longTerm);
    await controller.next();
    controller.back();
    expect(stateOf(container).question, 0);
    expect(stateOf(container).answers.first, Goal.longTerm);
  });

  test('the last answer saves the profile', () async {
    await start(container);
    final controller = controllerOf(container);
    for (final answer in answers) {
      controller.choose(answer);
      await controller.next();
    }
    expect(stateOf(container).done, isTrue);
    final saved = (await ProfileRepository(db).load())!;
    expect(saved.knowledge, Knowledge.etfs);
  });

  test('a retake starts from the previous answers', () async {
    await ProfileRepository(db).save(
      const Profile(
        goal: Goal.discovering,
        dropReaction: DropReaction.sellAll,
        knowledge: Knowledge.stocks,
        savings: Savings.none,
        weeklyTime: WeeklyTime.five,
      ),
    );
    final s = await start(container);
    expect(s.answers, [
      Goal.discovering,
      DropReaction.sellAll,
      Knowledge.stocks,
      Savings.none,
      WeeklyTime.five,
    ]);
  });

  test('a failed save keeps the answers and can be retried', () async {
    final repo = FlakyRepository(failures: 1);
    final c = containerWith([
      profileRepositoryProvider.overrideWithValue(repo),
    ]);
    await start(c);
    final controller = controllerOf(c);
    for (final answer in answers) {
      controller.choose(answer);
      await controller.next();
    }
    expect(stateOf(c).done, isFalse);
    expect(stateOf(c).saveError, isA<StorageFailure>());

    await controller.retrySave();
    expect(stateOf(c).done, isTrue);
    expect(repo.saved, isNotNull);
  });

  group('startExplanation', () {
    Profile p(Knowledge k, Savings s) => Profile(
      goal: Goal.longTerm,
      dropReaction: DropReaction.wait,
      knowledge: k,
      savings: s,
      weeklyTime: WeeklyTime.fifteen,
    );
    final cases = <(Knowledge, Savings, StartReason, int)>[
      (Knowledge.nothing, Savings.currentAccount, StartReason.knowledge, 1),
      (Knowledge.etfs, Savings.invested, StartReason.knowledge, 3),
      (
        Knowledge.alreadyInvesting,
        Savings.currentAccount,
        StartReason.knowledge,
        4,
      ),
      (
        Knowledge.alreadyInvesting,
        Savings.livret,
        StartReason.livretSavings,
        1,
      ),
      (Knowledge.etfs, Savings.none, StartReason.noSavings, 3),
    ];
    for (final (k, s, reason, node) in cases) {
      test('$k, $s → $reason, node $node', () {
        final e = startExplanation(p(k, s));
        expect(e.reason, reason);
        expect(e.node, node);
      });
    }
  });
}
