import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../core/failure.dart';
import '../../core/money/money.dart';
import '../../domain/analytics/returns.dart';
import '../../domain/livret/livret_interest.dart';
import '../../domain/wallet/dca.dart';
import '../../domain/wallet/order.dart';
import '../../domain/wallet/order_matcher.dart';
import '../../domain/wallet/position.dart';
import '../../domain/wallet/trip_engine.dart';
import '../../domain/wallet/wallet.dart';
import '../local/database.dart';
import '../local/tables.dart';
import 'guard.dart';

/// A wallet's settings: trading rules, monthly contribution, automatic stops
/// (BRIEF §4.5), stored as JSON in `wallets.params`.
final class WalletParams {
  const WalletParams({
    required this.rules,
    required this.monthlyContribution,
    required this.stops,
    this.difficulty,
  });

  final TradingRules rules;
  final Money monthlyContribution;
  final StopConditions stops;

  /// The difficulty preset a trip was created with; null for the live wallet.
  final String? difficulty;

  String toJson() => jsonEncode({
    'fxFeeRate': rules.fxFeeRate.toString(),
    'fixedFeeCents': rules.fixedFee.minorUnits,
    'fractionalShares': rules.fractionalShares,
    'monthlyContributionCents': monthlyContribution.minorUnits,
    'stopDrawdown': stops.drawdown?.toString(),
    'stopPositionLoss': stops.positionLoss?.toString(),
    'stopOrderFilled': stops.orderFilled,
    'stopContribution': stops.contribution,
  });

  factory WalletParams.fromJson(String json, {String? difficulty}) {
    final map = jsonDecode(json) as Map<String, Object?>;
    Decimal? decimal(String key) => switch (map[key]) {
      final String s => Decimal.parse(s),
      _ => null,
    };
    return WalletParams(
      rules: TradingRules(
        fxFeeRate: decimal('fxFeeRate')!,
        fixedFee: Money(map['fixedFeeCents']! as int, Currency.eur),
        fractionalShares: map['fractionalShares']! as bool,
      ),
      monthlyContribution: Money(
        map['monthlyContributionCents']! as int,
        Currency.eur,
      ),
      stops: StopConditions(
        drawdown: decimal('stopDrawdown'),
        positionLoss: decimal('stopPositionLoss'),
        orderFilled: map['stopOrderFilled']! as bool,
        contribution: map['stopContribution']! as bool,
      ),
      difficulty: difficulty,
    );
  }
}

/// What a wallets list shows of a wallet before valuing it.
final class WalletSummary {
  const WalletSummary({
    required this.id,
    required this.kind,
    required this.name,
    required this.status,
    required this.startDate,
    required this.simDate,
    required this.difficulty,
    required this.createdAt,
  });

  final String id;
  final WalletKind kind;
  final String name;
  final WalletStatus status;
  final DateTime startDate;
  final DateTime? simDate;
  final String? difficulty;
  final DateTime createdAt;
}

/// A wallet as stored, read into domain objects. Positions are derived from
/// the fills on every read, never stored (BRIEF §6.1).
final class WalletState {
  const WalletState({
    required this.id,
    required this.kind,
    required this.name,
    required this.startDate,
    required this.simDate,
    required this.status,
    required this.params,
    required this.cash,
    required this.fills,
    required this.positions,
    required this.pendingOrders,
    required this.values,
    required this.livretMovements,
    required this.plans,
  });

  final String id;
  final WalletKind kind;
  final String name;
  final DateTime startDate;

  /// The trip's simulated day; null for the live wallet.
  final DateTime? simDate;
  final WalletStatus status;
  final WalletParams params;

  /// The sum of the cash ledger.
  final Money cash;

  /// In execution order.
  final List<Fill> fills;
  final Map<String, Position> positions;
  final List<Order> pendingOrders;
  final List<DailyValue> values;

  /// Transfers into (+) and out of (−) the Livret, from the ledger.
  final List<LivretMovement> livretMovements;
  final List<DcaPlan> plans;
}

/// Reads and writes wallets (ADR-002: repositories own persistence). Every
/// storage error surfaces as a [StorageFailure].
class WalletRepository {
  WalletRepository(this._db);

  final AppDatabase _db;

