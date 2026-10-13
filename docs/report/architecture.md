# Architecture

Two programs. The **Flutter app** holds everything the user does and works offline once its cache is
filled. A small **Go backend** sits between the app and the market-data provider: it hides the provider's
key, keeps the whole price history, and spreads the free plan's credits over every user (ADR-004). The app
also calls **Frankfurter** directly for exchange rates (ECB, no key).

```mermaid
flowchart LR
  subgraph phone["Phone"]
    app["Flutter app<br/>Riverpod · drift (SQLite)"]
  end
  subgraph server["Self-hosted"]
    api["Go backend<br/>net/http · SQLite"]
  end
  td["Twelve Data<br/>(daily bars, quotes)"]
  fr["Frankfurter<br/>(ECB exchange rates)"]
  app -- "REST + JSON<br/>/v1/assets, /history, /quotes,<br/>/calendar, /livret, /content" --> api
  app -- "REST + JSON<br/>daily rates over a date range" --> fr
  api -- "after each US close,<br/>within a credit budget" --> td
  api -- "USD→EUR, daily" --> fr
```

## The app: four layers

`presentation → application → domain ← data` (CLAUDE.md rule 1). Each layer knows only the one below it;
the domain knows nobody.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 420}}}%%
flowchart TB
  subgraph P["presentation: widgets, no logic"]
    direction LR
    P1["Screens<br/>MapTab · ArchipelagoMap (CustomPainter)<br/>WalletScreen · AssetScreen · OrderSheet<br/>ExplorerScreen · TripWizardScreen · NodeScreen<br/>DcaScreen · GlossaryScreen · SettingsScreen"]
    P2["Shared states<br/>AsyncSkeleton · ErrorView(failure, onRetry)<br/>CacheStatusBanner"]
  end
  subgraph A["application: Riverpod providers and notifiers"]
    direction LR
    A1["Views<br/>walletOverview · assetOverview · explorerRows<br/>islandPath · nextStepView · walletsList<br/>dcaRun · settingsView · cacheStatus"]
    A2["Intents<br/>OrderTicket · OrderTracker · TripRunner<br/>LiveCatchUp · TripWizard · DcaFormController<br/>node players · SettingsController"]
  end
  subgraph D["domain: pure Dart, unit-tested"]
    direction LR
    D1["Wallet<br/>TripEngine · matchOnBar · fillAtQuote · valueWallet<br/>Position (average cost) · validateOrder<br/>dcaSchedule · investFlows · livret interest"]
    D2["Analytics<br/>returns (simple, TWR) · maxDrawdown<br/>annualisedVolatility · decomposeMove · risk"]
    D3["Learning and market<br/>nextStep · profile rules · node evaluators<br/>companion rules · MarketCalendar"]
  end
  subgraph DA["data: the only layer with I/O"]
    direction LR
    R["Repositories<br/>MarketRepository · FxService · WalletRepository<br/>ContentRepository · ProfileRepository · Favorites…"]
    L["Local: drift<br/>AppDatabase · MarketDao<br/>WalletDao · LearningDao"]
    N["Remote: dio<br/>BackendApi · FrankfurterApi<br/>deviceOnline (connectivity_plus)"]
  end
  C["core, used by every layer: SimulationClock (LiveClock, HistoricalClock)<br/>Money / Quantity / Price · sealed Failure · sealed CacheStatus · theme tokens · formats"]
  P -- "ref.watch (state), ref.read (intents)" --> A
  A -- "calls pure functions" --> D
  A -- "reads, writes" --> R
  R --> L
  R --> N
  R -.->|returns domain types| D
