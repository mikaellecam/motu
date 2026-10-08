package jobs

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"path/filepath"
	"testing"
	"time"

	"finance-companion/backend/internal/provider"
	"finance-companion/backend/internal/store"
)

func day(s string) time.Time {
	t, _ := time.Parse(time.DateOnly, s)
	return t
}

func ny(s string) time.Time {
	t, err := time.ParseInLocation("2006-01-02 15:04", s, newYork)
	if err != nil {
		panic(err)
	}
	return t
}

// clock is a fake time: sleeping moves it forward.
type clock struct{ now time.Time }

func (c *clock) Now() time.Time { return c.now }
func (c *clock) Sleep(ctx context.Context, d time.Duration) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	c.now = c.now.Add(d)
	return nil
}

func budget(c *clock, perMinute, perDay int) *Budget {
	b := NewBudget(perMinute, perDay)
	b.Now, b.Sleep = c.Now, c.Sleep
	return b
}

func TestBudgetSpreadsCreditsOverTheMinute(t *testing.T) {
	c := &clock{now: day("2026-10-08").Add(10 * time.Hour)}
	b := budget(c, 8, 800)
	start := c.now
	for range 8 {
		if err := b.Take(context.Background(), 1); err != nil {
			t.Fatal(err)
		}
	}
	if !c.now.Equal(start) {
		t.Fatalf("the first 8 credits wait: %v", c.now.Sub(start))
	}
	b.Take(context.Background(), 1)
	if c.now.Sub(start) != time.Minute {
		t.Fatalf("the 9th waits for the window: %v", c.now.Sub(start))
	}
}

func TestBudgetStopsAtTheDailyLimitAndResetsAtMidnightUTC(t *testing.T) {
	c := &clock{now: day("2026-10-08").Add(23 * time.Hour)}
	b := budget(c, 8, 3)
	for range 3 {
		b.Take(context.Background(), 1)
	}
	if err := b.Take(context.Background(), 1); !errors.Is(err, ErrDailyBudget) {
		t.Fatalf("4th credit: %v", err)
	}
	c.now = day("2026-10-09")
	if err := b.Take(context.Background(), 1); err != nil {
		t.Fatalf("next day: %v", err)
	}
}

func TestBudgetWaitingHonoursCancellation(t *testing.T) {
	c := &clock{now: day("2026-10-08")}
	b := budget(c, 1, 800)
	b.Take(context.Background(), 1)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := b.Take(ctx, 1); !errors.Is(err, context.Canceled) {
		t.Fatalf("%v", err)
	}
}

func TestLastClosedSession(t *testing.T) {
	cases := []struct{ now, want string }{
		{"2026-10-07 15:00", "2026-10-06"}, // Wednesday, session running
		{"2026-10-07 16:29", "2026-10-06"}, // closed, final bar not settled
		{"2026-10-07 16:30", "2026-10-07"},
		{"2026-10-10 12:00", "2026-10-09"}, // Saturday → Friday
		{"2026-10-12 10:00", "2026-10-09"}, // Monday morning → Friday
		{"2026-03-09 17:00", "2026-03-09"}, // first day of US summer time
	}
	for _, c := range cases {
		if got := LastClosedSession(ny(c.now)); !got.Equal(day(c.want)) {
			t.Errorf("%s: %s, want %s", c.now, got.Format(time.DateOnly), c.want)
		}
	}
}

func TestNextDailyRun(t *testing.T) {
	cases := []struct{ now, want string }{
		{"2026-10-07 10:00", "2026-10-07 17:00"},
		{"2026-10-07 17:00", "2026-10-08 17:00"},
		{"2026-10-09 18:00", "2026-10-12 17:00"}, // Friday evening → Monday
		{"2026-03-06 18:00", "2026-03-09 17:00"}, // across the DST change
	}
	for _, c := range cases {
		if got := NextDailyRun(ny(c.now)); !got.Equal(ny(c.want)) {
			t.Errorf("%s: %s, want %s", c.now, got, c.want)
		}
	}
}

// weekdays returns bars on every weekday from from to to.
func weekdays(from, to string) []store.Bar {
	var bars []store.Bar
	for d := day(from); !d.After(day(to)); d = d.AddDate(0, 0, 1) {
		if d.Weekday() != time.Saturday && d.Weekday() != time.Sunday {
			bars = append(bars, store.Bar{Date: d, Open: "1", High: "1", Low: "1", Close: d.Format("0102"), Volume: 1})
		}
	}
	return bars
}

