import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../domain/learning/content.dart';
import '../../domain/livret/livret_interest.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/market_calendar.dart';
import '../../domain/wallet/trip_setup.dart';
import '../../domain/wallet/trip_start.dart';
import '../../domain/wallet/wallet.dart';
import '../learning/content.dart';
import '../providers.dart';

part 'trip_wizard.g.dart';

/// Prefill of the trip wizard, from a deep link such as
/// `/wallets/new?step=1&date=2020-02-18&difficulty=realiste&from=ae.march-2020`
/// (a lesson's « Rejoue-le toi-même » bridge, BRIEF §1.2). Values that don't
/// parse are dropped; the wizard then asks for them.
final class TripWizardArgs {
  const TripWizardArgs({
    this.step = 1,
    this.date,
    this.difficulty,
    this.fromNode,
  });

  factory TripWizardArgs.fromQuery(Map<String, String> query) {
    final step = int.tryParse(query['step'] ?? '');
    final date = DateTime.tryParse(query['date'] ?? '');
    return TripWizardArgs(
      step: step != null && step >= 1 && step <= 3 ? step : 1,
      date: date == null ? null : DateTime.utc(date.year, date.month, date.day),
      difficulty: query['difficulty'],
      fromNode: query['from'],
    );
  }

  /// Wizard step, 1 to 3.
  final int step;
  final DateTime? date;
  final String? difficulty;

  /// The node the bridge came from.
  final String? fromNode;
}

/// Where a lesson's [bridge] leads: the wizard on step 1 at its date and
/// difficulty, remembering [nodeId] (read back by [TripWizardArgs.fromQuery]).
String bridgeLocation(TripBridge bridge, String nodeId) => Uri(
  path: '/wallets/new',
  queryParameters: {
    'step': '1',
    'date': bridge.date.toIso8601String().substring(0, 10),
    'difficulty': ?bridge.difficulty,
    'from': nodeId,
  },
).toString();

/// The start dates the wizard offers (BRIEF §4.5): four historic moments,
/// then « Il y a 1 / 5 / 10 ans ».
enum TripPreset {
  dotcom.on(2000, 3, 10),
  lehman.on(2008, 9, 15),
  covid.on(2020, 2, 18),
  inflation.on(2022, 1, 3),
  oneYear.back(1),
  fiveYears.back(5),
  tenYears.back(10);

  const TripPreset.on(int year, int month, int day)
    : _date = (year, month, day),
      years = null;
  const TripPreset.back(int this.years) : _date = null;

  final (int, int, int)? _date;

  /// For the « Il y a N ans » presets.
  final int? years;

  bool get historic => _date != null;

  DateTime? get fixedDate => switch (_date) {
    (final y, final m, final d) => DateTime.utc(y, m, d),
    null => null,
  };
}

/// A preset with its day and how many assets existed then.
final class PresetOption {
  const PresetOption(this.preset, this.date, this.available);
  final TripPreset preset;
  final DateTime date;

  /// Assets listed on or before [date] (« N actifs sur M disponibles »).
  final int available;
}

/// What step 1 shows.
final class WizardDates {
  const WizardDates({
    required this.presets,
    required this.catalogueSize,
    required this.exchanges,
    required this.listingDates,
  });

  final List<PresetOption> presets;
  final int catalogueSize;

  /// The exchanges of the catalogue: a trip day is one when any trades.
  final Set<Exchange> exchanges;
  final List<DateTime> listingDates;

  /// Assets listed on or before [day].
  int availableOn(DateTime day) =>
      listingDates.where((d) => !d.isAfter(day)).length;
}

