import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/learning/content.dart';
import '../../../application/onboarding/onboarding_controller.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/learning/profile.dart';
import '../../../domain/learning/profile_rules.dart';

/// Five questions, then where the path starts and why (BRIEF §4.1).
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final current = state.value;
    final asking = current != null && !current.done;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: asking && current.question > 0
            ? BackButton(onPressed: controller.back)
            : null,
        title: asking
            ? Text(l10n.onboarding_progress(current.question + 1))
            : null,
      ),
      body: SafeArea(
        child: switch (state) {
          AsyncData(:final value) when value.done => _Result(value),
          AsyncData(:final value) => _Question(value),
          AsyncError(:final error) => ErrorView(
            failure: error is Failure ? error : const StorageFailure(),
            onRetry: () => ref.invalidate(onboardingControllerProvider),
          ),
          _ => const Padding(
            padding: EdgeInsets.all(AppSpace.screenPadding),
            child: AsyncSkeleton(lines: 5),
          ),
        },
      ),
    );
  }
}

class _Question extends ConsumerWidget {
  const _Question(this.state);

  final OnboardingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final chosen = state.answers[state.question];

    return ListView(
      padding: const EdgeInsets.all(AppSpace.screenPadding),
      children: [
        Text(
          questionTitle(l10n, state.question),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpace.x2),
        Text(
          l10n.onboarding_reassurance,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpace.x6),
        for (final answer in onboardingQuestions[state.question]) ...[
          _AnswerCard(
            label: answerLabel(l10n, answer),
            selected: answer == chosen,
            onTap: () => controller.choose(answer),
          ),
          const SizedBox(height: AppSpace.x4),
        ],
        if (state.showError)
          _ValidationMessage(l10n.onboarding_error)
        else if (state.saveError case final failure?)
          ErrorView(failure: failure, onRetry: controller.retrySave),
        const SizedBox(height: AppSpace.x4),
        ChunkyButton(label: l10n.onboarding_next, onPressed: controller.next),
      ],
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ChunkyCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.x4,
              vertical: AppSpace.x3,
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: AppSpace.x3),
                Expanded(child: Text(label, style: AppText.bodyStrong)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ValidationMessage extends StatelessWidget {
  const _ValidationMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Row(
      children: [
        const ExcludeSemantics(
          child: Icon(Icons.error_outline, color: AppColors.alertText),
        ),
        const SizedBox(width: AppSpace.x2),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.alertText),
          ),
        ),
      ],
    ),
  );
}

class _Result extends ConsumerWidget {
  const _Result(this.state);

  final OnboardingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = state.profile!;
    final (:reason, :node) = startExplanation(profile);
    // The starting node's title comes from the island's content pack.
    final pack = ref.watch(contentPackProvider(actionsEtfIsland)).value;
    if (pack == null && reason != StartReason.noSavings) {
      return const Padding(
        padding: EdgeInsets.all(AppSpace.screenPadding),
        child: AsyncSkeleton(lines: 3),
      );
    }
    final start = reason == StartReason.noSavings
        ? l10n.onboarding_start_cushion
        : pack!.nodes[node - 1].title.of(
            Localizations.localeOf(context).languageCode,
          );
    final answer = answerLabel(
      l10n,
      reason == StartReason.knowledge ? profile.knowledge : profile.savings,
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpace.screenPadding),
      children: [
        ChunkyCard(
          child: Text(
            l10n.onboarding_result(start, answer),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: AppSpace.x6),
        ChunkyButton(
          label: l10n.onboarding_go,
          onPressed: () => context.go('/'),
        ),
      ],
    );
  }
}

String questionTitle(AppLocalizations l10n, int question) => switch (question) {
  0 => l10n.onboarding_goal_question,
  1 => l10n.onboarding_drop_question,
  2 => l10n.onboarding_knowledge_question,
  3 => l10n.onboarding_savings_question,
  _ => l10n.onboarding_time_question,
};

String answerLabel(AppLocalizations l10n, Enum answer) => switch (answer) {
  Goal.under3Years => l10n.onboarding_goal_under3Years,
  Goal.from3To8Years => l10n.onboarding_goal_from3To8Years,
  Goal.longTerm => l10n.onboarding_goal_longTerm,
  Goal.discovering => l10n.onboarding_goal_discovering,
  DropReaction.sellAll => l10n.onboarding_drop_sellAll,
  DropReaction.wait => l10n.onboarding_drop_wait,
  DropReaction.buyMore => l10n.onboarding_drop_buyMore,
  DropReaction.dontKnow => l10n.onboarding_drop_dontKnow,
  Knowledge.nothing => l10n.onboarding_knowledge_nothing,
  Knowledge.stocks => l10n.onboarding_knowledge_stocks,
  Knowledge.etfs => l10n.onboarding_knowledge_etfs,
  Knowledge.alreadyInvesting => l10n.onboarding_knowledge_alreadyInvesting,
  Savings.livret => l10n.onboarding_savings_livret,
  Savings.currentAccount => l10n.onboarding_savings_currentAccount,
  Savings.invested => l10n.onboarding_savings_invested,
  Savings.none => l10n.onboarding_savings_none,
  WeeklyTime.five => l10n.onboarding_time_five,
  WeeklyTime.fifteen => l10n.onboarding_time_fifteen,
  WeeklyTime.thirtyPlus => l10n.onboarding_time_thirtyPlus,
  _ => throw ArgumentError.value(answer, 'answer'),
};