type fixture struct {
	store *store.Store
	fake  *provider.Fake
	clock *clock
	sync  *Syncer
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	s, err := store.Open(filepath.Join(t.TempDir(), "market.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	s.UpsertAssets(context.Background(), []store.Asset{
		{ID: "a", Symbol: "A", Name: "A", Type: "stock", Exchange: "nyse", Currency: "USD", Region: "us", ListingDate: day("1990-01-01"), ProviderSymbol: "A"},
		{ID: "b", Symbol: "B", Name: "B", Type: "stock", Exchange: "otc", Currency: "USD", Region: "europe", ListingDate: day("2026-09-08"), ProviderSymbol: "B"},
	})
	fake := provider.NewFake()
	fake.Window = 7
	// Wednesday 16 September's bar exists but its session is still running.
	fake.Bars["A"] = weekdays("2026-08-25", "2026-09-16")
	fake.Bars["B"] = weekdays("2026-09-08", "2026-09-16")
	c := &clock{now: ny("2026-09-16 12:00")}
	return &fixture{s, fake, c, &Syncer{
		Store: s, Provider: fake, Budget: budget(c, 8, 800), DataFloor: day("2026-09-01"),
		Now: c.Now, Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}}
}

func (f *fixture) bars(t *testing.T, id string) []store.Bar {
	bars, err := f.store.Bars(context.Background(), id, day("2000-01-01"), day("2030-01-01"))
	if err != nil {
		t.Fatal(err)
	}
	return bars
}

func TestBackfillFromTheFloorToTheLastClosedSession(t *testing.T) {
	f := newFixture(t)
	if err := f.sync.SyncAll(context.Background()); err != nil {
		t.Fatal(err)
	}
	a := f.bars(t, "a")
	// 1–15 September: 11 weekdays; nothing before the floor, nothing from the
	// running session.
	if len(a) != 11 || !a[0].Date.Equal(day("2026-09-01")) || !a[10].Date.Equal(day("2026-09-15")) {
		t.Fatalf("a: %d bars, %v → %v", len(a), a[0].Date, a[len(a)-1].Date)
	}
	// B is listed after the floor: from its listing date.
	if b := f.bars(t, "b"); len(b) != 6 || !b[0].Date.Equal(day("2026-09-08")) {
		t.Fatalf("b: %+v", b)
	}
	// Windows of 7 days: A needs 3 calls (1–7, 8–14, 15), B 2 (8–14, 15).
	if f.fake.Calls != 5 {
		t.Fatalf("%d provider calls", f.fake.Calls)
	}
	state, _, _ := f.store.SyncState(context.Background(), "a")
	if !state.FirstDate.Equal(day("2026-09-01")) || !state.LastDate.Equal(day("2026-09-15")) {
		t.Fatalf("sync state %+v", state)
	}
}

