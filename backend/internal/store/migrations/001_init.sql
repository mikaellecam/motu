-- Market data served to the app (BRIEF §8.2). Dates are YYYY-MM-DD, instants
-- RFC 3339 UTC, prices and rates exact decimal strings: never floats.

CREATE TABLE assets (
  id              TEXT PRIMARY KEY,
  symbol          TEXT NOT NULL,
  name            TEXT NOT NULL,
  type            TEXT NOT NULL CHECK (type IN ('etf', 'stock')),
  exchange        TEXT NOT NULL,
  currency        TEXT NOT NULL,
  region          TEXT NOT NULL,
  listing_date    TEXT NOT NULL,
  provider_symbol TEXT NOT NULL
) STRICT;

CREATE TABLE bars (
  asset_id TEXT NOT NULL REFERENCES assets (id) ON DELETE CASCADE,
  date     TEXT NOT NULL,
  open     TEXT NOT NULL,
  high     TEXT NOT NULL,
  low      TEXT NOT NULL,
  close    TEXT NOT NULL,
  volume   INTEGER NOT NULL,
  PRIMARY KEY (asset_id, date)
) STRICT, WITHOUT ROWID;

CREATE TABLE fx_rates (
  base  TEXT NOT NULL,
  quote TEXT NOT NULL,
  date  TEXT NOT NULL,
  rate  TEXT NOT NULL,
  PRIMARY KEY (base, quote, date)
) STRICT, WITHOUT ROWID;

CREATE TABLE livret_rates (
  valid_from  TEXT PRIMARY KEY,
  annual_rate TEXT NOT NULL
) STRICT;

CREATE TABLE livret_ceilings (
  valid_from   TEXT PRIMARY KEY,
  amount_cents INTEGER NOT NULL
) STRICT;

-- How far each asset's history has been fetched, so a backfill can resume and
-- the daily job only asks for new days. adjusted_at marks the last full
-- refetch after a split.
CREATE TABLE sync_state (
  asset_id    TEXT PRIMARY KEY REFERENCES assets (id) ON DELETE CASCADE,
  first_date  TEXT NOT NULL,
  last_date   TEXT NOT NULL,
  fetched_at  TEXT NOT NULL,
  adjusted_at TEXT
) STRICT;
