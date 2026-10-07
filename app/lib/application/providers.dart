import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/local/database.dart';
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
