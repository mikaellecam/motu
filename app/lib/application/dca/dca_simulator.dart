import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../data/repositories/dca_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../domain/learning/profile_rules.dart';
import '../../domain/market/asset.dart';
import '../../domain/wallet/dca.dart';
import '../../domain/wallet/dca_simulator.dart';
import '../../domain/wallet/order.dart';
import '../../domain/wallet/trip_start.dart';
import '../providers.dart';
import '../trip/trip_wizard.dart' show parseAmount;
import '../wallet/wallet_overview.dart' show worldAssetId;

part 'dca_simulator.g.dart';

/// A simulator run (BRIEF §4.10): the DCA, the same total put in at once on
/// the first purchase day, the same money on a Livret A, and the insight.
final class DcaResult {
  const DcaResult({
    required this.params,
    required this.asset,
    required this.end,
    required this.dca,
    required this.lumpSum,
    required this.livret,
    required this.insight,
  });

  final DcaParams params;
  final Asset asset;

  /// The latest close the run used.
  final DateTime end;
  final InvestmentRun dca;
  final InvestmentRun lumpSum;
  final LivretRun livret;
  final DcaInsight? insight;

  DcaSummary get summary =>
      DcaSummary(end: end, invested: dca.invested, finalValue: dca.finalValue);
}

/// The simulator charges what the sandbox charges: the live wallet's rules
/// (decided 2026-10-11).
Future<TradingRules> _rules(WalletRepository wallets) async =>
    (await wallets.load(WalletRepository.liveWalletId)).params.rules;

