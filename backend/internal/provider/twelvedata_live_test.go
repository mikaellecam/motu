//go:build live

package provider

import (
	"context"
	"os"
	"testing"
)

// Checks the adapter against the real API (two credits). Not part of CI:
//
//	set -a; . ./.env; set +a; go test -tags live ./internal/provider/
func TestLiveTwelveData(t *testing.T) {
	key := os.Getenv("TWELVEDATA_API_KEY")
	if key == "" {
		t.Skip("TWELVEDATA_API_KEY not set")
	}
	td := NewTwelveData(key)
	// Apple's 4:1 split on 2020-08-31: adjusted closes stay continuous.
	bars, err := td.History(context.Background(), "AAPL", day("2020-08-27"), day("2020-09-01"))
	if err != nil {
		t.Fatal(err)
	}
	if len(bars) != 4 || !bars[0].Date.Equal(day("2020-08-27")) || !bars[3].Date.Equal(day("2020-09-01")) {
		t.Fatalf("bars: %+v", bars)
	}
	// A 15-year window comes back whole, from its first day: the provider
	// keeps the latest 5 000 bars of a range, so windows must stay under.
	long, err := td.History(context.Background(), "SPY", day("2000-01-03"), day("2000-01-03").AddDate(0, 0, td.MaxDays()-1))
	if err != nil || len(long) < 3500 || !long[0].Date.Equal(day("2000-01-03")) {
		t.Fatalf("15-year window: %d bars from %v, %v", len(long), long[0].Date, err)
	}
	quotes, err := td.Quotes(context.Background(), []string{"ACWI", "LVMUY"})
	if err != nil || quotes["ACWI"].Price == "" || quotes["LVMUY"].Currency != "USD" {
		t.Fatalf("quotes: %+v %v", quotes, err)
	}
}