```

The rules are checked, not only written: `app/test/architecture_test.dart` fails CI when a domain file
imports Flutter, Riverpod or `dart:io` or calls `DateTime.now()`, when anything outside `data/` imports dio,
and when a colour is written anywhere but the theme tokens.

| Folder | Holds | Examples |
|---|---|---|
| `lib/core/` | What every layer shares | `SimulationClock`, `Money`, `Failure`, `CacheStatus`, theme tokens, `Formats` |
| `lib/domain/` | Business rules and calculations, pure functions over immutable values | `trip_engine.dart`, `valuation.dart`, `order_matcher.dart`, `analytics/`, `dca.dart` |
| `lib/data/` | drift tables and DAOs, HTTP clients and DTOs, repositories | `market_repository.dart`, `wallet_repository.dart`, `tables.dart` |
| `lib/application/` | One provider or notifier per screen-level concern | `wallet_providers.dart`, `order_ticket.dart`, `trip_runner.dart` |
| `lib/presentation/` | Screens and widgets, by feature | `features/wallet/`, `features/map/`, `routing/router.dart` |

## The backend

```mermaid
flowchart LR
  subgraph cmd
    server["cmd/server<br/>HTTP + scheduler"]
    freeze["cmd/freeze<br/>frozen lesson datasets"]
    check["cmd/contentcheck<br/>validates lesson packs"]
  end
  subgraph internal
    apih["api<br/>handlers, ETag, gzip,<br/>per-client rate limit"]
    jobs["jobs<br/>Syncer (daily append)<br/>QuoteRefresher (30 min)<br/>Budget (credits)"]
    store["store<br/>SQLite: assets, bars,<br/>fx, livret, sync state"]
    prov["provider<br/>Twelve Data adapter"]
    content["content<br/>packs, manifest"]
  end
  server --> apih & jobs
  apih --> store & content
  jobs --> prov & store
  freeze --> prov
  check --> content
