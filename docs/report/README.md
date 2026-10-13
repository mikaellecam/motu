# Report material

The school report (subject §14) is written from this folder and the documents it points to. Each item the
subject asks the report to present, and where its material is:

| The report presents (subject §14) | Material |
|---|---|
| The concept, the target user, the objectives | `docs/BRIEF.md` §1: the problem, who it is for, the two halves (islands and sandbox), V1's scope and non-goals |
| Features planned, and those built | `docs/ROADMAP.md` (the plan, by milestone); `docs/BRIEF.md` §4, where each feature carries a « Built (Mx-y) » note on what shipped; §2 maps every graded requirement to where it lives |
| Screenshots of the main screens | [screens.md](screens.md), from `docs/screenshots/` |
| The architecture, and a diagram of the main components and classes | [architecture.md](architecture.md): the two programs, the app's four layers, the backend, a read end to end, the answers to the subject's §12 questions |
| State management, and why | [ADR-001](../decisions/ADR-001-state-management.md); [architecture.md](architecture.md) (where the state is, how errors and loading reach the screen, what a rebuild does); `docs/BRIEF.md` §5.3 |
| Persistence, and the data model | [ADR-002](../decisions/ADR-002-persistence.md); the data model in [architecture.md](architecture.md); [ADR-003](../decisions/ADR-003-money-representation.md) for how money is stored; `docs/BRIEF.md` §6.1 |
| Cache, invalidation and refresh | [cache.md](cache.md); [ADR-005](../decisions/ADR-005-market-cache-policy.md) |
| The APIs and the data used | [ADR-004](../decisions/ADR-004-market-data-provider.md) (Twelve Data, the 29 instruments, adjusted prices); `docs/BRIEF.md` §8.3 (our backend's endpoints); Frankfurter for exchange rates; [ADR-006](../decisions/ADR-006-content-packs.md) (lessons and their frozen datasets) |
| The main processing and calculations | `docs/BRIEF.md` §7 (15 calculations, with their formulas and edge cases); [ADR-003](../decisions/ADR-003-money-representation.md) (exact money); [tests.md](tests.md) |
| The animations and how they are built | `docs/BRIEF.md` §10.5: three hand-coded (the map's buildings with a `CustomPainter` and an `AnimationController`, construction to completion in three staged intervals, the reveal's curves drawn along their `PathMetric`) and fl_chart's own transitions |
| Scoring and recommendations | The risk band 1–5 from a year's volatility, with its thresholds (`docs/BRIEF.md` §7.8); the starting lesson chosen from the questionnaire, with its reason on screen (§4.1); the next step on the map (§4.2). Explainable asset scoring is still an open decision (§14.4) |
| The tests | [tests.md](tests.md): every test, by layer, with the edge cases they name; `docs/BRIEF.md` §12 |
| Difficulties, limits, improvements | The limits in [cache.md](cache.md); the open decisions (`docs/BRIEF.md` §14); the offline run on a phone, which found three bugs (PR #63); every ADR's « Consequences » |

The decisions: [`docs/decisions/README.md`](../decisions/README.md) indexes the ADRs and the product
decisions recorded in the brief.

## Images for the report

The diagrams are written in Mermaid inside these pages, so GitHub draws them and they change with the
text. `diagrams/` holds them as PNG for a document editor:

| File | Diagram |
|---|---|
| `diagrams/system.png` | The app, the backend and the two data providers |
| `diagrams/layers.png` | The app's four layers and their main classes |
| `diagrams/backend.png` | The backend's commands and packages |
| `diagrams/data-model.png` | The persisted data model |
| `diagrams/read-sequence.png` | Opening an asset page, end to end |
| `diagrams/cache-levels.png` | The two cache levels |

To draw them again after a change, with the Mermaid CLI (`npm install @mermaid-js/mermaid-cli`), each
diagram copied to a `.mmd` file, at its natural size so the text stays sharp:

```sh
echo '{"er": {"useMaxWidth": false}, "flowchart": {"useMaxWidth": false}, "sequence": {"useMaxWidth": false}}' > mermaid.json
mmdc -c mermaid.json -i layers.mmd -o docs/report/diagrams/layers.png -b white -s 2
```

## Regenerating the test list

```sh
(cd app && flutter test --reporter json) > app.json
(cd backend && go test -json ./...) > go.json
python3 docs/report/test_list.py app.json go.json > docs/report/tests.md
```