  /// Creates a wallet with its starting cash, booked in the ledger and as the
  /// first day of the value series.
  Future<void> createWallet({
    required String id,
    required WalletKind kind,
    required String name,
    required DateTime startDate,
    required Money startingCash,
    required WalletParams params,
    required DateTime createdAt,
  }) => guardStorage(
    () => _db.transaction(() async {
      final dao = _db.walletDao;
      await dao.createWallet(
        WalletsCompanion.insert(
          id: id,
          kind: kind,
          name: name,
          startDate: startDate,
          simDate: Value(kind == WalletKind.trip ? startDate : null),
          difficulty: Value(params.difficulty),
          params: params.toJson(),
          status: WalletStatus.active,
          createdAt: createdAt,
        ),
      );
      await dao.addLedgerEntry(
        CashLedgerCompanion.insert(
          walletId: id,
          date: startDate,
          amountCents: startingCash.minorUnits,
          kind: LedgerKind.start,
        ),
      );
      await dao.saveValue(
        WalletValuesCompanion.insert(
          walletId: id,
          date: startDate,
          valueCents: startingCash.minorUnits,
          flowCents: startingCash.minorUnits,
        ),
      );
    }),
  );

  /// The live wallet's id; created on first launch (BRIEF §4.5) with
  /// 50 000 €, a 0.15 % FX fee, fractional shares, no monthly contribution
  /// and no automatic stop. Its name comes from the UI copy, not from here.
  Future<String> ensureLiveWallet(DateTime now) => guardStorage(() async {
    final existing = await _db.walletDao.liveWallet();
    if (existing != null) return existing.id;
    final utc = now.toUtc();
    await createWallet(
      id: liveWalletId,
      kind: WalletKind.live,
      name: liveWalletId,
      startDate: DateTime.utc(utc.year, utc.month, utc.day),
      startingCash: Money(5000000, Currency.eur),
      params: WalletParams(
        rules: TradingRules(
          fxFeeRate: Decimal.parse('0.0015'),
          fixedFee: const Money.zero(Currency.eur),
          fractionalShares: true,
        ),
        monthlyContribution: const Money.zero(Currency.eur),
        stops: const StopConditions(),
      ),
      createdAt: utc,
    );
    return liveWalletId;
  });

  static const liveWalletId = 'live';

  /// Every wallet, then every change, oldest first.
  Stream<List<WalletSummary>> watchWallets() =>
      _db.walletDao.watchWallets().map(
        (rows) => [
          for (final row in rows)
            WalletSummary(
              id: row.id,
              kind: row.kind,
              name: row.name,
              status: row.status,
              startDate: row.startDate,
              simDate: row.simDate,
              difficulty: row.difficulty,
              createdAt: row.createdAt,
            ),
        ],
      );

  /// The wallet [id], or a [NotFoundFailure].
  Future<WalletState> load(String id) => guardStorage(() async {
    final dao = _db.walletDao;
    final row = await dao.wallet(id);
    if (row == null) throw const NotFoundFailure();
    final fills = [for (final f in await dao.fillsOf(id)) _fill(f)];
    final ledger = await dao.ledger(id);
    return WalletState(
      id: row.id,
      kind: row.kind,
      name: row.name,
      startDate: row.startDate,
      simDate: row.simDate,
      status: row.status,
      params: WalletParams.fromJson(row.params, difficulty: row.difficulty),
      cash: Money(
        ledger.fold(0, (sum, entry) => sum + entry.amountCents),
        Currency.eur,
      ),
      fills: fills,
      positions: positionsFrom(fills),
      pendingOrders: [for (final o in await dao.pendingOrders(id)) _order(o)],
      values: [
        for (final v in await dao.valuesOf(id))
          DailyValue(
            date: v.date,
            value: Money(v.valueCents, Currency.eur),
            flow: Money(v.flowCents, Currency.eur),
          ),
      ],
      livretMovements: [
        for (final entry in ledger)
          if (entry.kind == LedgerKind.livretIn ||
              entry.kind == LedgerKind.livretOut)
            // Cash out of the wallet is money into the Livret.
            LivretMovement(entry.date, Money(-entry.amountCents, Currency.eur)),
      ],
      plans: [
        for (final p in await dao.plansOf(id))
          DcaPlan(
            id: p.id,
            assetId: p.assetId,
            amount: Money(p.amountCents, Currency.eur),
            frequency: p.frequency,
            start: p.startDate,
            active: p.active,
          ),
      ],
    );
  });

  Future<void> placeOrder(String walletId, Order order) => guardStorage(() {
    final (amount, quantity) = switch (order.size) {
      AmountSize(:final amount) => (amount.minorUnits, null),
      QuantitySize(:final quantity) => (null, quantity.micros),
    };
    final trigger = order.limitPrice ?? order.stopPrice;
    return _db.walletDao.insertOrder(
      OrdersCompanion.insert(
        id: order.id,
        walletId: walletId,
        assetId: order.assetId,
        side: order.side,
        type: order.type,
        amountCents: Value(amount),
        quantityMicros: Value(quantity),
        limitPrice: Value(order.limitPrice?.value),
        stopPrice: Value(order.stopPrice?.value),
        priceCurrency: Value(trigger?.currency),
        status: OrderStatus.pending,
        planId: Value(order.planId),
        createdAt: order.createdAt,
      ),
    );
  });

