# Decisions

Each architecture choice is an ADR in this folder: context, the options weighed, the decision, its
consequences (`template.md`). Product decisions taken along the way are recorded, dated, in `docs/BRIEF.md`
where they apply; the main ones are listed below.

## Architecture decision records

| ADR | Decision | In short |
|---|---|---|
| [ADR-001](ADR-001-state-management.md) | Riverpod for state management | Riverpod with code generation: `AsyncValue` for every async state, `family` to scope a provider to one wallet, overrides to test without widgets. |
| [ADR-002](ADR-002-persistence.md) | drift (SQLite) for local persistence | The data is relational and range-queried (price bars by date, fills by wallet); drift gives SQL with compile-time types and tested migrations. Cache and user tables are kept apart. |
| [ADR-003](ADR-003-money-representation.md) | Money as integer cents, quantities as fixed point, prices as `Decimal` | No `double` for money. A value is rounded half-even once, when booked (a fill, a fee, interest) or displayed; ratios stay exact in `Decimal`. |
| [ADR-004](ADR-004-market-data-provider.md) | Twelve Data free plan, US listings only | 29 instruments with history from 2000-01-03 (`dataFloor`), adjusted for dividends and splits; ACWI as the world ETF; exchange rates from Frankfurter (ECB). |
| [ADR-005](ADR-005-market-cache-policy.md) | Market data cache policy | What the app fetches when, and keeps how long: whole history once then only new days, quotes for 15 min in session, catalogue and calendar daily, FX like history. Reads are cut at `asOf`; the cache stands in when the network fails. |
| [ADR-006](ADR-006-content-packs.md) | Content packs: one document per version, bundled and fetched | Lessons ship inside the app (offline from the first launch) and newer versions download once a day when they read correctly; `contentcheck` validates every pack in CI. |
| [ADR-007](ADR-007-provider-data-out-of-git.md) | Provider data stays out of git; recipes rebuild it | Git keeps each dataset's `cmd/freeze` recipe (`datasets.json`); `scripts/fetch-data.sh` rebuilds the datasets, the app's bundle and the logos from a key. CI runs on made-up prices, which a release refuses. |
| [ADR-008](ADR-008-insee-consumer-prices.md) | Inflation from INSEE's consumer price index | Les bases' purchasing-power datasets restate a Livret or notes at INSEE's monthly index (base 2025, from 1996), the figure the news gives; keyless, rebuilt from recipes like every dataset. |

## Product decisions in the brief

| Date | Decision | Where |
|---|---|---|
| 2026-10-08 | Market data provider and catalogue: Twelve Data free plan, US listings, data floor 2000-01-03 | ADR-004, BRIEF §14.5–6 |
| 2026-10-09 | Allocation bar: the primary colour, lighter as positions get smaller; cash and the Livret neutral | BRIEF §10.2 (`AppColors.allocationShade`) |
| 2026-10-11 | Predict-and-reveal curves show what the money invested became; the fees toy's return starts from real data and becomes an assumption once moved | BRIEF §4.3 |
| 2026-10-11 | Glossary: live examples on the asset's figures, a status per term (discovered, new, to discover) | BRIEF §4.4 |
| 2026-10-11 | Automatic stops: three neutral choices (« Garder », « Vendre la moitié », « Tout vendre »), each with its upside and downside | BRIEF §4.5 |
| 2026-10-11 | Pending orders in the live wallet: a catch-up runs the trip engine up to the last closed session; an order takes part from the first session that opened after it | BRIEF §4.6 |
| 2026-10-11 | Order sheet: quick amounts, fees and total before sending, a concentration coach that never blocks | BRIEF §4.6 |
| 2026-10-11 | DCA simulator: the live wallet's fees, compared with investing everything on day one and with a Livret A | BRIEF §4.10 |
| 2026-10-11 | A content release has no draft node or term (`contentcheck -release`) | BRIEF §9 |
| 2026-10-12 | Settings: language, level, data, simulation capital and FX fee | BRIEF §4.14 |
| 2026-10-12 | A live order placed offline waits as pending for the next session's open; it never fills at a cached price | BRIEF §6.4, §14.1 |
| 2026-10-13 | The map follows the approved art direction and may use colours of its own (`MapPalette`) | BRIEF §4.2, §10.2 |
| 2026-10-24 | Every screen follows the art direction canvas, artboard by artboard; two component families, chunky (the game talking, what you touch) and flat (the figures of your money) | BRIEF §4, §10.1 |
| 2026-10-24 | A trip has no maximum length; once it reaches today it goes on at the pace of real days | BRIEF §4.5, §14.2 |
| 2026-10-24 | Islands share no cash: each teaches its own thing | BRIEF §14.3 |
| 2026-10-24 | Comparisons with a Livret A respect the ceiling of each date; money above it waits as cash | BRIEF §4.11 |
| 2026-10-25 | « Stabilité passée »: a score out of 100 on the asset page, its four parts shown, never used to rank | BRIEF §4.8, §14.4 |
| 2026-10-27 | Motu's icon: the developed island, drawn like the map | BRIEF §10.6 |
| 2026-10-28 | Every control is chunky, on every screen; the glossary is a world screen | BRIEF §10.1, §4.4 |
| 2026-10-28 | Les bases comes first and opens Actions & ETF; the questionnaire can skip it | BRIEF §4.1, §4.2 |
| 2026-10-28 | A quiz's choices come in a new order each time | BRIEF §4.3 |
| 2026-11-16 | No map page: the « Archipel » tab opens on the island the user was on, up close; the sea chart sails between them | BRIEF §3, §4.2 |
| 2026-11-16 | Actions & ETF is a business district and Les bases the mainland's port, a building or a part per lesson | BRIEF §4.2 |
| 2026-11-16 | The lessons' islands and the wallets' islands are never mixed | BRIEF §4.2 |
| 2026-11-17 | A lesson goes on in cards after its interaction: a worked example, a comparison, a quick check | BRIEF §4.3 |
| 2026-11-17 | The questionnaire drops its weekly time question (schema v7) | BRIEF §4.1, §14.7 |
| 2026-11-17 | Lessons skipped at onboarding stay hidden until their turn | BRIEF §4.3 |
| 2026-11-17 | The wallets list joins the world family | BRIEF §4.5, §10.1 |

Every question BRIEF §14 listed is decided; none is open.
