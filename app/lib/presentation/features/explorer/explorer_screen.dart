import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/explorer/explorer.dart';
import '../../../core/failure.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/l10n/formats.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/chunky.dart';
import '../../../domain/market/asset.dart';
import '../../widgets/asset_avatar.dart';
import '../../widgets/cache_status_banner.dart';
import '../../widgets/risk_meter.dart';
import '../../widgets/section_title.dart';
import '../../widgets/sign_color.dart';

/// The catalogue: search, filters, favorites (BRIEF §4.9), the ETFs then
/// the stocks in flat cards, each under its title and what it is (artboard
/// Explore-A). With [walletId], as of that wallet's clock: a trip sees only
/// what existed on its day.
class ExplorerScreen extends ConsumerStatefulWidget {
  const ExplorerScreen({super.key, this.walletId});

  final String? walletId;

  @override
  ConsumerState<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends ConsumerState<ExplorerScreen> {
  final _search = TextEditingController();
  var _filter = ExplorerFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() => ref
      .refresh(explorerRowsProvider(widget.walletId).future)
      .then((_) {}, onError: (_) {});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = ref.watch(explorerRowsProvider(widget.walletId));
    final favorites = ref.watch(favoritesProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(
        leading: ChunkyBackButton.leadingOf(context),
        leadingWidth: ChunkyBackButton.width,
        title: Text(l10n.tab_explore),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screenPadding,
              AppSpace.x2,
              AppSpace.screenPadding,
              0,
            ),
            child: CacheStatusBanner(onRetry: _refresh),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.screenPadding),
            child: ChunkySearchField(
              controller: _search,
              hint: l10n.explorer_search_hint,
              onChanged: (_) => setState(() {}),
              onClear: _search.text.isEmpty
                  ? null
                  : () => setState(_search.clear),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.screenPadding,
            ),
            child: Row(
              children: [
                for (final (filter, label) in [
                  (ExplorerFilter.all, l10n.explorer_filter_all),
                  (ExplorerFilter.etfs, l10n.explorer_filter_etfs),
                  (ExplorerFilter.stocks, l10n.explorer_filter_stocks),
                  (ExplorerFilter.favorites, l10n.explorer_filter_favorites),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpace.x2),
                    child: ChunkyChip(
                      label: label,
                      selected: _filter == filter,
                      onTap: () => setState(() => _filter = filter),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.x2),
          Expanded(
            child: switch (rows) {
              AsyncValue(value: final all?) => _List(
                rows: filterRows(
                  all,
                  query: _search.text,
                  filter: _filter,
                  favorites: favorites,
                ),
                favorites: favorites,
                walletId: widget.walletId,
                empty:
                    _filter == ExplorerFilter.favorites &&
                        _search.text.trim().isEmpty
                    ? l10n.explorer_no_favorites
                    : l10n.explorer_no_match(_search.text.trim()),
                onRefresh: _refresh,
              ),
              AsyncValue(error: final error?) => Center(
                child: ErrorView(
                  failure: error is Failure ? error : const ServerFailure(),
                  onRetry: () =>
                      ref.invalidate(explorerRowsProvider(widget.walletId)),
                ),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(AppSpace.screenPadding),
                child: AsyncSkeleton(lines: 8),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({
    required this.rows,
    required this.favorites,
    required this.walletId,
    required this.empty,
    required this.onRefresh,
  });

  final List<ExplorerRow> rows;
  final Set<String> favorites;
  final String? walletId;
  final String empty;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.screenPadding),
        child: Text(
          empty,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.muted),
        ),
      );
    }
    final l10n = AppLocalizations.of(context);
    // The flat card's look, around rows built as they scroll in.
    final card = ShapeDecoration(
      color: AppColors.surface,
      shape: Theme.of(context).cardTheme.shape!,
    );
    const corner = Radius.circular(AppShape.flatCardRadius);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screenPadding,
              0,
              AppSpace.screenPadding,
              AppSpace.screenPadding,
            ),
            sliver: SliverMainAxisGroup(
              slivers: [
                for (final (i, (type, group)) in groupRows(rows).indexed) ...[
                  SliverToBoxAdapter(
                    child: switch (type) {
                      AssetType.etf => SectionTitle(
                        l10n.explorer_filter_etfs,
                        line: l10n.explorer_etfs_line,
                        top: i == 0 ? AppSpace.x2 : AppSpace.x4,
                      ),
                      AssetType.stock => SectionTitle(
                        l10n.explorer_filter_stocks,
                        line: l10n.explorer_stocks_line,
                        top: i == 0 ? AppSpace.x2 : AppSpace.x4,
                      ),
                    },
                  ),
                  DecoratedSliver(
                    decoration: card,
                    sliver: SliverList.separated(
                      itemCount: group.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, j) => _Row(
                        group[j],
                        favorite: favorites.contains(group[j].asset.id),
                        walletId: walletId,
                        corners: BorderRadius.vertical(
                          top: j == 0 ? corner : Radius.zero,
                          bottom: j == group.length - 1 ? corner : Radius.zero,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row(
    this.row, {
    required this.favorite,
    required this.walletId,
    required this.corners,
  });

  final ExplorerRow row;
  final bool favorite;
  final String? walletId;

  /// The card's rounded corners this row sits in, so its ink keeps to them.
  final BorderRadius corners;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final formats = Formats(Localizations.localeOf(context).languageCode);
    final text = Theme.of(context).textTheme;
    final asset = row.asset;
    final price = row.price;
    final change = row.yearChange;
    final region = switch (asset.region) {
      'world' => l10n.region_world,
      'us' => l10n.region_us,
      'europe' => l10n.region_europe,
      'emerging' => l10n.region_emerging,
      final other => other,
    };

    // Its own see-through material: the card is painted under the list, so
    // ink drawn on the screen's material would be hidden by it.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: corners,
        onTap: () => context.push(
          '/asset/${asset.id}${walletId == null ? '' : '?wallet=$walletId'}',
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.only(left: AppSpace.x4, right: AppSpace.x1),
          child: Row(
            children: [
              AssetAvatar(asset),
              const SizedBox(width: AppSpace.x3),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.x2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asset.name,
                        style: text.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: AppSpace.x2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            region,
                            style: text.bodySmall?.copyWith(
                              color: AppColors.muted,
                            ),
                          ),
                          RiskMeter(row.riskBand),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (price != null)
                    Text(
                      formats.price(price),
                      style: AppText.figure.copyWith(color: AppColors.ink),
                    ),
                  if (change != null)
                    Text(
                      l10n.explorer_year_change(
                        formats.percent(change, signed: true),
                      ),
                      style: text.bodySmall?.copyWith(
                        color: signColor(change, ratio: true),
                      ),
                    ),
                ],
              ),
              IconButton(
                tooltip: favorite
                    ? l10n.explorer_favorite_remove
                    : l10n.explorer_favorite_add,
                isSelected: favorite,
                icon: const Icon(Icons.star_border, color: AppColors.muted),
                selectedIcon: const Icon(Icons.star, color: AppColors.ink),
                onPressed: () =>
                    ref.read(favoritesProvider.notifier).toggle(asset.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
