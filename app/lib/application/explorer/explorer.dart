import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/clock/simulation_clock.dart';
import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../domain/analytics/returns.dart';
import '../../domain/analytics/risk.dart';
import '../../domain/analytics/volatility.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/price_bar.dart';
import '../../domain/market/quote.dart';
import '../../domain/wallet/wallet.dart';
import '../providers.dart';
import '../wallet/wallet_providers.dart' show liveQuotes;

part 'explorer.g.dart';

/// One row of the Explorer (BRIEF §4.9).
final class ExplorerRow {
  const ExplorerRow({
    required this.asset,
    required this.price,
    required this.yearChange,
    required this.riskBand,
    this.volatility,
  });

  final Asset asset;

  /// The live quote, or the last close on or before the clock's day; null
  /// when neither is known.
  final Price? price;

  /// Change over one year to [price]; null without a close a year back.
  final Decimal? yearChange;

  /// 1 to 5 from the 1-year volatility (BRIEF §7.8); null under 20 returns.
  final int? riskBand;

  /// Annualised volatility over the last year; null under 20 returns.
  final Decimal? volatility;
}

/// The row of [asset] at [asOf], from its [bars] (the last year and a bit,
/// none after [asOf]) and, for the live wallet, its [quote].
ExplorerRow explorerRow(
  Asset asset, {
  required List<PriceBar> bars,
  Quote? quote,
  required DateTime asOf,
}) {
  final utc = asOf.toUtc();
  final day = DateTime.utc(utc.year, utc.month, utc.day);
  final yearAgo = yearBefore(day);
  final known = [
    for (final b in bars)
      if (!b.date.isAfter(day)) b,
  ];
  PriceBar? reference;
  for (final b in known) {
    if (!b.date.isAfter(yearAgo)) reference = b;
  }
  final price =
      quote?.price ??
      (known.isEmpty ? null : Price(known.last.close, known.last.currency));
  final volatility = annualisedVolatility([
    for (final b in known)
      if (b.date.isAfter(yearAgo)) b.close,
  ]);
  return ExplorerRow(
    asset: asset,
    price: price,
    yearChange: price == null || reference == null
        ? null
        : simpleReturn(reference.close, price.value),
    riskBand: riskBand(volatility),
    volatility: volatility,
  );
}

/// The same day a year earlier; 28 February for 29 February.
DateTime yearBefore(DateTime day) => DateTime.utc(
  day.year - 1,
  day.month,
  day.month == 2 && day.day == 29 ? 28 : day.day,
);

enum ExplorerFilter { all, etfs, stocks, favorites }

/// The rows matching [query] (name or ticker; case, accents, spaces and
/// punctuation ignored) and [filter].
List<ExplorerRow> filterRows(
  List<ExplorerRow> rows, {
  required String query,
  required ExplorerFilter filter,
  required Set<String> favorites,
}) {
  final q = searchKey(query);
  return [
    for (final row in rows)
      if (switch (filter) {
            ExplorerFilter.all => true,
            ExplorerFilter.etfs => row.asset.type == AssetType.etf,
            ExplorerFilter.stocks => row.asset.type == AssetType.stock,
            ExplorerFilter.favorites => favorites.contains(row.asset.id),
          } &&
          (searchKey(row.asset.name).contains(q) ||
              searchKey(row.asset.symbol).contains(q)))
        row,
  ];
}

/// [rows] in two groups, ETFs then stocks, each in the order given; a group
/// with no row is left out (artboard Explore-A).
List<(AssetType, List<ExplorerRow>)> groupRows(List<ExplorerRow> rows) => [
  for (final type in const [AssetType.etf, AssetType.stock])
    (type, rows.where((row) => row.asset.type == type).toList()),
]..removeWhere((group) => group.$2.isEmpty);

/// Lower case, accents folded, letters and digits only: « L'Oréal » and
/// "loreal" give the same key.
String searchKey(String text) {
  const folds = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', //
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
    'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i', //
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', //
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', //
    'ç': 'c', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae', 'ÿ': 'y',
  };
  final out = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    final folded = folds[char] ?? char;
    if (RegExp(r'^[a-z0-9]+$').hasMatch(folded)) out.write(folded);
  }
  return out.toString();
}

/// The catalogue as of the clock of [walletId] (the live wallet's when
/// null), sorted by name. In a trip, assets listed after its day are left
/// out and every value is as of that day (BRIEF §4.9).
@riverpod
Future<List<ExplorerRow>> explorerRows(Ref ref, String? walletId) async {
  final market = ref.watch(marketRepositoryProvider);
  final wallets = ref.watch(walletRepositoryProvider);
  var asOf = ref.watch(liveClockProvider).now();
  var live = true;
  if (walletId != null) {
    final wallet = await wallets.load(walletId);
    if (wallet.kind == WalletKind.trip) {
      asOf = HistoricalClock(wallet.simDate!).now();
      live = false;
    }
  }
  final assets = await market.assets(asOf: asOf)
    ..sort((a, b) => searchKey(a.name).compareTo(searchKey(b.name)));
  final quotes = live
      ? await liveQuotes(market, [for (final a in assets) a.id], asOf: asOf)
      : const <String, Quote>{};
  final from = yearBefore(DateTime.utc(asOf.year, asOf.month, asOf.day))
      .subtract(const Duration(days: 10));

  // One asset whose history cannot be read (offline, never cached) keeps its
  // row without figures; the list fails only when no row has any.
  Failure? failure;
  final rows = await Future.wait([
    for (final asset in assets)
      market
          .history(asset.id, from: from, to: asOf, asOf: asOf)
          .then(
            (bars) => explorerRow(
              asset,
              bars: bars,
              quote: quotes[asset.id],
              asOf: asOf,
            ),
          )
          .onError<Failure>((error, _) {
            failure = error;
            return explorerRow(
              asset,
              bars: const [],
              quote: quotes[asset.id],
              asOf: asOf,
            );
          }),
  ]);
  if (failure != null && rows.every((r) => r.price == null)) throw failure!;
  return rows;
}

/// The starred asset ids, kept on the device.
@riverpod
class Favorites extends _$Favorites {
  @override
  Stream<Set<String>> build() => ref.watch(favoritesRepositoryProvider).watch();

  Future<void> toggle(String assetId) => ref
      .read(favoritesRepositoryProvider)
      .toggle(assetId, ref.read(liveClockProvider).now());
}
