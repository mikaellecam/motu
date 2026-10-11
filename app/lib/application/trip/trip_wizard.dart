import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/failure.dart';
import '../../domain/learning/content.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/market_calendar.dart';
import '../../domain/wallet/trip_start.dart';
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

/// The trip being set up, step by step.
final class TripDraft {
  const TripDraft({
    this.step = 1,
    this.preset,
    this.custom = '',
    this.check,
    this.fromNode,
  });

  final int step;

  /// The chosen preset; null when the date is typed.
  final TripPreset? preset;

  /// The typed `JJ/MM/AAAA`.
  final String custom;

  /// The verdict on the chosen or typed date; null before any choice.
  final StartCheck? check;
  final String? fromNode;

  /// The start day, once a valid one is chosen.
  DateTime? get start => switch (check) {
    StartOk(:final date) => date,
    _ => null,
  };

  TripDraft copyWith({
    int? step,
    TripPreset? preset,
    bool clearPreset = false,
    String? custom,
    StartCheck? check,
  }) => TripDraft(
    step: step ?? this.step,
    preset: clearPreset ? null : preset ?? this.preset,
    custom: custom ?? this.custom,
    check: check ?? this.check,
    fromNode: fromNode,
  );
}

@riverpod
class TripWizard extends _$TripWizard {
  @override
  TripDraft build() => const TripDraft();

  /// Starts from a deep link: its date selects the matching moment, or fills
  /// the typed date.
  Future<void> prefill(TripWizardArgs args) async {
    state = TripDraft(fromNode: args.fromNode);
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
  }

  void choose(PresetOption option) => state = state.copyWith(
    preset: option.preset,
    custom: '',
    check: StartOk(option.date),
  );

  /// Checks a typed date against the trip days of its year.
  Future<void> type(String input) async {
    state = TripDraft(fromNode: state.fromNode, custom: input);
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
    if (state.custom == input) state = state.copyWith(check: check);
  }

  void next() {
    if (state.start != null && state.step < 3) {
      state = state.copyWith(step: state.step + 1);
    }
  }

  void back() {
    if (state.step > 1) state = state.copyWith(step: state.step - 1);
  }
}

/// The lesson to link from a date before the data floor, from the packs.
@riverpod
Future<NodeContent?> lessonBefore(Ref ref, DateTime day) async =>
    lessonCovering([
      await ref.watch(contentPackProvider(actionsEtfIsland).future),
    ], day);

String _two(int n) => n.toString().padLeft(2, '0');
