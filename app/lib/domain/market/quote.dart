import '../../core/money/money.dart';

/// The latest price of an asset in the live wallet: a live quote while the
/// market is open, else the last close.
final class Quote {
  const Quote(this.price, this.asOf, {required this.marketOpen});

  final Price price;

  /// When the price was observed, UTC.
  final DateTime asOf;
  final bool marketOpen;
}
