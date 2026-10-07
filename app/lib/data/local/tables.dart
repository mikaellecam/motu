import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

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

/// Local schema (BRIEF §6.1, ADR-002). Two groups of tables:
///
/// - **cache**: data fetched from the network, cleared from Settings at any
///   time and fetched again;
/// - **user**: data only the user created, never touched by cache clearing.
///
/// User tables never reference cache tables, so clearing the cache cannot
/// break them. Money is integer cents (EUR), quantities integer millionths,
/// prices and rates exact decimal strings.

/// Exact decimals stored as text.
class DecimalConverter extends TypeConverter<Decimal, String> {
  const DecimalConverter();
  @override
  Decimal fromSql(String fromDb) => Decimal.parse(fromDb);
  @override
  String toSql(Decimal value) => value.toString();
}

// ---------------------------------------------------------------- cache ----

@DataClassName('AssetRow')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get symbol => text()();
  TextColumn get name => text()();
  TextColumn get type => textEnum<AssetType>()();
  TextColumn get exchange => textEnum<Exchange>()();
  TextColumn get currency => textEnum<Currency>()();
  TextColumn get region => text()();
  DateTimeColumn get listingDate => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PriceBarRow')
class PriceBars extends Table {
  TextColumn get assetId => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get open => text().map(const DecimalConverter())();
  TextColumn get high => text().map(const DecimalConverter())();
  TextColumn get low => text().map(const DecimalConverter())();
  TextColumn get close => text().map(const DecimalConverter())();
  IntColumn get volume => integer()();

  @override
  Set<Column> get primaryKey => {assetId, date};
}

/// Latest price per asset (live wallet only).
@DataClassName('QuoteRow')
class Quotes extends Table {
  TextColumn get assetId => text()();
  TextColumn get price => text().map(const DecimalConverter())();
  TextColumn get currency => textEnum<Currency>()();

  /// When the price was observed on the market.
  DateTimeColumn get asOf => dateTime()();
  DateTimeColumn get fetchedAt => dateTime()();
  BoolColumn get marketOpen => boolean()();

  @override
  Set<Column> get primaryKey => {assetId};
}

/// Units of [quote] per unit of [base] on a date.
@DataClassName('FxRateRow')
class FxRates extends Table {
  TextColumn get base => textEnum<Currency>()();
  TextColumn get quote => textEnum<Currency>()();
  DateTimeColumn get date => dateTime()();
  TextColumn get rate => text().map(const DecimalConverter())();

  @override
  Set<Column> get primaryKey => {base, quote, date};
}

@DataClassName('LivretRateRow')
class LivretRates extends Table {
  DateTimeColumn get validFrom => dateTime()();
  TextColumn get annualRate => text().map(const DecimalConverter())();

  @override
  Set<Column> get primaryKey => {validFrom};
}

@DataClassName('LivretCeilingRow')
class LivretCeilings extends Table {
  DateTimeColumn get validFrom => dateTime()();
  IntColumn get amountCents => integer()();

  @override
  Set<Column> get primaryKey => {validFrom};
}

/// How far each asset's history is cached: the next fetch starts at
/// [lastDate] + 1 (BRIEF §6.2).
@DataClassName('HistorySyncRow')
class HistorySync extends Table {
  TextColumn get assetId => text()();
  DateTimeColumn get firstDate => dateTime()();
  DateTimeColumn get lastDate => dateTime()();
  DateTimeColumn get fetchedAt => dateTime()();

  /// The backend's last full refetch after a split; a newer one invalidates
  /// the cached history.
  DateTimeColumn get adjustedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {assetId};
}

@DataClassName('ExchangeHolidayRow')
class ExchangeHolidays extends Table {
  TextColumn get exchange => textEnum<Exchange>()();
  DateTimeColumn get date => dateTime()();

  @override
  Set<Column> get primaryKey => {exchange, date};
}

/// Years whose holidays are cached, per exchange.
@DataClassName('CalendarYearRow')
class CalendarYears extends Table {
  TextColumn get exchange => textEnum<Exchange>()();
  IntColumn get year => integer()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {exchange, year};
}

@DataClassName('ContentPackRow')
class ContentPacks extends Table {
  TextColumn get islandId => text()();
  IntColumn get version => integer()();
  TextColumn get json => text()();
  TextColumn get etag => text().nullable()();
  DateTimeColumn get checkedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {islandId};
}

// ----------------------------------------------------------------- user ----

@DataClassName('WalletRow')
class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<WalletKind>()();
  TextColumn get name => text()();
  DateTimeColumn get startDate => dateTime()();

  /// The trip's simulated day; null for the live wallet.
  DateTimeColumn get simDate => dateTime().nullable()();
  TextColumn get difficulty => text().nullable()();

  /// Trading rules, contribution and stop conditions, as JSON.
  TextColumn get params => text()();
  TextColumn get status => textEnum<WalletStatus>()();
  DateTimeColumn get createdAt => dateTime()();

  /// Stop thresholds that held at the last evaluation (JSON list).
  TextColumn get breachedStops => text().withDefault(const Constant('[]'))();

  /// The companion's running facts (JSON); null before the first day.
  TextColumn get companionState => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

enum LedgerKind { start, contribution, buy, sell, fee, livretIn, livretOut }

