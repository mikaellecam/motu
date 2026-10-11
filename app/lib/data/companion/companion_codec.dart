import 'dart:convert';

import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../domain/companion/rules.dart';

/// JSON for what the companion keeps between trip days (`wallets.
/// companionState`) and for the values a moment's copy needs
/// (`companion_log.params`). Decimals and prices stay exact strings.

String encodeTracker(CompanionTracker t) => jsonEncode({
  'peaks': {for (final e in t.peaks.entries) e.key: _price(e.value)},
  'index': '${t.index}',
  'indexPeak': '${t.indexPeak}',
  'previousValue': t.previousValue?.toString(),
  'cashHighSince': t.cashHighSince == null ? null : _day(t.cashHighSince!),
  'recentPnl': {
    for (final e in t.recentPnl.entries) e.key: [for (final v in e.value) '$v'],
  },
  'usdRates': [
    for (final (date, rate) in t.usdRates) [_day(date), '$rate'],
  ],
  'followUps': {
    for (final e in t.followUps.entries)
      e.key: {
        'assetId': e.value.assetId,
        'sellPrice': _price(e.value.sellPrice),
        'due': _day(e.value.due),
      },
  },
});

CompanionTracker decodeTracker(String json) {
  final m = jsonDecode(json) as Map<String, dynamic>;
  return CompanionTracker.restore(
    peaks: {
      for (final e in (m['peaks'] as Map).entries)
        e.key as String: _readPrice(e.value as Map),
    },
    index: Decimal.parse(m['index'] as String),
    indexPeak: Decimal.parse(m['indexPeak'] as String),
    previousValue: switch (m['previousValue']) {
      final String v => Decimal.parse(v),
      _ => null,
    },
    cashHighSince: switch (m['cashHighSince']) {
      final String d => _readDay(d),
      _ => null,
    },
    recentPnl: {
      for (final e in (m['recentPnl'] as Map).entries)
        e.key as String: [
          for (final v in e.value as List) Decimal.parse(v as String),
        ],
    },
    usdRates: [
      for (final r in m['usdRates'] as List)
        (_readDay(r[0] as String), Decimal.parse(r[1] as String)),
    ],
    followUps: {
      for (final e in (m['followUps'] as Map).entries)
        e.key as String: FollowUp(
          e.value['assetId'] as String,
          _readPrice(e.value['sellPrice'] as Map),
          _readDay(e.value['due'] as String),
        ),
    },
  );
}

/// A moment's params: strings as they are, decimals and prices tagged.
String encodeParams(Map<String, Object> params) => jsonEncode({
  for (final e in params.entries)
    e.key: switch (e.value) {
      final String s => s,
      final Decimal d => {'decimal': '$d'},
      final Price p => _price(p),
      final other => throw ArgumentError.value(other, e.key, 'not storable'),
    },
});

Map<String, Object> decodeParams(String json) => {
  for (final e in (jsonDecode(json) as Map<String, dynamic>).entries)
    e.key: switch (e.value) {
      final String s => s,
      {'decimal': final String d} => Decimal.parse(d),
      final Map p => _readPrice(p),
      final other => throw FormatException('param ${e.key}: $other'),
    },
};

Map<String, String> _price(Price p) => {
  'price': '${p.value}',
  'currency': p.currency.code,
};

Price _readPrice(Map m) => Price(
  Decimal.parse(m['price'] as String),
  Currency.values.firstWhere((c) => c.code == m['currency']),
);

String _day(DateTime d) => d.toIso8601String().substring(0, 10);

DateTime _readDay(String s) => DateTime.parse('${s}T00:00:00Z');
