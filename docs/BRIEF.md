# Investment Companion — product & architecture brief

Status: V1 spec. Owner: Bob. Agents implement; they do not decide product questions (see §14).
Visual reference (for humans): design canvas "Investment Companion", direction A ("toy blocks").
Agents rely on the tokens and rules in §10, not on the canvas.

---

## 1. Product

### 1.1 Problem and target user

French beginners, 18–30, whose savings sit on a Livret A or a current account and who have never invested.
Investing feels risky and opaque; theory courses bore them; trading apps intimidate them. Many treat the
Livret A as "investing". Goal: learn by manipulating real data, with no real money.

### 1.2 Two halves

| Half | What it is | Data | Gated? |
|---|---|---|---|
| **Islands** | Map of islands (one per domain). Each island = a path of short interactive exercises ("nodes") + missions. | Frozen real historical datasets bundled in content packs. Deterministic. | Nodes unlock in order inside an island. |
| **Sandbox** | Wallets: one **live** wallet on today's prices, any number of **trip** wallets starting at a past date. DCA simulator. | Live/historical market data via backend, cached locally. | Never gated by lessons. |

Bridges between the two halves (keep them): a lesson can end with "Rejoue-le toi-même" which opens the
trip wizard prefilled (e.g. "Mars 2020 : vendre ou tenir ?" → trip starting 2020-02-18).

### 1.3 V1 scope

- Map with 5 islands; only **Actions & ETF** is playable, the others are visible and locked ("Bientôt").
- Actions & ETF island: 12 nodes (§4.3).
- Sandbox: live wallet, trip wallets with wizard, orders (market, limit, stop), DCA simulator.
- Glossary with bottom sheets and live examples.
- Livret A: rate history, simulated Livret line in wallets, comparisons (§4.11).
- Companion "teachable moments" (§4.12) and trip journal (§4.13).
- Onboarding questionnaire that changes the path and the UI level (§4.1).
- Offline mode, French + English.

### 1.4 Non-goals (V1)

Real trading, accounts/login, sync between devices, social or competitive features (no leaderboards),
crypto, real estate, trading island, push notifications, scoring/ranking of assets (open decision, §14).

---

## 2. School requirements → where they live (mandatory)

