import 'package:drift/drift.dart';

import '../../../domain/wallet/order.dart';
import '../../../domain/wallet/order_matcher.dart';
import '../database.dart';
import '../tables.dart';

part 'wallet_dao.g.dart';

/// Wallets and everything that happens in them. Positions are not stored:
/// repositories derive them from [fills] (BRIEF §6.1).
@DriftAccessor(
  tables: [
    Wallets,
    CashLedger,
    Orders,
    Fills,
    WalletValues,
    DcaPlans,
    JournalEntries,
  ],
)
class WalletDao extends DatabaseAccessor<AppDatabase> with _$WalletDaoMixin {
  WalletDao(super.attachedDatabase);

  Future<void> createWallet(WalletsCompanion row) => into(wallets).insert(row);

  Future<WalletRow?> wallet(String id) =>
      (select(wallets)..where((w) => w.id.equals(id))).getSingleOrNull();

  Stream<List<WalletRow>> watchWallets() => (select(
    wallets,
  )..orderBy([(w) => OrderingTerm(expression: w.createdAt)])).watch();

  /// Writes the non-absent fields of [row] to wallet [id].
  Future<void> updateWallet(String id, WalletsCompanion row) =>
      (update(wallets)..where((w) => w.id.equals(id))).write(row);

  /// Deletes a wallet and, by cascade, all its rows.
  Future<void> deleteWallet(String id) =>
      (delete(wallets)..where((w) => w.id.equals(id))).go();

  Future<int> addLedgerEntry(CashLedgerCompanion row) =>
      into(cashLedger).insert(row);

  Future<List<LedgerEntryRow>> ledger(String walletId) =>
      (select(cashLedger)
            ..where((l) => l.walletId.equals(walletId))
            ..orderBy([
              (l) => OrderingTerm(expression: l.date),
              (l) => OrderingTerm(expression: l.id),
            ]))
          .get();

  /// The wallet's cash: the sum of its ledger.
  Future<int> cashCents(String walletId) async {
    final total = cashLedger.amountCents.sum();
    final row =
        await (selectOnly(cashLedger)
              ..addColumns([total])
              ..where(cashLedger.walletId.equals(walletId)))
            .getSingle();
    return row.read(total) ?? 0;
  }

  Future<void> insertOrder(OrdersCompanion row) => into(orders).insert(row);

  Future<void> closeOrder(
    String id,
    OrderStatus status, {
    CancelReason? reason,
  }) => (update(orders)..where((o) => o.id.equals(id))).write(
    OrdersCompanion(status: Value(status), cancelReason: Value(reason)),
  );

  Future<List<OrderRow>> pendingOrders(String walletId) =>
      (select(orders)
            ..where(
              (o) =>
                  o.walletId.equals(walletId) &
                  o.status.equalsValue(OrderStatus.pending),
            )
            ..orderBy([(o) => OrderingTerm(expression: o.createdAt)]))
          .get();

  Future<OrderRow?> order(String id) =>
      (select(orders)..where((o) => o.id.equals(id))).getSingleOrNull();

  Future<void> insertFill(FillsCompanion row) => into(fills).insert(row);

  /// Fills in execution order, ready for `positionsFrom`.
  Future<List<FillRow>> fillsOf(String walletId) =>
      (select(fills)
            ..where((f) => f.walletId.equals(walletId))
            ..orderBy([
              (f) => OrderingTerm(expression: f.date),
              (f) => OrderingTerm(expression: f.id),
            ]))
          .get();

  Future<void> saveValue(WalletValuesCompanion row) =>
      into(walletValues).insertOnConflictUpdate(row);

  Future<List<WalletValueRow>> valuesOf(String walletId) =>
      (select(walletValues)
            ..where((v) => v.walletId.equals(walletId))
            ..orderBy([(v) => OrderingTerm(expression: v.date)]))
          .get();

  Future<void> savePlan(DcaPlansCompanion row) =>
      into(dcaPlans).insertOnConflictUpdate(row);

  Future<List<DcaPlanRow>> plansOf(String walletId) =>
      (select(dcaPlans)..where((p) => p.walletId.equals(walletId))).get();

  /// Whether any wallet runs a DCA plan (mission node 11).
  Future<bool> anyActivePlan() async =>
      (await (select(dcaPlans)
            ..where((p) => p.active.equals(true))
            ..limit(1))
          .getSingleOrNull()) !=
      null;

  Future<int> addJournalEntry(JournalEntriesCompanion row) =>
      into(journalEntries).insert(row);

  Future<List<JournalEntryRow>> journalOf(String walletId) =>
      (select(journalEntries)
            ..where((j) => j.walletId.equals(walletId))
            ..orderBy([
              (j) => OrderingTerm(expression: j.simDate),
              (j) => OrderingTerm(expression: j.id),
            ]))
          .get();
}
