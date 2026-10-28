import 'package:decimal/decimal.dart';

import '../analytics/volatility.dart';
import 'content.dart';

/// A `sort` node (BRIEF §4.3): items to put in order on a scale, then their
/// real values. V1 ranks by annualised volatility.
final class SortNode {
  const SortNode({
    required this.prompt,
    required this.low,
    required this.high,
    required this.items,
    required this.explanation,
  });

  final Localized prompt;

  /// What the top and the bottom of the scale mean (« Moins risqué »…).
  final Localized low;
  final Localized high;

  /// In the order they are first shown.
  final List<SortItem> items;
  final Localized explanation;
}

/// An item: the volatility of its daily [dataset], or a fixed [value] (a
/// Livret moves by no price: 0).
final class SortItem {
  const SortItem(
    this.id,
    this.label, {
    this.dataset,
    this.value,
    this.livret = false,
  });
  final String id;
  final Localized label;
  final String? dataset;
  final Decimal? value;

  /// The Livret A at the rate of the day (M12-4), never a number in the pack.
  final bool livret;
}

/// The item's real value: its fixed one, the Livret A's [livretRate], or the
/// annualised volatility of [points] (BRIEF §7.7); null when too short a
/// history, or no rate.
Decimal? itemValue(
  SortItem item, [
  List<(DateTime, Decimal)>? points,
  Decimal? livretRate,
]) =>
    item.value ??
    (item.livret
        ? livretRate
        : points == null
        ? null
        : annualisedVolatility([for (final (_, close) in points) close]));

/// The ids from the lowest value to the highest; equal values keep the order
/// of [ids].
List<String> trueOrder(List<String> ids, Map<String, Decimal> values) {
  final indexed = [...ids.indexed];
  indexed.sort((a, b) {
    final byValue = values[a.$2]!.compareTo(values[b.$2]!);
    return byValue != 0 ? byValue : a.$1.compareTo(b.$1);
  });
  return [for (final (_, id) in indexed) id];
}

/// How many items of [order] sit at their rank in [truth].
int wellPlaced(List<String> order, List<String> truth) => [
  for (var i = 0; i < order.length && i < truth.length; i++)
    if (order[i] == truth[i]) i,
].length;
