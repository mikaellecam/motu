package content

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"

	"finance-companion/backend/internal/store"
)

// Spec says what cmd/freeze freezes: an asset of the catalogue, at an
// interval, over [From, To].
type Spec struct {
	ID       string
	Asset    store.Asset
	Interval string
	From, To time.Time
}

// Dataset is a frozen series with its provenance (BRIEF §4.3, §9): real
// adjusted closes from the market data provider, never hand-typed.
type Dataset struct {
	ID       string
	Source   string
	Asset    string
	Symbol   string
	Adjusted bool
	Currency string
	// FX is the source of the rates the values were converted with ("ecb");
	// empty when they are as published.
	FX       string
	Interval string
	From, To time.Time
	FrozenAt time.Time
	Points   []Point
}

// Point is a close, digits as the provider gave them.
type Point struct {
	Date  time.Time
	Value string
}

var decimalNumber = regexp.MustCompile(`^\d+(\.\d+)?$`)

// Freeze keeps the closes of the adjusted daily [bars] in [spec.From,
// spec.To]: every one for "1day", else the last close of each ISO week or
// calendar month, dated by the day of that close.
func Freeze(spec Spec, bars []store.Bar, frozenAt time.Time) (Dataset, error) {
	if err := checkRange(spec.Interval, spec.From, spec.To); err != nil {
		return Dataset{}, err
	}
	sorted := slices.Clone(bars)
	slices.SortFunc(sorted, func(a, b store.Bar) int { return a.Date.Compare(b.Date) })

	var daily []Point
	for _, bar := range sorted {
		if bar.Date.Before(spec.From) || bar.Date.After(spec.To) {
			continue
		}
		if !decimalNumber.MatchString(bar.Close) {
			return Dataset{}, fmt.Errorf("close %q of %s is not a number", bar.Close, bar.Date.Format(time.DateOnly))
		}
		daily = append(daily, Point{bar.Date, trimZeros(bar.Close)})
	}
	points := bucket(daily, spec.Interval)
	if len(points) == 0 {
		return Dataset{}, fmt.Errorf("no close of %s between %s and %s", spec.Asset.ProviderSymbol,
			spec.From.Format(time.DateOnly), spec.To.Format(time.DateOnly))
	}
	return Dataset{
		ID: spec.ID, Source: "twelvedata", Asset: spec.Asset.ID, Symbol: spec.Asset.ProviderSymbol,
		Adjusted: true, Currency: spec.Asset.Currency, Interval: spec.Interval,
		From: spec.From, To: spec.To, FrozenAt: frozenAt, Points: points,
	}, nil
}

func checkRange(interval string, from, to time.Time) error {
	if !slices.Contains(Intervals, interval) {
		return fmt.Errorf("interval %q is not one of %v", interval, Intervals)
	}
	if from.After(to) {
		return fmt.Errorf("from %s is after to %s", from.Format(time.DateOnly), to.Format(time.DateOnly))
	}
	return nil
}

// bucket keeps the last of the daily points (oldest first) of each period.
func bucket(daily []Point, interval string) []Point {
	var points []Point
	var lastPeriod string
	for _, p := range daily {
		period := periodOf(p.Date, interval)
		if len(points) > 0 && period == lastPeriod {
			points[len(points)-1] = p
		} else {
			points = append(points, p)
		}
		lastPeriod = period
	}
	return points
}

// periodOf names the bucket a day falls in; every day is its own for 1day.
func periodOf(d time.Time, interval string) string {
	switch interval {
	case "1week":
		year, week := d.ISOWeek()
		return fmt.Sprintf("%d-W%02d", year, week)
	case "1month":
		return d.Format("2006-01")
	}
	return d.Format(time.DateOnly)
}

// trimZeros drops the trailing zeros of a decimal: "182.01000" → "182.01".
func trimZeros(s string) string {
	if !strings.Contains(s, ".") {
		return s
	}
	return strings.TrimSuffix(strings.TrimRight(s, "0"), ".")
}

// Encode writes the dataset as the pack's datasets/<id>.json: one field per
// line, one point per line. A series that is not an asset's leaves out asset
// and symbol; fx only when the values were converted.
func (d Dataset) Encode() []byte {
	var b bytes.Buffer
	b.WriteString("{\n")
	for _, f := range []struct {
		key   string
		value any
	}{
		{"id", d.ID}, {"source", d.Source}, {"asset", d.Asset}, {"symbol", d.Symbol},
		{"adjusted", d.Adjusted}, {"currency", d.Currency}, {"fx", d.FX}, {"interval", d.Interval},
		{"from", d.From.Format(time.DateOnly)}, {"to", d.To.Format(time.DateOnly)},
		{"frozen_at", d.FrozenAt.Format(time.DateOnly)},
	} {
		if f.value == "" {
			continue
		}
		value, _ := json.Marshal(f.value)
		fmt.Fprintf(&b, "  %q: %s,\n", f.key, value)
	}
	b.WriteString("  \"points\": [\n")
	for i, p := range d.Points {
		separator := ","
		if i == len(d.Points)-1 {
			separator = ""
		}
		fmt.Fprintf(&b, "    [%q, %s]%s\n", p.Date.Format(time.DateOnly), p.Value, separator)
	}
	b.WriteString("  ]\n}\n")
	return b.Bytes()
}
