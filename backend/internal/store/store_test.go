package store

import (
	"context"
	"database/sql"
	"errors"
	"path/filepath"
	"reflect"
	"testing"
	"testing/fstest"
	"time"
)

func day(s string) time.Time {
	t, err := time.Parse(time.DateOnly, s)
	if err != nil {
		panic(err)
	}
	return t
}

func open(t *testing.T) *Store {
	t.Helper()
	s, err := Open(filepath.Join(t.TempDir(), "market.db"))
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

var cw8 = Asset{
	ID: "cw8", Symbol: "CW8", Name: "Amundi MSCI World", Type: "etf", Exchange: "euronext",
	Currency: "EUR", Region: "world", ListingDate: day("2009-04-17"), ProviderSymbol: "CW8:EPA",
}

var aapl = Asset{
	ID: "aapl", Symbol: "AAPL", Name: "Apple", Type: "stock", Exchange: "nasdaq",
	Currency: "USD", Region: "us", ListingDate: day("1980-12-12"), ProviderSymbol: "AAPL",
}

func TestOpenCreatesTheSchemaAndReopens(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "market.db")
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.UpsertAssets(ctx, []Asset{cw8}); err != nil {
		t.Fatal(err)
	}
	s.Close()

	s, err = Open(path)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer s.Close()
	got, err := s.Asset(ctx, "cw8")
	if err != nil || !reflect.DeepEqual(got, cw8) {
		t.Fatalf("after reopen: %+v, %v", got, err)
	}
}

