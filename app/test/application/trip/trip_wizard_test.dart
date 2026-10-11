import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_wizard.dart';
import 'package:finance_companion/core/failure.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:finance_companion/domain/wallet/trip_setup.dart';
import 'package:finance_companion/domain/wallet/trip_start.dart';
import 'package:finance_companion/domain/wallet/wallet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';

DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);

const _l = Localized('x', 'x');

ContentPack pack(List<NodeContent> nodes) => ContentPack(
  id: 'actions-etf',
  version: 1,
  title: _l,
  nodes: nodes,
  datasets: const {},
  glossary: const {},
);

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    // Sunday 2026-10-11.
    final wall = WallClock(DateTime.utc(2026, 10, 11, 10));
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(wall),
        marketRepositoryProvider.overrideWithValue(
          MarketRepository(
            db,
            BackendApi('http://backend.test', adapter: FakeBackend()),
            wallClock: wall,
          ),
        ),
        contentPackProvider(actionsEtfIsland).overrideWith(
          (ref) async => pack([
            NodeContent(
              id: 'basics.1929',
              type: NodeType.predictReveal,
              title: const Localized('Le krach de 1929', 'The 1929 crash'),
              status: ContentStatus.draft,
              covers: Period(day(1929, 1, 1), day(1933, 12, 31)),
            ),
          ]),
        ),
      ],
    );
    container.listen(tripWizardProvider, (_, _) {});
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  TripWizard wizard() => container.read(tripWizardProvider.notifier);
  TripDraft draft() => container.read(tripWizardProvider);

  test('presets: the four moments, then 1, 5 and 10 years back', () async {
    final dates = await container.read(wizardDatesProvider.future);
    expect(dates.catalogueSize, 2); // Apple (1980) and Meta (2012)
    expect([for (final p in dates.presets) p.preset], TripPreset.values);
    final byPreset = {for (final p in dates.presets) p.preset: p};
    expect(byPreset[TripPreset.lehman]!.date, day(2008, 9, 15));
    expect(byPreset[TripPreset.dotcom]!.available, 1);
    expect(byPreset[TripPreset.covid]!.available, 2);
    // A year before Sunday 2026-10-11: Friday 2025-10-10.
    expect(byPreset[TripPreset.oneYear]!.date, day(2025, 10, 10));
    expect(byPreset[TripPreset.tenYears]!.date, day(2016, 10, 11));
  });

  test('a moment is a valid start; next and back walk the steps', () async {
    final dates = await container.read(wizardDatesProvider.future);
    wizard().next();
    expect(draft().step, 1, reason: 'no date yet');
    wizard().choose(dates.presets[1]);
    expect(draft().start, day(2008, 9, 15));
    expect(draft().preset, TripPreset.lehman);
    wizard().next();
    expect(draft().step, 2);
    wizard().back();
    expect(draft().step, 1);
    expect(draft().start, day(2008, 9, 15), reason: 'kept');
  });

  test('a typed date: every verdict', () async {
    await wizard().type('31/02/2020');
    expect(draft().check, isA<StartUnreadable>());
    expect(draft().start, isNull);

    await wizard().type('24/10/1929');
    expect((draft().check! as StartBeforeFloor).floor, dataFloor);

    await wizard().type('01/10/2026');
    expect((draft().check! as StartTooRecent).latest, day(2026, 9, 11));

    // A Saturday rolls to Monday.
    await wizard().type('13/09/2008');
    final ok = draft().check! as StartOk;
    expect(ok.date, day(2008, 9, 15));
    expect(ok.rolledFrom, day(2008, 9, 13));
    expect(draft().preset, isNull);
    expect(draft().custom, '13/09/2008');
  });

  test('typing replaces a chosen moment', () async {
    final dates = await container.read(wizardDatesProvider.future);
    wizard().choose(dates.presets.first);
    await wizard().type('16/09/2008');
    expect(draft().preset, isNull);
    expect(draft().start, day(2008, 9, 16));
  });

  test('a deep link selects its moment, or types its date', () async {
    await wizard().prefill(
      TripWizardArgs(date: day(2020, 2, 18), fromNode: 'ae.march-2020'),
    );
    expect(draft().preset, TripPreset.covid);
    expect(draft().fromNode, 'ae.march-2020');

    await wizard().prefill(TripWizardArgs(date: day(2008, 9, 13)));
    expect(draft().custom, '13/09/2008');
    expect(draft().start, day(2008, 9, 15));
  });

  test('a date before the data floor links the lesson about it', () async {
    expect(
      (await container.read(lessonBeforeProvider(day(1929, 10, 24)).future))!
          .id,
      'basics.1929',
    );
    expect(
      await container.read(lessonBeforeProvider(day(1995, 1, 1)).future),
      isNull,
    );
  });

  group('steps 2 and 3', () {
    Future<void> toStep2(TripPreset preset) async {
      final dates = await container.read(wizardDatesProvider.future);
      wizard().choose(dates.presets.firstWhere((p) => p.preset == preset));
      wizard().next();
    }

    test(
      'a difficulty is needed to go on; presets are valid as they are',
      () async {
        await toStep2(TripPreset.covid);
        expect(draft().step, 2);
        wizard().next();
        expect(draft().step, 2, reason: 'no difficulty yet');
        wizard().chooseDifficulty(Difficulty.serre);
        expect(draft().settings!.fixedFee, const Money(100, Currency.eur));
        wizard().next();
        expect(draft().step, 3);
        wizard().next();
        expect(draft().step, 3, reason: 'the last step');
        wizard().edit(1);
        expect(draft().step, 1);
        expect(draft().difficulty, Difficulty.serre, reason: 'kept');
      },
    );

    test(
      '« Sur mesure »: French or English numbers, ranges per field',
      () async {
        await toStep2(TripPreset.covid);
        wizard().chooseDifficulty(Difficulty.surMesure);
        expect(
          draft().settings!.startingCash,
          const Money(1000000, Currency.eur),
        );
        wizard().setCustom(SettingField.startingCash, '1 500,50');
        wizard().setCustom(SettingField.fxFee, '0.5');
        expect(
          draft().settings!.startingCash,
          const Money(150050, Currency.eur),
        );
        expect(draft().settings!.fxFeeRate, Decimal.parse('0.005'));
        expect(draft().settingErrors, isEmpty);

        wizard().setCustom(SettingField.startingCash, 'beaucoup');
        expect(draft().settingErrors, {SettingField.startingCash: 'number'});
        // One unreadable field leaves the others checked.
        wizard().setCustom(SettingField.fixedFee, '25');
        expect(draft().settingErrors, {
          SettingField.startingCash: 'number',
          SettingField.fixedFee: 'fixed_fee_range',
        });
        wizard().setCustom(SettingField.fixedFee, '0');
        wizard().next();
        expect(draft().step, 2);

        wizard().setCustom(SettingField.startingCash, '50');
        wizard().setCustom(SettingField.fixedFee, '25');
        wizard().setCustom(SettingField.contribution, '10');
        expect(draft().settingErrors, {
          SettingField.startingCash: 'starting_cash_range',
          SettingField.fixedFee: 'fixed_fee_range',
          SettingField.contribution: 'contribution_below_fee',
        });
        wizard().setFractional(false);
        expect(draft().settings!.fractionalShares, isFalse);
      },
    );

    test('creating the trip: wallet, settings, stops, name, cushion', () async {
      await toStep2(TripPreset.covid);
      wizard().chooseDifficulty(Difficulty.decouverte);
      wizard().setCushion(30);
      wizard().next();
      wizard().setStop(StopKind.orderFilled, false);
      wizard().setStop(StopKind.position, true);
      wizard().setName('  Covid 2020  ');
      final id = await wizard().create(defaultName: 'Covid');

      final trip = await WalletRepository(db).load(id);
      expect(trip.kind, WalletKind.trip);
      expect(trip.name, 'Covid 2020');
      expect(trip.startDate, day(2020, 2, 18));
      expect(trip.simDate, day(2020, 2, 18));
      expect(trip.params.difficulty, 'decouverte');
      expect(trip.params.rules.fxFeeRate, Decimal.zero);
      expect(trip.params.stops.drawdown, Decimal.parse('0.15'));
      expect(trip.params.stops.positionLoss, Decimal.parse('0.20'));
      expect(trip.params.stops.orderFilled, isFalse);
      // 30 % of 50 000 € = 15 000 €, under the 22 950 € ceiling.
      expect(
        trip.livretMovements.single.amount,
        const Money(1500000, Currency.eur),
      );
      expect(trip.cash, const Money(3500000, Currency.eur));
    });

    test('the cushion stops at the ceiling of the start date', () async {
      await toStep2(TripPreset.covid);
      wizard().chooseDifficulty(Difficulty.surMesure);
      wizard().setCustom(SettingField.startingCash, '100000');
      wizard().setCushion(30);
      wizard().next();
      final id = await wizard().create(defaultName: 'Covid');
      final trip = await WalletRepository(db).load(id);
      expect(
        trip.livretMovements.single.amount,
        const Money(2295000, Currency.eur),
      );
      expect(trip.name, 'Covid', reason: 'the default name');
    });

    test('no name, no trip', () async {
      await toStep2(TripPreset.covid);
      wizard().chooseDifficulty(Difficulty.realiste);
      wizard().next();
      wizard().setName('   ');
      await expectLater(
        wizard().create(defaultName: 'Covid'),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });
}