@riverpod
Future<WizardDates> wizardDates(Ref ref) async {
  final market = ref.watch(marketRepositoryProvider);
  final now = ref.watch(liveClockProvider).now();
  final assets = await market.assets(asOf: now);
  // No catalogue (first launch offline): no trip can be set up.
  if (assets.isEmpty) throw DataUnavailableFailure(now);
  final exchanges = {for (final Asset a in assets) a.exchange};
  final calendar = await market.calendar(
    exchanges,
    fromYear: now.year - 10,
    toYear: now.year,
  );
  bool tripDay(DateTime d) => exchanges.any((e) => calendar.isTradingDay(e, d));
  final listingDates = [for (final a in assets) a.listingDate];
  int available(DateTime day) =>
      listingDates.where((d) => !d.isAfter(day)).length;
  DateTime dateOf(TripPreset preset) =>
      preset.fixedDate ??
      yearsAgo(preset.years!, today: now, isTripDay: tripDay);
  return WizardDates(
    presets: [
      for (final preset in TripPreset.values)
        PresetOption(preset, dateOf(preset), available(dateOf(preset))),
    ],
    catalogueSize: assets.length,
    exchanges: exchanges,
    listingDates: listingDates,
  );
}

/// The lesson about the period of [day], if a pack has one: the wizard links
/// a date before the data floor to it (BRIEF §4.5).
NodeContent? lessonCovering(Iterable<ContentPack> packs, DateTime day) {
  for (final pack in packs) {
    for (final node in pack.nodes) {
      if (node.covers?.contains(day) ?? false) return node;
    }
  }
  return null;
}

/// The money fields of « Sur mesure ».
enum SettingField { startingCash, contribution, fxFee, fixedFee }

/// The automatic stops of step 3.
enum StopKind { portfolio, position, orderFilled, contribution }

const _keep = Object();

/// The trip being set up, step by step.
final class TripDraft {
  const TripDraft({
    this.step = 1,
    this.preset,
    this.custom = '',
    this.check,
    this.fromNode,
    this.difficulty,
    this.customText = const {},
    this.customFractional = true,
    this.cushionPercent,
    this.name,
    this.stops = const {StopKind.portfolio, StopKind.orderFilled},
  });

  final int step;

  /// The chosen preset; null when the date is typed.
  final TripPreset? preset;

  /// The typed `JJ/MM/AAAA`.
  final String custom;

  /// The verdict on the chosen or typed date; null before any choice.
  final StartCheck? check;
  final String? fromNode;

  /// Null until chosen.
  final Difficulty? difficulty;

  /// What was typed in the « Sur mesure » fields; a field never touched
  /// keeps the starting value (Réaliste's).
  final Map<SettingField, String> customText;
  final bool customFractional;

  /// Share of the starting cash for the safety cushion; null when off.
  final int? cushionPercent;

  /// The typed name; null while the default one stands.
  final String? name;

  /// The automatic stops switched on (defaults: BRIEF §4.5).
  final Set<StopKind> stops;

  /// Typing a date is the choice: asked for (a verdict, even on an empty
  /// field) or under way, and no moment chosen since.
  bool get typing => preset == null && (custom.isNotEmpty || check != null);

  /// The start day, once a valid one is chosen.
  DateTime? get start => switch (check) {
    StartOk(:final date) => date,
    _ => null,
  };

  /// The settings of the chosen difficulty; null when none is chosen or a
  /// « Sur mesure » field is not a number.
  TripSettings? get settings => _settings(strict: true);

  /// [strict] refuses a field that is not a number; otherwise it stands at
  /// its starting value, so the other fields can still be checked.
  TripSettings? _settings({required bool strict}) {
    final difficulty = this.difficulty;
    if (difficulty == null) return null;
    final base = presetSettings(difficulty);
    if (difficulty != Difficulty.surMesure) return base;
    Decimal start(SettingField f) => switch (f) {
      SettingField.startingCash => base.startingCash.amount,
      SettingField.contribution => base.monthlyContribution.amount,
      SettingField.fxFee => base.fxFeeRate.shift(2),
      SettingField.fixedFee => base.fixedFee.amount,
    };
    final values = <SettingField, Decimal>{};
    for (final f in SettingField.values) {
      final text = customText[f];
      final parsed = text == null ? start(f) : parseAmount(text);
      if (parsed == null && strict) return null;
      values[f] = parsed ?? start(f);
    }
    Money eur(SettingField f) => Money.book(values[f]!, Currency.eur);
    return TripSettings(
      startingCash: eur(SettingField.startingCash),
      monthlyContribution: eur(SettingField.contribution),
      fxFeeRate: values[SettingField.fxFee]!.shift(-2),
      fixedFee: eur(SettingField.fixedFee),
      fractionalShares: customFractional,
    );
  }

