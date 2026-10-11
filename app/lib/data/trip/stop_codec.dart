import 'dart:convert';

import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../domain/wallet/trip_engine.dart';

/// JSON for why a trip stopped by itself (`wallets.stopReasons`).
String encodeStops(List<StopReason> reasons) => jsonEncode([
  for (final r in reasons)
    switch (r) {
      DrawdownStop(:final value, :final threshold) => {
        'kind': 'drawdown',
        'valueCents': value.minorUnits,
        'thresholdCents': threshold.minorUnits,
      },
      PositionLossStop(:final assetId, :final loss) => {
        'kind': 'position',
        'assetId': assetId,
        'loss': '$loss',
      },
      OrderFilledStop(:final orderId) => {'kind': 'order', 'orderId': orderId},
      ContributionStop(:final amount) => {
        'kind': 'contribution',
        'amountCents': amount.minorUnits,
      },
    },
]);

List<StopReason> decodeStops(String json) => [
  for (final r in (jsonDecode(json) as List).cast<Map<String, dynamic>>())
    switch (r['kind']) {
      'drawdown' => DrawdownStop(
        value: Money(r['valueCents'] as int, Currency.eur),
        threshold: Money(r['thresholdCents'] as int, Currency.eur),
      ),
      'position' => PositionLossStop(
        r['assetId'] as String,
        Decimal.parse(r['loss'] as String),
      ),
      'order' => OrderFilledStop(r['orderId'] as String),
      'contribution' => ContributionStop(
        Money(r['amountCents'] as int, Currency.eur),
      ),
      final kind => throw FormatException('unknown stop: $kind'),
    },
];
