import 'package:decimal/decimal.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/money/money.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/wallet_repository.dart';
import '../learning/ui_level.dart';
import '../providers.dart';
import '../wallet/living_island.dart';
import '../wallet/wallet_providers.dart';
import '../wallet/wallets_list.dart';

part 'settings.g.dart';

/// The settings, then every change.
@riverpod
Stream<AppSettings> appSettings(Ref ref) =>
    ref.watch(profileRepositoryProvider).watchSettings();

/// The app's language: `fr`, `en`, or null for the device's.
@riverpod
String? appLanguage(Ref ref) => ref.watch(appSettingsProvider).value?.language;

/// The FX fee choices (decided 2026-10-12): none, the default, 0,5 %, 1 %.
final fxFeeChoices = [
  Decimal.zero,
  WalletRepository.defaultLiveFxFee,
  Decimal.parse('0.005'),
  Decimal.parse('0.01'),
];

/// The starting capital choices for the next live wallet.
const startingCashChoices = [
  Money(100000, Currency.eur),
  Money(1000000, Currency.eur),
  WalletRepository.defaultLiveCash,
  Money(10000000, Currency.eur),
];

/// Everything the Settings screen shows (BRIEF §4.14).
final class SettingsView {
  const SettingsView({
    required this.settings,
    required this.level,
    required this.fxFee,
    required this.startingCash,
    required this.cache,
  });

  final AppSettings settings;
  final int level;

  /// The live wallet's FX fee now.
  final Decimal fxFee;

  /// What the next live wallet starts with.
  final Money startingCash;
  final ({int histories, int closes, DateTime? lastFetch, int bytes}) cache;
}

@riverpod
Future<SettingsView> settingsView(Ref ref) async {
  final wallets = ref.watch(walletRepositoryProvider);
  final market = ref.watch(marketRepositoryProvider);
  final settingsF = ref.watch(appSettingsProvider.future)..ignore();
  final levelF = ref.watch(currentUiLevelProvider.future)..ignore();
  final settings = await settingsF;
  final live = await wallets.load(WalletRepository.liveWalletId);
  return SettingsView(
    settings: settings,
    level: await levelF,
    fxFee: live.params.rules.fxFeeRate,
    startingCash: settings.liveStartingCash ?? WalletRepository.defaultLiveCash,
    cache: await market.cacheInfo(),
  );
}

/// Every Settings action, and what each one changes on screen. Kept alive:
/// the screen holds it from its build, and nothing listens to it.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  @override
  void build() {}

  Future<void> setLanguage(String? code) =>
      ref.read(profileRepositoryProvider).setLanguage(code);

  Future<void> setShowAll(bool on) async {
    await ref.read(profileRepositoryProvider).setShowAll(on);
    ref.invalidate(currentUiLevelProvider);
  }

  Future<void> setStartingCash(Money amount) =>
      ref.read(profileRepositoryProvider).setLiveStartingCash(amount);

  Future<void> setFxFee(Decimal rate) async {
    await ref.read(walletRepositoryProvider).setLiveFxFee(rate);
    _wallet();
  }

  Future<void> refreshNow() async {
    await ref.read(marketRepositoryProvider).refreshNow();
    _wallet();
  }

  Future<void> clearCache() async {
    await ref.read(marketRepositoryProvider).clearCache();
    _wallet();
  }

  /// Starts the live wallet again with the capital chosen in Settings.
  Future<void> resetLiveWallet() async {
    // As stored now: the stream's last value may not have caught up yet.
    final settings = await ref
        .read(profileRepositoryProvider)
        .watchSettings()
        .first;
    await ref
        .read(walletRepositoryProvider)
        .resetLiveWallet(
          ref.read(liveClockProvider).now(),
          startingCash:
              settings.liveStartingCash ?? WalletRepository.defaultLiveCash,
        );
    _wallet();
    ref
      ..invalidate(walletsListProvider)
      ..invalidate(livingIslandProvider);
  }

  void _wallet() => ref
    ..invalidate(walletOverviewProvider(WalletRepository.liveWalletId))
    ..invalidate(settingsViewProvider);
}