  /// What is wrong with each « Sur mesure » field: `number` when it is not
  /// one, else the code of `validateSettings`.
  Map<SettingField, String> get settingErrors {
    if (difficulty != Difficulty.surMesure) return const {};
    final errors = <SettingField, String>{
      for (final MapEntry(key: f, value: text) in customText.entries)
        if (parseAmount(text) == null) f: 'number',
    };
    for (final failure in validateSettings(_settings(strict: false)!)) {
      final field = switch (failure.code) {
        'starting_cash_range' => SettingField.startingCash,
        'contribution_range' ||
        'contribution_below_fee' => SettingField.contribution,
        'fx_fee_range' => SettingField.fxFee,
        _ => SettingField.fixedFee,
      };
      errors.putIfAbsent(field, () => failure.code);
    }
    return errors;
  }

  bool get settingsValid => settings != null && settingErrors.isEmpty;

  TripDraft copyWith({
    int? step,
    Object? preset = _keep,
    String? custom,
    Object? check = _keep,
    Object? difficulty = _keep,
    Map<SettingField, String>? customText,
    bool? customFractional,
    Object? cushionPercent = _keep,
    Object? name = _keep,
    Set<StopKind>? stops,
  }) => TripDraft(
    step: step ?? this.step,
    preset: identical(preset, _keep) ? this.preset : preset as TripPreset?,
    custom: custom ?? this.custom,
    check: identical(check, _keep) ? this.check : check as StartCheck?,
    fromNode: fromNode,
    difficulty: identical(difficulty, _keep)
        ? this.difficulty
        : difficulty as Difficulty?,
    customText: customText ?? this.customText,
    customFractional: customFractional ?? this.customFractional,
    cushionPercent: identical(cushionPercent, _keep)
        ? this.cushionPercent
        : cushionPercent as int?,
    name: identical(name, _keep) ? this.name : name as String?,
    stops: stops ?? this.stops,
  );
}

/// An amount typed the French or the English way: `1 500,50`, `1500.50`.
Decimal? parseAmount(String text) => Decimal.tryParse(
  text.replaceAll(RegExp(r'[\s\u00a0\u202f]'), '').replaceAll(',', '.'),
);

@riverpod
class TripWizard extends _$TripWizard {
  @override
  TripDraft build() => const TripDraft();

  /// Starts from a deep link: its date selects the matching moment, or fills
  /// the typed date; its difficulty is preselected; then on to its step, as
  /// far as the steps before it are complete.
  Future<void> prefill(TripWizardArgs args) async {
    state = TripDraft(
      fromNode: args.fromNode,
      difficulty: Difficulty.byId(args.difficulty),
    );
    final date = args.date;
    if (date == null) return;
    final dates = await ref.read(wizardDatesProvider.future);
    final preset = dates.presets.where(
      (p) => p.preset.historic && p.date == date,
    );
    if (preset.isNotEmpty) {
      choose(preset.first);
    } else {
      await type(
        '${_two(date.day)}/${_two(date.month)}/${date.year.toString().padLeft(4, '0')}',
      );
    }
    for (var step = 1; step < args.step; step++) {
      next();
    }
  }

  void choose(PresetOption option) => state = state.copyWith(
    preset: option.preset,
    custom: '',
    check: StartOk(option.date),
  );

