import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/glossary.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/learning/glossary.dart';
import '../../widgets/search_title.dart';
import 'term_sheet.dart';

/// The glossary tab (BRIEF §4.4, artboard Glossary-A): how many notions
/// were discovered, search, « Toutes / Découvertes / À découvrir », the
/// terms by letter with where each stands; a term opens its sheet. A
/// collection of notions, not money, so a world screen: chunky cards (§10.1,
/// M11-2). One scroll, so the list keeps the room on a small phone.
class GlossaryScreen extends ConsumerWidget {
  const GlossaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final search = ref.watch(glossarySearchProvider);
    final index = ref.watch(glossaryIndexProvider(language));
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: AppColors.muted);
    Widget note(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpace.x8),
      child: Text(text, style: muted, textAlign: TextAlign.center),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpace.screenPadding,
        title: SearchTitle(
          title: l10n.tab_glossary,
          hint: l10n.glossary_search,
          query: search.query,
          onChanged: ref.read(glossarySearchProvider.notifier).setQuery,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screenPadding,
          AppSpace.x2,
          AppSpace.screenPadding,
          AppSpace.x6,
        ),
        children: [
          if (index.value case final i? when i.total > 0) ...[
            _Discovered(discovered: i.discovered, total: i.total),
            const SizedBox(height: AppSpace.x4),
          ],
          ChunkySegmented(
            segments: [
              (GlossaryFilter.all, l10n.glossary_filter_all),
              (GlossaryFilter.discovered, l10n.glossary_filter_discovered),
              (GlossaryFilter.toDiscover, l10n.glossary_filter_to_discover),
            ],
            selected: search.filter,
            onChanged: ref.read(glossarySearchProvider.notifier).setFilter,
          ),
          ...switch (index) {
            AsyncValue(:final value?) when value.total == 0 => [
              note(l10n.glossary_none_yet),
            ],
            AsyncValue(:final value?) when value.isEmpty => [
              note(l10n.glossary_no_match),
            ],
            AsyncValue(:final value?) => [
              for (final (letter, rows) in value.groups) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpace.x4,
                    bottom: AppSpace.x2,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      letter,
                      style: AppText.titleSmall.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                ChunkyCard(
                  padding: EdgeInsets.zero,
                  // The rows' ink stays inside the card's rounded border.
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppShape.chunkyCardRadius - AppShape.chunkyBorder,
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, row) in rows.indexed) ...[
                            if (i > 0) const Divider(height: 1),
                            _TermRow(row),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
            AsyncValue(:final error?) => [
              ErrorView(
                failure: error is Failure ? error : const ServerFailure(),
                onRetry: () => ref.invalidate(glossaryIndexProvider(language)),
              ),
            ],
            _ => [
              const SizedBox(height: AppSpace.x4),
              const AsyncSkeleton(lines: 6),
            ],
          },
        ],
      ),
    );
  }
}

/// « n notions découvertes sur m » in a chunky card, over a bar in the
/// levels' yellow outlined in ink, like a lesson path's.
class _Discovered extends StatelessWidget {
  const _Discovered({required this.discovered, required this.total});
  final int discovered;
  final int total;

  @override
  Widget build(BuildContext context) => ChunkyCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppLocalizations.of(context).glossary_progress(discovered, total),
          style: AppText.titleSmall,
        ),
        const SizedBox(height: AppSpace.x3),
        // The line above says it.
        ExcludeSemantics(
          child: Container(
            height: 14,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: AppColors.ink,
                width: AppShape.chunkySmallBorder,
              ),
            ),
            // A pill, its right end as round as the bar (M13-22).
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: discovered / total,
              child: const DecoratedBox(
                key: ValueKey('discovered-fill'),
                decoration: BoxDecoration(
                  color: AppColors.progress,
                  borderRadius: BorderRadius.all(
                    Radius.circular(7 - AppShape.chunkySmallBorder),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// A term: its title and one-line definition, then ✓ once discovered,
/// « Nouvelle » once met, « À découvrir » before.
class _TermRow extends StatelessWidget {
  const _TermRow(this.row);
  final GlossaryRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final title = row.term.title.of(language);
    final status = switch (row.status) {
      TermStatus.discovered => l10n.glossary_status_discovered,
      TermStatus.met => l10n.glossary_status_new,
      TermStatus.toDiscover => l10n.glossary_status_to_discover,
    };
    return Semantics(
      button: true,
      label: l10n.glossary_row_semantics(title, status),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showTermSheet(context, row.term.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.x4,
              vertical: AppSpace.x2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.titleXSmall),
                      Text(
                        row.term.short.of(language),
                        style: AppText.caption.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.x3),
                switch (row.status) {
                  TermStatus.discovered => Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.line,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.ink, width: 2),
                    ),
                    child: const Icon(
                      Icons.check,
                      size: AppSpace.x4,
                      color: AppColors.ink,
                    ),
                  ),
                  TermStatus.met => NotionBadge(l10n.glossary_new),
                  TermStatus.toDiscover => Text(
                    l10n.glossary_filter_to_discover,
                    style: AppText.label.copyWith(color: AppColors.muted),
                  ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}
