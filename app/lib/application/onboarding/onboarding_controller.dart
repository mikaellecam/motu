import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../domain/learning/profile.dart';
import '../../domain/learning/profile_rules.dart';
import '../learning/content.dart';
import '../providers.dart';

part 'onboarding_controller.g.dart';

/// The five questions in order, each with its answers in display order.
const onboardingQuestions = <List<Enum>>[
  Goal.values,
  DropReaction.values,
  Knowledge.values,
  Savings.values,
  WeeklyTime.values,
];

/// Where the questionnaire stands.
final class OnboardingState {
  const OnboardingState({
    required this.question,
    required this.answers,
    this.showError = false,
    this.saveError,
  });

  /// 0 to 4 while asking; [onboardingQuestions].length once answered.
  final int question;

  /// One per question, null until chosen.
  final List<Enum?> answers;

  /// « Choisis une réponse pour continuer » is shown.
  final bool showError;

  /// Saving the profile failed; the user can retry.
  final Failure? saveError;

  bool get done => question == onboardingQuestions.length;

  /// The profile the answers describe, once all are given.
  Profile? get profile => answers.contains(null)
      ? null
      : Profile(
          goal: answers[0]! as Goal,
          dropReaction: answers[1]! as DropReaction,
          knowledge: answers[2]! as Knowledge,
          savings: answers[3]! as Savings,
          weeklyTime: answers[4]! as WeeklyTime,
        );

  OnboardingState copyWith({
    int? question,
    List<Enum?>? answers,
    bool? showError,
    Failure? saveError,
  }) => OnboardingState(
    question: question ?? this.question,
    answers: answers ?? this.answers,
    showError: showError ?? this.showError,
    saveError: saveError,
  );
}

/// Drives the onboarding questionnaire (BRIEF §4.1). On a retake the
/// previous answers come preselected; saving replaces the answers only.
@riverpod
class OnboardingController extends _$OnboardingController {
  @override
  Future<OnboardingState> build() async {
    final previous = await ref.read(profileRepositoryProvider).load();
    return OnboardingState(
      question: 0,
      answers: previous == null
          ? List.filled(onboardingQuestions.length, null)
          : [
              previous.goal,
              previous.dropReaction,
              previous.knowledge,
              previous.savings,
              previous.weeklyTime,
            ],
    );
  }

  OnboardingState get _current => state.requireValue;

  void choose(Enum answer) {
    final answers = [..._current.answers];
    answers[_current.question] = answer;
    state = AsyncData(_current.copyWith(answers: answers, showError: false));
  }

  /// Moves on, or shows the validation message when nothing is chosen. After
  /// the last question, saves the profile.
  Future<void> next() async {
    final current = _current;
    if (current.answers[current.question] == null) {
      state = AsyncData(current.copyWith(showError: true));
      return;
    }
    if (current.question < onboardingQuestions.length - 1) {
      state = AsyncData(current.copyWith(question: current.question + 1));
      return;
    }
    await _save(current);
  }

  Future<void> retrySave() => _save(_current);

  Future<void> _save(OnboardingState current) async {
    try {
      await ref.read(profileRepositoryProvider).save(current.profile!);
      state = AsyncData(current.copyWith(question: onboardingQuestions.length));
    } on Failure catch (failure) {
      state = AsyncData(current.copyWith(saveError: failure));
    }
  }

  void back() {
    final current = _current;
    if (current.question == 0) return;
    state = AsyncData(
      current.copyWith(question: current.question - 1, showError: false),
    );
  }
}

/// Where the way starts and why, for « On commence par X parce que tu as
/// répondu Y »: Les bases' first lesson, or for those who skip it (M12-7)
/// Actions & ETF's node 1-based [node].
({StartReason reason, String island, int node}) startExplanation(
  Profile profile,
) => skipsTheBasics(profile)
    ? (
        reason: startReason(profile),
        island: actionsEtfIsland,
        node: forcedFirstNode(profile) ?? startingNode(profile),
      )
    : (reason: startReason(profile), island: lesBasesIsland, node: 1);
