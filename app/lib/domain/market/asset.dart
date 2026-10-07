import '../../core/money/money.dart';
import 'market_calendar.dart';

enum AssetType { etf, stock }

/// An instrument of the catalogue (BRIEF §6.1, §8.4).
final class Asset {
  const Asset({
    required this.id,
    required this.symbol,
    required this.name,
    required this.type,
    required this.exchange,
    required this.currency,
    required this.region,
    required this.listingDate,
  });

  final String id;
  final String symbol;
  final String name;
  final AssetType type;
  final Exchange exchange;

  /// Quote currency.
  final Currency currency;

  /// One region per asset, a catalogue code (`europe`, `us`, `world`…).
  final String region;

  /// Hidden from trips that start before it (no lookahead).
  final DateTime listingDate;
}
