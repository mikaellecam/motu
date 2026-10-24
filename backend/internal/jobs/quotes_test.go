package jobs

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"finance-companion/backend/internal/provider"
)

func TestInSessionAndNextOpen(t *testing.T) {
	cases := []struct {
		now     string
		session bool
		next    string
	}{
		{"2026-10-07 09:29", false, "2026-10-07 09:30"},
		{"2026-10-07 09:30", true, "2026-10-08 09:30"},
		{"2026-10-07 15:59", true, "2026-10-08 09:30"},
		{"2026-10-07 16:00", false, "2026-10-08 09:30"},
		{"2026-10-09 17:00", false, "2026-10-12 09:30"}, // Friday → Monday
		{"2026-10-10 12:00", false, "2026-10-12 09:30"}, // Saturday
		{"2026-12-24 12:59", true, "2026-12-28 09:30"},  // early close, then Christmas
		{"2026-12-24 13:00", false, "2026-12-28 09:30"}, // closed at 13:00
		{"2026-11-26 11:00", false, "2026-11-27 09:30"}, // Thanksgiving
	}
	for _, c := range cases {
		now := ny(c.now)
		if InSession(now) != c.session {
			t.Errorf("%s: session %v", c.now, !c.session)
		}
		if got := NextSessionOpen(now); !got.Equal(ny(c.next)) {
			t.Errorf("%s: next open %s", c.now, got)
		}
	}
}

func TestRefreshBatchesByTheMinuteBudget(t *testing.T) {
	f := newFixture(t)
	f.fake.QuoteData["A"] = provider.Quote{Price: "101.5", Currency: "USD", MarketOpen: true}
	f.fake.QuoteData["B"] = provider.Quote{Price: "20", Currency: "USD", MarketOpen: true}
	cache := NewQuoteCache()
	r := &QuoteRefresher{Store: f.store, Provider: f.fake, Budget: budget(f.clock, 1, 800), Cache: cache,
		Now: f.clock.Now, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	if err := r.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if q, ok := cache.Get("a"); !ok || q.Price != "101.5" {
		t.Fatalf("a: %+v", q)
	}
	if _, ok := cache.Get("b"); !ok {
		t.Fatal("b missing")
	}
	// One symbol per minute here: two calls, a minute apart.
	if f.fake.Calls != 2 || f.clock.now.Sub(ny("2026-09-16 12:00")) != time.Minute {
		t.Fatalf("%d calls, waited %v", f.fake.Calls, f.clock.now.Sub(ny("2026-09-16 12:00")))
	}
}

func TestRunRefreshesOnlyDuringTheSession(t *testing.T) {
	f := newFixture(t)
	f.clock.now = ny("2026-09-19 12:00") // Saturday
	cache := NewQuoteCache()
	b := budget(f.clock, 8, 800)
	var waits []time.Duration
	ctx, cancel := context.WithCancel(context.Background())
	b.Sleep = func(_ context.Context, d time.Duration) error {
		waits = append(waits, d)
		f.clock.now = f.clock.now.Add(d)
		if len(waits) == 2 {
			cancel()
			return context.Canceled
		}
		return nil
	}
	r := &QuoteRefresher{Store: f.store, Provider: f.fake, Budget: b, Cache: cache,
		Now: f.clock.Now, Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	r.Run(ctx)
	// Saturday noon → Monday 09:30 without a call; then one refresh and a
	// 30-minute wait.
	if waits[0] != ny("2026-09-21 09:30").Sub(ny("2026-09-19 12:00")) || waits[1] != QuoteInterval || f.fake.Calls != 1 {
		t.Fatalf("waits %v, %d calls", waits, f.fake.Calls)
	}
}
