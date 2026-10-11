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
	}, market, nil, time.Date(2026, 10, 11, 9, 0, 0, 0, time.UTC), &out, &errs)
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
		"two kinds at once": {[]string{"-pack", pack, "-id", "x", "-asset", "apple", "-livret", "-from", "2022-01-03", "-to", "2022-01-07"},
			"one of -asset, -fx and -livret"},
		"none": {[]string{"-pack", pack, "-id", "x", "-from", "2022-01-03", "-to", "2022-01-07"},
			"one of -asset, -fx and -livret"},
		"another currency": {[]string{"-pack", pack, "-id", "x", "-fx", "GBP", "-from", "2022-01-03", "-to", "2022-01-07"},
			"only USD"},
	} {
		var out, errs bytes.Buffer
		code := run(context.Background(), c.args, provider.NewFake(), &fakeRates{}, time.Now(), &out, &errs)
		if code == 0 || !strings.Contains(errs.String(), c.want) {
			t.Errorf("%s: exit %d, %s", name, code, errs.String())
		}
	}
}

// fakeRates serves EUR→USD rates, recording the ranges asked for.
type fakeRates struct {
	rates []store.Rate
	asked []string
}

func (f *fakeRates) Rates(_ context.Context, base, quote string, from, to time.Time) ([]store.Rate, error) {
	f.asked = append(f.asked, base+quote+" "+from.Format(time.DateOnly)+".."+to.Format(time.DateOnly))
	var out []store.Rate
	for _, r := range f.rates {
		if !r.Date.Before(from) && !r.Date.After(to) {
			out = append(out, r)
		}
	}
	return out, nil
}

func freeze(t *testing.T, market provider.Provider, rates *fakeRates, args ...string) string {
	t.Helper()
	pack := t.TempDir()
	os.WriteFile(filepath.Join(pack, "island.json"), []byte("{}"), 0o644)
	var out, errs bytes.Buffer
	code := run(context.Background(), append([]string{"-pack", pack, "-id", "ds.x"}, args...), market, rates,
		time.Date(2026, 10, 11, 9, 0, 0, 0, time.UTC), &out, &errs)
	if code != 0 {
		t.Fatalf("exit %d: %s", code, errs.String())
	}
	written, err := os.ReadFile(filepath.Join(pack, "datasets", "ds.x.json"))
	if err != nil {
		t.Fatal(err)
	}
	return string(written)
}

func TestFreezeInEuros_AtTheECBRateOfEachDay(t *testing.T) {
	market := provider.NewFake()
	market.Bars["AAPL"] = []store.Bar{{Date: day("2022-01-03"), Close: "182"}}
	rates := &fakeRates{rates: []store.Rate{{Date: day("2021-12-31"), Rate: "1.1326"}, {Date: day("2022-01-03"), Rate: "1.1355"}}}
	written := freeze(t, market, rates, "-asset", "apple", "-currency", "EUR", "-from", "2022-01-03", "-to", "2022-01-03")
	for _, want := range []string{`"currency": "EUR"`, `"fx": "ecb"`, `["2022-01-03", 160.281814]`} {
		if !strings.Contains(written, want) {
			t.Errorf("dataset lacks %s:\n%s", want, written)
		}
	}
	// From ten days before, for the rate in force on the first day.
	if len(rates.asked) != 1 || rates.asked[0] != "EURUSD 2021-12-24..2022-01-03" {
		t.Errorf("asked: %v", rates.asked)
	}
}

func TestFreezeTheDollarInEuros_FiveYearsPerRequest(t *testing.T) {
	rates := &fakeRates{rates: []store.Rate{{Date: day("2017-01-02"), Rate: "1.0465"}}}
	written := freeze(t, nil, rates, "-fx", "USD", "-interval", "1month", "-from", "2017-01-01", "-to", "2023-12-31")
	if !strings.Contains(written, `"symbol": "USD/EUR"`) || !strings.Contains(written, `["2017-01-02", 0.955566]`) {
		t.Errorf("dataset:\n%s", written)
	}
	if len(rates.asked) != 2 {
		t.Errorf("asked: %v", rates.asked)
	}
}

func TestFreezeALivretA_WithoutTheProvider(t *testing.T) {
	written := freeze(t, nil, nil, "-livret", "-deposit", "10000", "-interval", "1month", "-from", "2015-12-31", "-to", "2016-01-31")
	for _, want := range []string{`"source": "livret-a"`, `["2015-12-31", 10000]`, `["2016-01-31", 10003.125]`} {
		if !strings.Contains(written, want) {
			t.Errorf("dataset lacks %s:\n%s", want, written)
		}
	}
}

func TestFreezeAnAssetNeedsTheKey(t *testing.T) {
	pack := t.TempDir()
	os.WriteFile(filepath.Join(pack, "island.json"), []byte("{}"), 0o644)
	var out, errs bytes.Buffer
	code := run(context.Background(), []string{"-pack", pack, "-id", "x", "-asset", "apple", "-from", "2022-01-03",
		"-to", "2022-01-07"}, nil, nil, time.Now(), &out, &errs)
	if code == 0 || !strings.Contains(errs.String(), "TWELVEDATA_API_KEY") {
		t.Errorf("exit %d: %s", code, errs.String())
	}
}