func TestAnInterruptedBackfillResumesWhereItStopped(t *testing.T) {
	f := newFixture(t)
	f.fake.Fail = provider.FailFrom(3, errors.New("network down"))
	if err := f.sync.SyncAll(context.Background()); err == nil {
		t.Fatal("expected the failure to surface")
	}
	if got := len(f.bars(t, "a")); got != 10 {
		t.Fatalf("two windows kept before the failure: %d", got)
	}

	f.fake.Fail = nil
	calls := f.fake.Calls
	if err := f.sync.SyncAll(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := len(f.bars(t, "a")); got != 11 {
		t.Fatalf("a after resuming: %d", got)
	}
	// No window fetched twice: 1 more for A (the 15th), 2 for B.
	if f.fake.Calls-calls != 3 {
		t.Fatalf("%d calls to resume", f.fake.Calls-calls)
	}
}

func TestTheDailyAppendOnlyAsksForNewDays(t *testing.T) {
	f := newFixture(t)
	f.sync.SyncAll(context.Background())
	calls := f.fake.Calls
	f.clock.now = ny("2026-09-16 17:00")
	if err := f.sync.SyncAll(context.Background()); err != nil {
		t.Fatal(err)
	}
	if f.fake.Calls-calls != 2 {
		t.Fatalf("one call per asset: %d", f.fake.Calls-calls)
	}
	if a := f.bars(t, "a"); !a[len(a)-1].Date.Equal(day("2026-09-16")) {
		t.Fatalf("last bar %v", a[len(a)-1].Date)
	}
}

func TestASpentBudgetStopsTheRunUntilTomorrow(t *testing.T) {
	f := newFixture(t)
	f.sync.Budget = budget(f.clock, 8, 4)
	// Day 1: A takes 3 credits, B its first window, then the budget is spent.
	if err := f.sync.SyncAll(context.Background()); !errors.Is(err, ErrDailyBudget) {
		t.Fatalf("day 1: %v", err)
	}
	if len(f.bars(t, "a")) != 11 || len(f.bars(t, "b")) != 5 {
		t.Fatalf("day 1: a %d, b %d", len(f.bars(t, "a")), len(f.bars(t, "b")))
	}
	// Day 2 (the next UTC day): A's new day and B's last window.
	f.clock.now = ny("2026-09-17 12:00")
	if err := f.sync.SyncAll(context.Background()); err != nil {
		t.Fatalf("day 2: %v", err)
	}
	if len(f.bars(t, "a")) != 12 || len(f.bars(t, "b")) != 7 {
		t.Fatalf("day 2: a %d, b %d", len(f.bars(t, "a")), len(f.bars(t, "b")))
	}
}

func TestOneUnavailableAssetDoesNotStopTheOthers(t *testing.T) {
	f := newFixture(t)
	f.fake.Unavailable = map[string]bool{"A": true}
	err := f.sync.SyncAll(context.Background())
	if !errors.Is(err, provider.ErrNotAvailable) {
		t.Fatalf("%v", err)
	}
	if len(f.bars(t, "b")) != 6 {
		t.Fatal("b still synced")
	}
}

func TestARateLimitWaitsAMinuteAndRetriesOnce(t *testing.T) {
	f := newFixture(t)
	// Someone else spent this minute's credits: the first call is refused.
	f.fake.Fail = func(n int) error {
		if n == 1 {
			return provider.ErrRateLimited
		}
		return nil
	}
	start := f.clock.now
	if err := f.sync.SyncAll(context.Background()); err != nil {
		t.Fatal(err)
	}
	if f.clock.now.Sub(start) < time.Minute || len(f.bars(t, "a")) != 11 {
		t.Fatalf("waited %v, a has %d bars", f.clock.now.Sub(start), len(f.bars(t, "a")))
	}
}

func TestAPersistentRateLimitStopsTheRun(t *testing.T) {
	f := newFixture(t)
	f.fake.Fail = provider.FailFrom(1, provider.ErrRateLimited)
	if err := f.sync.SyncAll(context.Background()); !errors.Is(err, provider.ErrRateLimited) {
		t.Fatalf("%v", err)
	}
	if f.fake.Calls != 2 {
		t.Fatalf("one retry, no further asset: %d calls", f.fake.Calls)
	}
}

func TestRunDailyStopsWithItsContext(t *testing.T) {
	f := newFixture(t)
	ctx, cancel := context.WithCancel(context.Background())
	f.sync.Budget.Sleep = func(context.Context, time.Duration) error { cancel(); return context.Canceled }
	done := make(chan struct{})
	go func() { f.sync.RunDaily(ctx); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("RunDaily did not return")
	}
	if len(f.bars(t, "a")) != 11 {
		t.Fatal("it synced before waiting")
	}
}

func TestAReadjustedHistoryIsRefetchedWhole(t *testing.T) {
	f := newFixture(t)
	f.sync.SyncAll(context.Background())
	// A dividend: the provider now serves every past close lower.
	for i := range f.fake.Bars["A"] {
		f.fake.Bars["A"][i].Close = "0.98"
	}
	f.clock.now = ny("2026-09-16 17:00")
	if err := f.sync.SyncAll(context.Background()); err != nil {
		t.Fatal(err)
	}
	a := f.bars(t, "a")
	if len(a) != 12 || a[0].Close != "0.98" || a[11].Close != "0.98" {
		t.Fatalf("a refetched: %d bars, first %s", len(a), a[0].Close)
	}
	state, _, _ := f.store.SyncState(context.Background(), "a")
	if !state.AdjustedAt.Equal(f.clock.now) || !state.FirstDate.Equal(day("2026-09-01")) {
		t.Fatalf("adjusted_at tells the app to refetch: %+v", state)
	}
	// B was not re-adjusted: untouched, no adjusted_at.
	if b, _, _ := f.store.SyncState(context.Background(), "b"); !b.AdjustedAt.IsZero() {
		t.Fatalf("b: %+v", b)
	}
}

func TestTheSameCloseWrittenDifferentlyIsNotAnAdjustment(t *testing.T) {
	f := newFixture(t)
	f.sync.SyncAll(context.Background())
	// The provider pads decimals differently: same value.
	for i := range f.fake.Bars["A"] {
		f.fake.Bars["A"][i].Close += ".000"
	}
	calls := f.fake.Calls
	f.clock.now = ny("2026-09-16 17:00")
	f.sync.SyncAll(context.Background())
	if f.fake.Calls-calls != 2 {
		t.Fatalf("no refetch: %d calls", f.fake.Calls-calls)
	}
}