DateTime _day(DateTime t) {
  final utc = t.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// Runs [params] up to the latest close.
@riverpod
Future<DcaResult> dcaRun(Ref ref, DcaParams params) async {
  final market = ref.watch(marketRepositoryProvider);
  final fx = ref.watch(fxServiceProvider);
  final wallets = ref.watch(walletRepositoryProvider);
  final now = ref.watch(liveClockProvider).now();
  final rules = await _rules(wallets);
  final asset = (await market.assets(asOf: now))
      .where((a) => a.id == params.assetId)
      .firstOrNull;
  if (asset == null) throw const NotFoundFailure();
  final bars = await market.history(
    asset.id,
    from: params.start,
    to: _day(now),
    asOf: now,
  );
  if (bars.isEmpty) throw DataUnavailableFailure(params.start);
  final end = bars.last.date;
  final calendar = await market.calendar(
    {asset.exchange},
    fromYear: params.start.year,
    toYear: end.year,
  );
  final flows = [
    for (final date in dcaSchedule(
      start: params.start,
      end: end,
      frequency: params.frequency,
      calendar: calendar,
      exchange: asset.exchange,
    ))
      Flow(date, params.amount),
  ];
  final rate = await fx.lookup(
    asset.currency,
    Currency.eur,
    start: params.start.subtract(const Duration(days: 10)),
    asOf: now,
  );
  final dca = investFlows(
    flows,
    bars: bars,
    fxRate: rate,
    rules: rules,
    end: end,
  );
  final lumpSum = investFlows(
    [if (flows.isNotEmpty) Flow(flows.first.date, dca.invested)],
    bars: bars,
    fxRate: rate,
    rules: rules,
    end: end,
  );
  final history = await market.livret(asOf: now);
  final livret = livretFlows(
    [for (final p in dca.purchases) Flow(p.date, p.amount)],
    rates: history.rates,
    ceilings: history.ceilings,
    dates: [for (final v in dca.series) v.date],
  );
  return DcaResult(
    params: params,
    asset: asset,
    end: end,
    dca: dca,
    lumpSum: lumpSum,
    livret: livret,
    insight: dcaInsight(
      dca: dca,
      lumpSum: lumpSum,
      endPrice: Price(bars.last.close, bars.last.currency),
    ),
  );
}

/// The form as typed (BRIEF §4.10).
final class DcaForm {
  const DcaForm({
    this.assetId = worldAssetId,
    this.amount = '100',
    this.frequency = DcaFrequency.monthly,
    this.years,
    this.date = '',
    this.submitted = false,
    this.run,
  });

  final String assetId;
  final String amount;
  final DcaFrequency frequency;

  /// « Il y a N ans »; null for the profile's default, or for [date] once
  /// one is typed (JJ/MM/AAAA).
  final int? years;
  final String date;
  final bool submitted;

  /// What the result shows: the last valid inputs run.
  final DcaParams? run;

  DcaForm copyWith({
    String? assetId,
    String? amount,
    DcaFrequency? frequency,
    int? Function()? years,
    String? date,
    bool? submitted,
    DcaParams? Function()? run,
  }) => DcaForm(
    assetId: assetId ?? this.assetId,
    amount: amount ?? this.amount,
    frequency: frequency ?? this.frequency,
    years: years == null ? this.years : years(),
    date: date ?? this.date,
    submitted: submitted ?? this.submitted,
    run: run == null ? this.run : run(),
  );
}

/// The start presets.
const dcaYears = [1, 3, 5, 10];

/// The preset nearest below the profile's horizon (BRIEF §4.1: Q1 sets the
/// DCA defaults): 2 → 1 an, 5 → 5, 10 and 15 → 10.
int defaultDcaYears(int horizonYears) =>
    dcaYears.lastWhere((y) => y <= horizonYears, orElse: () => dcaYears.first);

@riverpod
class DcaFormController extends _$DcaFormController {
  @override
  DcaForm build() => const DcaForm();

  void setAsset(String id) => state = state.copyWith(assetId: id);
  void setAmount(String text) => state = state.copyWith(amount: text);
  void setFrequency(DcaFrequency f) => state = state.copyWith(frequency: f);
  void setYears(int years) =>
      state = state.copyWith(years: () => years, date: '');
  void setDate(String text) =>
      state = state.copyWith(years: () => null, date: text);

  /// « Simuler »: shows [valid]'s result, or the errors.
  void simulate(DcaParams? valid) => state = state.copyWith(
    submitted: true,
    run: valid == null ? null : () => valid,
  );

  /// A saved simulation back in the form, run again.
  void load(DcaParams p) => state = DcaForm(
    assetId: p.assetId,
    amount: p.amount.amount.toString(),
    frequency: p.frequency,
    date:
        '${p.start.day.toString().padLeft(2, '0')}/'
        '${p.start.month.toString().padLeft(2, '0')}/${p.start.year}',
    run: p,
  );

  /// « Enregistrer »: [result] in the saved simulations.
  Future<void> save(DcaResult result) async {
    await ref
        .read(dcaRepositoryProvider)
        .save(
          result.params,
          result.summary,
          ref.read(liveClockProvider).now().toUtc(),
        );
    ref.invalidate(savedDcaProvider);
  }
}

/// The form with what is wrong with it, and its inputs once all valid.
final class DcaFormView {
  const DcaFormView({
    required this.form,
    required this.assets,
    required this.years,
    required this.start,
    required this.amountErrors,
    required this.params,
  });

  final DcaForm form;

  /// The catalogue, by name.
  final List<Asset> assets;

  /// The preset in use; null when a date is typed.
  final int? years;

  /// The start as checked: `checkStart` against the asset's first close.
  final StartCheck start;
  final List<ValidationFailure> amountErrors;
  final DcaParams? params;
}

@riverpod
Future<DcaFormView> dcaFormView(Ref ref) async {
  final form = ref.watch(dcaFormControllerProvider);
  final market = ref.watch(marketRepositoryProvider);
  final wallets = ref.watch(walletRepositoryProvider);
  final profiles = ref.watch(profileRepositoryProvider);
  final now = ref.watch(liveClockProvider).now();
  final today = _day(now);
  final assets = [...await market.assets(asOf: now)]
    ..sort((a, b) => a.name.compareTo(b.name));
  final rules = await _rules(wallets);
  final profile = await profiles.load();
  final years =
      form.years ??
      (form.date.trim().isEmpty
          ? defaultDcaYears(profile == null ? 10 : defaultHorizonYears(profile))
          : null);

  final asset = assets.where((a) => a.id == form.assetId).firstOrNull;
  final amount = parseAmount(form.amount);
  final amountErrors = validateDcaAmount(
    Money.book(amount ?? Decimal.zero, Currency.eur),
    rules: rules,
  );
  if (asset == null) {
    return DcaFormView(
      form: form,
      assets: assets,
      years: years,
      start: const StartUnreadable(),
      amountErrors: amountErrors,
      params: null,
    );
  }
  final asked = years == null
      ? parseDay(form.date)
      : DateTime.utc(today.year - years, today.month, today.day);
  final calendar = await market.calendar(
    {asset.exchange},
    fromYear: (asked ?? today).year - 1,
    toYear: today.year,
  );
  bool trades(DateTime d) => calendar.isTradingDay(asset.exchange, d);
  final listed = _day(asset.listingDate);
  final start = checkStart(
    years == null ? asked : yearsAgo(years, today: today, isTripDay: trades),
    today: today,
    floor: listed.isAfter(dataFloor) ? listed : dataFloor,
    isTripDay: trades,
  );
  return DcaFormView(
    form: form,
    assets: assets,
    years: years,
    start: start,
    amountErrors: amountErrors,
    params: switch (start) {
      StartOk(:final date) when amountErrors.isEmpty => DcaParams(
        assetId: asset.id,
        amount: Money.book(amount!, Currency.eur),
        frequency: form.frequency,
        start: date,
      ),
      _ => null,
    },
  );
}

/// The saved simulations, newest first.
@riverpod
Future<List<SavedDca>> savedDca(Ref ref) =>
    ref.watch(dcaRepositoryProvider).saved();
