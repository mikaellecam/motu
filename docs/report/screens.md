# Screens

Every image in `docs/screenshots/` is rendered from the app's real widgets on fixed data by a test in
`app/screenshots/` (`flutter test screenshots --update-goldens`), at a phone's size (390 points wide), in
French unless marked. Below, the main screens by part of the app, each with what it shows of the subject's
requirements (§11).

## First launch

| | |
|---|---|
| <img src="../screenshots/m6-7-onboarding-question.png" width="240"> | <img src="../screenshots/m6-7-onboarding-result.png" width="240"> |
| Questionnaire, one question of five: a **form** whose answers choose where the path starts | Where the path starts, and why |

## The map and the lessons

| | | |
|---|---|---|
| <img src="../screenshots/m13-9-lesson-card.png" width="240"> | <img src="../screenshots/m7-1-map.png" width="240"> | <img src="../screenshots/m6-9-island-path.png" width="240"> |
| The « Archipel » tab: the island the user was on, up close, painted in code (`CustomPainter`); a marker touched shows its lesson | A first launch: the port, where the way starts, its old jetty | An island up close: a marker per lesson on its building, which grows when the lesson is done (**coded animation**); pan and pinch |
| <img src="../screenshots/m6-3-predict-reveal.png" width="240"> | <img src="../screenshots/m7-4-reveal-drawing.png" width="240"> | <img src="../screenshots/m6-8-livret-vs-etf.png" width="240"> |
| Predict, then reveal: Apple or the world ETF in 2022, on real data | The reveal's curves drawing themselves (**coded animation**) | « Livret or ETF? »: 10 000 € on each since 2015, real prices (**chart**) |
| <img src="../screenshots/m6-3-toy.png" width="240"> | <img src="../screenshots/m6-8-compound-toy.png" width="240"> | <img src="../screenshots/m6-8-dollar-trap.png" width="240"> |
| The fees toy: sliders, the gap after 30 years (**calculation**: compound growth net of fees) | Compound interest | The dollar trap: a US stock's return in dollars and in euros |
| <img src="../screenshots/m6-4-decision.png" width="240"> | <img src="../screenshots/m6-4-sort.png" width="240"> | <img src="../screenshots/m6-4-build-puzzle.png" width="240"> |
| « Mars 2020 : vendre ou tenir ? »: a decision on a past crisis | Rank by risk | Build a calm portfolio: under 8 % volatility (**calculation**) |
| <img src="../screenshots/m6-4-checkpoint.png" width="240"> | <img src="../screenshots/m6-5-mission.png" width="240"> | <img src="../screenshots/m13-5-sea-chart.png" width="240"> |
| A checkpoint | A mission, completed by doing it in the sandbox | The sea chart, drawn in code: sail between the port and the islands |
| <img src="../screenshots/m13-13-card-example.png" width="240"> | <img src="../screenshots/m13-13-card-compare.png" width="240"> | <img src="../screenshots/m13-13-card-check.png" width="240"> |
| After its interaction, a lesson goes on in cards: a worked example (**calculation**: the cushion's months) | Two ways compared on one **chart** | A quick check, right or wrong, with its why; the header shows the lesson's cards |

## The lessons' islands

Islands drawn in code (`CustomPainter`), at a tablet's size; each lesson done grows its building or its part.

|  |  |  |
|---|---|---|
| <img src="../screenshots/m13-2-district-0.png" width="240"> | <img src="../screenshots/m13-2-district-6.png" width="240"> | <img src="../screenshots/m13-2-district-12.png" width="240"> |
| Actions & ETF, a business district, before any lesson | Six lessons done: six buildings grown | All twelve: the spire wears its gold crown |
| <img src="../screenshots/m13-3-port-0.png" width="240"> | <img src="../screenshots/m13-3-port-5.png" width="240"> | <img src="../screenshots/m13-3-port-9.png" width="240"> |
| Les bases, the mainland's port: the old jetty and the village | Five lessons: the ferry quay, and the line to Actions & ETF | All nine: the lighthouse lit |
| <img src="../screenshots/m13-17-district-rising.png" width="240"> | <img src="../screenshots/m13-17-port-rising.png" width="240"> | <img src="../screenshots/m12-6-bases-path.png" width="240"> |
| A lesson done: its building rising into its ghost (**coded animation**) | The same at the port | Les bases up close, before its first lesson |

## Les bases' lessons

|  |  |  |
|---|---|---|
| <img src="../screenshots/m12-3-cushion-toy.png" width="240"> | <img src="../screenshots/m12-3-loan-toy.png" width="240"> | <img src="../screenshots/m12-5-cash-inflation.png" width="240"> |
| The safety cushion: months of spending, filled month by month (**calculation**) | A loan's real cost: equal payments, interest to the cent (**calculation**) | 10 000 € in notes, and what they buy at INSEE's prices |
| <img src="../screenshots/m12-5-livret-inflation.png" width="240"> | <img src="../screenshots/m12-5-cushion-2020.png" width="240"> | <img src="../screenshots/m12-5-spot-the-scam.png" width="240"> |
| The Livret A against inflation, 2021–2024 | « Février 2020 : et ton matelas ? », a decision | A quiz: spot the scam |
| <img src="../screenshots/m13-14-cash-inflation-example.png" width="240"> | <img src="../screenshots/m13-14-loan-cost-compare.png" width="240"> | <img src="../screenshots/m12-7-onboarding-result-bases.png" width="240"> |
| A worked example card | A comparison card: 12 or 48 months | Where the path starts, on Les bases |

## The portfolio

| | | |
|---|---|---|
| <img src="../screenshots/m4-7-wallets.png" width="240"> | <img src="../screenshots/m4-2-wallet.png" width="240"> | <img src="../screenshots/m4-2-wallet-benchmark.png" width="240"> |
| The wallets: live, the trips, the DCA simulator | The live wallet: its island, whose buildings follow its positions (**coded animation**), value, gain since the start, **chart**, allocation, positions (**calculations**: valuation, P&L, weights) | Compared with the world ETF over 3 months (time-weighted return) |
| <img src="../screenshots/m4-6-wallet-pending.png" width="240"> | <img src="../screenshots/m8-1-livret.png" width="240"> | <img src="../screenshots/m8-3-wallet-companion.png" width="240"> |
| An order waiting for the market to open: its building under construction (**coded animation**) | The Livret A beside the investments (**calculation**: fortnightly interest) | A companion moment in the wallet |

## Explore and the asset page

| | | |
|---|---|---|
| <img src="../screenshots/m4-3-explorer.png" width="240"> | <img src="../screenshots/m4-3-explorer-search.png" width="240"> | <img src="../screenshots/m4-4-asset.png" width="240"> |
| The catalogue: a **dynamic list** with filters and favourites | Search | An asset: price, **chart**, worst drop, volatility, why it moved (**calculations**: drawdown, volatility, move decomposition) |
| <img src="../screenshots/m4-4-asset-5y-benchmark.png" width="240"> | | |
| Five years, against the world ETF | | |

## Orders

| | | |
|---|---|---|
| <img src="../screenshots/m4-5-order-sheet.png" width="240"> | <img src="../screenshots/m4-5-order-coach.png" width="240"> | <img src="../screenshots/m4-6-order-pending.png" width="240"> |
| The order sheet: a **form with validation**, fees and total before sending | Every error in words; the coach when one line would weigh too much | An order's steps: sent, market opens, filled |

## Time trips

| | | |
|---|---|---|
| <img src="../screenshots/m5-1-trip-wizard-dates.png" width="240"> | <img src="../screenshots/m5-2-trip-wizard-difficulty.png" width="240"> | <img src="../screenshots/m5-2-trip-wizard-recap.png" width="240"> |
| A new trip: when (historic moments or an exact date: a **form with validation**) | How hard | The summary and the automatic stops |
| <img src="../screenshots/m5-3-trip-wallet.png" width="240"> | <img src="../screenshots/m5-4-stop.png" width="240"> | <img src="../screenshots/m5-5-trip-summary.png" width="240"> |
| A trip in 2020, moving forward by a day, a week, a month | An automatic stop: what happened and three choices | The end of a trip, against doing nothing |

## DCA simulator, glossary, settings

| | | |
|---|---|---|
| <img src="../screenshots/m8-2-dca-form.png" width="240"> | <img src="../screenshots/m8-2-dca-result.png" width="240"> | <img src="../screenshots/m6-6-glossary.png" width="240"> |
| The DCA form (**form with validation**) | The result against a lump sum and a Livret A (**calculation**: DCA; **chart**), saved | The glossary: a searchable **dynamic list** |
| <img src="../screenshots/m6-6-term-sheet.png" width="240"> | <img src="../screenshots/m9-1-settings.png" width="240"> | |
| A term, with a live example on real data | Settings: language, level, data and cache, simulation | |

## More states

|  |  |  |
|---|---|---|
| <img src="../screenshots/m9-36-asset-score.png" width="240"> | <img src="../screenshots/m9-17-order-error.png" width="240"> | <img src="../screenshots/m9-34-order-done-pending.png" width="240"> |
| « Stabilité passée »: a score out of 100, its four parts shown | An order refused: the error in words | An order placed: its building under construction |
| <img src="../screenshots/m9-34-order-done-filled.png" width="240"> | <img src="../screenshots/m9-34-order-done-mission.png" width="240"> | <img src="../screenshots/m9-41-plan-sheet.png" width="240"> |
| Filled | Filled, and a mission completed | « Investir chaque mois »: a DCA plan |
| <img src="../screenshots/m9-41-wallet-plans.png" width="240"> | <img src="../screenshots/m9-33-forward-sheet.png" width="240"> | <img src="../screenshots/m9-35-trip-at-today.png" width="240"> |
| The wallet's plans | A trip: « Avancer jusqu'à… » with its stops | A trip that reached today goes on day by day |
| <img src="../screenshots/m9-32-trip-wallet-stopped.png" width="240"> | <img src="../screenshots/m9-32-trip-wallet-finished.png" width="240"> | <img src="../screenshots/m9-24-trip-wizard-tight.png" width="240"> |
| A trip stopped, waiting for a decision | A trip finished | « Serré »: fixed fees and whole shares |
| <img src="../screenshots/m9-26-dca-result-fold.png" width="240"> | <img src="../screenshots/m9-28-term-sheet-drawdown.png" width="240"> | <img src="../screenshots/m13-16-glossary-search.png" width="240"> |
| The DCA result, its comparisons | A term's live example: the worst drop marked | The glossary's search, unfolded |
| <img src="../screenshots/m13-15-march-2020-example.png" width="240"> | <img src="../screenshots/m13-15-risk-ladder-compare.png" width="240"> | <img src="../screenshots/m11-4-wallet-empty.png" width="240"> |
| Actions & ETF's cards: an example | A comparison on one chart | A new live wallet |
| <img src="../screenshots/m13-21-sea-chart-en.png" width="240"> | <img src="../screenshots/m10-4-launcher.png" width="240"> | <img src="../screenshots/m10-4-splash.png" width="240"> |
| The sea chart, in English | Motu's icon | Its launch screen |

## Offline, accessibility, English

| | | |
|---|---|---|
| <img src="../screenshots/m9-5-wallet-offline.png" width="240"> | <img src="../screenshots/m9-4-order-offline.png" width="240"> | <img src="../screenshots/m9-3-asset-130.png" width="240"> |
| Relaunched offline: the last prices, dated (**partial offline mode**) | An order placed offline waits for the next open | Text at 130 %: every screen reflows |
| <img src="../screenshots/m9-2-map-en.png" width="240"> | <img src="../screenshots/m9-2-wallet-en.png" width="240"> | <img src="../screenshots/m9-2-lesson-en.png" width="240"> |
| In English | | |

Not shown above: `m0-2-gallery` (the design system's components), `m4-1-shell-explore`, `m4-1-shell-map`, `m4-6-order-filled`, `m5-1-trip-wizard-floor`, `m8-1-livret-sheet`, `m13-3-port-3`, `m13-3-port-6` (more states of screens shown).
