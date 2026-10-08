// Package store keeps the market data the backend serves: the catalogue,
// daily bars, FX rates, the Livret A history and the sync state of each
// asset. SQLite through a pure-Go driver; prices stay exact decimal strings.
package store

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"time"

	_ "modernc.org/sqlite"
)

//go:embed migrations/*.sql
var migrations embed.FS

// ErrNotFound is returned when a requested row does not exist.
var ErrNotFound = errors.New("store: not found")

// Store is safe for concurrent use.
type Store struct{ db *sql.DB }

// Asset is one instrument of the catalogue.
type Asset struct {
	ID, Symbol, Name string
	Type             string // "etf" or "stock"
	Exchange         string // "euronext", "nyse", "nasdaq"
	Currency         string // ISO 4217
	Region           string
	ListingDate      time.Time
	ProviderSymbol   string
}

// Bar is one adjusted daily bar; prices are exact decimal strings.
type Bar struct {
	Date                   time.Time
	Open, High, Low, Close string
	Volume                 int64
}

// Rate is a daily FX rate: units of quote per unit of base.
type Rate struct {
	Date time.Time
	Rate string
}

// LivretRate is an annual rate (0.017 for 1.7 %) valid from a date.
type LivretRate struct {
	ValidFrom  time.Time
	AnnualRate string
}

// LivretCeiling is the deposit ceiling valid from a date.
type LivretCeiling struct {
	ValidFrom   time.Time
	AmountCents int64
}

// SyncState records how far an asset's history has been fetched.
type SyncState struct {
	AssetID             string
	FirstDate, LastDate time.Time
	FetchedAt           time.Time
	AdjustedAt          time.Time // zero when never refetched after a split
}

// Open opens (or creates) the database at path and brings its schema up to
// date.
func Open(path string) (*Store, error) {
	db, err := sql.Open("sqlite", "file:"+path+
		"?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)")
	if err != nil {
		return nil, err
	}
	steps, err := fs.Sub(migrations, "migrations")
	if err == nil {
		err = migrate(context.Background(), db, steps)
	}
	if err != nil {
		db.Close()
		return nil, err
	}
	return &Store{db: db}, nil
}

func (s *Store) Close() error { return s.db.Close() }

// migrate applies, in name order, the *.sql files of fsys the database has
// not seen yet, each in its own transaction. PRAGMA user_version counts the
// applied files.
func migrate(ctx context.Context, db *sql.DB, fsys fs.FS) error {
	names, err := fs.Glob(fsys, "*.sql")
	if err != nil {
		return err
	}
	var version int
	if err := db.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	if version > len(names) {
		return fmt.Errorf("store: database schema %d is newer than this binary (%d)", version, len(names))
	}
	for i := version; i < len(names); i++ {
		script, err := fs.ReadFile(fsys, names[i])
		if err != nil {
			return err
		}
		if err := inTx(ctx, db, func(tx *sql.Tx) error {
			if _, err := tx.ExecContext(ctx, string(script)); err != nil {
				return fmt.Errorf("store: migration %s: %w", names[i], err)
			}
			_, err := tx.ExecContext(ctx, fmt.Sprintf("PRAGMA user_version = %d", i+1))
			return err
		}); err != nil {
			return err
		}
	}
	return nil
}

func inTx(ctx context.Context, db *sql.DB, fn func(*sql.Tx) error) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}

func formatDate(t time.Time) string { return t.Format(time.DateOnly) }

func parseDate(s string) (time.Time, error) { return time.Parse(time.DateOnly, s) }