```

No user data and no accounts: the backend serves the same public market data and lessons to everyone.

## The data the app keeps

Two groups of tables (`app/lib/data/local/tables.dart`, ADR-002). **Cache** tables hold what came from the
network: Settings can clear them, and they come back. **User** tables hold what only the user created; they
never point at a cache table, so clearing the cache cannot break them. Money is stored as integer cents,
quantities as integer millionths, prices and rates as exact decimal strings (ADR-003).

```mermaid
erDiagram
  WALLETS ||--o{ CASH_LEDGER : "cash = sum of entries"
  WALLETS ||--o{ ORDERS : places
  ORDERS ||--o| FILLS : "fills once"
  WALLETS ||--o{ FILLS : "positions derive from"
  WALLETS ||--o{ WALLET_VALUES : "one per closed day"
  WALLETS ||--o{ DCA_PLANS : has
  DCA_PLANS ||--o{ ORDERS : "places each period"
  WALLETS ||--o{ JOURNAL_ENTRIES : "trip journal"
  WALLETS ||--o{ COMPANION_LOG : "moments shown"
  WALLETS {
    text id PK
    text kind "live or trip"
    datetime startDate
    datetime simDate "a trip's day"
    text params "rules, contribution, stops"
    text status "active, stopped, finished"
  }
  ORDERS {
    text id PK
    text assetId
    text side
    text type "market, limit, stop"
    int amountCents "xor quantityMicros"
    text status "pending, filled, cancelled"
  }
  FILLS {
    int id PK
    text orderId
    datetime date
    text price
    int quantityMicros
    text fxRate
    int feesCents
  }
  CASH_LEDGER {
    int id PK
    datetime date
    int amountCents
    text kind
  }
  WALLET_VALUES {
    datetime date PK
    int valueCents
    int flowCents
  }
  PROFILES {
    int id PK "single row"
    text goal
    text dropReaction
    text language
    bool showAll
  }
  NODE_PROGRESS {
    text nodeId PK
    text status
    datetime completedAt
  }
  FAVORITES {
    text assetId PK
  }
  DCA_SIMULATIONS {
    text id PK
    text params
    text result
  }
  ASSETS ||--o{ PRICE_BARS : "daily, adjusted"
  ASSETS ||--o| HISTORY_SYNC : "how far cached"
  ASSETS ||--o| QUOTES : "latest"
  CALENDAR_YEARS ||--o{ EXCHANGE_HOLIDAYS : lists
  ASSETS {
    text id PK
    text symbol
    text exchange
    text currency
  }
  PRICE_BARS {
    text assetId PK
    datetime date PK
    text close
  }
  HISTORY_SYNC {
    text assetId PK
    datetime lastDate
    datetime fetchedAt
    datetime adjustedAt
  }
  QUOTES {
    text assetId PK
    text price
    datetime asOf
    datetime fetchedAt
  }
  FX_RATES {
    text base PK
    text quote PK
    datetime date PK
    text rate
  }
```

Not drawn: `glossary_state`, `livret_rates` and `livret_ceilings`, `calendar_years`' columns,
`content_packs`. Positions are never stored: they are derived from fills (average cost), so the ledger,
the fills and the daily values are the whole truth. The schema is at version 3; every version ships with a
migration and a test that upgrades a database of each older version (`app/test/drift/`).

## One read, end to end

Opening an asset page: what runs, and where each decision is taken.

```mermaid
sequenceDiagram
  autonumber
  participant S as AssetScreen
  participant P as assetOverview (provider)
  participant M as MarketRepository
  participant DB as drift
  participant B as BackendApi
  participant Dm as domain
  S->>P: ref.watch(assetOverviewProvider(id))
  P-->>S: AsyncLoading → AsyncSkeleton
  P->>M: history(id, asOf), latest, calendar
  M->>DB: history_sync: how far is it cached?
  alt cached and checked less than 15 min ago
    DB-->>M: bars up to asOf
  else new days may exist
    M->>B: GET /v1/assets/{id}/history?from=lastDate+1
    B-->>M: the missing days only
    M->>DB: one transaction: bars + history_sync
  end
  M-->>P: bars cut at asOf (no lookahead)
  P->>Dm: returns, drawdown, volatility, decomposition
  Dm-->>P: figures (Decimal)
  P-->>S: AsyncData → the page
  Note over M,B: Network failure: the cache stands in, status() emits Stale or Offline,<br/>CacheStatusBanner shows when prices were last fetched.<br/>Nothing cached: a typed Failure → AsyncError → ErrorView with Retry.
```

## The architecture questions (subject §12)

**Where is the application's state, and why?** The source of truth is the drift database: wallets, orders,
fills, progress, settings. Riverpod providers (`lib/application/`) hold what is derived from it for the
screens (a wallet's valuation, an asset's figures, a lesson's state) and recompute when what they watch
changes. Widgets keep only what belongs to the screen itself: a text field's controller, an animation's
controller. One place to persist, many cheap views, and every view testable without a widget (ADR-001).

**Who decides between the API and the cache?** The repositories, and only they (BRIEF §6.3):
`MarketRepository`, `FxService`, `ContentRepository`. A provider asks for « Apple's history as of this
date »; the repository answers from drift and decides on its own whether a request is due
(ADR-005, [cache.md](cache.md)). The UI never knows where data came from, except through `CacheStatus`.

**Where are the business calculations?** In `lib/domain/`, as pure functions over immutable values, with no
Flutter, no I/O and no clock: valuation, order matching, the trip engine, returns (simple and
time-weighted), drawdown, volatility, the move decomposition, DCA, Livret interest. Time is an argument
(`asOf`), so a function gives the same answer for a live wallet and for a trip in 2008. They carry most of
the unit tests ([tests.md](tests.md)).

**Who is responsible for persistence?** The data layer: `AppDatabase` (drift) and its DAOs, used only
through repositories (`WalletRepository`, `ProfileRepository`…). A trade is one transaction: the order, its
fill and its ledger entries (the amount and the fees) are written together or not at all.

**How do errors and loading reach the screen?** Every failure is typed where it happens: `http.dart` maps
Dio errors to `NetworkFailure`, `RateLimitedFailure`, `NotFoundFailure` or `ServerFailure`, and
`guardStorage` maps database errors to `StorageFailure`; a trip past the cached data throws
`DataUnavailableFailure`. Providers are asynchronous, so Riverpod hands the screen an `AsyncValue`:
loading, data or error. Screens switch on it and use three shared widgets: `AsyncSkeleton` while loading,
`ErrorView` (the failure in words, a Retry that invalidates the provider), and the content. A refresh keeps
the previous data on screen. Staleness is not an error: it travels separately, as the `CacheStatus` stream
behind `CacheStatusBanner`.

**What happens when a widget rebuilds?** Nothing expensive. `build` only watches providers and lays out
what they hold; nothing is fetched in `build`. A provider keeps its value across rebuilds and recomputes
only when something it watches changes or it is invalidated, so a rebuild reuses the last result. State that
must outlive a frame lives in `State` objects (an animation controller belongs to its widget's `State`,
which disposes it) or in a provider. A provider nobody watches anymore is disposed; an action controller that a
screen only reads is kept alive on purpose (M9-9).
