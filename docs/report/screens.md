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
| <img src="../screenshots/m7-3-next-step.png" width="240"> | <img src="../screenshots/m7-1-map.png" width="240"> | <img src="../screenshots/m6-9-island-path.png" width="240"> |
| The archipelago, painted in code (`CustomPainter`); the Actions & ETF island's buildings follow the live wallet (**coded animation**) and the next-step card names what to do | A first launch: no position yet, the island bare | An island's path: a **dynamic list** of lessons with their state |
| <img src="../screenshots/m6-3-predict-reveal.png" width="240"> | <img src="../screenshots/m7-4-reveal-drawing.png" width="240"> | <img src="../screenshots/m6-8-livret-vs-etf.png" width="240"> |
| Predict, then reveal: Apple or the world ETF in 2022, on real data | The reveal's curves drawing themselves (**coded animation**) | « Livret or ETF? »: 10 000 € on each since 2015, real prices (**chart**) |
| <img src="../screenshots/m6-3-toy.png" width="240"> | <img src="../screenshots/m6-8-compound-toy.png" width="240"> | <img src="../screenshots/m6-8-dollar-trap.png" width="240"> |
| The fees toy: sliders, the gap after 30 years (**calculation**: compound growth net of fees) | Compound interest | The dollar trap: a US stock's return in dollars and in euros |
| <img src="../screenshots/m6-4-decision.png" width="240"> | <img src="../screenshots/m6-4-sort.png" width="240"> | <img src="../screenshots/m6-4-build-puzzle.png" width="240"> |
| « Mars 2020 : vendre ou tenir ? »: a decision on a past crisis | Rank by risk | Build a calm portfolio: under 8 % volatility (**calculation**) |
| <img src="../screenshots/m6-4-checkpoint.png" width="240"> | <img src="../screenshots/m6-5-mission.png" width="240"> | <img src="../screenshots/m8-3-map-moment.png" width="240"> |
| A checkpoint | A mission, completed by doing it in the sandbox | The companion: a moment drawn from the user's own wallet |

## The portfolio

| | | |
|---|---|---|
| <img src="../screenshots/m4-7-wallets.png" width="240"> | <img src="../screenshots/m4-2-wallet.png" width="240"> | <img src="../screenshots/m4-2-wallet-benchmark.png" width="240"> |
| The wallets: live, the trips, the DCA simulator | The live wallet: value, gain since the start, **chart**, allocation, positions (**calculations**: valuation, P&L, weights) | Compared with the world ETF over 3 months (time-weighted return) |
| <img src="../screenshots/m4-6-wallet-pending.png" width="240"> | <img src="../screenshots/m8-1-livret.png" width="240"> | <img src="../screenshots/m8-3-wallet-companion.png" width="240"> |
| An order waiting for the market to open | The Livret A beside the investments (**calculation**: fortnightly interest) | A companion moment in the wallet |

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

## Offline, accessibility, English

| | | |
|---|---|---|
| <img src="../screenshots/m9-5-wallet-offline.png" width="240"> | <img src="../screenshots/m9-4-order-offline.png" width="240"> | <img src="../screenshots/m9-3-asset-130.png" width="240"> |
| Relaunched offline: the last prices, dated (**partial offline mode**) | An order placed offline waits for the next open | Text at 130 %: every screen reflows |
| <img src="../screenshots/m9-2-map-en.png" width="240"> | <img src="../screenshots/m9-2-wallet-en.png" width="240"> | <img src="../screenshots/m9-2-lesson-en.png" width="240"> |
| In English | | |

Not shown above: `m0-2-gallery`, `m4-1-shell-explore`, `m4-1-shell-map`, `m4-6-order-filled`, `m5-1-trip-wizard-floor`, `m7-2-living-island`, `m8-1-livret-sheet`, `m8-3-moment-sheet` (more states of these screens; `m0-2-gallery` is the design system's components).
