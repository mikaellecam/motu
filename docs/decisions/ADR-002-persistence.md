# ADR-002: drift (SQLite) for local persistence

Status: accepted
Date: 2026-10-07

## Context

The app stores two kinds of data on the device, and the school brief (§5) asks us to tell them apart:

- **User data**, the source of truth that nothing can refetch: wallets, the cash ledger, orders, fills,
  daily wallet values, DCA plans and saved simulations, the trip journal, the profile, lesson progress,
  discovered glossary terms, favorites, the companion log (`BRIEF.md` §6.1).
- **Cached API data**, refetchable but expensive: daily price bars, latest quotes, FX rates, Livret A rates,
  sync state per asset, content packs.

The data is relational and queried by range: "bars of asset X between two dates, on or before `asOf`",
"the last synced date of asset X", "every fill of wallet W". The cache is the largest part: about 30 assets ×
26 years × 252 trading days ≈ 200 000 price bars. Everything must be readable offline (§6.4). The schema will
grow over the project, so migrations are required, and every schema change ships with a migration test
(CLAUDE.md rule 7).

## Options considered

### `shared_preferences`

Key-value storage for a few small values. No queries, no transactions, no schema: unsuitable for a ledger or
200 000 bars. At most a fit for settings, which are better kept next to the rest of the data anyway.

### Hive / Isar (NoSQL object stores)

Fast and simple to start with, no SQL. But range and join queries ("fills of a wallet with their orders") are
written by hand, there is no relational integrity, and migrations are manual. Both projects lost their
original maintainers and now live on as community forks, a risk for a project graded on maintainable design.

### `sqflite` (raw SQLite)

The right storage engine, but queries are strings and rows are `Map<String, Object?>`: every mapping is
hand-written and type errors appear at runtime. Migrations are hand-rolled `ALTER TABLE` scripts with no
tooling to test them.

### drift (typed SQLite)

SQLite underneath, with tables declared in Dart and generated typed row classes and queries. Queries are
checked at compile time, can be watched as streams (the wallet screen updates when a fill is written), and
run in transactions. Migrations are versioned, and drift's schema dumps generate a test harness that checks
each migration step against the real schema. Tests run against an in-memory database. Costs: code generation
(`build_runner`) and a native SQLite library bundled with the app.

## Decision

drift with `sqlite3_flutter_libs`. Our data is relational and range-queried, and migrations must be tested:
drift is the only option that gives SQL's query power with compile-time types and migration tooling.

## Consequences

- **One database, two groups of tables.** User tables (`wallets`, `cash_ledger`, `orders`, `fills`,
  `wallet_values`, `dca_plans`, `dca_simulations`, `journal_entries`, `profile`, `node_progress`,
  `glossary_state`, `favorites`, `companion_log`) are never deleted by cache operations. Cache tables
  (`price_bars`, `quotes`, `fx_rates`, `livret_rates`, `history_sync`, `content_packs`) can be cleared from
  Settings at any time and rebuilt from the network.
- **Repositories own persistence.** DAOs are used only by repositories in `app/lib/data/`; notifiers and
  widgets never see tables or SQL.
- **Derived data is not stored.** Positions are computed from fills on read (average cost, §7.1), so there is
  a single source of truth and no position table to keep in sync.
- **Range queries are indexed by design:** `price_bars` has primary key `(assetId, date)` and `fx_rates`
  `(date, base, quote)`, which serve the incremental-fetch and `asOf` queries directly.
- **Every schema change** bumps the schema version, adds a migration step, dumps the new schema and adds a
  migration test.
- Adds `drift`, `sqlite3_flutter_libs`, `drift_dev` and `build_runner`, all on the §5.4 list.