| Requirement (teacher's brief) | Where in the app |
|---|---|
| ≥ 3 meaningful screens + navigation | Bottom tabs (Carte, Portefeuille, Explorer, Glossaire) + flows (asset, order, trip wizard, node player) |
| A form with validation | Order form, trip wizard (date + name), onboarding, DCA form |
| A dynamic list | Explorer catalogue, positions, glossary, wallets list |
| ≥ 1 REST API + JSON → Dart objects | Our backend (`/v1/...`) + Frankfurter called directly by the app |
| Persistence of business data | drift: wallets, orders, fills, journal, profile, progress, favorites, DCA simulations |
| Local cache of API data | Price history cache with incremental fetch, latest quotes, FX rates (§6) |
| Partial offline mode | Everything readable offline; stale-data banner with last update time (§6.4) |
| Explicit loading / data / error states | `AsyncValue` everywhere + shared skeleton / error / offline widgets (§5.3) |
| ≥ 1 meaningful chart | Price chart, portfolio chart, comparisons, allocation, volatility bars |
| ≥ 2 business calculations | §7 (portfolio value, P&L, drawdown, volatility, DCA, TWR, Livret interest, FX…) |
| ≥ 3 animations, ≥ 2 hand-coded | §10.5 (map buildings, construction → completion, reveal curve drawing; package chart animation as the extra) |
| Unit tests on business logic | Every domain function (§12) |
| Report must justify architecture, state, persistence, cache | Keep ADRs in `docs/decisions/` as you go — they feed the report |

---

## 3. Navigation and screens

Bottom tabs: **Carte** (home), **Portefeuille**, **Explorer**, **Glossaire**. Settings from the map header.

| Screen | Route | Notes |
|---|---|---|
| Onboarding (5 questions) | `/onboarding` | First launch only; re-takeable from Settings |
| Map | `/` | Islands, next-step card, level chip |
| Island path | `/island/:islandId` | Node list, progress |
| Node player | `/node/:nodeId` | Renders one node type (§4.3) |
| Wallets list | `/wallets` | Live wallet + trips + lesson suggestions + "Nouveau voyage" |
| Wallet (portfolio) | `/wallet/:walletId` | Same layout live and trip; trips add the trip header + time controls |
| Trip wizard | `/wallets/new?step=1..3` | Prefill via query (`date`, `difficulty`, `from=nodeId`) |
| Fast-forward sheet | modal on wallet | Trip only |
| Automatic stop | `/wallet/:id/stop/:eventId` | Decision + journal |
| Trip summary | `/wallet/:id/summary` | End of trip |
| Explorer | `/explore` | Catalogue, search, filters, favorites |
| Asset page | `/asset/:assetId?wallet=` | Scoped to a wallet's clock |
| Order sheet | modal on asset | Buy / sell |
| Order placed | `/wallet/:id/order/:orderId` | Pending lifecycle |
| Glossary | `/glossary` | Index |
| Glossary sheet | modal anywhere | Term + live example |
| DCA simulator | `/tools/dca` | Inputs, result, comparisons, save |
| Settings | `/settings` | §4.14 |

Routing: `go_router`. Deep links use the routes above (lesson → trip wizard prefill).

---

## 4. Features

### 4.1 Onboarding

Five single-choice questions, each required (validation error if none picked: « Choisis une réponse pour
continuer. Aucune n'est mauvaise. »). Reassurance line: the answers only choose a starting point, not advice.

| # | Question (fr) | Options | Drives |
|---|---|---|---|
| Q1 | Pourquoi veux-tu investir ? | Projet dans moins de 3 ans / Dans 3 à 8 ans / Long terme, plus de 8 ans / Je découvre | `defaultHorizonYears` (2 / 5 / 15 / 10) used by projections, DCA defaults, companion wording |
| Q2 | Ton portefeuille perd 20 % en un mois. Tu fais quoi ? | Je vends tout / J'attends / J'achète plus / Je ne sais pas | `riskComfort` (low/medium/high/unknown→medium) → moment thresholds + pre-trade coach sensitivity |
| Q3 | Tu sais déjà… | Rien / Ce qu'est une action / Ce qu'est un ETF / J'investis déjà | `startingNode` (1 / 1 / 3 / 4) and `initialUiLevel` (1 / 1 / 1 / 2) |
| Q4 | Où est ton épargne aujourd'hui ? | Livret A ou livrets / Compte courant / Déjà investie / Pas d'épargne | if Livret → node 1 "Livret ou ETF ?" is forced first and flagged; if none → safety-cushion content first |
| Q5 | Combien de temps par semaine ? | 5 min / 15 min / 30 min et plus | next-step pacing (1 / 2 / 3 suggestions per day) |

Rules:
- The profile **never** drives asset suggestions. It only shapes path, UI level, thresholds, wording.
- After onboarding, show one sentence explaining the choice ("On commence par X parce que tu as répondu Y").
- Pure domain functions, unit-tested: `startingNode(profile)`, `initialUiLevel(profile)`,
  `momentThresholds(profile)`, `pacing(profile)`.
- Retaking the questionnaire recomputes these but never erases progress.

### 4.2 Map

- Isometric archipelago drawn in code (`CustomPainter`), 5 islands: Actions & ETF (centre, playable),
  Trading, Immobilier, Crypto, Les bases (locked: clouds/greyed, label "Bientôt").
- Header: title "Ton archipel", islands opened count, level chip.
- Next-step card at the bottom: always exactly one recommended action (next node, pending mission,
  unread companion moment, or open trip). Selection is a pure function `nextStep(state)`.
- The Actions & ETF island reacts to the live wallet: building heights map to the 5 largest positions
  (normalised), animated on change. Pending orders show as a building under construction (§10.5).

### 4.3 Islands, nodes and content packs

Node types (each a widget + a pure evaluator):

| Type | Interaction | Completion |
|---|---|---|
| `predict_reveal` | User picks an answer, then frozen curves animate in, then a 2–3 sentence explanation with glossary links | Answer submitted (right or wrong) |
| `toy` | Sliders on a live formula chart (fees, compound interest…) | Interacted with every control |
| `decision` | Historical moment, 3 choices each with upside and downside, reveal what happened next | Choice made |
| `sort` | Drag items onto a scale (e.g. risk ladder), reveal real values | All items placed |
| `build_puzzle` | Pick assets/weights to satisfy constraints (e.g. volatility < X, ≥ 3 regions) | Constraints satisfied (validated by domain calcs) |
| `mission` | Do something in the sandbox (e.g. "own an ETF") | Detected automatically from wallet state |
| `checkpoint` | 4–6 quiz questions | ≥ 1 attempt finished |

Every node may end with:
- **"Et aujourd'hui ?"** — reruns the same widget on current data; hidden when offline or when the node
  has no live variant.
- **Bridge** — opens the trip wizard prefilled.

V1 island "Actions & ETF" (order matters, ids stable):

| # | id | Type | Title (fr) | Data |
|---|---|---|---|---|
| 1 | `ae.livret-vs-etf` | predict_reveal | Livret ou ETF ? | 10 000 € from 2016-01 to latest: Livret A (historical rates) vs MSCI World ETF |
| 2 | `ae.fees-toy` | toy | Le jouet des frais | Formula: 0.2 % vs 1.5 % yearly fees over 30 years |
| 3 | `ae.mission-first-etf` | mission | Ton premier ETF | Live wallet holds ≥ 1 ETF |
| 4 | `ae.apple-vs-world-2022` | predict_reveal | Apple ou ETF Monde : lequel a le plus chuté en 2022 ? | Weekly adjusted closes 2022, USD |
| 5 | `ae.march-2020` | decision | Mars 2020 : vendre ou tenir ? | World ETF 2020-02 → 2021-02; bridge → trip 2020-02-18 |
| 6 | `ae.risk-ladder` | sort | Classe par risque | Livret, world ETF, single stock, EM ETF; 1-year volatility |
| 7 | `ae.compound-toy` | toy | Les intérêts composés | Formula |
| 8 | `ae.mission-three-regions` | mission | Trois zones géographiques | Live wallet exposure to ≥ 3 regions |
| 9 | `ae.dollar-trap` | predict_reveal | Le piège du dollar | A US stock's return in USD vs EUR over a period with a big EUR/USD move |
| 10 | `ae.calm-portfolio` | build_puzzle | Construis un portefeuille calme | Volatility cap, ≥ 3 assets, frozen 3-year data |
| 11 | `ae.mission-dca` | mission | Mets en place un DCA | Any wallet has an active DCA plan |
| 12 | `ae.checkpoint-1` | checkpoint | Point d'étape | Quiz over nodes 1–11 |

Content pack format (`content/packs/<islandId>/<version>/`), validated by `cmd/contentcheck`:

```jsonc
// island.json
{ "id": "actions-etf", "version": 3, "title": {"fr": "Actions & ETF", "en": "Stocks & ETFs"},
  "nodes": ["ae.livret-vs-etf", "ae.fees-toy", "..."] }

// nodes/ae.apple-vs-world-2022.json
{ "id": "ae.apple-vs-world-2022", "type": "predict_reveal",
  "title": {"fr": "...", "en": "..."},
  "question": {"fr": "Apple ou un ETF Monde : lequel a le plus chuté en 2022 ?", "en": "..."},
  "choices": [{"id": "apple", "label": {"fr": "Apple", "en": "Apple"}},
              {"id": "world", "label": {"fr": "ETF Monde", "en": "World ETF"}}],
  "answer": "apple",
  "datasets": ["ds.aapl-2022-w", "ds.msci-world-2022-w"],
  "explanation": {"fr": "Apple, c'est une seule entreprise… C'est la {{diversification}}.", "en": "..."},
  "glossary": ["diversification", "volatilite"],
  "live_variant": {"widget": "compare_returns", "period": "1y"},
  "bridge": null }

// datasets/ds.aapl-2022-w.json  (produced by cmd/freeze, never hand-typed)
{ "id": "ds.aapl-2022-w", "source": "twelvedata", "adjusted": true, "currency": "USD",
  "interval": "1week", "frozen_at": "2026-10-06",
  "points": [["2022-01-03", 177.57], ["...", 0]] }
```

Rules:
- `{{term}}` in any text renders as a tappable glossary link; unknown terms fail `contentcheck`.
- Every text field has `fr` and `en`; missing locale fails `contentcheck`.
- Datasets are produced by `cmd/freeze` from the same provider as live data, adjusted for splits, with
  provenance shown in-app ("Cours réels, clôtures hebdo, 2022, en dollars").
- The app bundles a baseline pack in assets (first launch works offline) and fetches newer versions from
  `/v1/content`.

### 4.4 Glossary

- Term record: `id`, `title{fr,en}`, `short{fr,en}` (one line), `body{fr,en}` (2–3 short paragraphs),
  `live_example` (widget id + params, optional), `related[]`, `quiz` (1–3 questions, optional).
- Index screen: search, filters (Toutes / Découvertes / À découvrir), grouped by letter, status per term
  (discovered ✓, new, to discover).
- Sheet (modal bottom sheet, opened from any `{{term}}` link or essentials tile): title, "Nouvelle notion"
  chip on first open, definition, live example on real data (scoped to the current asset when opened from
  an asset page), "Ce que ça change pour toi", related chips, "Tester en 30 secondes".
- First open marks the term discovered (persisted).
- V1 terms (≈ 26): action, etf, indice, diversification, volatilite, pire-baisse, rendement, performance,
  plus-value, frais, risque-de-change, taux-de-change, inflation, interets-composes, dca, livret-a,
  matelas-de-securite, liquidites, ordre-au-marche, ordre-limite, ordre-stop, cours-de-cloture, allocation,
  concentration, horizon-de-placement, rebond.

### 4.5 Wallets and time trips

Wallet kinds: `live` (exactly one, created at first launch) and `trip` (0..n).

**Live wallet:** 50 000 € starting cash, no monthly contribution, FX fee 0.15 %, fractional shares, clock =
`LiveClock`.

**Trip wizard** (3 steps, chunky "world" style):

1. *When* — historic presets, quick presets, or a custom date.

   | Preset | Start date | Teaser (fr) |
   |---|---|---|
   | Bulle internet | 2000-03-10 | Au sommet de l'euphorie technologique |
   | Crise financière | 2008-09-15 | Le jour de la faillite de Lehman Brothers |
   | Covid | 2020-02-18 | Juste avant l'une des chutes les plus rapides de l'histoire |
   | Inflation et hausse des taux | 2022-01-03 | Avant une année difficile pour les actions et les obligations |
   | Il y a 1 / 5 / 10 ans | today − N years, rolled to previous trading day | — |
   | Date précise | user input `JJ/MM/AAAA` | — |

   Each preset shows "N actifs sur M disponibles" (assets whose `listingDate ≤ startDate` and with history).
   Validation: date parses; `dataFloor ≤ date ≤ today − 30 days`; non-trading day → roll forward to next
   trading day (inform the user). Before `dataFloor`: error « Nos cours commencent le {dataFloor}. » with a
   link to the matching lesson when one exists (e.g. 1929 → Les bases).

2. *Difficulty*

   | Level | Starting cash | Monthly contribution | FX fee | Fixed fee / order | Fractional |
   |---|---|---|---|---|---|
   | Découverte | 50 000 € | 0 | 0 % | 0 € | yes |
   | Réaliste | 10 000 € | 200 € | 0.15 % | 0 € | yes |
   | Serré | 2 000 € | 0 | 0.15 % | 1 € | no (whole shares) |
   | Sur mesure | 100 € – 1 000 000 € | 0 – 10 000 € | 0 – 2 % | 0 – 20 € | yes/no |

   Option: "Commencer avec un matelas de sécurité" → X % of starting cash moved to the simulated Livret line.
   Companion note explains that fixed fees and whole shares are what make small budgets harder.

3. *Recap* — summary rows with "Modifier" links, name (required, 1–30 chars, trimmed), automatic stop
   conditions (defaults: portfolio −15 %, order filled), reminder that only data known at the simulated date
   is shown. CTA « Partir le {date} ».

**Trip wallet screen:** identical to the live wallet plus:
- Trip header (neutral background): clock tile, trip name + difficulty chip, simulated date in large type,
  exit button. No colored banner (color rule §10.2).
- Time controls card above the tab bar: +1 jour, +1 semaine, +1 mois, « Avancer jusqu'à… ».

**Advancing time** (domain service `TripEngine.advance(wallet, target, stopConditions)`), one trading day at
a time:
1. Credit monthly contribution if due (first trading day of the month).
2. Execute active DCA plan purchases due that day.
3. Run `OrderMatcher` on that day's bar for every pending order (§4.6).
4. Accrue Livret interest bookkeeping (§4.11).
5. Compute end-of-day valuation, append to the wallet's daily value series.
6. Evaluate stop conditions and companion rules; if a stop condition fires → stop, persist, emit event.

Stop conditions: portfolio drawdown from start > X % (default 15), any position loss > Y % (default 20),
an order filled, a contribution arrived. The automatic-stop screen shows the drop chart with the threshold,
three neutral choices (each with upside and downside), an optional "Pourquoi ?" text saved to the journal.

**End of trip** (any time, or when the clock reaches the last available trading day): summary with the
user's time-weighted return (§7.6) compared with counterfactuals computed from the same start date and the
same contributions:
- *Sans rien toucher*: everything (start cash + contributions) into the world ETF on the day it arrives.
- *Sur un Livret A*: everything into the Livret (historical rates, §4.11).
- *Ta pire décision*: if the journal has a sell decision, "if you had sold everything at that moment".
Plus journal replay ("Le 12 mars, tu as vendu 30 %… ils ont ensuite regagné 61 %") and glossary terms met.

**No lookahead (enforced in data layer):** a trip can only see bars, quotes, FX rates, assets and Livret
rates dated ≤ its clock. Assets with `listingDate > clock.now()` are hidden in Explorer and unavailable
in the order sheet.

### 4.6 Orders

Types: market, limit, stop (stop-loss on sells; stop-buy allowed). Sides: buy, sell. Input in € amount or
in quantity (toggle). A € amount is the value of the shares traded: fees come on top of a buy and out of a
sell's proceeds. Fractional to 6 decimals unless wallet disallows; whole-share wallets accept € orders and
floor them to whole shares. Good-till-cancelled.

**Soft gate:** limit and stop are visible from day one. The first time a user selects one, the glossary
sheet for that order type opens; after it is closed the type works normally. No hard locks in the sandbox.

**Validation** (domain `validateOrder`, returns typed errors):
- amount/quantity > 0; whole number if non-fractional wallet; a € amount must buy at least one share
  (whole-share wallets);
- buy: total cost incl. fees ≤ available cash; error copy: « Tu as {cash} de liquidités. Baisse le
  montant, ou vends d'abord une position. »;
- sell: quantity ≤ position quantity; proceeds > fees;
- limit/stop price > 0;
- asset available at `asOf`.

Pending orders reserve what they need: available cash = cash − Σ pending buys (an amount reserves amount +
fees; a quantity reserves its cost at the limit, stop or last price, + fees), and a sell can use the
position minus pending sells. Codes and params: `domain/wallet/validation.dart`.

**Fees:** `fxFee = notionalEUR × fxFeeRate` when asset currency ≠ EUR; `fixedFee` per order. Shown in the
order summary.

**Execution rules** (`OrderMatcher`, pure):
- Live, market open: market order fills at the latest quote (delayed is fine); timestamp shown.
- Live, market closed: order becomes `pending`; fills at the next session's open price once that bar is
  known. The UI explains it (« Le Nasdaq est fermé. Ton ordre partira à l'ouverture, demain à 15 h 30 »).
- Trip: the simulated day is "after close" of day D. Market orders fill at the open of the next trading day.
- Limit buy: first day with `low ≤ limit` fills at `min(open, limit)`; limit sell: `high ≥ limit` → `max(open, limit)`.
- Stop sell: first day with `low ≤ stop` fills at `min(open, stop)` (gap slippage is real and taught);
  stop buy: `high ≥ stop` → `max(open, stop)`.
- Fill computes quantity (amount orders) at fill price, fees, FX rate of the fill date.
- A triggered order that cannot execute as asked is cancelled with its reason, never partly filled: cash
  short after a gap, shares no longer held, an amount below one share, fees above a sell's proceeds.

Market hours (Paris time, exchange holidays from provider or a static calendar): Euronext 09:00–17:30,
NYSE/Nasdaq 15:30–22:00 (adjust for US/EU DST mismatch via exchange time zones, never hardcode offsets).

Order lifecycle UI: sent → market opens → executed. The map shows a pending buy as a building under
construction that completes on fill.

**Pre-trade coach** (companion card in the order sheet): new weight of the asset in the wallet ("Apple
pèserait 8 % de ton portefeuille, contre 4 % aujourd'hui"), threshold from `momentThresholds(profile)`.
Never blocks.

### 4.7 Wallet (portfolio) screen

- Header: total value, change since start (amount and %; TWR when contributions exist), data timestamp,
  two tiles "Investi" / "Liquidités disponibles", primary button « Investir » (→ Explorer scoped to wallet).
- Period selector 1S / 1M / 3M / 1A / Tout; chart of daily value with dashed starting-capital baseline;
  benchmark toggle: ETF Monde / Livret A.
- Allocation bar + legend (includes cash and Livret lines).
- Companion card when a moment is active.
- Positions list (cash is **not** a row): avatar, name, quantity, value in €, P&L % with sign.

### 4.8 Asset page

- Name, ticker + exchange + quote currency in words, price in quote currency and ≈ € equivalent,
  last-session change, data timestamp.
- Period chart (1S / 1M / 1A / 5A) with: user's buy markers, worst-drop annotation (peak → trough),
  optional benchmark (ETF Monde, dashed).
- Essentials tiles (each opens its glossary sheet): Performance sur 1 an, Volatilité (label from risk band),
  Pire baisse, Risque de change.
- "Pourquoi ça bouge ?" card: decomposition of the period move (§7.9) as a stacked bar + three rows.
- User position: quantity, value, P&L (amount, %), of which currency effect.
- Buy / Sell buttons.

### 4.9 Explorer

- Catalogue (§8.4), search (name, ticker), filter chips: Tout / ETF / Actions / Favoris.
- Row: avatar, name, region, risk meter (5 bars, §7.8), price, 1-year change, favorite toggle (persisted).
- Offline banner « Hors connexion. Tu vois les cours du {date}, {heure}. » + Réessayer.
- In a trip, the list is filtered by availability and every value is as of the trip date.

### 4.10 DCA simulator

- Inputs: asset (select), amount per period (€, > 0, ≤ 100 000), frequency (monthly / weekly), start date
  (validated like the trip wizard), end = latest data.
- Output: total invested, final value, gain (amount, %), chart (value vs stepped invested line), number of
  purchases.
- Comparisons: lump sum at start (same total), same contributions on a Livret A.
- Companion insight (fr copy written per result shape, e.g. "tes achats de 2022 se sont faits à prix
  cassés…").
- Save simulation (persisted, listed in the tool), rerun with another asset.

### 4.11 Livret A

Facts to encode (verify at implementation, keep in backend data, never hardcode in the app):
- Annual rate history (dated rows; reviewed every 1 February and 1 August). Current: 1.7 % since 2026-08-01.
- Deposit ceiling, dated like the rates: 15 300 € until 30 September 2012, 19 125 € from 1 October 2012,
  22 950 € since 1 January 2013 (capitalised interest may exceed it).
- Interest by fortnight ("quinzaine": 1st–15th, 16th–end of month). Deposits earn from the next quinzaine
  start; withdrawals stop earning from the start of the quinzaine in which they happen. Interest is credited
  and capitalised on 31 December.

Uses:
- Simulated Livret line in any wallet (transfer cash ↔ Livret, instant, no fees).
- Benchmark line on the wallet chart; counterfactual in trip summary; comparison in DCA; island node 1.
  These comparisons respect the ceiling valid at each date: money above it stays as uninvested cash at 0 %,
  and the result says it was capped.
- Teaching stance: the Livret is the right place for a safety cushion (3–6 months of expenses), not for
  long-term money. Never mock it.

### 4.12 Companion (teachable moments)

Pure rule engine over domain events, outputs `CompanionCard{ruleId, title, body, links[]}`.

| Rule | Trigger (defaults; profile adjusts) | Cooldown |
|---|---|---|
| `first_loss` | First time a position is < −5 % | once |
| `position_drop` | Position −15 % from its peak since purchase | 30 days per position |
| `portfolio_drawdown` | Wallet −10 % from peak | 30 days |
| `concentration` | One non-cash position > 30 % (low comfort) / 40 % (others) | 14 days |
| `idle_cash` | Cash > 25 % of wallet for > 30 days | 30 days |
| `panic_sell` | Sell within 10 trading days after that position was −15 % | per event; revisited 3 months later ("what happened after you sold") |
| `fx_swing` | EUR/USD move > 3 % in a month with USD exposure > 20 % | 30 days |

Cards link to glossary terms or nodes. Wording describes, never prescribes.

### 4.13 Trip journal

Entry: `{walletId, simDate, eventId?, decision, reasonText?}`. Created by automatic-stop decisions and
optional on any order in a trip. Replayed in the trip summary with what happened next (computed).

### 4.14 Settings

Language (fr/en), level + "Tout afficher dès maintenant" switch, retake questionnaire, data (last update,
cached histories count and size, refresh now, clear cache), simulation (starting capital of live wallet,
simulated FX fee), reset live wallet (keeps island progress, confirmation required), about (fictional money,
no advice, data sources).

### 4.15 Levels and progressive UI

- `uiLevel` 1–3. Level 1: risk meter instead of volatility numbers; essentials tiles show bands
  ("Élevée") rather than raw figures. Level 2 (after node 4 or Q3 = "J'investis déjà"): raw figures.
  Level 3 (after checkpoint): advanced stats (TWR breakdown, effective number of positions).
- Override switch in Settings shows everything.
- Order types are never locked (soft gate, §4.6).

---

## 5. App architecture (Flutter)

### 5.1 Folder structure (feature-first, layered inside)

```
app/lib/
  core/          clock/, money/, failure.dart, result.dart, l10n/, theme/ (tokens), widgets/ (async states)
  domain/        pure Dart, no Flutter imports
    market/      Asset, PriceBar, Quote, FxRate, MarketCalendar
    wallet/      Wallet, Order, Fill, Position, LivretAccount, DcaPlan, valuation.dart, order_matcher.dart,
                 trip_engine.dart, validation.dart
    analytics/   returns.dart (simple, TWR), volatility.dart, drawdown.dart, decomposition.dart, risk.dart
    learning/    Profile, Node, NodeProgress, profile_rules.dart, next_step.dart, missions.dart
    companion/   rules.dart, events.dart
    livret/      livret_interest.dart
  data/
    remote/      backend_api.dart (dio), frankfurter_api.dart, dto/ (json_serializable)
    local/       database.dart (drift), tables/, daos/
    repositories/ market_repository.dart, fx_repository.dart, wallet_repository.dart, content_repository.dart…
  application/   Riverpod notifiers / providers per feature
  presentation/  features/<feature>/ screens + widgets
```

### 5.2 Key abstractions

```dart
abstract interface class SimulationClock { DateTime now(); }      // LiveClock, HistoricalClock(date)
abstract interface class MarketRepository {
  Future<List<PriceBar>> history(AssetId id, {required DateRange range, required DateTime asOf});
  Future<Quote?> latest(AssetId id, {required DateTime asOf});
  Stream<CacheStatus> status();                                     // fresh / stale(lastUpdated) / offline
}
abstract interface class FxService { Future<Rate> rate(Currency from, Currency to, {required DateTime asOf}); }
```

Repositories clamp every query to `asOf`. A trip wallet's providers are created with its `HistoricalClock`
(Riverpod family keyed by `walletId`).

### 5.3 State and async conventions

- One notifier per screen-level concern; widgets `ref.watch` and render `AsyncValue` through shared
  widgets: `AsyncSkeleton`, `ErrorView(failure, onRetry)`, `StaleBanner(lastUpdated)`.
- Refresh keeps previous data visible (`AsyncValue.copyWithPrevious`), never flashes a spinner over data.
- Failures: `NetworkFailure`, `RateLimitedFailure(retryAfter)`, `NotFoundFailure`, `DataUnavailableFailure(asOf)`,
  `ValidationFailure(code, params)`, `StorageFailure`.
- What happens on rebuild: widgets are stateless where possible; `AnimationController`s live in `State`
  objects and are disposed; no fetching in `build`.

### 5.4 Dependencies (allowed list)

flutter_riverpod (+ riverpod_annotation / riverpod_generator), go_router, drift + sqlite3_flutter_libs,
dio, freezed + json_serializable, decimal, intl + flutter_localizations, fl_chart, connectivity_plus,
mocktail (dev), build_runner (dev). Fonts are **bundled as assets** (Baloo 2, Figtree — both OFL); do not
fetch fonts at runtime (offline requirement).

---

## 6. Data, cache and offline

### 6.1 Local schema (drift)

| Table | Key columns |
|---|---|
| `assets` | id, symbol, name, type (etf/stock), exchange, currency, region, listingDate, providerSymbol |
| `price_bars` | assetId, date, open, high, low, close, adjClose, volume — PK (assetId, date) |
| `quotes` | assetId, price, currency, asOf, fetchedAt |
| `fx_rates` | date, base, quote, rate — PK (date, base, quote) |
| `livret_rates` | validFrom, annualRate |
| `history_sync` | assetId, firstDate, lastDate, lastFetchedAt |
| `wallets` | id, kind, name, startDate, simDate (trip), difficulty, params json, status, createdAt |
| `cash_ledger` | walletId, simDate, amount (cents), kind (start, contribution, buy, sell, fee, livret_in/out, interest) |
| `orders` | id, walletId, assetId, side, type, amountCents?, quantity?, limitPrice?, stopPrice?, status, createdSimAt |
| `fills` | orderId, simDate, price, quantity, fxRate, feesCents |
| `wallet_values` | walletId, date, valueCents, flowCents — daily series for charts and TWR |
| `dca_plans` | walletId, assetId, amountCents, frequency, active |
| `dca_simulations` | id, params json, result json, savedAt |
| `journal_entries` | walletId, simDate, eventId, decision, reason |
| `profile` | single row: answers, derived fields, uiLevel, showAll |
| `node_progress` | nodeId, status, attempts, lastAnswer |
| `glossary_state` | termId, discoveredAt, quizPassed |
| `favorites` | assetId |
| `companion_log` | ruleId, key, firedAt, dismissedAt |
| `content_packs` | islandId, version, json |

Positions are **derived** from fills (average-cost method), never stored as the source of truth.

### 6.2 Cache policy (to justify in the report — write an ADR)

- **History:** immutable once a day is closed. On first need, fetch from `dataFloor` (or from the trip start)
  to latest. Afterwards fetch only `from = lastDate + 1`. Never refetch closed days unless a split/adjustment
  invalidation flag is returned by the backend (then refetch that asset fully).
- **Quotes (live wallet):** TTL 15 min during the asset's market hours, until next session open otherwise.
- **FX:** daily ECB rates; refetch only missing dates; a date's rate never changes.
- **Content packs:** ETag; check at most once a day.
- **Livret rates:** check once a day.

### 6.3 Who decides cache vs network

Repositories only. Notifiers ask for data; repositories return cached data immediately, decide whether a
fetch is needed, and emit updates. UI never knows the source except through `CacheStatus`.

### 6.4 Offline

Everything readable offline: map, islands (bundled packs), wallets, positions, charts (cached), glossary,
saved simulations, trip advancing (only within cached history; past that → `DataUnavailableFailure` with a
clear message). Live orders while offline: open decision (§14). Stale-data banner shows date and time of
the last update.

---

## 7. Domain calculations (all pure, all unit-tested)

Money in integer cents; prices `Decimal`; intermediate ratios `Decimal` with 10-digit precision; rounding
half-even only when an amount is booked as Money (fill, fee, interest, daily value) or displayed (ADR-003).

1. **Position (average cost):** buy fills add quantity and cost (price × qty × fx + fees, in €); sell fills
   reduce quantity, realised P&L = proceeds − avgCost × qty; avgCost unchanged on sells.
2. **Market value (€)** = qty × price(asOf) × fx(asset ccy → EUR, asOf). Missing price for asOf → last
   available price ≤ asOf, flagged stale.
3. **Wallet value** = cash + Σ market values + Livret balance (incl. accrued, not yet credited interest shown
   separately).
4. **Unrealised P&L** = market value − cost basis (amount and %); % undefined when cost basis = 0.
5. **Allocation** weight_i = value_i / wallet value (cash and Livret are lines); weights sum to 1 ± 1e-9.
6. **Time-weighted return:** daily `r_t = (V_t − F_t) / V_{t−1} − 1` where `F_t` is the external flow
   (contribution) credited on day t; `TWR = Π(1 + r_t) − 1`. `V_{t−1} = 0` days are skipped. Use TWR for every
   "performance" shown on a wallet that has contributions.
7. **Volatility (annualised):** sample standard deviation of daily log returns over the window × √252.
   Fewer than 20 returns → `null` (UI shows "pas assez de données").
8. **Risk band 1–5** from 1-year annualised volatility: < 8 % → 1, < 15 % → 2, < 25 % → 3, < 40 % → 4,
   else 5 (thresholds in config).
9. **Move decomposition** over [a, b] for an asset quoted in currency L, benchmark = world ETF:
   `r_local` asset return in L, `r_fx` = EUR value of 1 L at b / at a − 1, `total_eur = (1 + r_local)(1 + r_fx) − 1`,
   `market = r_benchmark_local`, `currency = r_fx`, `specific = total_eur − market − currency` (residual,
   includes cross terms — documented approximation). EUR assets: `r_fx = 0`.
10. **Max drawdown:** running peak; `dd_t = P_t / peak_t − 1`; return min dd with peak and trough dates.
    Empty or single point → 0 with null dates.
11. **Concentration** = max weight among non-cash lines; **effective number of positions** = 1 / Σ w_i²
    over invested lines.
12. **DCA:** schedule dates (monthly on start day-of-month, weekly on start weekday; non-trading → next
    trading day), quantity += (amount − fees) / close(date); value = Σqty × close(end). Lump sum: whole total
    at start. Livret: same flows through §4.11 rules.
13. **Livret interest:** per quinzaine `interest += eligibleBalance × annualRate(at quinzaine start) / 24`,
    eligibility per §4.11, credited 31 December; partial year shown as accrued.
14. **Order fill and validation:** §4.6.
15. **Profile rules, next step, missions, companion rules:** §4.1, §4.2, §4.3, §4.12.

Required edge-case tests (minimum): empty history; one bar; zero/negative amounts; amount smaller than
fees; sell more than owned; limit never reached; gap through stop; weekend/holiday dates; DST weeks for
market hours; FX missing for a date (use previous); asset not yet listed at asOf; contribution on a
non-trading day; Livret deposit on the 15th vs 16th; withdrawal mid-quinzaine; ceiling reached; TWR with a
zero-value day; drawdown on monotonic series.

---

## 8. Backend (Go)

### 8.1 Responsibilities

Single gateway for market data and content. Hides provider keys, normalises providers into one schema,
stores price history permanently, appends new days after each close, serves content packs, and spreads the
provider rate limit across all clients. No user data, no accounts.

### 8.2 Layout

```
backend/
  cmd/server/        HTTP server + scheduler
  cmd/freeze/        builds frozen datasets for content (writes into content/…/datasets)
  cmd/contentcheck/  validates content packs (schema, locales, glossary refs, dataset refs)
  internal/provider/ Provider interface + twelvedata adapter (+ fake for tests)
  internal/store/    SQLite (modernc.org/sqlite) — assets, bars, fx, livret_rates, sync state
  internal/api/      handlers, DTOs, ETag/Last-Modified
  internal/jobs/     daily append, backfill with rate-limit budget
```

Go ≥ 1.22, stdlib `net/http` routing, structured logs (`log/slog`), config via env, Docker image, self-hosted.

### 8.3 Endpoints (JSON, read-only)

| Method & path | Returns |
|---|---|
| `GET /v1/assets` | Catalogue with listingDate, currency, region, type |
| `GET /v1/assets/{id}/history?from=&to=` | Adjusted daily OHLCV bars, ascending; `to` defaults to latest |
| `GET /v1/quotes?ids=a,b,c` | Latest price per asset with `asOf` and market status |
| `GET /v1/fx?base=USD&quote=EUR&from=&to=` | Daily rates (cached Frankfurter; the app also calls Frankfurter directly) |
| `GET /v1/livret/rates` | Dated Livret A rate history and dated ceiling history |
| `GET /v1/calendar/{exchange}?year=` | Trading days / holidays |
| `GET /v1/content/manifest` · `GET /v1/content/packs/{islandId}/{version}` | Content distribution |
| `GET /healthz` | Liveness |

Errors: `{"error": {"code": "...", "message": "..."}}` with proper status codes; 429 carries `Retry-After`.
Every list endpoint supports conditional requests.

### 8.4 Catalogue V1 (≈ 30; provider symbols to verify in M2)

ETFs: MSCI World (Euronext), S&P 500, Nasdaq 100, Stoxx Europe 600, MSCI Emerging Markets, a euro government
bond ETF, a global aggregate bond ETF.
Europe: LVMH, TotalEnergies, Airbus, ASML, SAP, Schneider Electric, L'Oréal, Sanofi, Siemens, Novo Nordisk,
Hermès, BNP Paribas.
US: Apple, Microsoft, Nvidia, Amazon, Alphabet, Meta, Tesla, Berkshire Hathaway, JPMorgan, Coca-Cola.

### 8.5 Provider notes

Primary: Twelve Data (free tier advertised at 8 credits/min, 800/day — verify). Before M2 is closed, confirm
on the free tier: history depth, availability of split-adjusted prices, European exchange coverage. Record
findings and the chosen `dataFloor` in an ADR. FX: Frankfurter (ECB data, no key).

---

## 9. Content production

- Lesson text is written in `content/` (fr first, en second), reviewed by Bob. Agents may draft, marked
  `"status": "draft"`; drafts never ship in a release pack.
- Datasets only via `cmd/freeze` (provenance, adjusted prices, frozen_at date).
- `contentcheck` runs in CI.

---

## 10. Design system

### 10.1 Two component families

- **World / companion ("chunky")**: map, island path, node player, wizard, companion cards, missions,
  celebrations. White surfaces, 3 px ink border, offset shadow `0 4–6 px 0 ink`, radius 16–24, Baloo 2 titles.
- **Money ("flat")**: wallet, asset page, order sheet, explorer, settings, charts. White cards, 1 px line
  border, no offset shadow, radius 14–18. Numbers in Figtree with tabular figures.

Rule: chunky = the game is talking to you; flat = your money.

### 10.2 Color tokens and their meaning

| Token | Hex | Use only for |
|---|---|---|
| `ink` | #1D2340 | Text, chunky borders |
| `muted` | #4A5670 | Secondary text |
| `line` | #DDE5EA | Flat borders, dividers |
| `page` | #F4F8FA | App background |
| `surface` | #FFFFFF | Cards |
| `primary` | #3157E8 | Primary actions, main chart line |
| `progress` | #FFC845 | Levels, missions, new notions, companion buttons |
| `alert` | #FF7D5C | Alerts and thresholds: drawdowns, automatic stops, validation errors (with #C23E22 text) |
| `gain` / `loss` | #167A52 / #C23E22 | Gain/loss figures only, always with + / − sign |
| `sea` | #86D9EC | World screens background only |

No decorative color. A screen state (e.g. being in a trip) is signalled by content (date, icon, label), not
by tinting the screen.

### 10.3 Typography

Baloo 2 (800) for display/titles; Figtree (400–700) for body and numbers (`FontFeature.tabularFigures()`).
French formatting: narrow no-break space before « : ? ! », thousands with narrow no-break space, decimal comma.

### 10.4 Spacing and targets

4-pt scale; screen padding 16; touch targets ≥ 44; bottom tab bar 80 high.

### 10.5 Animations

Hand-coded (count for the school requirement):
1. Map buildings grow/shrink with positions (`AnimationController` + `CustomPainter`).
2. Pending order: building under construction → completes on fill (staged controller).
3. Predict-reveal: curves draw progressively (`Tween<double>` over `PathMetric`).
Others: value counters (`TweenAnimationBuilder`), favorite star pop, sheet transitions, fl_chart transitions
(package-provided, counts as the third non-coded animation).

---

## 11. Localization

ARB files `app_fr.arb` (default) and `app_en.arb`. Keys by feature (`wallet_header_invested`). Plurals via
ICU. Content packs carry their own fr/en. Language switch in Settings applies immediately.

---

## 12. Testing strategy

- Domain: exhaustive unit tests (§7 edge cases), table-driven, fixed clocks and fixtures.
- Data: repository tests with fake remote + in-memory drift; cache policy tests (incremental fetch,
  TTL, offline fallback, no-lookahead clamp).
- Application: notifier tests with mocktail fakes (loading → data, error → retry, refresh keeps data).
- Widget: key flows (order validation, wizard validation, onboarding validation).
- Backend: handler tests with fake provider; store tests; `contentcheck` tests.

---

## 13. Delivery

Milestones and issue breakdown: `docs/ROADMAP.md`. Each architecture choice gets an ADR in
`docs/decisions/` (context, options, decision, consequences) — the school report is built from them.

---

## 14. Open decisions (ask, do not guess)

1. Live orders while offline: block with an explanation, or queue until next sync?
2. Trip maximum length (open-ended to today, or capped at 1–3 years)?
3. Cash shared across future islands, or one wallet per island?
4. Explainable asset scoring in V1 or later?
5. Final data provider and `dataFloor` (after the M2 verification).
6. Final catalogue list and symbols.
