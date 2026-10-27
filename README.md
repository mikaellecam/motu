<p align="center"><img src="docs/brand/motu-icon.svg" alt="Motu's icon: an island with a growing skyline" width="120"></p>

# Motu

Motu teaches beginners to invest, with fictional money on real market history. It is a Flutter app with a
small self-hosted Go backend, and its first audience is French (the app is in French, with English as the
second language).

> Motu is a teaching tool. Nothing in it is investment advice or a prediction, and no real money, broker or
> bank is involved, ever.

It has two halves:

- **Islands.** A map of islands, one per domain, each a path of short interactive lessons built on real
  prices, frozen so that everyone sees the same story. The first island, *Actions & ETF*, is playable:
  Apple against a world ETF in 2022, March 2020, the dollar trap, the Livret A against an ETF, and more.
- **Sandbox.** A fictional portfolio on today's prices, and "time trips": a wallet that starts on a past
  date and moves forward through real history, with automatic stops. Plus a DCA simulator.

<p align="center">
  <img src="docs/screenshots/m7-1-map.png" alt="The map of islands" width="180">
  <img src="docs/screenshots/m6-9-island-path.png" alt="The Actions & ETF island's path of lessons" width="180">
  <img src="docs/screenshots/m6-3-predict-reveal.png" alt="A lesson revealing what happened" width="180">
  <img src="docs/screenshots/m4-2-wallet.png" alt="The live wallet" width="180">
  <img src="docs/screenshots/m5-3-trip-wallet.png" alt="A time-trip wallet" width="180">
</p>

## How it is built

- **App** (`app/`, Flutter): layers `presentation → application → domain ← data`, Riverpod for state, drift
  (SQLite) for persistence and the market-data cache. Money is integer cents, never a `double`, and every
  read is cut at the simulation's clock, so a time trip never sees a price from its future.
- **Backend** (`backend/`, Go): syncs daily prices from Twelve Data into SQLite, serves them and the lesson
  packs over a small REST API, and spends the provider's free-plan credits carefully.
- **Content** (`content/`): lessons, glossary and the recipes of their frozen datasets, checked by
  `cmd/contentcheck`.

The spec is [`docs/BRIEF.md`](docs/BRIEF.md), the architecture decisions are in
[`docs/decisions/`](docs/decisions/), and [`docs/report/architecture.md`](docs/report/architecture.md) walks
through the whole design.

## Getting started

You need Flutter 3.47.6, Go 1.27, and a free [Twelve Data](https://twelvedata.com) API key (Basic plan).

```bash
cp backend/.env.example backend/.env    # then set TWELVEDATA_API_KEY
scripts/fetch-data.sh                   # the lessons' datasets, the app's bundle and the stock logos
```

The provider's data stays out of this repository (its terms forbid redistributing it: ADR-007), so
`fetch-data.sh` rebuilds it from your key: about 15 credits and a few minutes, once. Without a key,
`scripts/fetch-data.sh --synthetic` writes made-up prices of the same shape, enough to build and look around.

Run the backend (its first start backfills price history, which takes several minutes):

```bash
cd backend && set -a && . ./.env && set +a && go run ./cmd/server
```

Run the app, which calls `http://localhost:8080` by default:

```bash
cd app && flutter pub get && dart run build_runner build --delete-conflicting-outputs
adb reverse tcp:8080 tcp:8080           # an Android device or emulator reaches the backend on your machine
flutter run                             # or --dart-define=BACKEND_URL=https://your.server
```

Tests: `flutter test` and `go test ./...` in their folders. `flutter test --exclude-tags real-data` is what
CI runs on made-up prices. To host the backend yourself, see [`docs/deploy.md`](docs/deploy.md).

## Data and credits

- Prices and company logos: [Twelve Data](https://twelvedata.com). Each logo is the property of its company.
- Exchange rates: the European Central Bank's reference rates, via [Frankfurter](https://frankfurter.dev).
- Livret A: the official rate history.
- Fonts: Baloo 2 and Figtree, under the SIL Open Font License (`app/assets/fonts/`).

## About

Motu started as a graded project for the mobile development module at INSA. The code is under the
[MIT licence](LICENSE).
