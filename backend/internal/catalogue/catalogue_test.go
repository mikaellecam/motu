package catalogue

import (
	"strconv"
	"testing"
	"time"

	"finance-companion/backend/internal/store"
)

func TestCatalogue(t *testing.T) {
	if len(Assets) != 29 {
		t.Fatalf("%d assets", len(Assets))
	}
	ids, symbols := map[string]bool{}, map[string]bool{}
	allowed := map[string]map[string]bool{
		"Type":     {"etf": true, "stock": true},
		"Exchange": {"nyse": true, "nasdaq": true, "otc": true},
		"Region":   {"world": true, "us": true, "europe": true, "emerging": true},
	}
	for _, a := range Assets {
		if ids[a.ID] || symbols[a.ProviderSymbol] {
			t.Errorf("duplicate %s / %s", a.ID, a.ProviderSymbol)
		}
		ids[a.ID], symbols[a.ProviderSymbol] = true, true
		for field, value := range map[string]string{"Type": a.Type, "Exchange": a.Exchange, "Region": a.Region} {
			if !allowed[field][value] {
				t.Errorf("%s: %s %q", a.ID, field, value)
			}
		}
		if a.Currency != "USD" || a.ListingDate.IsZero() || a.Name == "" {
			t.Errorf("%s: incomplete %+v", a.ID, a)
		}
	}
	if !ids["world"] {
		t.Error("the world ETF (benchmark) is missing")
	}
}

func TestLivretHistory(t *testing.T) {
	floor := date("2000-01-03")
	for _, series := range [][]time.Time{livretDates(LivretRates), ceilingDates(LivretCeilings)} {
		if series[0].After(floor) {
			t.Errorf("starts %s, after the data floor", series[0].Format(time.DateOnly))
		}
		for i := 1; i < len(series); i++ {
			if !series[i].After(series[i-1]) {
				t.Errorf("%s is out of order", series[i].Format(time.DateOnly))
			}
		}
	}
	for _, r := range LivretRates {
		if _, err := strconv.ParseFloat(r.AnnualRate, 64); err != nil || r.AnnualRate[:2] != "0." {
			t.Errorf("%s: rate %q", r.ValidFrom.Format(time.DateOnly), r.AnnualRate)
		}
	}
}

func livretDates(rates []store.LivretRate) (out []time.Time) {
	for _, r := range rates {
		out = append(out, r.ValidFrom)
	}
	return
}

func ceilingDates(ceilings []store.LivretCeiling) (out []time.Time) {
	for _, c := range ceilings {
		out = append(out, c.ValidFrom)
	}
	return
}