  /// Checks a typed date against the trip days of its year.
  Future<void> type(String input) async {
    state = state.copyWith(preset: null, custom: input, check: null);
    final day = parseDay(input);
    final today = ref.read(liveClockProvider).now();
    StartCheck check;
    if (day == null || day.isBefore(dataFloor) || day.isAfter(today)) {
      // No calendar needed to refuse it.
      check = checkStart(
        day,
        today: today,
        floor: dataFloor,
        isTripDay: (_) => true,
      );
    } else {
      final dates = await ref.read(wizardDatesProvider.future);
      final calendar = await ref
          .read(marketRepositoryProvider)
          .calendar(dates.exchanges, fromYear: day.year, toYear: day.year + 1);
      check = checkStart(
        day,
        today: today,
        floor: dataFloor,
        isTripDay: (d) =>
            dates.exchanges.any((e) => calendar.isTradingDay(e, d)),
      );
    }
    // A slower check of an older input never overwrites a newer one.
    if (state.custom == input && state.preset == null) {
      state = state.copyWith(check: check);
    }
  }

  void chooseDifficulty(Difficulty difficulty) =>
      state = state.copyWith(difficulty: difficulty);

  void setCustom(SettingField field, String text) =>
      state = state.copyWith(customText: {...state.customText, field: text});

  void setFractional(bool on) => state = state.copyWith(customFractional: on);

  void setCushion(int? percent) =>
      state = state.copyWith(cushionPercent: percent);

  void setName(String name) => state = state.copyWith(name: name);

  void setStop(StopKind stop, bool on) => state = state.copyWith(
    stops: on ? {...state.stops, stop} : ({...state.stops}..remove(stop)),
  );

  /// To the next step, once this one is complete.
  void next() {
    final ready = switch (state.step) {
      1 => state.start != null,
      2 => state.settingsValid,
      _ => false,
    };
    if (ready) state = state.copyWith(step: state.step + 1);
  }

  void back() {
    if (state.step > 1) state = state.copyWith(step: state.step - 1);
  }

  /// Back to an earlier step (the recap's « Modifier »).
  void edit(int step) {
    if (step >= 1 && step < state.step) state = state.copyWith(step: step);
  }

  /// Creates the trip wallet and moves the cushion to its Livret; returns
  /// its id. [defaultName] stands when no name was typed.
  Future<String> create({required String defaultName}) async {
    final draft = state;
    final start = draft.start;
    final settings = draft.settings;
    final name = tripName(draft.name ?? defaultName);
    if (start == null || settings == null || !draft.settingsValid) {
      throw const ValidationFailure('incomplete');
    }
    if (name == null) throw const ValidationFailure('name');
    final wallets = ref.read(walletRepositoryProvider);
    final now = ref.read(liveClockProvider).now();
    final percent = draft.cushionPercent;
    final kept = percent == null
        ? null
        : cushion(
            settings.startingCash,
            percent,
            ceiling: await ref.read(livretCeilingOnProvider(start).future),
          );
    final id = 'trip-${now.microsecondsSinceEpoch}';
    await wallets.createWallet(
      id: id,
      kind: WalletKind.trip,
      name: name,
      startDate: start,
      startingCash: settings.startingCash,
      params: WalletParams(
        rules: settings.rules,
        monthlyContribution: settings.monthlyContribution,
        stops: stopsFrom(
          portfolio: draft.stops.contains(StopKind.portfolio),
          position: draft.stops.contains(StopKind.position),
          orderFilled: draft.stops.contains(StopKind.orderFilled),
          contribution: draft.stops.contains(StopKind.contribution),
        ),
        difficulty: draft.difficulty!.id,
      ),
      createdAt: now,
    );
    if (kept != null && kept.amount.isPositive) {
      await wallets.moveToLivret(id, start, kept.amount);
    }
    return id;
  }
}

/// The Livret A ceiling valid on [day] (BRIEF §4.11).
@riverpod
Future<Money> livretCeilingOn(Ref ref, DateTime day) async {
  final history = await ref.watch(marketRepositoryProvider).livret(asOf: day);
  return ceilingAt(day, history.ceilings);
}

/// The lesson to link from a date before the data floor, from the packs.
@riverpod
Future<NodeContent?> lessonBefore(Ref ref, DateTime day) async =>
    lessonCovering([
      await ref.watch(contentPackProvider(actionsEtfIsland).future),
    ], day);

String _two(int n) => n.toString().padLeft(2, '0');
