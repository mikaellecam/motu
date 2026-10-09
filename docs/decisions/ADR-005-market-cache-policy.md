# ADR-005: Market data cache policy

Status: accepted
Date: 2026-10-09

## Context

The app shows market data that comes from our backend (`BRIEF.md` §8.3) and keeps it in drift (ADR-002).
Several forces shape how the cache behaves:

- **Offline first** (§6.4). Wallets, charts and trips must work from the cache, and a network failure must
  never hide data the app already has.
- **History is immutable, with one exception** (§6.2). Once a session closes, its bar never changes. But
  prices are adjusted for dividends and splits (`adjust=all`, ADR-004). When an asset pays a dividend, the
  backend refetches its whole history and every past close moves slightly; it then advances `adjustedAt`.
- **Two clocks.** Trips read the market on a past date (`HistoricalClock`), and the live wallet reads it
  now (`LiveClock`). Nothing dated after the clock's day may reach the domain (CLAUDE.md rule 3). Cache
  ages, on the other hand, are about the device's real time: a trip in 2008 must not decide that a quote
  fetched a minute ago is 18 years old.
- **Market hours.** A live quote changes only while its exchange is open, and holidays come from the
  backend calendar (M2-5).
- **Cost.** The backend has a per-client rate limit, and a full history is about 6 700 bars (≈ 600 KB of
  JSON) per asset.

## Options considered

### First fetch: whole history, or only the range asked for

Fetching only the range asked for (for example from a trip's start) sends less data at first. But a later
request for an earlier range (a "max" chart, a volatility window before the trip) leaves a hole in front of
the cache. The repository would then have to track gaps on both sides. Fetching the whole history once
keeps a single invariant, "the cache holds `[firstDate, lastDate]` with no gap", at a one-time cost of
about 600 KB per asset that is actually viewed.

### Freshness: by TTL only, or by "can a newer bar exist"

A plain TTL on history would refetch days that never change. Asking "is the range's end after `lastDate`?"
fetches only when a newer bar can exist. Alone, though, it would hit the backend on every read during a
holiday, a weekend, or the hour before the backend's daily sync. A short recheck delay after each fetch
bounds that.

### Re-adjustment: compare prices, or trust `adjustedAt`

Comparing overlapping closes would need an extra request and a tolerance. The backend already detects
re-adjustments and publishes `adjustedAt` with every history answer, so the app compares that value.

## Decision

`MarketRepository` (`app/lib/data/repositories/market_repository.dart`) applies these rules.

| Data | Fetched when | Kept |
|---|---|---|
| History | First need: the whole history. After that: only if the range's end (cut at `asOf`) is after `lastDate` and the last fetch is older than 15 min, with `from = lastDate + 1`. If the answer's `adjustedAt` differs from the cached one, the asset's history is dropped and fetched whole again, in one transaction. | Forever |
| Quotes | When the cached one has expired: 15 min after its fetch if the exchange was open at that moment, otherwise at the next open (holidays included). | Until replaced |
| Catalogue | Once a day, and once more when an unknown asset id is asked for. | Until replaced |
| FX rates (`FxService`, from Frankfurter) | First need of a pair: its whole history since the data floor (one request, about 200 KB). After that: only if `asOf`'s day is after the last cached rate and the last check is older than 15 min, from the day after it. A day without a fixing (weekend, ECB holiday) takes the previous rate. | Forever |
| Calendar | Past years once. The current year and later once a day, since an unscheduled closure can be announced. Years the backend does not serve count as weekends-only. | Forever |

These rules hold for every kind of data:

- **Cut at `asOf`.** History ends at `asOf`'s day: `HistoricalClock` sees a day after its close. A quote
  observed after `asOf`'s day is withheld, so trips price from history, never from quotes. The catalogue
  hides assets listed after `asOf`.
- **The device clock times the cache.** The repository takes a wall clock (`LiveClock` in the app) for TTLs
  and `fetchedAt`; `asOf` is used only to cut reads.
- **Failures.** A network failure falls back to the cache. It surfaces, typed (`Failure`), only when nothing
  is cached. An unknown asset is `NotFoundFailure`.

## Consequences

- Reads are local after the first fetch. A trip that advances through cached history makes no request.
- The first view of an asset downloads its whole history. If that becomes a problem on mobile data, gzip
  on the backend would cut it about five-fold without changing this policy.
- Adjusted history can change in the past, so derived values that the app stores (daily wallet values)
  keep the prices they were computed with. Recomputing them after a re-adjustment is not done.
- `CacheStatus` (fresh / stale / offline, M3-5) will be reported by this repository. The fallback paths
  above are where it learns that it is offline.
