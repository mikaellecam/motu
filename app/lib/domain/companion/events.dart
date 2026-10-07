import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';

/// What the companion sees of a wallet at the end of a day (BRIEF §4.12).
/// Built by whoever values the wallet: the trip engine, or the live wallet.
final class DaySnapshot {
  const DaySnapshot({
    required this.date,
    required this.value,
    required this.flow,
    required this.cashWeight,
    required this.holdings,
    required this.sells,
    required this.usdRate,
    required this.priceOf,
  });

  final DateTime date;

  /// Wallet value in EUR, and the external flow (contribution) of the day.
  final Decimal value;
  final Decimal flow;

  /// Cash share of the wallet value.
  final Decimal cashWeight;

  /// Open positions.
  final List<HoldingFacts> holdings;

  /// Sells executed that day.
  final List<SellFact> sells;

  /// EUR per USD that day; null when unknown.
  final Decimal? usdRate;

  /// The latest price of any asset, held or not (for follow-ups); null when
  /// unknown.
  final Price? Function(String assetId) priceOf;
}

final class HoldingFacts {
  const HoldingFacts({
    required this.assetId,
    required this.price,
    required this.weight,
    required this.pnlRatio,
  });

  final String assetId;
  final Price price;

  /// Share of the wallet value.
  final Decimal weight;

  /// Unrealised P&L over cost basis; null when the cost basis is zero.
  final Decimal? pnlRatio;
}

final class SellFact {
  const SellFact(this.assetId, this.price);
  final String assetId;
  final Price price;
}
