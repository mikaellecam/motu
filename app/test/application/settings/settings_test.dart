import 'package:decimal/decimal.dart';
import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/application/settings/settings.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/market_repository.dart';
import 'package:finance_companion/data/repositories/wallet_repository.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';
import '../../fakes/lesson_pack.dart';

import 'package:finance_companion/data/content/pack_codec.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  final now = DateTime.utc(2026, 10, 12, 9);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final wall = WallClock(now);
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        liveClockProvider.overrideWithValue(wall),
        marketRepositoryProvider.overrideWithValue(
          MarketRepository(
            db,
            BackendApi('http://t', adapter: FakeBackend()),
            wallClock: wall,
          ),
        ),
        contentPackProvider(actionsEtfIsland).overrideWith(
          (ref) async => const ContentPack(
            id: 'actions-etf',
            version: 1,
            title: Localized('Actions & ETF', 'Stocks & ETFs'),
            nodes: [],
            datasets: {},
            glossary: {},
          ),
        ),
        contentPackProvider(lesBasesIsland)
            .overrideWith((ref) async => decodePack(emptyBasesJson())),
      ],
    );
    await c.read(walletRepositoryProvider).ensureLiveWallet(now);
    await c
        .read(profileRepositoryProvider)
        .save(
          const Profile(
            goal: Goal.longTerm,
            dropReaction: DropReaction.wait,
            knowledge: Knowledge.nothing,
            savings: Savings.livret,
            weeklyTime: WeeklyTime.five,
          ),
        );
    c.listen(settingsViewProvider, (_, _) {});
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<SettingsView> view() async {
    await pumpEventQueue();
    return c.read(settingsViewProvider.future);
  }

  SettingsController actions() => c.read(settingsControllerProvider.notifier);

  test('the defaults: device language, level 1, 0,15 %, 50 000 €', () async {
    final v = await view();
    expect(v.settings.language, isNull);
    expect(v.level, 1);
    expect(v.fxFee, Decimal.parse('0.0015'));
    expect(v.startingCash, WalletRepository.defaultLiveCash);
    expect(v.cache.histories, 0);
  });

  test('each setting is kept and shows at once', () async {
    await actions().setLanguage('en');
    await actions().setShowAll(true);
    await actions().setFxFee(Decimal.parse('0.005'));
    await actions().setStartingCash(const Money(1000000, Currency.eur));
    final v = await view();
    expect(v.settings.language, 'en');
    expect(c.read(appLanguageProvider), 'en');
    expect(v.level, 3, reason: '« Tout afficher » shows everything');
    expect(v.fxFee, Decimal.parse('0.005'));
    expect(v.startingCash, const Money(1000000, Currency.eur));
  });

  test('read once, as the screen does: it still acts later', () async {
    final held = actions();
    await pumpEventQueue();
    await held.setLanguage('fr');
    await held.setShowAll(true);
    await held.refreshNow();
    final v = await view();
    expect(v.settings.language, 'fr');
    expect(v.level, 3);
  });

  test('a reset starts the live wallet with the chosen capital', () async {
    await actions().setStartingCash(const Money(10000000, Currency.eur));
    await actions().resetLiveWallet();
    final live = await c
        .read(walletRepositoryProvider)
        .load(WalletRepository.liveWalletId);
    expect(live.cash, const Money(10000000, Currency.eur));
  });
}
