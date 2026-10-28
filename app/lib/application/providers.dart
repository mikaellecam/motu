import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/cache_status.dart';
import '../core/clock/simulation_clock.dart';
import '../data/content/bundled_packs.dart';
import '../data/local/database.dart';
import '../data/remote/backend_api.dart';
import '../data/remote/connectivity.dart';
import '../data/remote/frankfurter_api.dart';
import '../data/repositories/companion_repository.dart';
import '../data/repositories/content_repository.dart';
import '../data/repositories/dca_repository.dart';
import '../data/repositories/favorites_repository.dart';
import '../data/repositories/fx_service.dart';
import '../data/repositories/glossary_repository.dart';
import '../data/repositories/market_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/wallet_repository.dart';

part 'providers.g.dart';

/// The device clock (the live wallet's), overridable in tests.
@Riverpod(keepAlive: true)
SimulationClock liveClock(Ref ref) => const LiveClock();

/// Where a quiz draws its choices' order (M12-14), seeded in tests.
@Riverpod(keepAlive: true)
Random random(Ref ref) => Random();

/// The app's database, opened once and closed with the app (ADR-002).
@Riverpod(keepAlive: true)
AppDatabase database(Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
}

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) =>
    ProfileRepository(ref.watch(databaseProvider));

@Riverpod(keepAlive: true)
WalletRepository walletRepository(Ref ref) =>
    WalletRepository(ref.watch(databaseProvider));

/// The backend's address, set at build time:
/// `flutter run --dart-define=BACKEND_URL=https://api.example.org`.
const backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8080',
);

/// Our backend, shared by every repository that calls it.
@Riverpod(keepAlive: true)
BackendApi backendApi(Ref ref) => BackendApi(backendUrl);

@Riverpod(keepAlive: true)
MarketRepository marketRepository(Ref ref) {
  final repository = MarketRepository(
    ref.watch(databaseProvider),
    ref.watch(backendApiProvider),
    online: deviceOnline(),
  );
  ref.onDispose(repository.dispose);
  return repository;
}

/// Whether the prices on screen are current (BRIEF §6.3).
@riverpod
Stream<CacheStatus> cacheStatus(Ref ref) =>
    ref.watch(marketRepositoryProvider).status();

@Riverpod(keepAlive: true)
FxService fxService(Ref ref) =>
    FxService(ref.watch(databaseProvider), FrankfurterApi());

@Riverpod(keepAlive: true)
CompanionRepository companionRepository(Ref ref) =>
    CompanionRepository(ref.watch(databaseProvider));

@Riverpod(keepAlive: true)
DcaRepository dcaRepository(Ref ref) =>
    DcaRepository(ref.watch(databaseProvider));

@Riverpod(keepAlive: true)
GlossaryRepository glossaryRepository(Ref ref) =>
    GlossaryRepository(ref.watch(databaseProvider));

@Riverpod(keepAlive: true)
FavoritesRepository favoritesRepository(Ref ref) =>
    FavoritesRepository(ref.watch(databaseProvider));

@Riverpod(keepAlive: true)
ContentRepository contentRepository(Ref ref) => ContentRepository(
  ref.watch(databaseProvider),
  ref.watch(backendApiProvider),
  bundled: bundledPack,
);
