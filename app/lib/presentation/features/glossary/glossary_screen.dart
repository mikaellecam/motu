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
        title: _SearchTitle(title: l10n.tab_glossary, query: search.query),
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
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: discovered / total,
              child: const ColoredBox(color: AppColors.progress),
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

/// The title bar's search, folded into its magnifier at the right of the
/// title (M13-16, decided 2026-11-17): touched, the box slides open leftward
/// across the bar, focused; its ✕ clears the search and folds it back. A
/// search still typed keeps it open. At once with reduced motion.
class _SearchTitle extends ConsumerStatefulWidget {
  const _SearchTitle({required this.title, required this.query});

  final String title;
  final String query;

  @override
  ConsumerState<_SearchTitle> createState() => _SearchTitleState();
}

class _SearchTitleState extends ConsumerState<_SearchTitle> {
  // Its text comes from the search, so it survives the tab being left.
  late final _text = TextEditingController(text: widget.query);
  final _focus = FocusNode();
  late bool _open = widget.query.isNotEmpty;

  /// The folded box: the magnifier inside the block's border.
  static const _folded = 48 + 2 * AppShape.chunkyBorder;
  static const _height = AppSpace.minTarget + 2 * AppShape.chunkyBorder;
  static const _unfold = Duration(milliseconds: 280);

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _unfoldIt() {
    setState(() => _open = true);
    _focus.requestFocus();
  }

  void _foldIt() {
    _text.clear();
    ref.read(glossarySearchProvider.notifier).setQuery('');
    _focus.unfocus();
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : _unfold;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The bar's width: the toolbar keeps the screen's margin at its end.
        final full = constraints.maxWidth;
        return SizedBox(
          width: constraints.maxWidth,
          height: _height + AppShape.chunkyButtonShadow,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedOpacity(
                opacity: _open ? 0 : 1,
                duration: duration,
                child: ExcludeSemantics(
                  excluding: _open,
                  child: Text(widget.title),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: _open ? full : _folded,
                  height: _height,
                  decoration: ChunkySearchField.box,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppShape.chunkyButtonRadius - AppShape.chunkyBorder,
                    ),
                    child: _open
                        ? OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: full - 2 * AppShape.chunkyBorder,
                            maxWidth: full - 2 * AppShape.chunkyBorder,
                            child: ChunkySearchField(
                              controller: _text,
                              focusNode: _focus,
                              hint: l10n.glossary_search,
                              onChanged: ref
                                  .read(glossarySearchProvider.notifier)
                                  .setQuery,
                              onClear: _foldIt,
                              boxed: false,
                            ),
                          )
                        : Semantics(
                            container: true,
                            button: true,
                            label: l10n.glossary_search,
                            excludeSemantics: true,
                            child: InkWell(
                              onTap: _unfoldIt,
                              child: const Center(
                                child: Icon(Icons.search, color: AppColors.ink),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
