package content

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"finance-companion/backend/internal/store"
)

func day(s string) time.Time {
	t, err := time.Parse(time.DateOnly, s)
	if err != nil {
		panic(err)
	}
	return t
}

func bars(closes ...string) []store.Bar {
	var out []store.Bar
	for i := 0; i+1 < len(closes); i += 2 {
		out = append(out, store.Bar{Date: day(closes[i]), Close: closes[i+1]})
	}
	return out
}

var appleAsset = store.Asset{ID: "apple", ProviderSymbol: "AAPL", Currency: "USD"}

func points(t *testing.T, d Dataset) string {
	t.Helper()
	var out []string
	for _, p := range d.Points {
		out = append(out, p.Date.Format(time.DateOnly)+"="+p.Value)
	}
	return strings.Join(out, " ")
}

func spec(interval, from, to string) Spec {
	return Spec{ID: "ds.aapl", Asset: appleAsset, Interval: interval, From: day(from), To: day(to)}
}

func TestFreezeKeepsTheDailyClosesOfTheRange(t *testing.T) {
	d, err := Freeze(spec("1day", "2022-01-04", "2022-01-05"), bars(
		"2022-01-03", "182.01000", "2022-01-04", "179.70", "2022-01-05", "174.920", "2022-01-06", "172.00",
	), day("2026-10-11"))
	if err != nil {
		t.Fatal(err)
	}
	if got := points(t, d); got != "2022-01-04=179.7 2022-01-05=174.92" {
		t.Errorf("points: %s", got)
	}
	if d.Source != "twelvedata" || !d.Adjusted || d.Currency != "USD" || d.Symbol != "AAPL" || d.Asset != "apple" {
		t.Errorf("provenance: %+v", d)
	}
}

func TestFreezeWeekly_TheLastCloseOfEachWeek(t *testing.T) {
	d, err := Freeze(spec("1week", "2019-12-30", "2021-01-08"), bars(
		// One ISO week across New Year: 2020-W01.
		"2019-12-30", "1", "2019-12-31", "2", "2020-01-03", "3",
		// A week whose Friday is a holiday.
		"2020-04-06", "4", "2020-04-09", "5",
		// 2020-12-31 is in 2020-W53; 2021-01-04 starts 2021-W01.
		"2020-12-31", "6", "2021-01-04", "7", "2021-01-08", "8",
	), day("2026-10-11"))
	if err != nil {
		t.Fatal(err)
	}
	if got := points(t, d); got != "2020-01-03=3 2020-04-09=5 2020-12-31=6 2021-01-08=8" {
		t.Errorf("points: %s", got)
	}
}

func TestFreezeMonthly_TheLastCloseOfEachMonth(t *testing.T) {
	d, err := Freeze(spec("1month", "2022-01-01", "2022-03-31"), bars(
		"2022-01-28", "1", "2022-01-31", "2", "2022-02-25", "3", "2022-03-01", "4",
	), day("2026-10-11"))
	if err != nil {
		t.Fatal(err)
	}
	if got := points(t, d); got != "2022-01-31=2 2022-02-25=3 2022-03-01=4" {
		t.Errorf("points: %s", got)
	}
}

func TestFreezeRefuses(t *testing.T) {
	for name, c := range map[string]struct {
		spec Spec
		bars []store.Bar
		want string
	}{
		"no bar in the range": {spec("1day", "2022-01-01", "2022-01-02"), bars("2022-01-03", "1"), "no close"},
		"an inverted range":   {spec("1day", "2022-02-01", "2022-01-01"), bars("2022-01-03", "1"), "after"},
		"an unknown interval": {spec("1hour", "2022-01-01", "2022-12-31"), bars("2022-01-03", "1"), "interval"},
		"a close that is not a number": {spec("1day", "2022-01-01", "2022-12-31"),
			bars("2022-01-03", "1,5"), "not a number"},
		"a negative close": {spec("1day", "2022-01-01", "2022-12-31"), bars("2022-01-03", "-1"), "not a number"},
	} {
		if _, err := Freeze(c.spec, c.bars, day("2026-10-11")); err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: %v", name, err)
		}
	}
}

func TestAFrozenDatasetPassesTheCheck(t *testing.T) {
	d, err := Freeze(spec("1week", "2022-01-03", "2022-01-14"), bars(
		"2022-01-07", "172.17", "2022-01-14", "173.07",
	), day("2026-10-11"))
	if err != nil {
		t.Fatal(err)
	}
	encoded := string(d.Encode())
	for _, want := range []string{
		`"frozen_at": "2026-10-11"`, `"from": "2022-01-03"`, `"interval": "1week"`,
		"    [\"2022-01-07\", 172.17],\n    [\"2022-01-14\", 173.07]\n",
	} {
		if !strings.Contains(encoded, want) {
			t.Errorf("encoded lacks %q:\n%s", want, encoded)
		}
	}
	ref := pack(t, nil)
	if err := os.WriteFile(filepath.Join(ref.Dir, "datasets", "ds.aapl.json"), d.Encode(), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := problems(t, ref, true); got != "" {
		t.Errorf("problems: %s", got)
	}
}
