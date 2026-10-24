import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/lesson_play.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../widgets/term_text.dart';
import 'node_screen.dart';

/// `build_puzzle` (BRIEF §4.3): a weight slider per asset, the portfolio's
/// volatility and every rule checked by the domain as the weights move;
/// « Valider » once they all hold.
class PuzzlePlayer extends ConsumerWidget {
  const PuzzlePlayer({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final formats = Formats(language);
    final text = Theme.of(context).textTheme;
    final actions = ref.read(puzzlePlayProvider(nodeId).notifier);

    return playerState(
      ref.watch(puzzlePlayProvider(nodeId)),
      onRetry: () => ref.invalidate(puzzlePlayProvider(nodeId)),
      data: (s) {
        final puzzle = s.view.puzzle;
        final rules = puzzle.rules;
        final steps = (Decimal.one / puzzle.step)
            .toDecimal(scaleOnInfinitePrecision: 0)
            .toBigInt()
            .toInt();
        return ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            LessonCard(
              label: nodeTypeName(l10n, s.view.node.type),
              headline: s.view.node.title.of(language),
              children: [
                TermText(
                  puzzle.prompt.of(language),
                  terms: s.view.terms,
                  style: text.bodyLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.x4),
            ChunkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final asset in puzzle.assets) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                asset.label.of(language),
                                style: AppText.bodyStrong,
                              ),
                              Text(
                                _region(l10n, asset.region),
                                style: AppText.caption.copyWith(
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formats.percent(
                            s.weights[asset.dataset]!,
                            decimals: 0,
                          ),
                          style: AppText.figure.copyWith(color: AppColors.ink),
                        ),
                      ],
                    ),
                    Semantics(
                      label: l10n.puzzle_weight_semantics(
                        asset.label.of(language),
                      ),
                      child: Slider(
                        value: s.weights[asset.dataset]!.toDouble(),
                        divisions: steps,
                        semanticFormatterCallback: (v) => formats.percent(
                          Decimal.parse(v.toStringAsFixed(4)),
                          decimals: 0,
                        ),
                        onChanged: s.completed
                            ? null
                            : (v) => actions.setSteps(
                                asset.dataset,
                                (v * steps).round(),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpace.x4),
            ChunkyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.puzzle_total(formats.percent(s.total, decimals: 0)),
                    style: AppText.bodyStrong,
                  ),
                  Text(switch (s.volatility) {
                    null => l10n.puzzle_volatility_none,
                    final v => l10n.puzzle_volatility(formats.percent(v)),
                  }, style: AppText.bodyStrong),
                  const SizedBox(height: AppSpace.x3),
                  _Rule(l10n.puzzle_rule_total, s.check.total),
                  _Rule(
                    l10n.puzzle_rule_volatility(
                      formats.percent(rules.maxVolatility, decimals: 0),
                    ),
                    s.check.volatility,
                  ),
                  if (rules.minAssets case final n?)
                    _Rule(l10n.puzzle_rule_assets(n), s.check.assets),
                  if (rules.minRegions case final n?)
                    _Rule(l10n.puzzle_rule_regions(n), s.check.regions),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.x6),
            if (s.failure case final failure?)
              Text(
                failureMessage(context, failure),
                style: text.bodyMedium?.copyWith(color: AppColors.alertText),
              ),
            if (!s.completed)
              ChunkyButton(
                label: l10n.node_check,
                onPressed: s.check.solved ? actions.submit : null,
              )
            else ...[
              Semantics(
                liveRegion: true,
                child: LessonCard(
                  label: l10n.node_why,
                  headline: l10n.puzzle_done,
                  children: [
                    TermText(
                      puzzle.explanation.of(language),
                      terms: s.view.terms,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.x6),
              LessonEnd(node: s.view.node),
            ],
          ],
        );
      },
    );
  }
}

String _region(AppLocalizations l10n, String region) => switch (region) {
  'world' => l10n.region_world,
  'us' => l10n.region_us,
  'europe' => l10n.region_europe,
  'emerging' => l10n.region_emerging,
  _ => region,
};

/// A rule and whether it holds: a filled check, or an empty circle.
class _Rule extends StatelessWidget {
  const _Rule(this.label, this.met);
  final String label;
  final bool met;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: '$label, ${met ? l10n.puzzle_rule_met : l10n.puzzle_rule_unmet}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.x1),
        child: Row(
          children: [
            Icon(
              met ? Icons.check_circle : Icons.radio_button_unchecked,
              color: met ? AppColors.ink : AppColors.muted,
            ),
            const SizedBox(width: AppSpace.x2),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: met ? AppColors.ink : AppColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
