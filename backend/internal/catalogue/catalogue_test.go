package catalogue

import "testing"

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
