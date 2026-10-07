import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/money/money.dart';
import '../../domain/companion/rules.dart';
import '../../domain/learning/profile.dart';
import '../../domain/market/asset.dart';
import '../../domain/market/market_calendar.dart';
import '../../domain/wallet/dca.dart';
import '../../domain/wallet/order.dart';
import '../../domain/wallet/order_matcher.dart';
import '../../domain/wallet/position.dart';
import '../../domain/wallet/wallet.dart';
import 'daos/learning_dao.dart';
import 'daos/market_dao.dart';
import 'daos/wallet_dao.dart';
import 'tables.dart';

part 'database.g.dart';

/// The app's SQLite database (ADR-002). Repositories reach it through the
/// DAOs only.
///
/// Every schema change bumps [schemaVersion], adds a step to [migration] and
/// is followed by `dart run drift_dev make-migrations`, which records the new
/// schema under `drift_schemas/` and generates its migration test.
@DriftDatabase(
  tables: [
    Assets,
    PriceBars,
    Quotes,
    FxRates,
    LivretRates,
    LivretCeilings,
    HistorySync,
    ExchangeHolidays,
    CalendarYears,
    ContentPacks,
    Wallets,
    CashLedger,
    Orders,
    Fills,
    WalletValues,
    DcaPlans,
    DcaSimulations,
    JournalEntries,
    Profiles,
    NodeProgress,
    GlossaryState,
    Favorites,
    CompanionLog,
  ],
  daos: [MarketDao, WalletDao, LearningDao],
)
class AppDatabase extends _$AppDatabase {
  /// The on-device database, or [executor] (tests use an in-memory one).
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'investment_companion'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
  );
}