// UpsertAssets inserts assets or updates them by id.
func (s *Store) UpsertAssets(ctx context.Context, assets []Asset) error {
	return inTx(ctx, s.db, func(tx *sql.Tx) error {
		for _, a := range assets {
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO assets (id, symbol, name, type, exchange, currency, region, listing_date, provider_symbol)
				VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
				ON CONFLICT (id) DO UPDATE SET
					symbol = excluded.symbol, name = excluded.name, type = excluded.type,
					exchange = excluded.exchange, currency = excluded.currency, region = excluded.region,
					listing_date = excluded.listing_date, provider_symbol = excluded.provider_symbol`,
				a.ID, a.Symbol, a.Name, a.Type, a.Exchange, a.Currency, a.Region,
				formatDate(a.ListingDate), a.ProviderSymbol); err != nil {
				return err
			}
		}
		return nil
	})
}

const assetColumns = `id, symbol, name, type, exchange, currency, region, listing_date, provider_symbol`

func scanAsset(row interface{ Scan(...any) error }) (Asset, error) {
	var a Asset
	var listing string
	if err := row.Scan(&a.ID, &a.Symbol, &a.Name, &a.Type, &a.Exchange, &a.Currency,
		&a.Region, &listing, &a.ProviderSymbol); err != nil {
		return Asset{}, err
	}
	var err error
	a.ListingDate, err = parseDate(listing)
	return a, err
}

// Assets lists the catalogue by id.
func (s *Store) Assets(ctx context.Context) ([]Asset, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+assetColumns+` FROM assets ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var assets []Asset
	for rows.Next() {
		a, err := scanAsset(rows)
		if err != nil {
			return nil, err
		}
		assets = append(assets, a)
	}
	return assets, rows.Err()
}

// Asset returns one asset, or ErrNotFound.
func (s *Store) Asset(ctx context.Context, id string) (Asset, error) {
	a, err := scanAsset(s.db.QueryRowContext(ctx, `SELECT `+assetColumns+` FROM assets WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return Asset{}, ErrNotFound
	}
	return a, err
}

// UpsertBars stores bars of a known asset; a bar on an existing date replaces
// it (re-adjusted history).
func (s *Store) UpsertBars(ctx context.Context, assetID string, bars []Bar) error {
	return inTx(ctx, s.db, func(tx *sql.Tx) error {
		for _, b := range bars {
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO bars (asset_id, date, open, high, low, close, volume)
				VALUES (?, ?, ?, ?, ?, ?, ?)
				ON CONFLICT (asset_id, date) DO UPDATE SET
					open = excluded.open, high = excluded.high, low = excluded.low,
					close = excluded.close, volume = excluded.volume`,
				assetID, formatDate(b.Date), b.Open, b.High, b.Low, b.Close, b.Volume); err != nil {
				return err
			}
		}
		return nil
	})
}

// DeleteBars drops an asset's whole history, before refetching it.
func (s *Store) DeleteBars(ctx context.Context, assetID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM bars WHERE asset_id = ?`, assetID)
	return err
}

// Bars returns an asset's bars from from to to, both included, oldest first.
func (s *Store) Bars(ctx context.Context, assetID string, from, to time.Time) ([]Bar, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT date, open, high, low, close, volume FROM bars
		WHERE asset_id = ? AND date BETWEEN ? AND ? ORDER BY date`,
		assetID, formatDate(from), formatDate(to))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var bars []Bar
	for rows.Next() {
		var b Bar
		var date string
		if err := rows.Scan(&date, &b.Open, &b.High, &b.Low, &b.Close, &b.Volume); err != nil {
			return nil, err
		}
		if b.Date, err = parseDate(date); err != nil {
			return nil, err
		}
		bars = append(bars, b)
	}
	return bars, rows.Err()
}

// LastBarDate is the date of an asset's latest bar; ok is false without bars.
func (s *Store) LastBarDate(ctx context.Context, assetID string) (last time.Time, ok bool, err error) {
	var date sql.NullString
	if err := s.db.QueryRowContext(ctx, `SELECT max(date) FROM bars WHERE asset_id = ?`, assetID).
		Scan(&date); err != nil || !date.Valid {
		return time.Time{}, false, err
	}
	last, err = parseDate(date.String)
	return last, err == nil, err
}

