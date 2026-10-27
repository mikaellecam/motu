# ADR-007: Provider data stays out of git; recipes rebuild it

Status: accepted
Date: 2026-10-27

## Context

The repository goes public. Twelve Data's terms let a customer store their data for internal use only. They
forbid redistributing it or displaying it to third parties without a redistribution agreement
(§2.2(e), §2.3(b)). A public repository that holds their prices redistributes them. Git held them three
times:

- the frozen datasets of the lessons, `content/packs/<island>/<version>/datasets/*.json` (14 of the 16
  Actions & ETF datasets have `"source": "twelvedata"`)
- the app's bundled pack, `app/assets/packs/<island>.json`, which contains those datasets
- the stock logos, `app/assets/logos/*.jpg`, fetched from the provider's `/logo` endpoint
- the price history the asset screenshots render, `app/screenshots/fixtures/apple.json` (found later,
  M10-8), and before it `fixtures/actions-etf.json`, which only history still holds

Lessons must keep working as they do: frozen data (BRIEF §4.3, §9), every learner seeing the same figures,
and offline from the first launch (ADR-006). CI must stay green on pull requests from forks, which get no
secrets, so it cannot reach the provider.

## Options considered

### Ask Twelve Data for written permission

If they grant it, nothing changes. But it depends on an answer we may never get, and it covers only this
provider.

### Commit a derived form of the data

The terms allow derived data that cannot be reverse-engineered into the original (§2.2(c)). But lessons
quote real moves (−24 % for Apple in 2022), and any series that still shows them can be scaled back to the
prices.

### Keep the recipe in git and rebuild the data

Each dataset is already fully described by the `cmd/freeze` flags that produced it. Git keeps those, and
whoever builds the app rebuilds the data with their own key: about 15 credits, once. Re-freezing reproduced
every committed dataset exactly (2026-10-27). CI cannot rebuild real data, so it runs on made-up prices
shaped like the real ones.

## Decision

Keep the recipes in git and rebuild the data.

- **Recipes:** each pack version has a `datasets.json`, one recipe per dataset: the `cmd/freeze` flags
  (`asset` with optional `currency`, `fx`, or `livret` with `deposit`; `interval`, `from`, `to`). A
  single-dataset freeze records its recipe there. `content.Read` reports a recipe without its dataset and
  a dataset without its recipe.
- **Out of git:** every `datasets/` folder, `app/assets/packs/*.json` and `app/assets/logos/*`. The
  screenshot fixture is a pack-shaped folder too, `app/screenshots/fixtures/packs/screens/1/`, with its
  recipes in `datasets.json`. The ECB and
  Livret A datasets are rebuilt as well, so the rule is the same for every dataset.
- **Rebuilding:** `scripts/fetch-data.sh` runs `freeze -recipes` (each missing dataset, paced to 8 provider
  calls a minute), `contentcheck -bundle -write`, then `cmd/logos`. A real run replaces made-up datasets.
  `freeze` and `logos` also wait out a call the provider refuses for its rate, three tries in all: they share
  the plan's credits with each other and with a running server (M10-9).
- **CI:** `scripts/fetch-data.sh --synthetic` writes a deterministic walk per recipe, with the same id,
  shape, interval and range, `"source": "synthetic"` and no network. Made-up data never replaces real
  data. `contentcheck -release`, and so the server, refuses it: a release ships real data.
- **Tests:** the tests that check what a lesson says against the real prices live in
  `app/test/data/content/actions_etf_copy_test.dart`, tagged `real-data`. CI runs
  `flutter test --exclude-tags real-data`; locally, `flutter test` runs them on the real data. Likewise
  in Go, the check that every catalogue stock has its fetched logo has the build tag `realdata`
  (`go test -tags realdata ./cmd/logos/`).

## Consequences

- A fresh clone needs one step before the app builds: `scripts/fetch-data.sh` with a free Twelve Data key,
  or `--synthetic` to look around without one. Building the app without it fails on the missing
  `assets/packs/` folder.
- A self-hosted server rebuilds its datasets the same way. The published image (M10-11) carries the lessons
  and recipes but no dataset; at each start it freezes the missing datasets into its data volume and prunes
  those no recipe lists (`backend/start.sh`, `docs/deploy.md`).
- CI no longer compares the bundle with the source, because there is no committed bundle. It still checks
  every pack, on made-up data. The check of the copy against the real prices now runs on the developer's
  machine, before a release, not on every push.
- The history still holds the data until it is rewritten before going public (M10-7).