/// Every movement of a wallet's cash. Cash = the sum of [amountCents].
/// Livret transfers are the Livret's movements too; its interest is computed
/// from them and the rates, never stored.
@DataClassName('LedgerEntryRow')
class CashLedger extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get walletId =>
      text().references(Wallets, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get date => dateTime()();
  IntColumn get amountCents => integer()();
  TextColumn get kind => textEnum<LedgerKind>()();

  /// The order or plan the movement belongs to, if any.
  TextColumn get refId => text().nullable()();
}

@DataClassName('OrderRow')
class Orders extends Table {
  TextColumn get id => text()();
  TextColumn get walletId =>
      text().references(Wallets, #id, onDelete: KeyAction.cascade)();
  TextColumn get assetId => text()();
  TextColumn get side => textEnum<Side>()();
  TextColumn get type => textEnum<OrderType>()();

  /// Exactly one of [amountCents] and [quantityMicros] is set.
  IntColumn get amountCents => integer().nullable()();
  IntColumn get quantityMicros => integer().nullable()();
  TextColumn get limitPrice =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get stopPrice => text().map(const DecimalConverter()).nullable()();

  /// Currency of the limit or stop price.
  TextColumn get priceCurrency => textEnum<Currency>().nullable()();
  TextColumn get status => textEnum<OrderStatus>()();
  TextColumn get cancelReason => textEnum<CancelReason>().nullable()();

  /// The DCA plan that placed the order.
  TextColumn get planId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK ((amount_cents IS NULL) != (quantity_micros IS NULL))',
  ];
}

/// One per filled order: no partial fills. [id] keeps same-day fills in
/// execution order, which average cost depends on.
@DataClassName('FillRow')
class Fills extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get orderId =>
      text().unique().references(Orders, #id, onDelete: KeyAction.cascade)();
  TextColumn get walletId =>
      text().references(Wallets, #id, onDelete: KeyAction.cascade)();
  TextColumn get assetId => text()();
  TextColumn get side => textEnum<Side>()();
  DateTimeColumn get date => dateTime()();
  TextColumn get price => text().map(const DecimalConverter())();
  TextColumn get currency => textEnum<Currency>()();
  IntColumn get quantityMicros => integer()();
  TextColumn get fxRate => text().map(const DecimalConverter())();
  IntColumn get feesCents => integer()();
}

/// End-of-day value and external flow: charts and TWR.
@DataClassName('WalletValueRow')
class WalletValues extends Table {
  TextColumn get walletId =>
      text().references(Wallets, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get date => dateTime()();
  IntColumn get valueCents => integer()();
  IntColumn get flowCents => integer()();

  @override
  Set<Column> get primaryKey => {walletId, date};
}

@DataClassName('DcaPlanRow')
class DcaPlans extends Table {
  TextColumn get id => text()();
  TextColumn get walletId =>
      text().references(Wallets, #id, onDelete: KeyAction.cascade)();
  TextColumn get assetId => text()();
  IntColumn get amountCents => integer()();
  TextColumn get frequency => textEnum<DcaFrequency>()();
  DateTimeColumn get startDate => dateTime()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DcaSimulationRow')
class DcaSimulations extends Table {
  TextColumn get id => text()();
  TextColumn get params => text()();
  TextColumn get result => text()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The trip journal (BRIEF §4.13).
@DataClassName('JournalEntryRow')
class JournalEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get walletId =>
      text().references(Wallets, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get simDate => dateTime()();

  /// The automatic stop that asked for the decision, if any.
  TextColumn get eventId => text().nullable()();
  TextColumn get decision => text()();
  TextColumn get reason => text().nullable()();
}

/// The onboarding answers: a single row (id 1).
@DataClassName('ProfileRow')
class Profiles extends Table {
  IntColumn get id => integer()();
  TextColumn get goal => textEnum<Goal>()();
  TextColumn get dropReaction => textEnum<DropReaction>()();
  TextColumn get knowledge => textEnum<Knowledge>()();
  TextColumn get savings => textEnum<Savings>()();
  TextColumn get weeklyTime => textEnum<WeeklyTime>()();

  /// « Tout afficher dès maintenant » (BRIEF §4.15).
  BoolColumn get showAll => boolean().withDefault(const Constant(false))();

  /// `fr` or `en`; null follows the device.
  TextColumn get language => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (id = 1)'];
}

enum NodeStatus { started, completed }

@DataClassName('NodeProgressRow')
class NodeProgress extends Table {
  TextColumn get nodeId => text()();
  TextColumn get status => textEnum<NodeStatus>()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastAnswer => text().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {nodeId};
}

@DataClassName('GlossaryStateRow')
class GlossaryState extends Table {
  TextColumn get termId => text()();
  DateTimeColumn get discoveredAt => dateTime()();
  BoolColumn get quizPassed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {termId};
}

@DataClassName('FavoriteRow')
class Favorites extends Table {
  TextColumn get assetId => text()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {assetId};
}

/// Moments the companion showed, for cooldowns and the unread list.
@DataClassName('CompanionLogRow')
class CompanionLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get walletId =>
      text().references(Wallets, #id, onDelete: KeyAction.cascade)();
  TextColumn get rule => textEnum<CompanionRule>()();
  TextColumn get key => text()();
  DateTimeColumn get firedAt => dateTime()();

  /// What the card's copy needs (JSON).
  TextColumn get params => text()();
  DateTimeColumn get dismissedAt => dateTime().nullable()();
}
