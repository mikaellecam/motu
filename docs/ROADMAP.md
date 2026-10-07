# Investment Companion — roadmap

One issue = one branch = one PR. Each issue lists its spec sections, scope, acceptance criteria (AC) and
guardrails. Issues are sized for one agent session. Order inside a milestone follows dependencies.
Spec references point to `docs/BRIEF.md`.

---

## M0 — Foundations

**M0-1 · Monorepo scaffold**
Spec: CLAUDE.md, §5.1, §8.2
Scope: `app/` Flutter project, `backend/` Go module, `content/`, `docs/decisions/`, CI (analyze + test for
both sides, contentcheck stub).
AC: CI green on an empty feature set; `flutter analyze` and `go vet` run in CI; README links CLAUDE.md.
Guardrails: no feature code; no dependencies outside §5.4.

**M0-2 · Theme tokens and base widgets**
Spec: §10
Scope: `core/theme` (colors with role names, Baloo 2 + Figtree bundled, text styles with tabular figures,
spacing), chunky and flat card/button variants, `AsyncSkeleton`, `ErrorView`, `StaleBanner`.
AC: a debug-only gallery screen shows every component in both families; no hex values outside `core/theme`.

**M0-3 · Localization setup**
Spec: §11, §10.3
Scope: ARB fr/en, French number/date/currency formatting helpers (narrow no-break spaces, decimal comma).
AC: formatting helpers unit-tested (`51 534,60 €`, `−2,88 %`, `+1 534,60 €`).

**M0-4 · ADR template + first ADRs**
Scope: template; ADR-001 state management (Riverpod), ADR-002 persistence (drift), ADR-003 money
representation.
AC: three ADRs merged, each with options considered.

---

## M1 — Domain core (pure Dart, test-first)

**M1-1 · Money, Quantity, Price, Currency**
Spec: §7 intro, CLAUDE rule 4
AC: arithmetic, rounding half-even at format time, currency mismatch throws typed error; 100 % branch coverage.

**M1-2 · SimulationClock + MarketCalendar**
Spec: §5.2, §4.6 market hours
Scope: `LiveClock`, `HistoricalClock`, trading-day helpers (next/previous trading day), market open/closed for
Euronext and NYSE/Nasdaq using exchange time zones.
AC: DST-mismatch weeks (late March, late October) tested; holidays from an injected calendar.

**M1-3 · Positions and valuation**
Spec: §7.1–7.5
AC: average-cost behaviour, realised/unrealised P&L, allocation sums to 1, stale price fallback flagged.

**M1-4 · Analytics: returns, TWR, volatility, drawdown, risk band, concentration**
Spec: §7.6–7.11
AC: all §7 edge-case tests for these functions; volatility `null` under 20 returns.

**M1-5 · Move decomposition**
Spec: §7.9
AC: EUR asset → currency component 0; USD asset fixtures with known results; residual documented in code.

**M1-6 · Order validation and OrderMatcher**
Spec: §4.6, §7.14
AC: every validation error has a code + params for l10n; fill rules for market/limit/stop incl. gaps; fees
(fx + fixed); whole-share wallets reject fractional quantities.

**M1-7 · Livret A interest**
Spec: §4.11, §7.13
AC: quinzaine eligibility (deposit on 15th vs 16th, withdrawal mid-quinzaine), rate change mid-year,
31 December capitalisation, ceiling on deposits.

**M1-8 · DCA engine + counterfactuals**
Spec: §4.10, §7.12
AC: schedule rolling over non-trading days; lump sum and Livret comparisons on the same flows.

**M1-9 · TripEngine.advance**
Spec: §4.5 "Advancing time"
AC: day-by-day loop order (contribution → DCA → matcher → Livret → valuation → stop/companion checks);
each stop condition tested; never reads data after the target day.

