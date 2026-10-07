# Investment Companion — agent guide

Read this file at the start of every session. Then read the issue you were given, then the sections of
`docs/BRIEF.md` it points to. `docs/BRIEF.md` is the product and architecture spec; `docs/ROADMAP.md` is the
milestone and issue breakdown. When they disagree with this file, this file wins; when the issue disagrees
with the brief, ask.

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
backend/    Go service + CLI tools (cmd/server, cmd/freeze, cmd/contentcheck)
content/    Lesson packs, glossary, frozen datasets — source of truth for all learning content
docs/       BRIEF.md, ROADMAP.md, decisions/ (ADRs, one file per decision)
```

## Commands

```bash
# app
cd app && flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze && flutter test

# backend
cd backend && go vet ./... && go test ./...
go run ./cmd/server                 # needs .env (see backend/.env.example)
go run ./cmd/contentcheck ../content  # validates every content pack against the schema
```

A change is not done until `flutter analyze`, `flutter test` and (when touched) `go vet` + `go test` pass.

## Architecture rules (non-negotiable)

1. **Layers in the app:** `presentation → application → domain ← data`. The domain layer is pure Dart: no
   Flutter imports, no I/O, no Riverpod, no `DateTime.now()`.
2. **No business logic in widgets.** Widgets render state and dispatch intents to notifiers.
3. **Time comes from `SimulationClock`.** Live wallet = `LiveClock`; trips = `HistoricalClock`. Every
   market-data read goes through a repository that takes `asOf`. **No lookahead:** no price, rate, chart
   point or asset dated after `clock.now()` may reach the domain or the UI.
4. **Money is never a `double`.** Use `Money` (integer minor units + currency), `Quantity` (fixed-point,
   6 decimals), `Price` (`Decimal`). Round only at the presentation edge.
5. **Currency conversion only through `FxService`**, always with a dated rate (latest rate on or before `asOf`).
6. **State:** Riverpod. Async state is `AsyncValue`; errors are typed (`sealed class Failure`), never raw strings.
7. **Persistence:** drift (SQLite). Any schema change ships with a migration and a migration test.
8. **Network** only in the data layer. The app calls our backend, plus Frankfurter directly for FX rates.
9. **UI copy** only through ARB localization files (`fr` default, `en`). No hardcoded strings in widgets.
10. **Colors and type only through theme tokens** (`docs/BRIEF.md` §10). Color must mean something.

## Guardrails

- **Do not make product decisions.** If the spec is silent or ambiguous, stop, list the options with their
  trade-offs in the issue or PR, and ask. Known open decisions: `docs/BRIEF.md` §14.
- One issue per branch and per PR. Small diffs. No drive-by refactors or renames outside the issue's scope.
- New dependency → justify it in the PR. Prefer the allowed list in `docs/BRIEF.md` §5.4.
- Every domain function ships with unit tests, including edge cases: empty history, single data point, zero
  or negative amount, missing price for a date, weekend/holiday dates, dates outside the data range, division
  by zero, currency mismatch.
- Never weaken, skip or delete a test to make CI pass. Fix the code or ask.
- Never commit secrets. Provider API keys exist only in the backend environment.
- No lorem ipsum or invented copy in the UI. Use the French copy given in the spec or the issue; if missing, ask.
- Accessibility: `Semantics` labels on icon-only controls, touch targets ≥ 44×44, gains and losses always
  carry a + or − sign (never color alone).
- Financial wording: describe what happened, never what will happen. No "you should buy", no forecasts.

## Definition of done

- Acceptance criteria in the issue are met.
- `flutter analyze` clean, all tests green (app and/or backend).
- New strings exist in both `app_fr.arb` and `app_en.arb`.
- UI changes: screenshot or short screen recording in the PR description.
- If behaviour or a contract changed: `docs/BRIEF.md` (or the relevant ADR) updated in the same PR.
