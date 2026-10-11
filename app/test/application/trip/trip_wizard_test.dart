import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/trip/trip_wizard.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:finance_companion/domain/wallet/trip_start.dart';
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
}
