package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"finance-companion/backend/internal/provider"
	"finance-companion/backend/internal/store"
)

func day(s string) time.Time {
	t, _ := time.Parse(time.DateOnly, s)
	return t
}

func TestFreezeWritesTheDatasetIntoThePack(t *testing.T) {
	pack := t.TempDir()
	os.WriteFile(filepath.Join(pack, "island.json"), []byte("{}"), 0o644)
	market := provider.NewFake()
	market.Window = 10
	for d := day("2022-01-03"); d.Before(day("2022-02-01")); d = d.AddDate(0, 0, 1) {
		if d.Weekday() != time.Saturday && d.Weekday() != time.Sunday {
			market.Bars["AAPL"] = append(market.Bars["AAPL"], store.Bar{Date: d, Close: "100.50"})
		}
	}
	var out, errs bytes.Buffer
	code := run(context.Background(), []string{
		"-pack", pack, "-id", "ds.aapl-2022-01-w", "-asset", "apple",
		"-interval", "1week", "-from", "2022-01-03", "-to", "2022-01-28",
	}, market, time.Date(2026, 10, 11, 9, 0, 0, 0, time.UTC), &out, &errs)
	if code != 0 {
		t.Fatalf("exit %d: %s", code, errs.String())
	}
	// 26 days in windows of 10.
	if market.Calls != 3 {
		t.Errorf("calls: %d", market.Calls)
	}
	written, err := os.ReadFile(filepath.Join(pack, "datasets", "ds.aapl-2022-01-w.json"))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{`"symbol": "AAPL"`, `"frozen_at": "2026-10-11"`, `["2022-01-28", 100.5]`} {
		if !strings.Contains(string(written), want) {
			t.Errorf("dataset lacks %s:\n%s", want, written)
		}
	}
	if !strings.Contains(out.String(), "4 points") {
		t.Errorf("out: %s", out.String())
	}
}

func TestFreezeRefuses(t *testing.T) {
	pack := t.TempDir()
	os.WriteFile(filepath.Join(pack, "island.json"), []byte("{}"), 0o644)
	for name, c := range map[string]struct {
		args []string
		want string
	}{
		"no pack there": {[]string{"-pack", t.TempDir(), "-id", "x", "-asset", "apple", "-from", "2022-01-03", "-to", "2022-01-07"},
			"not a pack version directory"},
		"an unknown asset": {[]string{"-pack", pack, "-id", "x", "-asset", "nope", "-from", "2022-01-03", "-to", "2022-01-07"},
			"not a catalogue asset"},
		"a bad day": {[]string{"-pack", pack, "-id", "x", "-asset", "apple", "-from", "03/01/2022", "-to", "2022-01-07"},
			"YYYY-MM-DD"},
		"no data": {[]string{"-pack", pack, "-id", "x", "-asset", "apple", "-from", "2022-01-03", "-to", "2022-01-07"},
			"no close"},
	} {
		var out, errs bytes.Buffer
		code := run(context.Background(), c.args, provider.NewFake(), time.Now(), &out, &errs)
		if code == 0 || !strings.Contains(errs.String(), c.want) {
			t.Errorf("%s: exit %d, %s", name, code, errs.String())
		}
	}
}
