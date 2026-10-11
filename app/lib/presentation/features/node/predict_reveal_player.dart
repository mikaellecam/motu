import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/node_player.dart';
import '../../../application/providers.dart';
import '../../../core/cache_status.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../widgets/sign_color.dart';
import '../../widgets/term_text.dart';
import 'node_screen.dart';
import 'reveal_chart.dart';

/// `predict_reveal` (BRIEF §4.3): pick an answer, then the frozen curves
/// draw themselves, then the explanation; « Et aujourd'hui ? » reruns the
/// curves on current prices when online.
class PredictRevealPlayer extends ConsumerWidget {
  const PredictRevealPlayer({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final play = ref.watch(predictPlayProvider(nodeId));
    final actions = ref.read(predictPlayProvider(nodeId).notifier);
    final online = switch (ref.watch(cacheStatusProvider).value) {
      null || Offline() => false,
      _ => true,
    };

    return playerState(
      ref.watch(revealViewProvider(nodeId)),
      onRetry: () => ref.invalidate(revealViewProvider(nodeId)),
      data: (view) {
        final reveal = view.reveal;
        final answer = reveal.choices.firstWhere((c) => c.id == reveal.answer);
        return ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            Text(view.node.title.of(language), style: AppText.title),
            const SizedBox(height: AppSpace.x2),
            Text(reveal.question.of(language), style: text.bodyLarge),
            const SizedBox(height: AppSpace.x4),
            for (final choice in reveal.choices) ...[
              ChunkyChoice(
                label: choice.label.of(language),
                selected: play.chosen == choice.id,
                onTap: () => actions.choose(choice.id),
              ),
              const SizedBox(height: AppSpace.x3),
            ],
            if (play.failure case final failure?)
              Text(
                failureMessage(context, failure),
                style: text.bodyMedium?.copyWith(color: AppColors.alertText),
              ),
            if (!play.submitted)
              ChunkyButton(
                label: l10n.node_check,
                onPressed: play.chosen == null ? null : actions.submit,
              )
            else ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  play.chosen == reveal.answer
                      ? l10n.node_right
                      : l10n.node_wrong(answer.label.of(language)),
                  style: AppText.titleSmall,
                ),
              ),
              const SizedBox(height: AppSpace.x3),
              ChunkyCard(
                child: CurvesBlock(
                  curves: view.curves,
                  invested: reveal.invested,
                  caption: _provenance(context, view.provenance),
                ),
              ),
              const SizedBox(height: AppSpace.x4),
              TermText(reveal.explanation.of(language), terms: view.terms),
              if (view.hasLiveVariant && online) ...[
                const SizedBox(height: AppSpace.x4),
                _LiveSection(nodeId: nodeId, invested: reveal.invested),
              ],
              const SizedBox(height: AppSpace.x6),
              LessonEnd(node: view.node),
            ],
          ],
        );
      },
    );
  }

  String _provenance(BuildContext context, Provenance p) {
    final period = p.from.year == p.to.year
        ? '${p.from.year}'
        : '${p.from.year}–${p.to.year}';
    return AppLocalizations.of(context).node_provenance(
      switch (p.interval) {
        '1day' => 'daily',
        '1week' => 'weekly',
        '1month' => 'monthly',
        _ => 'other',
      },
      period,
      p.currency,
    );
  }
}

/// « Et aujourd'hui ? »: a button, then the same curves on current prices.
class _LiveSection extends ConsumerStatefulWidget {
  const _LiveSection({required this.nodeId, required this.invested});
  final String nodeId;
  final Decimal? invested;

  @override
  ConsumerState<_LiveSection> createState() => _LiveSectionState();
}

class _LiveSectionState extends ConsumerState<_LiveSection> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!_open) {
      return OutlinedButton(
        onPressed: () => setState(() => _open = true),
        child: Text(l10n.node_today),
      );
    }
    final formats = Formats(Localizations.localeOf(context).languageCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.node_today, style: AppText.titleSmall),
        const SizedBox(height: AppSpace.x2),
        playerState(
          ref.watch(liveRevealProvider(widget.nodeId)),
          onRetry: () => ref.invalidate(liveRevealProvider(widget.nodeId)),
          data: (live) => ChunkyCard(
            child: CurvesBlock(
              curves: live.curves,
              invested: widget.invested,
              caption: l10n.node_today_caption(
                formats.date(live.from),
                formats.date(live.to),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Curves drawing in, a legend row each (end value and signed change), and
/// what they start from and where they come from.
class CurvesBlock extends StatelessWidget {
  const CurvesBlock({
    super.key,
    required this.curves,
    required this.invested,
    required this.caption,
  });

  final List<LessonCurve> curves;
  final Decimal? invested;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final formats = Formats(language);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.muted);
    String valueOf(Decimal v, String? currency) =>
        formatValue(formats, v, currency);

    final first = curves.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RevealChart(
          lines: [
            for (final (i, c) in curves.indexed)
              ChartLine([
                for (final (date, value) in c.points)
                  (date.millisecondsSinceEpoch.toDouble(), value.toDouble()),
              ], lineColors[i % lineColors.length]),
          ],
          semanticsLabel: l10n.node_chart_semantics(
            [
              for (final c in curves)
                l10n.node_chart_line(
                  c.label.of(language),
                  valueOf(c.points.first.$2, c.currency),
                  valueOf(c.points.last.$2, c.currency),
                ),
            ].join('; '),
          ),
        ),
        const SizedBox(height: AppSpace.x3),
        for (final (i, c) in curves.indexed)
          ChartLegendRow(
            color: lineColors[i % lineColors.length],
            label: c.label.of(language),
            value: valueOf(c.points.last.$2, c.currency),
            change: c.change == null
                ? null
                : formats.percent(c.change!, signed: true),
            changeColor: c.change == null
                ? null
                : signColor(c.change!, ratio: true),
          ),
        const SizedBox(height: AppSpace.x2),
        Text(
          invested == null
              ? l10n.node_base_100
              : l10n.node_invested(valueOf(invested!, first.currency)),
          style: muted,
        ),
        Text(caption, style: muted),
      ],
    );
  }
}