// UpsertRates stores daily rates of a currency pair.
func (s *Store) UpsertRates(ctx context.Context, base, quote string, rates []Rate) error {
	return inTx(ctx, s.db, func(tx *sql.Tx) error {
		for _, r := range rates {
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO fx_rates (base, quote, date, rate) VALUES (?, ?, ?, ?)
				ON CONFLICT (base, quote, date) DO UPDATE SET rate = excluded.rate`,
				base, quote, formatDate(r.Date), r.Rate); err != nil {
				return err
			}
		}
		return nil
	})
}

// Rates returns a pair's rates from from to to, both included, oldest first.
func (s *Store) Rates(ctx context.Context, base, quote string, from, to time.Time) ([]Rate, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT date, rate FROM fx_rates
		WHERE base = ? AND quote = ? AND date BETWEEN ? AND ? ORDER BY date`,
		base, quote, formatDate(from), formatDate(to))
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var rates []Rate
	for rows.Next() {
		var r Rate
		var date string
		if err := rows.Scan(&date, &r.Rate); err != nil {
			return nil, err
		}
		if r.Date, err = parseDate(date); err != nil {
			return nil, err
		}
		rates = append(rates, r)
	}
	return rates, rows.Err()
}

// ReplaceLivret replaces the whole Livret A history: it is small, seeded data.
func (s *Store) ReplaceLivret(ctx context.Context, rates []LivretRate, ceilings []LivretCeiling) error {
	return inTx(ctx, s.db, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `DELETE FROM livret_rates; DELETE FROM livret_ceilings;`); err != nil {
			return err
		}
		for _, r := range rates {
			if _, err := tx.ExecContext(ctx, `INSERT INTO livret_rates (valid_from, annual_rate) VALUES (?, ?)`,
				formatDate(r.ValidFrom), r.AnnualRate); err != nil {
				return err
			}
		}
		for _, c := range ceilings {
			if _, err := tx.ExecContext(ctx, `INSERT INTO livret_ceilings (valid_from, amount_cents) VALUES (?, ?)`,
				formatDate(c.ValidFrom), c.AmountCents); err != nil {
				return err
			}
		}
		return nil
	})
}

// Livret returns the rate and ceiling histories, oldest first.
func (s *Store) Livret(ctx context.Context) ([]LivretRate, []LivretCeiling, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT valid_from, annual_rate FROM livret_rates ORDER BY valid_from`)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	var rates []LivretRate
	for rows.Next() {
		var r LivretRate
		var from string
		if err := rows.Scan(&from, &r.AnnualRate); err != nil {
			return nil, nil, err
		}
		if r.ValidFrom, err = parseDate(from); err != nil {
			return nil, nil, err
		}
		rates = append(rates, r)
	}
	if err := rows.Err(); err != nil {
		return nil, nil, err
	}

	rows, err = s.db.QueryContext(ctx, `SELECT valid_from, amount_cents FROM livret_ceilings ORDER BY valid_from`)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	var ceilings []LivretCeiling
	for rows.Next() {
		var c LivretCeiling
		var from string
		if err := rows.Scan(&from, &c.AmountCents); err != nil {
			return nil, nil, err
		}
		if c.ValidFrom, err = parseDate(from); err != nil {
			return nil, nil, err
		}
		ceilings = append(ceilings, c)
	}
	return rates, ceilings, rows.Err()
}

// SyncState returns an asset's sync state; ok is false before its first
// fetch.
func (s *Store) SyncState(ctx context.Context, assetID string) (state SyncState, ok bool, err error) {
	var first, last, fetched string
	var adjusted sql.NullString
	err = s.db.QueryRowContext(ctx, `
		SELECT first_date, last_date, fetched_at, adjusted_at FROM sync_state WHERE asset_id = ?`, assetID).
		Scan(&first, &last, &fetched, &adjusted)
	if errors.Is(err, sql.ErrNoRows) {
		return SyncState{}, false, nil
	}
	if err != nil {
		return SyncState{}, false, err
	}
	state.AssetID = assetID
	if state.FirstDate, err = parseDate(first); err != nil {
		return SyncState{}, false, err
	}
	if state.LastDate, err = parseDate(last); err != nil {
		return SyncState{}, false, err
	}
	if state.FetchedAt, err = time.Parse(time.RFC3339, fetched); err != nil {
		return SyncState{}, false, err
	}
	if adjusted.Valid {
		if state.AdjustedAt, err = time.Parse(time.RFC3339, adjusted.String); err != nil {
			return SyncState{}, false, err
		}
	}
	return state, true, nil
}

// SaveSyncState inserts or replaces an asset's sync state.
func (s *Store) SaveSyncState(ctx context.Context, state SyncState) error {
	var adjusted sql.NullString
	if !state.AdjustedAt.IsZero() {
		adjusted = sql.NullString{String: state.AdjustedAt.UTC().Format(time.RFC3339), Valid: true}
	}
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO sync_state (asset_id, first_date, last_date, fetched_at, adjusted_at)
		VALUES (?, ?, ?, ?, ?)
		ON CONFLICT (asset_id) DO UPDATE SET
			first_date = excluded.first_date, last_date = excluded.last_date,
			fetched_at = excluded.fetched_at, adjusted_at = excluded.adjusted_at`,
		state.AssetID, formatDate(state.FirstDate), formatDate(state.LastDate),
		state.FetchedAt.UTC().Format(time.RFC3339), adjusted)
	return err
}
