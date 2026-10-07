# Investment Companion — agent guide

Work happens one issue at a time, following **Workflow** below. `docs/BRIEF.md` is the product and
architecture spec; `docs/ROADMAP.md` is the original plan the tracker was seeded from. When they disagree
with this file, this file wins; when the issue disagrees with the brief, ask.

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
tracker/    Local issue tracker, gitignored (see Workflow)
```

## Commands

```bash
# app
cd app && flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format . && flutter analyze && flutter test

# backend
cd backend && gofmt -w . && go vet ./... && go test ./...
go run ./cmd/server                 # needs .env (see backend/.env.example)
go run ./cmd/contentcheck ../content  # validates every content pack against the schema

# tracker
tracker/board        # every issue in roadmap order, then the next one to work on
tracker/board next   # only the next issue id
```

## Workflow

`tracker/` holds one Markdown file per issue. It is gitignored, so Grep and Glob skip it: open issue files by
path and list them with `tracker/board`. It exists only in the main checkout, as does `backend/.env`; from a
worktree, reach them through `../../` (symlink `.env` into the worktree when the backend needs it).
Frontmatter: `status` (todo | doing | blocked | done), `priority` (`must` = covers a graded requirement of
`docs/BRIEF.md` §2, `normal` otherwise), `depends` (issue ids), `spec` (BRIEF sections).

1. **Pick.** Take the issue the user names, or `tracker/board next`. Set `status: doing`, then work in a
   worktree branched from an up-to-date `main` (lowercase id + slug):
   `git pull && git worktree add .worktrees/m1-2-simulation-clock -b m1-2-simulation-clock`.
2. **Read.** The issue, every BRIEF section in `spec`, and the code the change touches. Done when you can name
   every file you will change.
3. **Build.** Domain code test-first. Tick an acceptance-criterion box when its test passes. Work outside the
   issue's scope becomes a new issue file (next free number in the milestone), not part of this branch.
4. **Blocked.** On a product question, or something only the user can provide (API key, account), write it
   under `## Questions` with the options and their trade-offs, set `status: blocked`, tell the user, and
   move to `tracker/board next`.
5. **Finish.** Definition of done met. Commit, push the branch, and open a PR to `main` with `gh pr create`:
   title `M1-2: <issue title>`, body = what changed, the acceptance criteria, screenshots for UI changes.
   Watch CI with `gh pr checks --watch` and fix until green, then `gh pr merge --squash --delete-branch` and
   `git worktree remove`. Set `status: done` and add a dated line under `## Log`: PR link, decisions taken,
   anything deferred.

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

- **Do not make product decisions.** If the spec is silent or ambiguous, ask (Workflow step 4). Known open
  decisions: `docs/BRIEF.md` §14.
- One issue per branch and per PR. Small diffs. No drive-by refactors or renames outside the issue's scope.
- New dependency → justify it in the issue log. Prefer the allowed list in `docs/BRIEF.md` §5.4.
- Every domain function ships with unit tests, including edge cases: empty history, single data point, zero
  or negative amount, missing price for a date, weekend/holiday dates, dates outside the data range, division
  by zero, currency mismatch.
- Never weaken, skip or delete a test to make CI pass. Fix the code or ask.
- Never commit secrets. Provider API keys exist only in the backend environment.
- Commits and PRs carry no AI or tool attribution: no Co-Authored-By trailer, no "generated with" line.
- No lorem ipsum or invented copy in the UI. Use the French copy given in the spec or the issue; if missing, ask.
- Accessibility: `Semantics` labels on icon-only controls, touch targets ≥ 44×44, gains and losses always
  carry a + or − sign (never color alone).
- Financial wording: describe what happened, never what will happen. No "you should buy", no forecasts.

## Definition of done

- Every acceptance-criterion box in the issue is ticked.
- `flutter analyze` clean and `flutter test` green; `go vet` + `go test` green when `backend/` changed.
- New strings exist in both `app_fr.arb` and `app_en.arb`.
- UI changes: screenshots committed under `docs/screenshots/` (they feed the report) and shown in the PR.
- If behaviour or a contract changed: `docs/BRIEF.md` (or the relevant ADR) updated on the same branch.
