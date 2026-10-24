import 'package:decimal/decimal.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../core/money/money.dart';
import '../../domain/livret/livret_interest.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/market_calendar.dart';
import '../../domain/market/price_bar.dart';

part 'dto.g.dart';

// JSON shapes of the backend (BRIEF §8.3) and of Frankfurter. Prices and
// rates arrive as decimal strings and never pass through a double; dates
// (YYYY-MM-DD) become `DateTime.utc(y, m, d)`.

class DayConverter implements JsonConverter<DateTime, String> {
  const DayConverter();

  @override
  DateTime fromJson(String json) {
    final d = DateTime.parse(json);
    return DateTime.utc(d.year, d.month, d.day);
  }

  @override
  String toJson(DateTime day) => day.toIso8601String().substring(0, 10);
}

/// RFC 3339 instants, for the fields that are not days.
class InstantConverter implements JsonConverter<DateTime, String> {
  const InstantConverter();

  @override
  DateTime fromJson(String json) => DateTime.parse(json).toUtc();

  @override
  String toJson(DateTime instant) => instant.toUtc().toIso8601String();
}

/// `13:00`: a local time of day, as (hour, minute).
class TimeOfDayConverter implements JsonConverter<(int, int), String> {
  const TimeOfDayConverter();

  @override
  (int, int) fromJson(String json) {
    final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(json);
    if (m == null) throw FormatException('not a time of day: $json');
    return (int.parse(m[1]!), int.parse(m[2]!));
  }

  @override
  String toJson((int, int) time) =>
      '${time.$1.toString().padLeft(2, '0')}:${time.$2.toString().padLeft(2, '0')}';
}

class DecimalConverter implements JsonConverter<Decimal, String> {
  const DecimalConverter();

  @override
  Decimal fromJson(String json) => Decimal.parse(json);

  @override
  String toJson(Decimal value) => value.toString();
}

/// `USD`, `EUR`.
class CurrencyConverter implements JsonConverter<Currency, String> {
  const CurrencyConverter();

  @override
  Currency fromJson(String json) =>
      Currency.values.firstWhere((c) => c.code == json);

  @override
  String toJson(Currency currency) => currency.code;
}

const _decode = JsonSerializable(
  createToJson: false,
  converters: [DayConverter(), DecimalConverter(), CurrencyConverter()],
);

@_decode
class AssetDto {
  const AssetDto({
    required this.id,
    required this.symbol,
    required this.name,
    required this.type,
    required this.exchange,
    required this.currency,
    required this.region,
    required this.listingDate,
  });

  factory AssetDto.fromJson(Map<String, dynamic> json) =>
      _$AssetDtoFromJson(json);

  final String id;
  final String symbol;
  final String name;
  final AssetType type;
  final Exchange exchange;
  final Currency currency;
  final String region;
  final DateTime listingDate;

  Asset toDomain() => Asset(
    id: id,
    symbol: symbol,
    name: name,
    type: type,
    exchange: exchange,
    currency: currency,
    region: region,
    listingDate: listingDate,
  );
}

