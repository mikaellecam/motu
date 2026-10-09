import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/local/database.dart';
import '../data/remote/backend_api.dart';
import '../data/repositories/market_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/wallet_repository.dart';

part 'providers.g.dart';

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

@Riverpod(keepAlive: true)
MarketRepository marketRepository(Ref ref) =>
    MarketRepository(ref.watch(databaseProvider), BackendApi(backendUrl));
