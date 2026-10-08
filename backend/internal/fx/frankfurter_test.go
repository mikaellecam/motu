package fx

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"finance-companion/backend/internal/store"
)

func day(s string) time.Time {
	t, _ := time.Parse(time.DateOnly, s)
	return t
}

func TestRatesKeepThePublishedDigits(t *testing.T) {
	var path, query string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path, query = r.URL.Path, r.URL.RawQuery
		w.Write([]byte(`{"amount":1.0,"base":"USD","rates":{"2026-10-01":{"EUR":0.88511},"2026-10-02":{"EUR":0.8909}}}`))
	}))
	defer srv.Close()
	f := NewFrankfurter()
	f.BaseURL = srv.URL
	rates, err := f.Rates(context.Background(), "USD", "EUR", day("2026-10-01"), day("2026-10-02"))
	if err != nil {
		t.Fatal(err)
	}
	if path != "/2026-10-01..2026-10-02" || query != "base=USD&symbols=EUR" {
		t.Fatalf("request %s?%s", path, query)
	}
	got := map[string]string{}
	for _, r := range rates {
		got[r.Date.Format(time.DateOnly)] = r.Rate
	}
	if got["2026-10-01"] != "0.88511" || got["2026-10-02"] != "0.8909" {
		t.Fatalf("rates %v", got)
	}
}

func TestRatesErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()
	f := NewFrankfurter()
	f.BaseURL = srv.URL
	if _, err := f.Rates(context.Background(), "USD", "EUR", day("2026-10-01"), day("2026-10-02")); err == nil {
		t.Fatal("expected an error")
	}
}

// fakeSource returns one rate per requested window end, recording windows.
type fakeSource struct{ windows [][2]time.Time }

func (f *fakeSource) Rates(_ context.Context, _, _ string, from, to time.Time) ([]store.Rate, error) {
	f.windows = append(f.windows, [2]time.Time{from, to})
	return []store.Rate{{Date: to, Rate: "0.9"}}, nil
}

func TestSyncInFiveYearWindowsThenOnlyNewDays(t *testing.T) {
	db, err := store.Open(filepath.Join(t.TempDir(), "m.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	src := &fakeSource{}
	if err := Sync(context.Background(), db, src, "USD", "EUR", day("2000-01-03"), day("2012-06-01")); err != nil {
		t.Fatal(err)
	}
	if len(src.windows) != 3 || !src.windows[1][0].Equal(day("2005-01-03")) || !src.windows[2][1].Equal(day("2012-06-01")) {
		t.Fatalf("windows %v", src.windows)
	}
	src.windows = nil
	Sync(context.Background(), db, src, "USD", "EUR", day("2000-01-03"), day("2012-06-04"))
	if len(src.windows) != 1 || !src.windows[0][0].Equal(day("2012-06-02")) {
		t.Fatalf("append %v", src.windows)
	}
}