**M1-10 · Learning rules: profile, next step, missions**
Spec: §4.1, §4.2, §4.3
AC: `startingNode`, `initialUiLevel`, `momentThresholds`, `pacing`, `nextStep`, mission detectors for nodes
3, 8, 11 — all table-driven tests.

**M1-11 · Companion rule engine**
Spec: §4.12
AC: each rule fires and respects cooldown; `panic_sell` follow-up scheduled 3 months later.

---

## M2 — Backend gateway

**M2-1 · Provider verification spike** (blocks M2-3)
Spec: §8.5
Scope: check Twelve Data free tier for history depth, adjusted prices, EU exchange coverage, symbols for the
§8.4 catalogue.
AC: ADR-004 with findings, chosen `dataFloor`, final symbol map. **No production code.**

**M2-2 · Store + schema**
Spec: §8.2
AC: SQLite store for assets, bars, fx, livret rates, sync state; migrations; tests on a temp DB.

**M2-3 · Provider adapter + backfill job**
AC: adapter behind interface with a fake for tests; backfill respects a configurable rate budget and resumes
after interruption; daily append job after US close.

**M2-4 · HTTP API**
Spec: §8.3
AC: all endpoints with conditional requests (ETag/Last-Modified), error envelope, 429 + Retry-After;
handler tests with the fake provider.

**M2-5 · Livret rates + calendar data**
AC: dated rate history seeded and served; exchange calendars served per year.

**M2-6 · Docker + deploy notes**
AC: image builds; `.env.example`; healthcheck; deploy steps documented for self-hosting.

---

## M3 — App data layer

**M3-1 · drift database**
Spec: §6.1
AC: all tables, DAOs, migration test harness.

**M3-2 · Remote clients + DTOs**
Spec: §8.3, §5.4
AC: backend client and Frankfurter client; JSON → Dart via json_serializable; typed failures mapped from
HTTP errors and timeouts.

**M3-3 · MarketRepository with incremental cache**
Spec: §6.2, §6.3, §5.2
AC: first fetch, incremental `from = lastDate + 1`, quote TTL by market hours, adjustment invalidation, `asOf`
clamp (no lookahead) — all tested with fakes.

**M3-4 · FxService (Frankfurter direct + cache)**
AC: missing date → previous available rate; never calls the network for a cached date.

**M3-5 · Connectivity + CacheStatus**
AC: `fresh / stale(lastUpdated) / offline` stream; `StaleBanner` driven by it.

**M3-6 · Wallet repository**
AC: ledger + orders + fills persistence; positions derived on read; daily value series appended.

---

## M4 — Sandbox: live wallet

**M4-1 · Navigation shell + tabs**
Spec: §3
AC: go_router routes, bottom tabs, deep-link to trip wizard with prefill params.

**M4-2 · Wallet screen**
Spec: §4.7
AC: header (value, change, Investi, Liquidités disponibles, Investir), period chart with baseline and
benchmark toggle, allocation, positions without cash row; loading/error/stale states.

**M4-3 · Explorer**
Spec: §4.9
AC: search, filters, favorites persisted, risk meter, offline banner; dynamic list performance OK with 30+ rows.

**M4-4 · Asset page**
Spec: §4.8
AC: price + € equivalent + timestamp, chart periods, buy markers, drawdown annotation, essentials tiles
opening glossary sheets, decomposition card, position block.

**M4-5 · Order sheet + validation + pre-trade coach**
Spec: §4.6
AC: amount/quantity toggle, quick amounts, fees summary, all validation errors with fr/en copy, soft gate on
first limit/stop selection, coach card, market-closed notice.

**M4-6 · Pending orders lifecycle**
AC: pending → filled on next session bar (app start / refresh); order-placed screen with steps.

**M4-7 · Wallets list**
Spec: §4.5
AC: live wallet card, trips with status, lesson suggestion cards, « Nouveau voyage ».

---

## M5 — Time travel

**M5-1 · Trip wizard step 1 (dates)**
AC: presets with availability counts, quick presets, custom date with all validation rules incl. the
pre-`dataFloor` error and lesson link.

