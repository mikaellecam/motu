import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../map/archipelago.dart';

/// Five questions, then where the path starts and why (BRIEF §4.1), on the
/// sea under the island, as the art direction's « onboarding question »
/// draws it.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    return Scaffold(
      // World screens sit on the sea (BRIEF §10.2).
      backgroundColor: AppColors.sea,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SafeArea(
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
      ),
    );
  }
}

/// Actions & ETF as the map paints it, bare: where the path will start.
class _Island extends StatelessWidget {
  const _Island();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 170,
    child: CustomPaint(
      painter: ArchipelagoPainter(
        only: archipelago.firstWhere((i) => i.id == IslandId.actionsEtf),
      ),
    ),
  );
}

class _Question extends ConsumerWidget {
  const _Question(this.state);

  final OnboardingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final chosen = state.answers[state.question];
    final questions = onboardingQuestions.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.screenPadding,
            ),
            children: [
              const _Island(),
              ChunkyCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.onboarding_progress(state.question + 1),
                      style: AppText.label.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: AppSpace.x2),
                    ExcludeSemantics(
                      child: _Steps(done: state.question + 1, of: questions),
                    ),
                    const SizedBox(height: AppSpace.x3),
                    Text(
                      questionTitle(l10n, state.question),
                      style: AppText.title,
                    ),
                    const SizedBox(height: AppSpace.x2),
                    Text(
                      l10n.onboarding_reassurance,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.x4),
              for (final answer in onboardingQuestions[state.question]) ...[
                ChunkyChoice(
                  label: answerLabel(l10n, answer),
                  selected: answer == chosen,
                  onTap: () => controller.choose(answer),
                ),
                const SizedBox(height: AppSpace.x3),
              ],
            ],
          ),
        ),
        // Always in reach, however long the question; a missing answer is
        // said where « Suivant » was tapped.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screenPadding,
            AppSpace.x2,
            AppSpace.screenPadding,
            AppSpace.screenPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.showError) ...[
                _ValidationMessage(l10n.onboarding_error),
                const SizedBox(height: AppSpace.x3),
              ] else if (state.saveError case final failure?) ...[
                ErrorView(failure: failure, onRetry: controller.retrySave),
                const SizedBox(height: AppSpace.x3),
              ],
              Row(
                children: [
                  if (state.question > 0) ...[
                    Expanded(
                      child: ChunkyButton(
                        label: l10n.onboarding_back,
                        kind: ChunkyButtonKind.secondary,
                        onPressed: controller.back,
                      ),
                    ),
                    const SizedBox(width: AppSpace.x3),
                  ],
                  Expanded(
                    child: ChunkyButton(
                      label: l10n.onboarding_next,
                      onPressed: controller.next,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One segment per question, the ones reached filled.
class _Steps extends StatelessWidget {
  const _Steps({required this.done, required this.of});

  final int done;
  final int of;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < of; i++) ...[
        if (i > 0) const SizedBox(width: AppSpace.x1),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: i < done ? AppColors.progress : AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpace.x2),
              border: Border.all(color: AppColors.ink, width: 2),
            ),
          ),
        ),
      ],
    ],
  );
}

/// A missing answer, in an alert box.
class _ValidationMessage extends StatelessWidget {
  const _ValidationMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(AppSpace.x3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppShape.flatCardRadius),
        border: Border.all(color: AppColors.alertText, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExcludeSemantics(
            child: Icon(
              Icons.warning_amber_rounded,
              color: AppColors.alertText,
            ),
          ),
          const SizedBox(width: AppSpace.x2),
          Expanded(
            child: Text(
              text,
              style: AppText.label.copyWith(color: AppColors.alertText),
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.screenPadding),
      children: [
        const _Island(),
        ChunkyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.onboarding_start_label,
                style: AppText.label.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: AppSpace.x1),
              Text(start, style: AppText.title),
              const SizedBox(height: AppSpace.x2),
              Text(
                l10n.onboarding_result(start, answer),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.x6),
        ChunkyButton(
          label: l10n.onboarding_go,
          onPressed: () => context.go('/'),
        ),
        const SizedBox(height: AppSpace.screenPadding),
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
