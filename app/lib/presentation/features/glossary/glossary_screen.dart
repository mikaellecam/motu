import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/learning/glossary.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../domain/learning/glossary.dart';
import 'term_sheet.dart';

/// The glossary tab (BRIEF §4.4): search, « Toutes / Découvertes / À
/// découvrir », the terms by letter with where each stands; a term opens
/// its sheet.
class GlossaryScreen extends ConsumerWidget {
  const GlossaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final search = ref.watch(glossarySearchProvider);
    final actions = ref.read(glossarySearchProvider.notifier);
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: AppColors.muted);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tab_glossary)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screenPadding,
              AppSpace.x2,
              AppSpace.screenPadding,
              AppSpace.x2,
            ),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.glossary_search,
              ),
              onChanged: actions.setQuery,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.screenPadding,
            ),
            child: SegmentedButton<GlossaryFilter>(
              showSelectedIcon: false,
              segments: [
                for (final (filter, label) in [
                  (GlossaryFilter.all, l10n.glossary_filter_all),
                  (GlossaryFilter.discovered, l10n.glossary_filter_discovered),
                  (GlossaryFilter.toDiscover, l10n.glossary_filter_to_discover),
                ])
                  ButtonSegment(value: filter, label: Text(label)),
              ],
              selected: {search.filter},
              onSelectionChanged: (selected) =>
                  actions.setFilter(selected.first),
            ),
          ),
          const SizedBox(height: AppSpace.x2),
          Expanded(
            child: switch (ref.watch(glossaryIndexProvider(language))) {
              AsyncValue(:final value?) when value.total == 0 => Center(
                child: Text(l10n.glossary_none_yet, style: muted),
              ),
              AsyncValue(:final value?) when value.isEmpty => Center(
                child: Text(l10n.glossary_no_match, style: muted),
              ),
              AsyncValue(:final value?) => ListView(
                padding: const EdgeInsets.only(bottom: AppSpace.x6),
                children: [
                  for (final (letter, rows) in value.groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.screenPadding,
                        AppSpace.x4,
                        AppSpace.screenPadding,
                        AppSpace.x1,
                      ),
                      child: Semantics(
                        header: true,
                        child: Text(letter, style: AppText.titleSmall),
                      ),
                    ),
                    for (final row in rows) _TermRow(row),
                  ],
                ],
              ),
              AsyncValue(:final error?) => Center(
                child: ErrorView(
                  failure: error is Failure ? error : const ServerFailure(),
                  onRetry: () =>
                      ref.invalidate(glossaryIndexProvider(language)),
                ),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(AppSpace.screenPadding),
                child: AsyncSkeleton(lines: 6),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// A term: its title and one-line definition, then ✓ once discovered or
/// « Nouvelle » once met.
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
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.screenPadding,
              vertical: AppSpace.x2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.bodyStrong),
                      Text(
                        row.term.short.of(language),
                        style: AppText.caption.copyWith(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.x2),
                switch (row.status) {
                  TermStatus.discovered => const Icon(
                    Icons.check_circle,
                    color: AppColors.ink,
                  ),
                  TermStatus.met => Chip(
                    label: Text(l10n.glossary_new),
                    backgroundColor: AppColors.progress,
                    visualDensity: VisualDensity.compact,
                  ),
                  TermStatus.toDiscover => const SizedBox.shrink(),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }
}