**M5-2 · Trip wizard steps 2–3**
AC: difficulty presets table, custom ranges validated, safety-cushion option, recap with Modifier links,
name validation, stop-condition defaults; creates the wallet.

**M5-3 · Trip wallet screen + time controls**
AC: neutral trip header (no tinted banner), +1 day/week/month, all providers scoped to the trip clock.

**M5-4 · Fast-forward sheet + automatic stop**
AC: target date validation, stop conditions editable, stop screen with threshold chart, three neutral
choices, optional reason saved to the journal.

**M5-5 · Trip summary**
AC: TWR vs counterfactuals (sans rien toucher, Livret A, ta pire décision when applicable), journal replay,
glossary terms met.

---

## M6 — Learning engine

**M6-1 · Content pack loader + bundled baseline**
Spec: §4.3
AC: bundled pack loads offline; newer manifest version fetched and cached; corrupt pack falls back to bundled.

**M6-2 · `contentcheck` + `freeze` CLIs**
Spec: §4.3, §9
AC: schema, locales, glossary refs, dataset refs validated in CI; `freeze` writes adjusted datasets with
provenance.

**M6-3 · Node player: predict_reveal + toy**
AC: both types render from pack data; "Et aujourd'hui ?" variant online only; completion persisted.

**M6-4 · Node player: decision + sort + build_puzzle + checkpoint**
AC: each type renders and completes; build_puzzle constraints checked by domain calcs.

**M6-5 · Missions + bridges**
AC: mission nodes complete automatically from wallet state; bridge opens the prefilled wizard.

**M6-6 · Glossary index + sheet**
Spec: §4.4
AC: discovered states persisted, live example widget registry, related chips, mini-quiz.

**M6-7 · Onboarding**
Spec: §4.1
AC: five questions with validation error state, derived profile persisted, explanation sentence, retake from
Settings without losing progress.

**M6-8 · Actions & ETF content (12 nodes, ≈ 26 glossary terms)**
AC: all nodes and terms in fr + en, datasets frozen, `contentcheck` green. Text drafted by agent →
`status: draft` until Bob validates.

---

## M7 — Map and animations

**M7-1 · Isometric renderer**
Spec: §4.2, §10.5
AC: `CustomPainter` iso primitives (tile, box, roof, candle, crystal), 5 islands, locked state, pan/zoom,
tap targets with Semantics.

**M7-2 · Living island**
AC: building heights from live positions with animated transitions; pending order = construction →
completion animation.

**M7-3 · Next-step card + level chip**
AC: driven by `nextStep(state)`; updates live.

**M7-4 · Reveal curve animation + counters**
AC: `PathMetric`-based progressive drawing; value counters; respects reduced-motion setting.

---

## M8 — Livret, DCA tool, companion

**M8-1 · Livret line in wallets**
AC: transfers cash ↔ Livret, interest accrual shown, ceiling enforced, benchmark toggle on wallet chart.

**M8-2 · DCA simulator screen**
Spec: §4.10
AC: form validation, result, chart, lump-sum and Livret comparisons, save/list/rerun simulations.

**M8-3 · Companion cards in UI**
AC: cards on map/wallet/asset as specified, dismiss + cooldown persisted, links open glossary/nodes.

---

## M9 — Polish and hand-in

**M9-1 · Settings screen** (§4.14) — AC: every setting persisted; reset requires confirmation; cache size shown.
**M9-2 · English pass** — AC: no missing keys; content packs complete in en.
**M9-3 · Accessibility pass** — AC: Semantics on all icon buttons, 44 px targets, signed numbers, text scale 1.3 OK.
**M9-4 · Offline QA script** — AC: documented manual test (kill app, airplane mode) passes on every tab.
**M9-5 · Report material** — AC: architecture diagram, ADR index, cache strategy write-up, test list, screenshots.