func TestMigrateAppliesOnlyNewSteps(t *testing.T) {
	ctx := context.Background()
	db, err := sql.Open("sqlite", filepath.Join(t.TempDir(), "m.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()

	v1 := fstest.MapFS{"001_a.sql": {Data: []byte("CREATE TABLE a (x INTEGER); INSERT INTO a VALUES (1);")}}
	if err := migrate(ctx, db, v1); err != nil {
		t.Fatal(err)
	}
	v2 := fstest.MapFS{
		"001_a.sql": v1["001_a.sql"],
		"002_b.sql": {Data: []byte("ALTER TABLE a ADD COLUMN y INTEGER DEFAULT 2;")},
	}
	if err := migrate(ctx, db, v2); err != nil {
		t.Fatal(err)
	}
	// Running again is a no-op: step 1 would fail on CREATE TABLE.
	if err := migrate(ctx, db, v2); err != nil {
		t.Fatal(err)
	}
	var version, x, y int
	db.QueryRow("PRAGMA user_version").Scan(&version)
	db.QueryRow("SELECT x, y FROM a").Scan(&x, &y)
	if version != 2 || x != 1 || y != 2 {
		t.Fatalf("version %d, row (%d, %d)", version, x, y)
	}
}

func TestMigrateRefusesANewerDatabase(t *testing.T) {
	ctx := context.Background()
	db, _ := sql.Open("sqlite", filepath.Join(t.TempDir(), "m.db"))
	defer db.Close()
	db.Exec("PRAGMA user_version = 5")
	err := migrate(ctx, db, fstest.MapFS{"001_a.sql": {Data: []byte("SELECT 1;")}})
	if err == nil {
		t.Fatal("expected an error for a database newer than the binary")
	}
}

func TestMigrateRollsBackAFailedStep(t *testing.T) {
	ctx := context.Background()
	db, _ := sql.Open("sqlite", filepath.Join(t.TempDir(), "m.db"))
	defer db.Close()
	broken := fstest.MapFS{"001_a.sql": {Data: []byte("CREATE TABLE a (x INTEGER); NOT SQL;")}}
	if err := migrate(ctx, db, broken); err == nil {
		t.Fatal("expected the broken step to fail")
	}
	var version, tables int
	db.QueryRow("PRAGMA user_version").Scan(&version)
	db.QueryRow("SELECT count(*) FROM sqlite_master WHERE name = 'a'").Scan(&tables)
	if version != 0 || tables != 0 {
		t.Fatalf("version %d, table a exists: %d", version, tables)
	}
}

func TestAssets(t *testing.T) {
	ctx := context.Background()
	s := open(t)
	if err := s.UpsertAssets(ctx, []Asset{cw8, aapl}); err != nil {
		t.Fatal(err)
	}
	renamed := cw8
	renamed.Name = "Amundi MSCI World UCITS ETF"
	if err := s.UpsertAssets(ctx, []Asset{renamed}); err != nil {
		t.Fatal(err)
	}
	all, err := s.Assets(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(all, []Asset{aapl, renamed}) {
		t.Fatalf("assets: %+v", all)
	}
	if _, err := s.Asset(ctx, "nope"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing asset: %v", err)
	}
}

func TestBars(t *testing.T) {
	ctx := context.Background()
	s := open(t)
	s.UpsertAssets(ctx, []Asset{cw8})
	bars := []Bar{
		{Date: day("2026-10-07"), Open: "520.10", High: "523.00", Low: "519.50", Close: "522.40", Volume: 1200},
		{Date: day("2026-10-05"), Open: "515.00", High: "518.00", Low: "514.20", Close: "517.60", Volume: 900},
		{Date: day("2026-10-06"), Open: "517.60", High: "521.00", Low: "516.00", Close: "520.10", Volume: 1000},
	}
	if err := s.UpsertBars(ctx, "cw8", bars); err != nil {
		t.Fatal(err)
	}

	got, err := s.Bars(ctx, "cw8", day("2026-10-06"), day("2026-10-07"))
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, []Bar{bars[2], bars[0]}) {
		t.Fatalf("range, ascending and inclusive: %+v", got)
	}
	// Exact decimals survive: no float in the way.
	if got[0].Close != "520.10" {
		t.Fatalf("close %q", got[0].Close)
	}

	// A re-adjusted bar replaces the old one.
	adjusted := bars[0]
	adjusted.Close = "261.20"
	s.UpsertBars(ctx, "cw8", []Bar{adjusted})
	got, _ = s.Bars(ctx, "cw8", day("2026-10-07"), day("2026-10-07"))
	if len(got) != 1 || got[0].Close != "261.20" {
		t.Fatalf("replaced: %+v", got)
	}

	last, ok, err := s.LastBarDate(ctx, "cw8")
	if err != nil || !ok || !last.Equal(day("2026-10-07")) {
		t.Fatalf("last bar: %v %v %v", last, ok, err)
	}
	if _, ok, _ := s.LastBarDate(ctx, "aapl"); ok {
		t.Fatal("no bar yet for aapl")
	}
	if err := s.UpsertBars(ctx, "ghost", bars); err == nil {
		t.Fatal("bars need a known asset")
	}
}

func TestFxRates(t *testing.T) {
	ctx := context.Background()
	s := open(t)
	rates := []Rate{{Date: day("2026-10-05"), Rate: "0.85310"}, {Date: day("2026-10-06"), Rate: "0.85420"}}
	if err := s.UpsertRates(ctx, "USD", "EUR", rates); err != nil {
		t.Fatal(err)
	}
	s.UpsertRates(ctx, "GBP", "EUR", []Rate{{Date: day("2026-10-05"), Rate: "1.15"}})
	got, err := s.Rates(ctx, "USD", "EUR", day("2026-10-01"), day("2026-10-31"))
	if err != nil || !reflect.DeepEqual(got, rates) {
		t.Fatalf("rates: %+v %v", got, err)
	}
}

func TestLivret(t *testing.T) {
	ctx := context.Background()
	s := open(t)
	rates := []LivretRate{
		{ValidFrom: day("2025-08-01"), AnnualRate: "0.017"},
		{ValidFrom: day("2023-02-01"), AnnualRate: "0.03"},
	}
	ceilings := []LivretCeiling{
		{ValidFrom: day("2013-01-01"), AmountCents: 2295000},
		{ValidFrom: day("2012-10-01"), AmountCents: 1912500},
	}
	if err := s.ReplaceLivret(ctx, rates, ceilings); err != nil {
		t.Fatal(err)
	}
	// Replacing drops rows that are no longer in the data.
	if err := s.ReplaceLivret(ctx, rates, ceilings[:1]); err != nil {
		t.Fatal(err)
	}
	gotRates, gotCeilings, err := s.Livret(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(gotRates, []LivretRate{rates[1], rates[0]}) {
		t.Fatalf("rates oldest first: %+v", gotRates)
	}
	if !reflect.DeepEqual(gotCeilings, ceilings[:1]) {
		t.Fatalf("ceilings: %+v", gotCeilings)
	}
}

func TestSyncState(t *testing.T) {
	ctx := context.Background()
	s := open(t)
	s.UpsertAssets(ctx, []Asset{cw8})
	if _, ok, err := s.SyncState(ctx, "cw8"); ok || err != nil {
		t.Fatalf("no state yet: %v %v", ok, err)
	}
	state := SyncState{
		AssetID: "cw8", FirstDate: day("2009-04-17"), LastDate: day("2026-10-06"),
		FetchedAt: time.Date(2026, 10, 6, 22, 30, 0, 0, time.UTC),
	}
	if err := s.SaveSyncState(ctx, state); err != nil {
		t.Fatal(err)
	}
	state.LastDate = day("2026-10-07")
	state.AdjustedAt = time.Date(2026, 10, 7, 22, 30, 0, 0, time.UTC)
	if err := s.SaveSyncState(ctx, state); err != nil {
		t.Fatal(err)
	}
	got, ok, err := s.SyncState(ctx, "cw8")
	if err != nil || !ok || !reflect.DeepEqual(got, state) {
		t.Fatalf("sync state: %+v %v %v", got, ok, err)
	}
}