@_decode
class BarDto {
  const BarDto({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory BarDto.fromJson(Map<String, dynamic> json) => _$BarDtoFromJson(json);

  final DateTime date;
  final Decimal open;
  final Decimal high;
  final Decimal low;
  final Decimal close;
  final int volume;
}

/// Adjusted daily bars of one asset, oldest first.
@_decode
class HistoryDto {
  const HistoryDto({
    required this.assetId,
    required this.currency,
    required this.adjustedAt,
    required this.bars,
  });

  factory HistoryDto.fromJson(Map<String, dynamic> json) =>
      _$HistoryDtoFromJson(json);

  final String assetId;
  final Currency currency;

  /// The backend's last full refetch after a dividend or split; when it
  /// moves, the cached history of the asset is dropped (BRIEF §6.2).
  @InstantConverter()
  final DateTime? adjustedAt;
  final List<BarDto> bars;

  List<PriceBar> toDomain() => [
    for (final b in bars)
      PriceBar(
        date: b.date,
        open: b.open,
        high: b.high,
        low: b.low,
        close: b.close,
        volume: b.volume,
        currency: currency,
      ),
  ];
}

/// The live quote, or the last close when the market is shut.
@_decode
class QuoteDto {
  const QuoteDto({
    required this.assetId,
    required this.price,
    required this.currency,
    required this.asOf,
    required this.marketOpen,
  });

  factory QuoteDto.fromJson(Map<String, dynamic> json) =>
      _$QuoteDtoFromJson(json);

  final String assetId;
  final Decimal price;
  final Currency currency;

  /// When the price was observed, UTC.
  @InstantConverter()
  final DateTime asOf;
  final bool marketOpen;
}

@_decode
class LivretRateDto {
  const LivretRateDto({required this.validFrom, required this.annualRate});

  factory LivretRateDto.fromJson(Map<String, dynamic> json) =>
      _$LivretRateDtoFromJson(json);

  final DateTime validFrom;
  final Decimal annualRate;
}

@_decode
class LivretCeilingDto {
  const LivretCeilingDto({required this.validFrom, required this.amountCents});

  factory LivretCeilingDto.fromJson(Map<String, dynamic> json) =>
      _$LivretCeilingDtoFromJson(json);

  final DateTime validFrom;
  final int amountCents;
}

@_decode
class LivretDto {
  const LivretDto({required this.rates, required this.ceilings});

  factory LivretDto.fromJson(Map<String, dynamic> json) =>
      _$LivretDtoFromJson(json);

  final List<LivretRateDto> rates;
  final List<LivretCeilingDto> ceilings;

  List<LivretRate> toRates() => [
    for (final r in rates) LivretRate(r.validFrom, r.annualRate),
  ];

  List<LivretCeiling> toCeilings() => [
    for (final c in ceilings)
      LivretCeiling(c.validFrom, Money(c.amountCents, Currency.eur)),
  ];
}

/// The weekdays without a session in one year, and the sessions that close
/// early; every other weekday trades regular hours.
@_decode
class CalendarDto {
  const CalendarDto({
    required this.exchange,
    required this.year,
    required this.holidays,
    required this.earlyCloses,
  });

  factory CalendarDto.fromJson(Map<String, dynamic> json) =>
      _$CalendarDtoFromJson(json);

  final Exchange exchange;
  final int year;
  final List<DateTime> holidays;

  /// Absent from a backend older than M9-37.
  @JsonKey(defaultValue: <EarlyCloseDto>[])
  final List<EarlyCloseDto> earlyCloses;
}

/// A session that ends at [close], local time, before the regular close.
@_decode
class EarlyCloseDto {
  const EarlyCloseDto({required this.date, required this.close});

  factory EarlyCloseDto.fromJson(Map<String, dynamic> json) =>
      _$EarlyCloseDtoFromJson(json);

  final DateTime date;
  @TimeOfDayConverter()
  final (int, int) close;
}

/// One day's rate: units of the quote currency per unit of the base.
class FxRateDto {
  const FxRateDto(this.date, this.rate);
  final DateTime date;
  final Decimal rate;
}

/// Frankfurter's time series: `{"rates": {"2026-10-05": {"EUR": 0.85}}}`.
@_decode
class FrankfurterSeriesDto {
  const FrankfurterSeriesDto({required this.rates});

  factory FrankfurterSeriesDto.fromJson(Map<String, dynamic> json) =>
      _$FrankfurterSeriesDtoFromJson(json);

  final Map<String, Map<String, num>> rates;

  /// The rates of [quote], oldest first. Frankfurter sends JSON numbers: the
  /// shortest representation of the double gives back the published digits
  /// (ECB rates have at most 6 significant figures).
  List<FxRateDto> ratesOf(Currency quote) {
    final out = [
      for (final MapEntry(key: day, value: byQuote) in rates.entries)
        if (byQuote[quote.code] case final rate?)
          FxRateDto(
            const DayConverter().fromJson(day),
            Decimal.parse(rate.toString()),
          ),
    ];
    return out..sort((a, b) => a.date.compareTo(b.date));
  }
}