  /// Books [fill] of [order]: the fill, its notional and fees in the ledger,
  /// and the order closed. All or nothing.
  Future<void> recordFill(String walletId, Order order, Fill fill) =>
      guardStorage(
        () => _db.transaction(() async {
          final dao = _db.walletDao;
          await dao.insertFill(
            FillsCompanion.insert(
              orderId: order.id,
              walletId: walletId,
              assetId: fill.assetId,
              side: fill.side,
              date: fill.date,
              price: fill.price.value,
              currency: fill.price.currency,
              quantityMicros: fill.quantity.micros,
              fxRate: fill.fxRate,
              feesCents: fill.fees.minorUnits,
            ),
          );
          final buy = fill.side == Side.buy;
          await dao.addLedgerEntry(
            CashLedgerCompanion.insert(
              walletId: walletId,
              date: fill.date,
              amountCents: buy
                  ? -fill.notional.minorUnits
                  : fill.notional.minorUnits,
              kind: buy ? LedgerKind.buy : LedgerKind.sell,
              refId: Value(order.id),
            ),
          );
          if (!fill.fees.isZero) {
            await dao.addLedgerEntry(
              CashLedgerCompanion.insert(
                walletId: walletId,
                date: fill.date,
                amountCents: -fill.fees.minorUnits,
                kind: LedgerKind.fee,
                refId: Value(order.id),
              ),
            );
          }
          await dao.closeOrder(order.id, OrderStatus.filled);
        }),
      );

  Future<void> cancelOrder(String orderId, CancelReason reason) => guardStorage(
    () => _db.walletDao.closeOrder(
      orderId,
      OrderStatus.cancelled,
      reason: reason,
    ),
  );

  /// Appends a day to the value series; a day computed again replaces its row.
  Future<void> appendValue(String walletId, DailyValue value) => guardStorage(
    () => _db.walletDao.saveValue(
      WalletValuesCompanion.insert(
        walletId: walletId,
        date: value.date,
        valueCents: value.value.minorUnits,
        flowCents: value.flow.minorUnits,
      ),
    ),
  );

  Future<void> addContribution(String walletId, DateTime date, Money amount) =>
      guardStorage(
        () => _db.walletDao.addLedgerEntry(
          CashLedgerCompanion.insert(
            walletId: walletId,
            date: date,
            amountCents: amount.minorUnits,
            kind: LedgerKind.contribution,
          ),
        ),
      );

  /// Moves [amount] from cash into the Livret; a negative amount moves it
  /// back. Validate it first (`validateLivretTransfer`).
  Future<void> moveToLivret(String walletId, DateTime date, Money amount) =>
      guardStorage(
        () => _db.walletDao.addLedgerEntry(
          CashLedgerCompanion.insert(
            walletId: walletId,
            date: date,
            amountCents: -amount.minorUnits,
            kind: amount.isNegative
                ? LedgerKind.livretOut
                : LedgerKind.livretIn,
          ),
        ),
      );

  Future<void> savePlan(String walletId, DcaPlan plan) => guardStorage(
    () => _db.walletDao.savePlan(
      DcaPlansCompanion.insert(
        id: plan.id,
        walletId: walletId,
        assetId: plan.assetId,
        amountCents: plan.amount.minorUnits,
        frequency: plan.frequency,
        startDate: plan.start,
        active: Value(plan.active),
      ),
    ),
  );

  Fill _fill(FillRow f) => Fill(
    assetId: f.assetId,
    side: f.side,
    date: f.date,
    quantity: Quantity.micros(f.quantityMicros),
    price: Price(f.price, f.currency),
    fxRate: f.fxRate,
    fees: Money(f.feesCents, Currency.eur),
  );

  Order _order(OrderRow o) {
    Price? price(Decimal? value) =>
        value == null ? null : Price(value, o.priceCurrency!);
    return Order(
      id: o.id,
      assetId: o.assetId,
      side: o.side,
      type: o.type,
      size: o.amountCents != null
          ? AmountSize(Money(o.amountCents!, Currency.eur))
          : QuantitySize(Quantity.micros(o.quantityMicros!)),
      limitPrice: price(o.limitPrice),
      stopPrice: price(o.stopPrice),
      createdAt: o.createdAt,
      planId: o.planId,
    );
  }
}
