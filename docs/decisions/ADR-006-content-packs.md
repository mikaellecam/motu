# ADR-006: Content packs: one document per version, bundled and fetched

Status: accepted
Date: 2026-10-10

## Context

Lessons, datasets and glossary terms live in `content/` (BRIEF §4.3, §9) and reach the app as content
packs. The constraints:

- **First launch offline** (§6.4): the app must have its islands with no network.
- **Content changes without an app release**: a fixed typo or a new node should reach installed apps.
- **One table**: the local schema keeps a pack as one row, `content_packs (islandId, version, json, etag,
  checkedAt)` (ADR-002).
- **Trust nothing downloaded**: a pack cut short, or written by a buggy tool, must not break the islands.

## Options considered

### Ship files, or one document

The source tree splits a pack into files (`island.json`, `nodes/*.json`, `datasets/*.json`). Shipping them
as they are would mean many requests and many rows. One document per pack version,
`{island, nodes, datasets, glossary}`, is one request, one row, and one parse that either fully succeeds or
fails.

### Revalidate with an ETag, or with the version

A published version never changes, so its number already says everything an ETag would. The app asks a
small manifest (`islandId → latest version`) and downloads only a higher version. ETags stay useful for the
manifest itself, but at one request a day, plain requests are simpler.

### Where the glossary lives

V1 has one island, and its terms ship with it. A separate glossary pack would only pay off once several
islands share terms; moving terms out then is a format change of the tool, not of the app's model.

## Decision

- **Source:** `content/packs/<islandId>/<version>/` with `island.json`, `nodes/<id>.json`,
  `datasets/<id>.json` (written by `cmd/freeze` only), and `glossary/<id>.json`.
- **Document:** `{"island": …, "nodes": […], "datasets": […], "glossary": […]}`. The app bundles one per
  island in `app/assets/packs/<islandId>.json`. The backend serves `GET /v1/content/manifest`
  (`{"packs": [{"islandId", "version"}]}`) and `GET /v1/content/packs/{islandId}/{version}`.
- **Node fields:** `id`, `type`, `title`, `status` (`draft` until validated), `glossary`, `datasets`,
  `bridge` (`{date, difficulty?}`: the trip the lesson opens).
  Everything else is the type's payload, read by that type's player.
- **Loading** (`ContentRepository`):
  - Start from the bundled pack. A cached pack wins only if it reads and is newer, so an app update that
    ships a newer bundle replaces an older cache.
  - At most once a day, ask the manifest; download a higher version, then cache it only if it reads, has
    the right island and has the right version.
  - A cached pack that cannot be read is deleted, and the bundled one stands in. Network failures keep the
    current pack.
- **Reading** (`decodePack`): a pack is corrupt when it is not JSON or misses a field, when a text lacks
  `fr` or `en`, when a node type or status is unknown, or when a reference points to a node, dataset or
  term the pack does not hold. The deeper checks (glossary links inside texts, dataset provenance, drafts
  in a release) belong to `cmd/contentcheck`.

## Consequences

- The islands work offline from the first launch, and the next content version reaches every install
  within a day of being published, without an app update.
- The bundled document duplicates the source tree. It is assembled from `content/` by tooling (M6-2), and
  CI fails when the two differ.
- `content_packs.etag` stays unused.
