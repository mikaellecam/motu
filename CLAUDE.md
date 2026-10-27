# Motu — agent guide

Work happens one issue at a time: one branch and one pull request per issue, domain code test-first.
`docs/BRIEF.md` is the product and architecture spec; `docs/ROADMAP.md` is the original plan. When they
disagree with this file, this file wins; when the issue disagrees with the brief, ask.

## What we are building

A Flutter app that teaches beginners (French market first) to invest, backed by a small self-hosted Go
service. It has two halves that never block each other:

- **Islands (lessons).** A map of islands, one per domain. Each island is a path of short interactive
  exercises built on *frozen* real historical data. V1 ships one playable island: **Actions & ETF**.
- **Sandbox.** A Trading 212-style fictional portfolio: one wallet on today's prices, plus "time-trip"
  wallets that start at a past date and move forward through real history. Plus a DCA simulator.

No real money, no broker or bank connection, ever. Nothing in the app is investment advice or a prediction.

It is a graded school project (INSA, mobile development module). The mandatory requirements are listed in
`docs/BRIEF.md` §2 — do not drop any of them.

## Repository layout

```
app/        Flutter app (Dart)
backend/    Go service + CLI tools (cmd/server, cmd/freeze, cmd/contentcheck, cmd/logos)
content/    Lesson packs, glossary, dataset recipes — source of truth for all learning content
scripts/    fetch-data.sh: rebuilds what git leaves out (datasets, app bundle, logos; ADR-007)
docs/       BRIEF.md, ROADMAP.md, decisions/ (ADRs, one file per decision)
```

## Commands

```bash
# app
cd app && flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format . && flutter analyze && flutter test   # needs real data (scripts/fetch-data.sh)
flutter test --exclude-tags real-data              # what CI runs, on made-up prices
flutter test screenshots --update-goldens   # renders screens to docs/screenshots/
# after a drift schema change (bump schemaVersion, add the step first):
dart run drift_dev make-migrations
dart run drift_dev schema generate --data-classes --companions drift_schemas/app_database/ test/drift/app_database/generated/

# backend
cd backend && gofmt -w . && go vet ./... && go test ./...
set -a; . ./.env; set +a; go run ./cmd/server   # .env from .env.example; syncs market data
go test -tags live ./internal/provider/            # adapter against the real API (needs .env)
go test -tags realdata ./cmd/logos/                # every stock has its logo (after scripts/fetch-data.sh)
../scripts/fetch-data.sh        # after a clone: datasets, app bundle, logos from .env (~17 credits once)
../scripts/fetch-data.sh --synthetic   # made-up prices, no key (CI; never a release)
go run ./cmd/contentcheck -bundle ../app/assets/packs ../content  # checks every pack + the app's bundle
go run ./cmd/contentcheck -bundle ../app/assets/packs -write ../content   # after a content change
go run ./cmd/contentcheck -release ../content      # no draft, no made-up data in the latest versions
set -a; . ./.env; set +a; go run ./cmd/freeze -pack ../content/packs/actions-etf/1 -id ds.aapl-2022-w \
  -asset apple -interval 1week -from 2022-01-01 -to 2022-12-31   # a new dataset + its recipe (1 credit)
set -a; . ./.env; set +a; go run ./cmd/freeze -recipes ../content   # every dataset a recipe lists and git lacks
set -a; . ./.env; set +a; go run ./cmd/logos   # stock logos into ../app/assets/logos (paced, resumes)
docker build -t motu-backend .        # the image; self-hosting steps in docs/deploy.md
```

## Architecture rules (non-negotiable)

1. **Layers in the app:** `presentation → application → domain ← data`. The domain layer is pure Dart: no
   Flutter imports, no I/O, no Riverpod, no `DateTime.now()`.
2. **No business logic in widgets.** Widgets render state and dispatch intents to notifiers.
3. **Time comes from `SimulationClock`.** Live wallet = `LiveClock`; trips = `HistoricalClock`. Every
   market-data read goes through a repository that takes `asOf`. **No lookahead:** no price, rate, chart
   point or asset dated after `clock.now()` may reach the domain or the UI.
4. **Money is never a `double`.** Use `Money` (integer minor units + currency), `Quantity` (fixed-point,
   6 decimals), `Price` (`Decimal`). Round half-even only when booking an amount as `Money` or when
   displaying it (ADR-003).
5. **Currency conversion only through `FxService`**, always with a dated rate (latest rate on or before `asOf`).
6. **State:** Riverpod. Async state is `AsyncValue`; errors are typed (`sealed class Failure`), never raw strings.
7. **Persistence:** drift (SQLite). Any schema change ships with a migration and a migration test.
8. **Network** only in the data layer. The app calls our backend, plus Frankfurter directly for FX rates.
9. **UI copy** only through ARB localization files (`fr` default, `en`). No hardcoded strings in widgets.
10. **Colors and type only through theme tokens** (`docs/BRIEF.md` §10). Color must mean something.

## Guardrails

- **Do not make product decisions.** If the spec is silent or ambiguous, ask. Known open
  decisions: `docs/BRIEF.md` §14.
- One issue per branch and per PR. Small diffs. No drive-by refactors or renames outside the issue's scope.
- New dependency → justify it in the PR. Prefer the allowed list in `docs/BRIEF.md` §5.4.
- Every domain function ships with unit tests, including edge cases: empty history, single data point, zero
  or negative amount, missing price for a date, weekend/holiday dates, dates outside the data range, division
  by zero, currency mismatch.
- Never weaken, skip or delete a test to make CI pass. Fix the code or ask.
- Never commit secrets. Provider API keys exist only in the backend environment.
- Commits and PRs carry no AI or tool attribution: no Co-Authored-By trailer, no "generated with" line.
- No lorem ipsum in the UI. Use the copy given in the spec or the issue; when it is missing, draft it (fr + en)
  in the spec's voice and list every new string in the PR for review: no approval round needed.
- Accessibility: `Semantics` labels on icon-only controls, touch targets ≥ 44×44, gains and losses always
  carry a + or − sign (never color alone).
- Financial wording: describe what happened, never what will happen. No "you should buy", no forecasts.

## Definition of done

- Every acceptance-criterion box in the issue is ticked.
- `flutter analyze` clean and `flutter test` green; `go vet` + `go test` green when `backend/` changed.
- New strings exist in both `app_fr.arb` and `app_en.arb`.
- UI changes: screenshots committed under `docs/screenshots/` (they feed the report) and shown in the PR.
- If behaviour or a contract changed: `docs/BRIEF.md` (or the relevant ADR) updated on the same branch.
