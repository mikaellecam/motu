# Motu — product & architecture brief

Status: V1 spec. Owner: Bob. Agents implement; they do not decide product questions (see §14).
Visual reference (for humans): design canvas "Investment Companion" (the project's working name), direction A
("toy blocks").
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
crypto, real estate, trading island, push notifications, ranking of assets. An explainable score per asset
is in: « Stabilité passée » on the asset page (§4.8, decided 2026-10-25); ranking or sorting assets by it is
not.

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
| Wallets list | `/wallets` | Live wallet + trips (newest first, with status) + "Nouveau voyage" + lesson suggestions: the bridges of completed lessons |
| Wallet (portfolio) | `/wallet/:walletId` | Same layout live and trip; trips add the trip header + time controls |
| Trip wizard | `/wallets/new?step=1..3` | Prefill via query (`date`, `difficulty`, `from=nodeId`) |
| Fast-forward sheet | modal on wallet | Trip only |
| Automatic stop | `/wallet/:id/stop/:eventId` | Decision + journal |
| Trip summary | `/wallet/:id/summary` | End of trip |
| Explorer | `/explore` | Catalogue, search, filters, favorites |
| Asset page | `/asset/:assetId?wallet=` | Scoped to a wallet's clock |
| Order sheet | modal on asset | Buy / sell |
| Plan sheet | modal on asset, DCA result | « Investir chaque mois »: a DCA plan (§4.5) |
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
Layout (decided 2026-10-24, artboard `Onboarding-A` of the art direction canvas): a world screen on the
sea under the bare Actions & ETF island. One chunky card holds « Question n sur 5 », a segmented progress
bar, the question and the reassurance line; the answers are toy blocks under it (they press down, so they
sit on the sea rather than inside the card). « Retour » (from the second question) and « Suivant » stay at
the bottom, with the validation error in an alert box just above them. The result: the island, then a card
« Ton point de départ » naming the starting node over the sentence that explains it. No « Passer »: every
question is required.

| # | Question (fr) | Options | Drives |
|---|---|---|---|
| Q1 | Pourquoi veux-tu investir ? | Projet dans moins de 3 ans / Dans 3 à 8 ans / Long terme, plus de 8 ans / Je découvre | `defaultHorizonYears` (2 / 5 / 15 / 10) used by projections, DCA defaults, companion wording |
| Q2 | Ton portefeuille perd 20 % en un mois. Tu fais quoi ? | Je vends tout / J'attends / J'achète plus / Je ne sais pas | `riskComfort` (low/medium/high/unknown→medium) → moment thresholds + pre-trade coach sensitivity |
| Q3 | Tu sais déjà… | Rien / Ce qu'est une action / Ce qu'est un ETF / J'investis déjà | `startingNode` (1 / 1 / 3 / 4) and `initialUiLevel` (1 / 1 / 1 / 2) |
| Q4 | Où est ton épargne aujourd'hui ? | Livret A ou livrets / Compte courant / Déjà investie / Pas d'épargne | if Livret → node 1 "Livret ou ETF ?" is forced first and flagged; if none → the "matelas de sécurité" glossary sheet comes first |
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
  Built (M9-11): in the style of the approved art direction, the « map » artboard of the canvas « Investment
  Companion — Art direction » (https://claude.ai/artifact/Fjf3tVK7odDPsGXX6JzFw5), its islands where it places
  them: block islands on the sea, Actions & ETF in sand and grass with trees, the locked ones in grey stone
  with their props (candlesticks, houses and towers, a crystal, a lighthouse) under clouds. The map opens on all
  five above the next-step card, the smallest zoom it allows. Labels: Actions & ETF in a chunky pill with its
  lessons done (« 2/12 »); a locked island's name with a lock (screen readers: « {île}, bientôt »).
- Header: title "Ton archipel", islands opened count, level chip.
- Next-step card at the bottom: always exactly one recommended action. Selection is a pure function
  `nextStep(state)`, first match wins: an unread companion moment; the safety-cushion sheet (Q4 "Pas
  d'épargne", until read); the current node if it is a mission; the current lesson node while fewer nodes
  than the pacing (Q5) were completed today; an open trip; the live wallet.
  Built (M7-3): the card names what it opens (the lesson, the mission, the term, the trip) and follows the
  user's progress as it happens; "today" is the user's local day; an open trip is one not finished, the newest
  first. Header: « {n} île(s) ouverte(s) sur 5 » under the title, and « Niveau {n} » (§4.15) in the level
  colour. Unread companion moments lead the card (M8-3, §4.12).
- Lessons grow the Actions & ETF island too (decided 2026-10-24, M9-19): from a sand bank (none done) to the
  art direction's island (all done). Nature comes first: a tree with the first lesson, all five by half the
  lessons (`grownTrees`); the grass turns green from the island's middle out, a share per lesson
  (`grownTiles`); every lesson done raises its landmark, a stone column capped in the levels' gold, at its
  right end (`landmarkStands`). Its shape never changes, so the wallet's buildings always stand on land. On
  the map the change eases in over 1,4 s (at once with animations off, and at once when the lessons first
  load); the island path's header shows it too, and onboarding the sand bank the user starts from.
- The Actions & ETF island reacts to the live wallet: building heights map to the 5 largest positions
  (normalised), animated on change. Pending orders show as a building under construction (§10.5).
  Built (M7-2, `islandBuildings`): an asset's size is its market value plus what its pending buys hold back
  (sells change nothing until they fill); the 5 largest stand in a row across the island, rising to the
  right, the largest last with a flag (M9-11), each as tall as its size against the largest's (1 to 4 height
  units, one unit a block's height). A pending buy shows the building it will make as a ghost: its finished
  volume in its own colours, see-through, with dashed edges. The part already standing is solid inside it;
  an asset not held yet stands on a bare foundation slab (decided 2026-10-28, M9-45).

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

Player (decided 2026-10-24, artboard `Reveal-A` of the art direction canvas): a world screen on the sea, a
chunky ✕ and the island's lessons as pills on top (each done in `progress`, this one in `primary`). Each node
opens with a chunky card: its type, its title, its prompt. Once answered, the verdict takes the question's
place in that card: « Bien vu ! » or « Raté, et c'est comme ça qu'on apprend », then what was answered and the
right answer; a checkpoint marks the right answer ✓ and a wrong pick ✗ (icons and screen-reader labels, never
colour alone); a decision shows what each choice became, the user's named. The explanation sits in a chunky
« Pourquoi ? » card; sliders and other controls in a chunky card.

Every node may end with:
- **"Et aujourd'hui ?"** — reruns the same widget on current data; hidden when offline or when the node
  has no live variant.
- **Bridge** — opens the trip wizard prefilled: node field `"bridge": {"date": "2020-02-18", "difficulty"?}`.

V1 island "Actions & ETF" (order matters, ids stable):

| # | id | Type | Title (fr) | Data |
|---|---|---|---|---|
| 1 | `ae.livret-vs-etf` | predict_reveal | Livret ou ETF ? | 10 000 € from 2015-12-31 to the last full month (2026-09-30), monthly: the world ETF (ACWI, in EUR at ECB rates) vs a Livret A (historical rates) |
| 2 | `ae.fees-toy` | toy | Le jouet des frais | Formula: 0.2 % vs 1.5 % yearly fees over 30 years |
| 3 | `ae.mission-first-etf` | mission | Ton premier ETF | Live wallet holds ≥ 1 ETF |
| 4 | `ae.apple-vs-world-2022` | predict_reveal | Apple ou ETF Monde : lequel a le plus chuté en 2022 ? | Weekly adjusted closes 2022, USD |
| 5 | `ae.march-2020` | decision | Mars 2020 : vendre ou tenir ? | World ETF 2020-02 → 2021-02; bridge → trip 2020-02-18 |
| 6 | `ae.risk-ladder` | sort | Classe par risque | Livret, world ETF, single stock, EM ETF; 1-year volatility |
| 7 | `ae.compound-toy` | toy | Les intérêts composés | Formula |
| 8 | `ae.mission-three-regions` | mission | Trois zones géographiques | ≥ 3 distinct regions among the live wallet's positions (one region per asset; a world ETF counts as one) |
| 9 | `ae.dollar-trap` | predict_reveal | Le piège du dollar | Coca-Cola in 2017, weekly: in USD (+14 %), in EUR (+0,5 %), and the dollar in euros (−12 %) |
| 10 | `ae.calm-portfolio` | build_puzzle | Construis un portefeuille calme | Volatility cap, ≥ 3 assets, frozen 3-year data |
| 11 | `ae.mission-dca` | mission | Mets en place un DCA | Any wallet has an active DCA plan |
| 12 | `ae.checkpoint-1` | checkpoint | Point d'étape | Quiz over nodes 1–11 |

Island path (`/island/:islandId`): the nodes in order, each done (✓, replayable), current (the node the
next-step card points to), open or locked, with « {done} sur {total} terminées » on top. Decided 2026-10-11:
nodes skipped at onboarding stay open; a pending mission does not lock what follows (the lessons after it
open, the mission completes whenever the wallet satisfies it); « Tout afficher dès maintenant » changes the
UI level only, never the node order.
Layout (decided 2026-10-23, « stepping islets », artboard `Path-E` of the art direction canvas
https://claude.ai/artifact/Fjf3tVK7odDPsGXX6JzFw5): on the sea, the island as the map paints it (its living
buildings included), then a chunky header card (title, « {done} sur {total} terminées », progress bar). Each
node stands on an identical 2×2 block islet on the island art's iso grid, in a strict zig-zag one constant
step apart; a round chunky bubble on it shows the node type's icon, filled by its state (done `progress`,
current `primary` and larger with a white ring, open `surface`, locked grey stone), its title and « type ·
state » beside it. A plank bridge is built from each node done to the next; a dotted plank route on the
water leads on from the others. Under the current node's islet, a card with its type, its title and
« Commencer ». Locked islets are grey stone, as on the map.

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
  "series": [{"dataset": "ds.aapl-2022-w", "label": {"fr": "Apple", "en": "Apple"}},
             {"dataset": "ds.msci-world-2022-w", "label": {"fr": "ETF Monde", "en": "World ETF"}}],
  "invested": 1000,
  "explanation": {"fr": "Apple, c'est une seule entreprise… C'est la {{diversification|diversification}}.", "en": "..."},
  "glossary": ["diversification", "volatilite"],
  "live_variant": {"widget": "compare_returns", "period": "1y"},
  "bridge": null }

// datasets/ds.aapl-2022-w.json  (produced by cmd/freeze, never hand-typed; out of git, ADR-007)
{ "id": "ds.aapl-2022-w", "source": "twelvedata", "asset": "apple", "symbol": "AAPL", "adjusted": true,
  "currency": "USD", "interval": "1week", "from": "2022-01-01", "to": "2022-12-31", "frozen_at": "2026-10-06",
  "points": [["2022-01-07", 168.14415], ["...", 0]] }
```

Type payloads (M6-3; the player refuses a pack that breaks them):
- `predict_reveal`: `question`, `choices[{id, label}]`, `answer` (a choice id), `series[{dataset, label}]` (the
  curves, datasets the node draws), `explanation`, optional `invested` and `live_variant`. Each curve shows what
  `invested` (in the dataset's currency) became, with its end value and signed change; base 100 without it
  (decided 2026-10-11). `live_variant` `{"widget": "compare_returns", "period": "1y" | "6m" | …}` reruns the
  curves on current prices of the datasets' `asset`s; any other widget is ignored.
- `toy`: `formula` (`fees`: `amount`, `years`, `return`, `fee_low`, `fee_high`; `compound`: `amount`, `monthly`,
  `years`, `return`), `controls[{id, label, min, max, step, default}]` (one per input, no other), `intro`,
  `explanation`, optional `return_from` `{dataset, label}`: the `return` slider starts at that dataset's
  average yearly return, shown as « ce qu'a fait {label} de {from} à {to} », and is called an assumption once
  moved (decided 2026-10-11). Fees: each year the money grows by the return, then the fee takes its share;
  compound: each year what is there grows, then the year's twelve monthly amounts come in.
- `decision` (M6-4): `context` (the moment as known then), `moment` (a day inside the curve), `series {dataset,
  label}`, `invested` (in the dataset's currency), `choices[{id, label, upside, downside, kept}]` (two or more;
  `kept` is the share left invested, 0 to 1), `explanation`. Before the choice the curve stops at the moment;
  after it, the whole curve draws itself and each choice shows what `invested` became by the end: the kept
  share follows the market, the rest stays as cash.
- `sort` (M6-4): `prompt`, `scale {low, high}` (what the top and the bottom of the list mean),
  `items[{id, label, dataset | value}]` (two or more; a daily dataset ranks by its annualised volatility, §7.7,
  a fixed `value` such as the Livret's 0 as is), `explanation`. Done once the user validates the order; then
  « {n} sur {total} à la bonne place » and the real order with each value.
- `build_puzzle` (M6-4): `prompt`, `assets[{dataset, label, region}]` (daily datasets), `rules {max_volatility,
  min_assets?, min_regions?}`, `step` (the weight step, dividing 100 %), `explanation`. The portfolio's
  volatility (rebalanced daily, over the days every weighted asset has; below 100 % the rest is cash) and each
  rule are checked live by domain calculations; « Valider » once they all hold.
- `checkpoint` (M6-4): `questions[{question, choices[{id, label}], answer, explanation?}]` (4–6 in content),
  one at a time; done at the end whatever the score.
- `mission` (M6-5): `goal` (what to do), `go` (`explorer` | `wallet`: where the button leads). It completes by
  itself, never by a button: while the app runs, the live wallet's holdings and the DCA plans are watched and
  each mission they satisfy is saved as done.
- A played lesson ends on « Continuer », preceded by « Rejoue-le toi-même » when it has a `bridge`: the trip
  wizard on step 1 at the bridge's date and difficulty (`/wallets/new?step=1&date=…&difficulty=…&from=<node>`).
- Completion is saved in `node_progress` (status, attempts, last answer, first completion kept).

Rules:
- `{{term}}` in any text renders as a tappable glossary link showing the term's title; `{{term|text}}` shows
  `text` instead, to fit the sentence (« la {{diversification|diversification}} »). Unknown terms fail
  `contentcheck`.
- Every text field has `fr` and `en`; missing locale fails `contentcheck`.
- Datasets are produced by `cmd/freeze` from the same provider as live data, adjusted for splits, with
  provenance shown in-app ("Cours réels, clôtures hebdo, 2022, en dollars"). A weekly or monthly point is
  the last close of its ISO week or calendar month, dated by the day of that close. Besides an asset's closes
  (M6-8): `-currency EUR` converts each close at the ECB rate of its day or the last one before (`"fx":
  "ecb"`); `-fx USD` is what one dollar was worth in euros (`"source": "ecb"`); `-livret` is a Livret A
  holding of `-deposit` euros put in on `-from`, valued each day as the app values a Livret (§4.11) from the
  backend's rate history (`"source": "livret-a"`). A series that is not an asset's has no `asset` nor
  `symbol`, so it has no « Et aujourd'hui ? ».
- The app bundles a baseline pack in assets (first launch works offline) and fetches newer versions from
  `/v1/content`. On the wire and in the bundle a pack is one document, `{island, nodes, datasets,
  glossary}`; glossary terms live in `glossary/<id>.json` inside the pack (ADR-006).

### 4.4 Glossary

- Term record: `id`, `status` (`draft` | `published`, §9), `title{fr,en}`, `short{fr,en}` (one line),
  `body{fr,en}` (2–3 short paragraphs), `for_you{fr,en}` (optional: « Ce que ça change pour toi », decided
  2026-10-11), `live_example` (`{"widget": …}`, optional), `related[]`, `quiz` (1–3 questions, optional:
  `{question, choices[{id, label}], answer}`; passed with every answer right, persisted).
- Live examples (decided 2026-10-11): `performance`, `volatility`, `drawdown`, `currency`, the asset page's
  essentials over the last year, for the asset the sheet was opened from (the world ETF elsewhere) beside the
  world ETF's figure, with the asset's year as a small line. `contentcheck` refuses another widget and a quiz
  answer that is not one of its choices.
- Status per term (decided 2026-10-11): discovered ✓ (its sheet was opened), « Nouvelle » (met in a completed
  lesson's terms or a companion moment, not opened yet), to discover (not met yet). « À découvrir » keeps
  both of the latter.
- Index screen: search, filters (Toutes / Découvertes / À découvrir), grouped by letter, status per term
  (discovered ✓, new, to discover).
- Sheet (modal bottom sheet, opened from any `{{term}}` link or essentials tile): title, "Nouvelle notion"
  chip on first open, definition, live example on real data (scoped to the current asset when opened from
  an asset page), "Ce que ça change pour toi", related chips, "Tester en 30 secondes".
- First open marks the term discovered (persisted).
- Layout (decided 2026-10-24, artboards Glossary-A, GlossarySheet-A): the index scrolls as one page and
  opens with « n notions découvertes sur m » (the pack's terms, whatever the search) over a bar in
  `progress`, then an outlined search box and the filters. Letters in small Baloo `primary`; each letter's
  terms in a flat card, a line between rows; on the right ✓ (an ink check in a `line` disc: the artboard's
  green is `gain`, kept for gain figures), « Nouvelle » (a small `progress` pill with an ink edge, a label
  rather than a button) or « À découvrir » in words. The sheet: the title, the « Nouvelle notion » pill and a
  chunky ✕; the one-line definition (`short`) first, the 2–3 paragraphs (`body`) behind « En savoir plus »,
  so the live example and « Tester en 30 secondes » stay within a short scroll; the live example in a chunky
  card, « Sur données réelles » over a Baloo headline; related terms as pills.
- A world screen (decided 2026-10-28 by the user, M11-2, the canvas « The world on every tab »): the glossary is
  a collection of notions, not money. « n notions découvertes sur m » in Baloo in a chunky card, its bar in
  `progress` outlined in ink; each letter's terms in one chunky card, a `line` between rows, each name in Baloo;
  the ✓ disc outlined in ink. Search and filters are the chunky controls (§10.1).
- Live examples show their notion (decided 2026-10-24 by the user, M9-28): volatility draws each day's change
  (`dailyChanges`) as thin bars, the asset above the ETF Monde on one scale (an ordinary day's move, the rarer
  bigger ones reaching the row's edge); the worst drop marks its peak and trough on the year's line. Performance
  and currency keep their line.
- V1 terms (≈ 26): action, etf, indice, diversification, volatilite, pire-baisse, rendement, performance,
  plus-value, frais, risque-de-change, taux-de-change, inflation, interets-composes, dca, livret-a,
  matelas-de-securite, liquidites, ordre-au-marche, ordre-limite, ordre-stop, cours-de-cloture, allocation,
  concentration, horizon-de-placement, rebond.

### 4.5 Wallets and time trips

Wallet kinds: `live` (exactly one, created at first launch) and `trip` (0..n).

**Live wallet:** 50 000 € starting cash, no monthly contribution, FX fee 0.15 %, fractional shares, clock =
`LiveClock`.

**Wallets list** (the Portefeuille tab; layout decided 2026-10-24, artboard `Wallets-A` of the art direction
canvas, money family §10.1): « Mes portefeuilles », and under it « Un portefeuille d'aujourd'hui, et autant de
voyages dans le temps que tu veux. » Each wallet is a flat row: its islet (decided 2026-10-28, M11-3: the
wallet's buildings on Actions & ETF as the map draws them and as the lessons greened it, on a 68 px square of
`sea`, still; « Ton île » or « La ville du voyage {nom} » for screen readers), its name and a chip, a status line, and on the right its value over its change in %
(signed; the amount when nothing was put in). The live wallet is « Aujourd'hui », chip « En direct », « Cours
réels du jour ». A trip's chip is its difficulty; its status line reads « En cours, tu es le {date} » until it
ends (a stopped trip adds « Arrêt automatique : à toi de décider » in `alertText`), then « Terminé, de {mois} à
{mois} » (« Terminé, en {mois} » within one month). « Voyages dans le temps » shows the trip count. A completed
lesson's bridge is a chunky card « Suggéré par ta leçon »: the lesson's title, « Tu as vu la réponse dans la
leçon. Rejoue maintenant ce moment avec ton propre portefeuille. » and « Préparer ce voyage » (`progress`).
Then « Nouveau voyage dans le temps », a chunky primary with a +, and the DCA simulator as a flat row (not on
the artboard). Not taken from the artboard: the tiles' tints and the green « En direct » chip (no token means
them, §10.2: tiles `line`, chips ink on white); the title stays in the app bar, as on the other tabs.

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
   Validation: date parses; `dataFloor ≤ date ≤ today − 30 days`; a day that is not a trip day (no exchange
   of the catalogue trades) → roll forward to the next trip day (inform the user), which must still be in
   range. Before `dataFloor`: error « Nos cours commencent le {dataFloor}. » with a link to the lesson whose
   node declares `covers: {from, to}` around the date, when a pack has one (e.g. 1929 → Les bases; none in
   V1).

2. *Difficulty*

   | Level | Starting cash | Monthly contribution | FX fee | Fixed fee / order | Fractional |
   |---|---|---|---|---|---|
   | Découverte | 50 000 € | 0 | 0 % | 0 € | yes |
   | Réaliste | 10 000 € | 200 € | 0.15 % | 0 € | yes |
   | Serré | 2 000 € | 0 | 0.15 % | 1 € | no (whole shares) |
   | Sur mesure | 100 € – 1 000 000 € | 0 – 10 000 € | 0 – 2 % | 0 – 20 € | yes/no |

   Option: "Commencer avec un matelas de sécurité" → 10 / 20 / 30 % of starting cash (20 % preselected)
   moved to the simulated Livret line on the start date, capped at the Livret ceiling of that date (shown).
   « Sur mesure »: a monthly contribution, when not 0, must at least pay one order's fixed fee.
   Companion note explains that fixed fees and whole shares are what make small budgets harder (shown when
   the settings have a fixed fee or whole shares only).

3. *Recap* — summary rows with "Modifier" links, name (required, 1–30 chars, trimmed; prefilled with the
   moment's name, or « Voyage du JJ/MM/AAAA »), automatic stop conditions as switches with fixed thresholds
   (defaults: portfolio −15 %, order filled; position −20 % and contribution off), reminder that only data
   known at the simulated date is shown. CTA « Partir le {date} » creates the trip and opens it.

Layout (decided 2026-10-24, artboards `TripStep1-A`, `TripStep1Error-A`, `TripStep2-A`, `TripStep3-A` of the
art direction canvas): every step has a chunky close tile, a 3-segment step bar and « Nouveau voyage, étape n
sur 3 »; « Retour » (from step 2) sits beside the next action at the bottom, always in reach. An option is
quiet (2 px `line` border, no shadow) until chosen, then a toy block; a radio says which, never colour alone.
Step 1: the moments as cards with their day on the title row, the « Il y a N ans » shortcuts as pills that
keep « N actifs sur M », then « Choisir une date précise », which opens the date field; a date out of range
turns the field's border `alertText` and shows in an alert box under it. Step 2 recalls the start day; each
difficulty has a 1–3 meter, a tagline and its settings as chips (« Sur mesure »: a tagline only); the
companion note is a chunky card « Ton compagnon »; the cushion sits in a flat card. Step 3: label / value rows
with lines between (Départ with the moment's name, Budget, Frais, Actions, Matelas de sécurité, Fin « Quand
tu veux. Arrivé à aujourd'hui, il suit les vrais jours de bourse »), the automatic stops in a flat card under their title, the reminder by
a clock. Not taken from the artboards: « Suggéré par ta leçon » (not in this spec), the tinted fill of the
chosen option and the coral meter bars (no token means them, §10.2: the meter is ink).

**Trip wallet screen:** identical to the live wallet plus:
- Trip header (neutral background): clock tile, trip name + difficulty chip, simulated date in large type,
  exit button. No colored banner (color rule §10.2).
- Time controls card at the bottom of the screen (a trip's route has no tab bar): +1 jour (the next trip
  day), +1 semaine, +1 mois (same day next month, or its last day), « Avancer jusqu'à… ». They are off
  while time moves, once the trip stopped by itself (until the user decides, §4.5 automatic stop), and
  once the trip is at today (End of trip below). Each advance runs `TripEngine.advance` on a snapshot of the cached market and
  books its result in one transaction (orders, fills, contributions, daily values, companion moments,
  simulated day, status).

Layout (decided 2026-10-24, artboard `Trip-A` of the art direction canvas): no app bar; the trip's header
on top, as on its automatic stop (clock tile, « Voyage « {nom} » » with the difficulty chip, the simulated
day in Baloo, the automatic stops' button until the trip ends, « Quitter le voyage » back to the wallets).
Under the change since the start, when the trip has a monthly contribution and has not ended: « Prochain
versement : +200 € le 3 novembre » (the first trip day of the next month, step 1 below). The time controls
in one chunky card: « Avancer le temps » by a clock with « Terminer le voyage » beside it, +1 jour / +1
semaine / +1 mois as small toy blocks, then « Avancer jusqu'à… » the chunky primary; stopped, the alert box
« Arrêt automatique : à toi de décider » over the steps (off) and « Voir l'arrêt » in its place; ended,
« Voyage terminé le {date}. » and « Voir le bilan ». The rest is the wallet's (§4.7). Not taken from the
artboard: the weekday in the date and the flat exit button (the stop screen's header, M9-25), and what the
trip shares with the live wallet (the label over the value, the « + » in « Investir », « depuis le 18
février », the chart without its card, periods and comparisons, its « Départ » tag in place of the legend,
the positions' dividers, no allocation).

**Advancing time** (domain service `TripEngine.advance(wallet, target, stopConditions)`), one trip day at a
time. A trip day is a day when any exchange of the catalogue trades; an asset whose exchange is closed keeps
its last close and its orders wait.
1. Credit monthly contribution if due (first trip day of the month).
2. Active DCA plans due that day place a € market order, filled at that day's open through the
   `OrderMatcher` rules (fees, whole shares, cancellation). Cash reserved by pending orders stays reserved.
3. Run `OrderMatcher` on that day's bar for every pending order (§4.6).
4. Accrue Livret interest bookkeeping (§4.11).
5. Compute end-of-day valuation, append to the wallet's daily value series.
6. Evaluate stop conditions and companion rules; if a stop condition fires → stop, persist, emit event.

**DCA plans** (decided 2026-10-26, M9-41): any wallet but a finished trip runs plans, each an asset, a € amount
per purchase (> 0, ≤ 100 000 €, above the fixed fee: `validateDcaAmount`) and a frequency, « Chaque mois » or
« Chaque semaine ». One is set up from the asset page's « Investir chaque mois » (§4.8) or the DCA simulator's
« Le mettre en place » (§4.10), in a flat sheet like the order sheet's: the asset with « Versement programmé »,
a line on what DCA does, « Montant par achat » as the boxed headline with 50 / 100 / 200 € chips and its errors
under it, « Fréquence », then a card « Premier achat : le {date} » with the schedule that follows and what a
short day does, and the button « Investir 100,00 € chaque mois » over « Argent fictif. Aucune transaction
réelle. ». Saved, it says « Versement programmé : premier achat le {date}. » with « Mon portefeuille ».
- *First purchase* (`firstPurchaseDay`): the first session of the asset's exchange after the wallet's day that
  opens after the plan is set up: by the real time for the live wallet and a trip at today, after the trip's
  day (seen after its close) otherwise. No purchase uses a price known when the plan was set up: set up at
  15:00 in New York, mid-session, a plan buys at the next session's open. The day is checked again when the
  plan is saved, then stored as its `startDate`; the purchases after it follow `dcaSchedule`, as in the
  simulator. A plan's id is its wallet's id and its rank in that wallet (plans are stopped, never deleted).
- *Each due day* (step 2): a € market order `dca-<plan>-<day>` filled at that day's open. With too little cash
  it is cancelled with its reason, as any order (« Les liquidités ne suffisaient plus quand il s'est
  déclenché. » on its screen), and the plan goes on to its next date.
- *« Arrêter »* (confirmed, on the wallet's « Versements programmés », §4.7) sets a plan inactive: it places no
  more purchases. Those it made stay; one still waiting (its asset had no bar that day) stays an order in
  « Ordres en attente », where « Annuler l'ordre » cancels it.

Stop conditions: portfolio value more than X % below the money put in so far (start + contributions;
default 15), any position loss > Y % (default 20), an order the user placed filled (DCA purchases don't
count), a contribution arrived. Threshold conditions fire when they start to hold and re-arm once false
again, so a portfolio stuck below the line stops the trip once. The automatic-stop screen shows the drop chart with the threshold,
three neutral choices (each with upside and downside), an optional "Pourquoi ?" text saved to the journal.
The choices (decided 2026-10-11): for a portfolio or position drop, « Garder », « Vendre la moitié », « Tout
vendre » (every position for a portfolio drop, the dropped one otherwise; halves round down, to whole shares
when fractions are off), the sells being market orders filled at the next session; for an order filled or a
contribution, « Continuer ». The trip stays stopped (time controls off) until the user answers. The
automatic stops can be changed any time from the trip header, the stop screen or « Avancer jusqu'à… ».
« Avancer jusqu'à… » (decided 2026-10-25, artboard `TripFF-A`): a sheet titled with a close button and a
line saying time runs day by day, orders and contributions going through on the way. « Durée »: 1 mois,
3 mois, 1 an or « Date précise », then the day « Jusqu'au » (typed, strictly after the trip's day and up to
yesterday). « Arrête-moi si… »: the trip's own automatic stops as checkboxes, saved to the trip before time
moves when changed (one set of stops, decided 2026-10-25); the thresholds stay 15 % and 20 %. When the
next contribution comes on the way and no DCA plan invests it, a line says it will stay as cash, « DCA »
linking its term. Then the chunky « Avancer jusqu'au {date} ».
Stop screen layout (decided 2026-10-24, artboard `TripStop-A` of the art direction canvas): no app bar; the
trip's header on top (clock tile, « Voyage « {nom} » » with an `alert` « Arrêt automatique » chip, the
simulated day in Baloo, « Quitter le voyage » back to the wallets). The event in one chunky card: « Arrêt
automatique » in `alertText`, what happened as a Baloo headline (a portfolio drop as its loss against the money
put in: « Ton portefeuille a perdu −16,77 % par rapport à l'argent versé. »; another reason of the same day in
body text under it). For a drop, its chart over dated days (`dateAxis`), lightly filled, ending on an `alert`
dot, against the dashed line it crossed, labelled « Ton seuil : −15 % » (the fixed threshold, even if that
stop was turned off since); then the market meanwhile, « Sur la même période, l'ETF Monde a fait −17,12 %. »
(the world ETF's return over the chart's days in its currency, left out when it was not listed by the first
day) and « Il te reste 1 834,50 € de liquidités. ». The answers' titles in Baloo. « Pourquoi ? (facultatif) »
labels its field from above (an example inside it for a drop), with « Ta décision est notée dans ton journal
de voyage. On la relira ensemble à la fin. » under it. For a drop, « Avant de choisir : c'est quoi, une pire
baisse ? » opens that term's sheet. Not taken from the artboard: its answers (the choices decided 2026-10-11
stay), its comparison in words (« presque autant que tes actions »: the figure instead) and the time span in
the headline (« en trois semaines »).

**End of trip** (any time, with « Terminer le voyage »): summary with the
user's time-weighted return (§7.6) compared with counterfactuals computed from the same start date and the
same contributions:
- *Sans rien toucher*: everything (start cash + contributions) into the world ETF on the day it arrives.
- *Sur un Livret A*: everything into the Livret (historical rates, §4.11).
- *Ta pire décision*: if the journal has a sell decision, "if you had sold everything at that moment".
Plus journal replay ("Le 12 mars, tu as vendu 30 %… ils ont ensuite regagné 61 %") and glossary terms met.
Decided 2026-10-11: with several sell decisions, *Ta pire décision* is the one whose "everything sold"
line ends lowest (earliest on a tie); everything is sold at that day's close, after the selling fees (§4.6),
then kept as cash, later contributions added as cash. A Livret A keeps earning in that line (decided
2026-10-11, M8-1): « everything » is the positions, as with the stop's « Tout vendre », and the interest
the Livret earns after that day is added. The replay shows, for a sell, how the shares it sold
moved from their sale price to the end of the trip (EUR); for « Garder », the portfolio's time-weighted
return from that day to the end; for « Continuer », the event and its reason only. The glossary terms met
are those of the companion moments that fired during the trip (§4.12), in the order they first came up.
« Terminer le voyage » (confirmed) sets the trip `finished`: time controls and « Investir » give way to
« Voir le bilan »; the wallet stays readable. A trip has no maximum length (decided 2026-10-24, §14.2): one
whose day is on or after the last closed session the market data covers is *at today*, stays open and
keeps trading. It can no longer be sped up, since prices ahead are not known: its steps and « Avancer
jusqu'à… » are off, the time card saying « Ton voyage a rejoint aujourd'hui : il avance maintenant au
rythme des vrais jours de bourse. », and « Terminer le voyage » stays. It goes on by itself at the pace of
real days, like the live wallet: at launch and on its pull-to-refresh, it moves to the last closed session,
an advance like any other (contributions, pending orders, automatic stops; a stop waits for the user's
decision, shown when the trip is opened). Offline, it waits. As in the live wallet, an order placed in a
trip at today takes part from the first session that opened after it was placed: it carries the real time,
not the trip's day. Trips that ended at the last day of the data before this rule stay ended.
Summary layout (decided 2026-10-24, artboard `TripEnd-A` of the art direction canvas): a world screen on the
sea under the Actions & ETF island with the city the trip built (its own positions, §4.2) and the greenery
the lessons grew (M9-19). A chunky card « Fin du voyage « {nom} » » with the dates and the money paid in,
then each outcome with its signed time-weighted return and value over a bar from zero (gain right, loss
left, every bar on the widest return's scale). The journal and the terms met in a second chunky card. Then,
decided by the user: « Rejouer avec une autre difficulté » (the trip wizard at its difficulty step, from the
same start date) and « Retour à mes portefeuilles ». A wizard link names its step; the wizard goes there as
far as the steps before it are complete.

**No lookahead (enforced in data layer):** a trip can only see bars, quotes, FX rates, assets and Livret
rates dated ≤ its clock. Assets with `listingDate > clock.now()` are hidden in Explorer and unavailable
in the order sheet.

### 4.6 Orders

Types: market, limit, stop (stop-loss on sells; stop-buy allowed). Sides: buy, sell. Input in € amount or
in quantity (toggle). A € amount is the value of the shares traded: fees come on top of a buy and out of a
sell's proceeds. Fractional to 6 decimals unless wallet disallows; whole-share wallets accept € orders and
floor them to whole shares. Good-till-cancelled.

Sheet (decided 2026-10-24, artboards `Order-A` and `OrderError-A` of the art direction canvas, money family
§10.1): the title with a ✕; « Type d'ordre »; the amount or quantity as the headline, a large boxed figure
with what is available under it and a compact € / Parts toggle beside its label; round quick chips
(« 500 € »); the summary; the coach in a chunky card « Avant de valider ». A validation error turns the box
`alertText` and shows under it with a warning icon; the button then waits. The main button stays at the
bottom of the sheet whatever scrolls above it, names the amount (« Acheter pour 500,00 € »), over « Argent
fictif. Aucune transaction réelle. » No lock on limit and stop (soft gate below). Its controls are chunky,
as on every screen (M11-1, §10.1).

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

Market hours (Paris time, exchange holidays from the backend calendar, §8.3): Euronext 09:00–17:30,
NYSE/Nasdaq 15:30–22:00 (adjust for US/EU DST mismatch via exchange time zones, never hardcode offsets).
On an early close (M9-37: usually 13:00 New York on 3 July, the day after Thanksgiving and 24 December,
served by the same calendar) the session ends then: `closeAt` and `isOpen` use that time, so a live market
order sent after it waits for the next opening.

Order lifecycle UI: sent → market opens → executed. The map shows a pending buy as a building under
construction that completes on fill.

**After a buy** (decided 2026-10-25, M9-34, artboard `OrderDone-A` of the art direction canvas): every buy,
in the live wallet and in trips, opens a world screen on the sea instead of the message
(`/wallet/:walletId/order/:orderId/done`, `orderDone`): the wallet's island (the live wallet's, or the trip's
own city) with the order's building, under construction while the buy waits, built when it filled at once
(drawn even when the asset is not among the five largest: it takes the last place, M9-43);
a chunky card with « Ordre programmé » / « Ordre exécuté », « Ton immeuble {actif} est en chantier » /
« … est construit », one line saying why it waits and when it goes (the sheet's own copy) or at what price it
filled, the order's steps (as on the order screen, ✓ done in `progress`, the current one in `primary`) and
« Voir l'ordre »; « Mission accomplie : {mission} » with its step on the island for each mission the buy
completed (a live buy filled at once: the missions it satisfies that were not done before); then « Retour à
l'île » (the map) and « Mon portefeuille » (the wallet it was placed in). A sell keeps its message. No
confetti: the app has no celebration widget to reuse.

**Pending orders, live wallet** (M4-6, decided 2026-10-11): at launch and on the wallet's pull-to-refresh, a
catch-up runs the trip engine over the live wallet up to the last day whose sessions have all closed. A pending
order takes part from the first session that opened after it was placed (a limit set mid-session never fills on
that session's earlier prices), and each closed session gets its end-of-day value. Offline, nothing is booked
and the wallet works on what it has. The order sheet runs the catch-up before it opens, so a fill at the quote
never lands before a closed session is valued; when the catch-up fails, an order waits for the next opening,
as offline (M9-38). The order screen (`/wallet/:walletId/order/:orderId`) shows the steps:
« Envoyé » → « Ouverture du marché » (live market order sent while closed) / « Prochain jour de cotation du
voyage » (trip market order) / « En attente du cours » (limit, stop) → « Exécuté » with its fill and fees, or
« Annulé » with its reason. « Annuler l'ordre » (confirmed) cancels a pending order and frees what it held
back. The wallet screen lists « Ordres en attente », each opening its screen; the message after placing a
sell, and the screen after a buy, carry « Voir l'ordre ».

**Pre-trade coach** (companion card in the order sheet): new weight of the asset in the wallet ("Apple
pèserait 8 % de ton portefeuille, contre 4 % aujourd'hui"), threshold from `momentThresholds(profile)`.
Never blocks. Shown on every order; above the threshold it adds « Au-delà de {seuil}, une seule ligne pèse
lourd : c'est la concentration » in the alert color (decided 2026-10-11).

**Order sheet** (M4-5, decided 2026-10-11): opened from the asset page's « Acheter · Vendre » (Vendre only with
a position; neither on a finished trip). Quick chips: 100 / 500 / 1 000 € and « Max » (all available cash, fees
included) to buy in euros, 1 / 5 / 10 shares in quantity, « La moitié » and « Tout » to sell. The summary shows
shares, value, fees and total, estimated at the last known price. Errors show once there is input or after
« Valider ». Placing closes the sheet back on the asset; a buy then opens its world screen (above, M9-34), a
sell leaves a message: « Vente exécutée : … » (live market order, market open: filled at the quote now),
« Ordre envoyé : il partira à l'ouverture, le … à … » (market closed), « … il attend que le cours atteigne ton
prix » (limit, stop) or « … au prochain jour de cotation du voyage » (trip). In a trip, an optional « Pourquoi ? » saves the order to the journal (decision `buy` or
`sell`, event the order id); the summary replays it with how the traded shares moved since their fill.

### 4.7 Wallet (portfolio) screen

- The wallet's island first (decided 2026-10-28 by the user, M11-4, the canvas « The world on every tab »),
  for the live wallet and every trip (under its header): a 250 px panel of `sea` with its city, zoomed ×1.75 on
  its buildings so that each one, as the map draws it (pending ghosts included), is a 44 px target that opens
  its asset (`/asset/{id}?wallet=`), its name for screen readers. Under it « Touche un immeuble pour ouvrir sa
  ligne », or before the first buy « Ton île attend son premier immeuble ». Still: it changes at once.
- Header: total value, change since start (amount and %; TWR when contributions exist), data timestamp
  (the oldest price on screen), two tiles "Investi" (market value of the positions now, so tiles + Livret
  add up to the total) / "Liquidités disponibles" (cash minus what pending buys hold back), primary button
  « Investir » (→ Explorer scoped to wallet).
- Period selector 1S / 1M / 3M / 1A / Tout (each opens on the last day before the period); chart of daily
  value with a dashed "Argent versé" baseline (starting cash + contributions so far); benchmark chips
  « Comparer à : » ETF Monde / Livret A, none by default: the same money put in on the same days, into the
  world ETF (wallet fees, fractional shares) or the Livret A (within its ceiling).
- Allocation bar + legend (includes cash and Livret lines): positions in shades of `primary`, largest first;
  cash `line`; Livret `muted`.
- Companion card when a moment is active.
- Positions list (cash is **not** a row): avatar, name, quantity, value in €, P&L % with sign. None yet (and
  the wallet not finished): a bare plot on `sea`, « Aucune position pour l'instant. », « Ton premier achat
  posera la première pierre de ton île. » and « Explorer les actifs » (M11-4).
- « Versements programmés » (M9-41), under the pending orders and only while the wallet has an active DCA plan
  (none on a finished trip): each plan with its asset's avatar and name, « 100,00 € chaque mois », « Prochain
  achat : le 9 novembre » (its first scheduled purchase after the wallet's day, §4.5) and « Arrêter ».

### 4.8 Asset page

- Name, ticker + exchange + quote currency in words, price in quote currency and ≈ € equivalent,
  last-session change (from the previous close), data timestamp.
- Period chart (1S / 1M / 1A / 5A, each opening on the last close before it) with: the scoped wallet's buy
  markers (at the price paid), worst-drop annotation (peak → trough, `alert` dots), optional benchmark
  (ETF Monde, dashed, rebased to the asset's first close of the period).
- Essentials tiles (each opens its glossary sheet, M6-6), over the last year: Performance sur 1 an,
  Volatilité (band label at level 1; label + figure from level 2), Pire baisse, Risque de change (the
  currency and its 1-year move against the euro; « Aucun » for EUR assets).
- "Pourquoi ça bouge ?" card: decomposition of the chart period's move (§7.9), from its first close to the
  price now, as a stacked bar + three rows.
- « Stabilité passée » (decided 2026-10-25, M9-36), a flat card after the essentials: a score out of 100 of
  how little the price moved in the past. Higher means it moved less, not « better »: it is not a ranking, so
  the Explorer never shows, sorts or ranks assets by it. Computed from the closes on or before the clock's day
  (`pastStability`), so a trip scores as of its date. Four parts, each with its points and the fact behind it:
  - Mouvements, 40: the annualised volatility of the last year of closes (the Volatilité tile's), 40 minus
    one point per point of volatility, 0 from 40 % (band 5). Level 1 shows its band, level 2 its figure.
  - Pire baisse, 30: the max drawdown over five years (opening on the last close before them, like the 5A
    chart), with its months (« −34 % entre février et mars 2020 »), 30 minus one point per 2 % fallen, 0 from
    −60 %.
  - Une entreprise ou un panier, 15: an ETF spreads the risk (15), a stock does not (0).
  - Durée de l'historique, 15: 1,5 point per full year since the asset's first close (`listingDate`), 15 from
    ten years; a long history makes the other figures more reliable.

  Each part is rounded half-even to a whole point and the score is their sum, so the rows add up to it.
  Under a year of closes (none on or before the same day a year back, or under 20 daily returns in that year)
  the movements cannot be measured: no score, « Pas de score : il faut au moins un an de cours. » Under five
  years, the worst fall uses what exists. Under the parts: « Ce score décrit les cinq dernières années. Il ne
  dit rien de l'avenir et ce n'est pas un conseil. » Neutral colours (it is neither a gain nor a loss);
  screen readers hear the card as one sentence.
- User position: quantity, value, P&L (amount, %), of which currency effect = value now − value at the
  average purchase rate (notional-weighted, kept by sells like the average cost).
- Beside the position, its building (decided 2026-10-28 by the user, M11-6, option B of the canvas « The world
  on every tab »): on a 92×116 square of `sea`, as Actions & ETF draws it at the island's scale, in the colours,
  windows and flag of its place there, a waiting buy's ghost included (`BuildingPortraitPainter`), « Ton
  immeuble » under it. An asset the island does not draw shows none.
- Buy / Sell buttons, and under them « Investir chaque mois » (M9-41): the plan sheet for this asset in the
  scoped wallet (§4.5). None of them on a finished trip.

### 4.9 Explorer

- Catalogue (§8.4) sorted by name, search (name, ticker; case, accents and punctuation ignored), filter
  chips: Tout / ETF / Actions / Favoris.
- Row: avatar, name, region, risk meter (5 bars, §7.8, from the volatility of the last year of closes),
  price (quote currency), change over 1 year to that price, favorite toggle (persisted). A row whose history
  cannot be read keeps its name without figures; the list fails only when no row has any.
- Offline banner « Hors connexion. Tu vois les cours du {date}, {heure}. » + Réessayer.
- In a trip, the list is filtered by availability and every value is as of the trip date.
- Layout (decided 2026-10-24, artboard `Explore-A`): the list reads in two groups, « ETF » then « Actions »,
  each under its section title (`SectionTitle`) with what it is (« Un panier d'entreprises en un seul achat »,
  « Une seule entreprise : plus de potentiel, plus de secousses »), its rows in a flat card, sorted by name
  inside. Search and filters narrow both groups; a group with nothing left is not shown. Filter chips are
  pills; a long name wraps to a second line.
- Each section title beside what it holds (decided 2026-10-28 by the user, M11-5: « it shows what each is »),
  a 60×56 scene on `sea` in `MapPalette` (§10.2): ETF, four small buildings on one plot (a basket); Actions,
  one tower with its flag (one company). Decorative: the title and its line say it.

### 4.10 DCA simulator

- Inputs: asset (select), amount per period (€, > 0, ≤ 100 000), frequency (monthly / weekly), start date
  (validated like the trip wizard), end = latest data.
- Output: total invested, final value, gain (amount, %), chart (value vs stepped invested line), number of
  purchases.
- Comparisons: lump sum at start (same total), same contributions on a Livret A.
- Companion insight (fr copy written per result shape, e.g. "tes achats de 2022 se sont faits à prix
  cassés…").
- Save simulation (persisted, listed in the tool), rerun with another asset.

Built (M8-2), decided 2026-10-11:
- Fees: the live wallet's rules (0,15 % FX fee on dollar assets, no fixed fee; the Settings FX fee later).
- Start: « 1 an · 3 ans · 5 ans · 10 ans » (default: the preset nearest below the Q1 horizon) or an exact date,
  checked like the trip wizard from the asset's first close; a day without a session rolls to the next.
- Amount: > 0, ≤ 100 000 €, above the fixed fee (`validateDcaAmount`). Purchases at each scheduled day's
  close (`dcaSchedule`, `investFlows`); the lump sum puts the same total in on the first purchase day; the
  Livret gets the same deposits within its ceiling.
- Insight, first match wins (`dcaInsight`): ended below the money put in → « Le DCA lisse le prix d'achat : il
  n'empêche pas une baisse »; else the calendar year whose buys cost on average at least 15 % under the last
  close, the cheapest → « Tes achats de {year} se sont faits à prix cassés »; else which of DCA and the lump sum
  ended ahead, and by how much.
- Saved: inputs and what they gave (`dca_simulations`), newest first; « Relancer » puts them back in the form
  and runs them again on the latest data, where the asset can be changed. Reached from the Portefeuille tab.

Layout (decided 2026-10-24, artboard DCA-A): titled « Et si j'avais investi… ». The form is one flat card of
outlined boxes: the asset, then the amount and the frequency side by side, then « Depuis » (the presets and the
exact date). The result leads with a chunky card « Résultat, n achats »: the asset and its dates, « Tu aurais
versé » and « Ça vaudrait » in large round euros (one under the other when they do not fit), and the gain signed
in its colour. Then the chart in a flat card, its legend on top: the value with a light fill and a dot at its
end, the money put in dashed, the x-axis dated (`dateAxis`, §10.1). Then « Avec la même somme » as a titled
flat card, each name on one line with its round value and signed change stacked beside it; then the insight in
a chunky « Ton compagnon » card with the glossary's DCA as a chip; then « Enregistrer » as a chunky button.
« Tes simulations » is a titled flat card. The lump sum and the Livret A stay, though the artboard has none.
No « Autre actif » button (decided 2026-10-24 by the user): the asset field opens the form, one swipe above
the result.
« Le mettre en place » (decided 2026-10-26, M9-41), a chunky button under « Enregistrer », opens the plan sheet
(§4.5) for the simulated asset in the live wallet with the simulated amount and frequency; the plan starts from
now, not from the simulated start.

### 4.11 Livret A

Facts encoded in the backend (`backend/internal/catalogue/livret.go`, never hardcoded in the app), from the
rate in force on the data floor:
- Annual rate history (dated rows; reviewed every 1 February and 1 August). Current: 1.7 % since 2026-08-01.
- Deposit ceiling, dated like the rates: 100 000 F (15 244,90 €) until 2001, 15 300 € from 1 January 2002,
  19 125 € from 1 October 2012, 22 950 € since 1 January 2013 (capitalised interest may exceed it).
- Interest by fortnight ("quinzaine": 1st–15th, 16th–end of month). Deposits earn from the next quinzaine
  start; withdrawals stop earning from the start of the quinzaine in which they happen. Interest is credited
  and capitalised on 31 December.

Uses:
- Simulated Livret line in any wallet (transfer cash ↔ Livret, instant, no fees). Built (M8-1): a « Livret A »
  card under the positions: balance, « Intérêts de l'année : +x €, versés le 31 décembre », the rate and
  ceiling of the wallet's day, « Verser » · « Retirer » (none on a finished trip; « Retirer » needs a
  balance). The sheet shows the cash available (deposit) or the balance (withdrawal) and the room under the
  ceiling, checks each amount with `validateLivretTransfer`, and books it on the wallet's day (today, or the
  trip's day); the allocation and the chart's « Livret A » comparison follow.
- Benchmark line on the wallet chart; counterfactual in trip summary; comparison in DCA; island node 1.
  These comparisons respect the ceiling valid at each date: money above it stays as uninvested cash at 0 %
  until a ceiling rise makes room for it (decided 2026-10-24), and the result says when some is still out.
- Teaching stance: the Livret is the right place for a safety cushion (3–6 months of expenses), not for
  long-term money. Never mock it.

### 4.12 Companion (teachable moments)

Pure rule engine over domain events, outputs `CompanionCard{ruleId, title, body, links[]}`.

| Rule | Trigger (defaults; only concentration follows the profile) | Cooldown |
|---|---|---|
| `first_loss` | First time a position is < −5 % | once |
| `position_drop` | Position −15 % from its peak since purchase | 30 days per position |
| `portfolio_drawdown` | Wallet performance −10 % from its peak (contributions excluded) | 30 days |
| `concentration` | One non-cash position > 30 % (low comfort) / 40 % (others) | 14 days |
| `idle_cash` | Cash > 25 % of wallet for > 30 days | 30 days |
| `panic_sell` | Sell within 10 trading days after that position was −15 % | per event; revisited 3 months later ("what happened after you sold") |
| `fx_swing` | EUR/USD move > 3 % in a month with USD exposure > 20 % | 30 days |

Cards link to glossary terms or nodes. Wording describes, never prescribes.

Built (M8-3): a moment stays « non lu » until its card's « J'ai compris » (`companion_log.dismissedAt`); the
cooldowns run on the log whether read or not. Where cards show: the oldest unread moment of any wallet leads the
map's next-step card (« Ton compagnon », its title, « Lire » opens the card in a sheet); a wallet shows its oldest
unread moment under « Investir »; an asset page shows the oldest unread moment of its wallet about that asset.
A card: « Ton compagnon », a title and a body per rule (figures from the moment's params, signed only where the
words do not already say which way), chips to its glossary terms, « Revoir la leçon : … » to its lesson
(`CompanionRule.lesson`: first loss → risk ladder; position drop and concentration → Apple vs world 2022;
portfolio drawdown and panic sells → March 2020; idle cash → Livret vs ETF; FX swing → the dollar trap), and
« J'ai compris ».

### 4.13 Trip journal

Entry: `{walletId, simDate, eventId?, decision, reasonText?}`. Created by automatic-stop decisions and
optional on any order in a trip. Replayed in the trip summary with what happened next (computed).

### 4.14 Settings

Language (fr/en), level + "Tout afficher dès maintenant" switch, retake questionnaire, data (last update,
cached histories count and size, refresh now, clear cache), simulation (starting capital of live wallet,
simulated FX fee), reset live wallet (keeps island progress, confirmation required), about (fictional money,
no advice, data sources).

Built (M9-1), decided 2026-10-12:
- Language: « Celle de l'appareil » · Français · English, applied at once (`profiles.language`).
- Level: « Niveau n sur 3 », and « Tout afficher dès maintenant » (`profiles.showAll`), which sets level 3.
- « Refaire le questionnaire » opens it with the previous answers; progress and settings are kept.
- Data: when prices last came from the network, the histories and closes cached and the database's size on the
  device; « Actualiser maintenant » makes every price due again (the cached ones stand until then, offline
  included, and the last fetch time stays; M9-10); « Vider le cache » deletes prices, quotes and
  rates (wallets, lessons, the catalogue and calendars stay).
- Starting capital: 1 000 · 10 000 · 50 000 · 100 000 €, applied at the next reset (`profiles.liveStartingCents`,
  schema v3).
- FX fee: 0 · 0,15 · 0,5 · 1 %, for the live wallet's orders from now on and the DCA simulator; trips keep
  theirs, past fills keep their fees.
- Reset: confirmed in a dialog naming the capital; the live wallet and everything in it go, and it starts again
  today with the chosen capital and its FX fee.
- Layout (decided 2026-10-24, artboard `Settings-A` of the art direction canvas, money family §10.1): Baloo
  section titles over flat cards, a line between rows. A setting with values to pick (language, capital, FX
  fee) is one row: its name, its value under it in bold, its note; tapped, a dialog lists the values. Data:
  « Actualiser maintenant » (refresh icon) and « Vider le cache » stacked. Reset: an `alertText`-bordered
  button with a warning icon, and a line under it saying what it puts back and that island progress stays.

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
class MarketRepository {                                           // ADR-005
  Future<List<Asset>> assets({required DateTime asOf});
  Future<List<PriceBar>> history(String assetId, {required DateTime from, required DateTime to, required DateTime asOf});
  Future<Quote?> latest(String assetId, {required DateTime asOf});  // live only; trips price from history
  Future<MarketCalendar> calendar(Set<Exchange> exchanges, {required int fromYear, required int toYear});
  Stream<CacheStatus> status();                                     // fresh / stale(lastUpdated) / offline (M3-5)
}
class FxService { Future<Decimal> rate(Currency from, Currency to, {required DateTime asOf}); }  // ADR-005
```

Repositories clamp every query to `asOf`. A trip wallet's providers are created with its `HistoricalClock`
(Riverpod family keyed by `walletId`).

### 5.3 State and async conventions

- One notifier per screen-level concern; widgets `ref.watch` and render `AsyncValue` through shared
  widgets: `AsyncSkeleton`, `ErrorView(failure, onRetry)`, `StaleBanner(lastUpdated)`.
- Refresh keeps previous data visible (`AsyncValue.copyWithPrevious`), never flashes a spinner over data.
- Failures: `NetworkFailure` (unreachable, timeout, HTTP 502–504), `RateLimitedFailure(retryAfter)`,
  `NotFoundFailure`, `ServerFailure` (other HTTP errors, unreadable body), `DataUnavailableFailure(asOf)`,
  `ValidationFailure(code, params)`, `StorageFailure`.
- What happens on rebuild: widgets are stateless where possible; `AnimationController`s live in `State`
  objects and are disposed; no fetching in `build`.

### 5.4 Dependencies (allowed list)

flutter_riverpod (+ riverpod_annotation / riverpod_generator), go_router, drift + drift_flutter (SQLite is
bundled by `package:sqlite3` 3.x; `sqlite3_flutter_libs` is end-of-life),
dio, freezed + json_serializable, decimal, intl + flutter_localizations, fl_chart, connectivity_plus,
mocktail (dev), build_runner (dev). Fonts are **bundled as assets** (Baloo 2, Figtree — both OFL); do not
fetch fonts at runtime (offline requirement).

---

## 6. Data, cache and offline

### 6.1 Local schema (drift)

Cache (cleared from Settings, refetched): user tables never reference them.

| Table | Key columns |
|---|---|
| `assets` | id, symbol, name, type (etf/stock), exchange, currency, region, listingDate |
| `price_bars` | assetId, date, open, high, low, close, volume — PK (assetId, date); bars are already adjusted |
| `quotes` | assetId, price, currency, asOf, fetchedAt, marketOpen |
| `fx_rates` | base, quote, date, rate — PK (base, quote, date) |
| `livret_rates` · `livret_ceilings` | validFrom, annualRate · validFrom, amountCents |
| `history_sync` | assetId, firstDate, lastDate, fetchedAt, adjustedAt (backend refetch after a split) |
| `exchange_holidays` · `exchange_early_closes` · `calendar_years` | exchange, date · exchange, date, closeHour, closeMinute (local time) · exchange, year, fetchedAt |
| `content_packs` | islandId, version, json, etag, checkedAt |

User data (only the user creates it; rows of a wallet cascade when it is deleted):

| Table | Key columns |
|---|---|
| `wallets` | id, kind, name, startDate, simDate (trip), difficulty, params json, status, createdAt, breachedStops json, companionState json, stopReasons json (v2: why a trip stopped, until the user answers) |
| `cash_ledger` | walletId, date, amountCents, kind (start, contribution, buy, sell, fee, livretIn, livretOut), refId — cash = Σ amounts; Livret interest is computed, not stored |
| `orders` | id, walletId, assetId, side, type, amountCents xor quantityMicros, limitPrice?, stopPrice?, priceCurrency?, status, cancelReason?, planId?, createdAt |
| `fills` | id (execution order), orderId (unique), walletId, assetId, side, date, price, currency, quantityMicros, fxRate, feesCents |
| `wallet_values` | walletId, date, valueCents, flowCents — daily series for charts and TWR |
| `dca_plans` | id, walletId, assetId, amountCents, frequency, startDate, active |
| `dca_simulations` | id, params json, result json, savedAt |
| `journal_entries` | walletId, simDate, eventId, decision, reason |
| `profiles` | single row: the five answers, showAll, language |
| `node_progress` | nodeId, status, attempts, lastAnswer, completedAt |
| `glossary_state` | termId, discoveredAt, quizPassed |
| `favorites` | assetId, addedAt |
| `companion_log` | walletId, rule, key, firedAt, params json, dismissedAt |

Positions are **derived** from fills (average-cost method), never stored as the source of truth.

### 6.2 Cache policy (ADR-005)

- **History:** immutable once a day is closed. On first need, fetch the whole history (from `dataFloor`).
  Afterwards fetch only `from = lastDate + 1`, at most every 15 min. Never refetch closed days unless the
  backend's `adjustedAt` moved (then refetch that asset fully).
- **Quotes (live wallet):** TTL 15 min during the asset's market hours, until next session open otherwise.
- **Catalogue:** once a day. **Calendar:** a year fetched after it ended is final; any other year is
  checked once a day.
- **FX:** daily ECB rates from Frankfurter; a date's rate never changes. First need of a pair: its whole
  history since `dataFloor` in one request; afterwards only the days after the last cached rate, at most
  every 15 min. A day without a fixing takes the previous rate.
- **Content packs:** manifest checked at most once a day; a higher version is downloaded and cached if it
  reads, otherwise the bundled pack stands in (ADR-006).
- **Livret rates:** check once a day.

### 6.3 Who decides cache vs network

Repositories only. Notifiers ask for data; repositories return cached data immediately, decide whether a
fetch is needed, and emit updates. UI never knows the source except through `CacheStatus`.

### 6.4 Offline

Everything readable offline: map, islands (bundled packs), wallets, positions, charts (cached), glossary,
saved simulations, trip advancing (only within cached history; past that → `DataUnavailableFailure` with a
clear message). A live order while offline (or while the price fetch fails) never fills at a cached
price: a market order waits as pending for the first session that opens after it was placed, as when the
market is closed, and the catch-up fills it at that open once back online (§14.1, decided 2026-10-12). A
held asset without any cached quote is valued at its last cached close. Stale-data banner shows date and
time of the last successful price fetch, in local time. Manual check: `docs/qa/offline.md`.

`CacheStatus` (from `MarketRepository.status()`): `Offline(lastUpdated)` when the device has no connection
(`connectivity_plus`); `Stale(lastUpdated)` when it has one but the last price fetch (history or quote)
failed and the cache stood in; `Fresh` otherwise. `CacheStatusBanner` shows the banner for the first two.

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
  cmd/freeze/        builds frozen datasets for content (writes into content/…/datasets; -recipes
                     rebuilds them from datasets.json, ADR-007)
  cmd/contentcheck/  validates content packs (schema, locales, glossary refs, dataset refs)
  internal/provider/ Provider interface + twelvedata adapter (+ fake for tests)
  internal/store/    SQLite (modernc.org/sqlite) — assets, bars, fx, livret_rates, sync state
  internal/api/      handlers, DTOs, ETag/Last-Modified
  internal/jobs/     daily append, backfill with rate-limit budget
```

Go ≥ 1.22, stdlib `net/http` routing, structured logs (`log/slog`), config via env, Docker image, self-hosted.
The image is published on each `v*` tag as `ghcr.io/mikaellecam/motu-backend` (amd64, arm64), with the lessons
and no dataset: it freezes them at start (ADR-007, `docs/deploy.md`).

### 8.3 Endpoints (JSON, read-only)

| Method & path | Returns |
|---|---|
| `GET /v1/assets` | Catalogue with listingDate, currency, region, type |
| `GET /v1/assets/{id}/history?from=&to=` | Adjusted daily OHLCV bars, ascending; `to` defaults to latest; `adjustedAt` = last full refetch after a dividend or split (the app drops its cached history when it moves) |
| `GET /v1/quotes?ids=a,b,c` | Latest price per asset with `asOf` and market status: the live quote (refreshed every 30 min in session) or else the last close |
| `GET /v1/fx?base=USD&quote=EUR&from=&to=` | Daily rates (cached Frankfurter; the app also calls Frankfurter directly) |
| `GET /v1/livret/rates` | Dated Livret A rate history and dated ceiling history |
| `GET /v1/calendar/{exchange}?year=` | Holidays (weekdays without a session) of `nyse`, `nasdaq` or `otc`, all on the NYSE calendar, from 2000 to next year, and `earlyCloses` (`[{date, close: "13:00"}]`, New York time); every other weekday trades regular hours. Early closes are listed by hand to 2028 from pandas_market_calendars, checked against exchange_calendars (XNYS) and nyse.com; later years follow the rule since 2013 |
| `GET /v1/content/manifest` · `GET /v1/content/packs/{islandId}/{version}` | Content distribution |
| `GET /healthz` | Liveness |

Errors: `{"error": {"code": "...", "message": "..."}}` with proper status codes; 429 carries `Retry-After` (per-client
limit). Every endpoint answers conditional requests (`ETag`, and `Last-Modified` where the data's date is
known). Bodies over 1 KB are gzipped for clients that accept it (own ETag, `Vary: Accept-Encoding`). Prices and
rates are decimal strings, never JSON numbers.

### 8.4 Catalogue V1 (29 instruments, US listings: ADR-004)

The provider's free plan covers US exchanges only, so every instrument is a US listing quoted in USD; the
symbol map, listings and history depth are in ADR-004.

ETFs: world (MSCI ACWI, the « ETF Monde » benchmark), S&P 500, Nasdaq 100, Europe (FTSE Developed Europe),
emerging markets, international government bonds, aggregate bonds.
Europe (as ADRs): LVMH, TotalEnergies, Airbus, ASML, SAP, Schneider Electric, L'Oréal, Sanofi, Siemens,
Novo Nordisk, Hermès, BNP Paribas.
US: Apple, Microsoft, Nvidia, Amazon, Alphabet, Meta, Tesla, Berkshire Hathaway, JPMorgan, Coca-Cola.

### 8.5 Provider notes

Twelve Data, Basic (free) plan: 8 credits/min, 800/day, US exchanges only (European listings need the paid
Grow plan); verified 2026-10-07 (ADR-004). History is fetched with `adjust=all` (dividends and splits) from
`dataFloor` = 2000-01-03. Budget: one-off backfill ≈ 60 credits, daily append 29, quotes refreshed by the
backend every 30 minutes during the US session (≈ 380); about half the daily limit. FX: Frankfurter (ECB
data, no key).

---

## 9. Content production

- Lesson text is written in `content/` (fr first, en second), reviewed by Bob. Content ships published as it
  is written and is corrected afterwards (decided 2026-10-24 by the user); `"status": "draft"` holds back a
  piece on purpose, and drafts never ship in a release pack.
- A release is the latest version of an island once `contentcheck -release` passes: no draft node or term
  (decided 2026-10-11). The server publishes only such versions; drafts stay in the app's bundle while the
  island is being built, and the graded build passes `-release` first.
- Datasets only via `cmd/freeze` (provenance, adjusted prices, frozen_at date), each with its recipe in the
  pack's `datasets.json`. The datasets, the app's bundle and the logos stay out of git (ADR-007):
  `scripts/fetch-data.sh` rebuilds them from a Twelve Data key. A lesson's copy quotes only what its
  datasets show; `app/test/data/content/actions_etf_copy_test.dart` (tag `real-data`) checks each figure
  against the real prices, on the developer's machine.
- `contentcheck` runs in CI on made-up prices (`scripts/fetch-data.sh --synthetic`), which
  `contentcheck -release` refuses. `app/assets/packs/<island>.json` is the assembled latest version
  (`contentcheck -bundle ../app/assets/packs -write` rewrites it).

---

## 10. Design system

### 10.1 Two component families

- **World / companion ("chunky")**: map, island path, node player, wizard, companion cards, missions,
  celebrations, the glossary (M11-2). White surfaces, 3 px ink border, offset shadow `0 4–6 px 0 ink`, radius 16–24, Baloo 2 titles.
- **Money ("flat")**: wallet, asset page, order sheet, explorer, settings, charts. White cards, 1 px line
  border, no offset shadow, radius 14–18. Numbers in Figtree with tabular figures.

Rule: chunky = the game is talking to you, or what you touch; flat = the figures of your money.
Controls are chunky on every screen (decided 2026-10-28, M11-1, the canvas « The world on every tab »): buttons
(`ChunkyButton`: primary, secondary, progress, and alert for the one action that loses something), segmented
controls (`ChunkySegmented`), chips, filters and shortcuts alike (`ChunkyChip`, 44 high, 2.5 px border, 3 px
shadow), search fields (`ChunkySearchField`), back and close (`ChunkyIconButton`; `ChunkyBackButton` on a
pushed screen's bar) and the tab bar (a 3 px ink top edge, the selected tab's pill outlined in ink). A selected
segment or chip keeps the neutral `line` fill (§10.2). The cards holding figures, the charts and the lessons'
curves stay as they are. Text links (`TextButton`), switches, sliders and form fields other than search keep
their Material look.
Shared by the money screens (decided 2026-10-24, M9-22, from the artboards `Portfolio-A` and `Asset-A`):
section titles in Baloo above their flat cards (`SectionTitle`), not inside them; a stock's avatar shows its
company's logo (M9-29, §10.2), an ETF's (or a stock's whose logo is missing) two letters from its name (`assetInitials`: the initials of two words, « ETF » left out, or a word's first two
letters: Apple « AP », Airbus « AI »); a chart dates its x-axis with a few labels in the unit its span calls
for (days, months, years; a label repeating its neighbour is left out: `dateAxis`), fills lightly under its
main line and marks where it ends with a dot.

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
by tinting the screen. One exception (decided 2026-10-13): the painted archipelago (§4.2) uses the art
direction's own colours (sand, grass, dirt, coloured buildings, grey stone), tokens of their own
(`MapPalette`), on the map and the island path's islets (§4.3) only; they draw a place and carry no meaning.
Since M11-3 (decided 2026-10-28) they, and `sea` under them, may also draw a small world scene inside a money
screen: a wallet's islet (§4.5); still a place, never a tint. A second
(decided 2026-10-24, M9-29): a stock's avatar shows its company's logo, in the company's colours, bundled
with the app (`go run ./cmd/logos`) and credited in « À propos »; it identifies the company and carries no
other meaning. ETFs keep their two letters (§10.1). Selected tabs, segments and chips use the neutral `line` container; app bars use
`page`, so a bar and the screen under it read as one background (decided 2026-10-23), and stay `page` when
content scrolls under them.

### 10.3 Typography

Baloo 2 (800) for display/titles; Figtree (400–700) for body and numbers (`FontFeature.tabularFigures()`).
French formatting: narrow no-break space before « : ? ! », thousands with narrow no-break space, decimal comma.

### 10.4 Spacing and targets

4-pt scale; screen padding 16; touch targets ≥ 44; bottom tab bar 80 high.

### 10.5 Animations

Hand-coded (count for the school requirement):
1. Map buildings grow/shrink with positions (`AnimationController` + `CustomPainter`).
2. Pending order: building under construction → completes on fill (staged controller). One 1,4 s controller,
   three intervals (`islandFrame`): heights 0–0.6, the built part rising into its ghost 0.3–0.9, a completed
   building's ghost fading 0.85–1. With animations turned off in the system, the island changes at once.
3. Predict-reveal: curves draw progressively (`Tween<double>` over `PathMetric`). Built (M6-3, M7-4): 1,6 s,
   ease in-out, a dot at each line's tip; the decision's curve draws the same way once a choice is made.
All three run at once, without motion, when the system's animations are off.
Value counters (M7-4, `CountUp`): under a reveal and a decision, each end value counts up from the amount it
started from, with its signed change, in step with the curve (same duration and curve), then shows the exact
figures; screen readers hear the end figures only.
Others: value counters (`TweenAnimationBuilder`), favorite star pop, sheet transitions, fl_chart transitions
(package-provided, counts as the third non-coded animation).


### 10.6 App icon and splash

Motu's icon is the developed island, drawn like the map (`MapPalette`, the map's 2:1 projection): sand and
grass tiles, cube trees, and a skyline that rises from the yellow building to the flagged blue tower, on the
`sea`. The user chose it on 2026-10-27, as "Motu · Tour" on the design canvas. The launch screen is the
island on the `sea`; from Android 12 the system draws it from the adaptive icon. Sources are in
`docs/brand/`: `motu.py` writes the SVGs, and `icons.sh` renders every Android and iOS file from them.

---

## 11. Localization

ARB files `app_fr.arb` (default) and `app_en.arb`. Keys by feature (`wallet_header_invested`). Plurals via
ICU. Content packs carry their own fr/en. Language switch in Settings applies immediately.

English pass (M9-2): « portefeuille » is « portfolio » throughout the English (UI and content), never
« wallet »; English typography (no space before % or :, no guillemets). `test/core/l10n/arb_test.dart` keeps
both files with the same keys and placeholders, English free of French typography, and English equal to the
French only for the names and symbols both share.

---

## 12. Testing strategy

- Domain: exhaustive unit tests (§7 edge cases), table-driven, fixed clocks and fixtures.
- Data: repository tests with fake remote + in-memory drift; cache policy tests (incremental fetch,
  TTL, offline fallback, no-lookahead clamp).
- Application: notifier tests with mocktail fakes (loading → data, error → retry, refresh keeps data).
- Widget: key flows (order validation, wizard validation, onboarding validation).
- Accessibility (M9-3): every screen's tests render it once with text at 130 % (an overflow fails the test)
  and check Flutter's guidelines with `expectAccessible` (`test/helpers.dart`): tap targets of at least
  44 × 44, a label on every tappable, readable text contrast. The loading skeleton reads « Chargement… ».
- Backend: handler tests with fake provider; store tests; `contentcheck` tests.

---

## 13. Delivery

Milestones and issue breakdown: `docs/ROADMAP.md`. Each architecture choice gets an ADR in
`docs/decisions/` (context, options, decision, consequences) — the school report is built from them, with the
material in `docs/report/` (architecture and data model diagrams, the cache strategy, the test list, the
screens; M9-5).

---

## 14. Open decisions (ask, do not guess)

1. ~~Live orders while offline~~: decided 2026-10-12, queued as pending until the next session's open (§6.4).
2. ~~Trip maximum length~~: decided 2026-10-24, none. A trip that reaches today can no longer be sped up:
   it goes on at the pace of real days, since prices ahead cannot be known (§4.5).
3. ~~Cash shared across future islands~~: decided 2026-10-24, no: islands teach different things. An idea
   for after V1 (the user's): a life simulation bringing everything together. A scenario, chosen or given,
   sets a salary and fixed expenses; the player decides how much to save, then what to invest it in
   (stocks, crypto, housing…).
4. ~~Explainable asset scoring~~: decided 2026-10-24, can be in V1; what it shows decided 2026-10-25:
   « Stabilité passée », out of 100, on the asset page only (§4.8).
5. ~~Final data provider and `dataFloor`~~: decided in ADR-004 (Twelve Data free plan, `dataFloor` 2000-01-03).
6. ~~Final catalogue list and symbols~~: decided in ADR-004 (US listings).
