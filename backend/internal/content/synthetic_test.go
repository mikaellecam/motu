package content

import (
	"bytes"
	"math/big"
	"testing"
	"time"

	"finance-companion/backend/internal/store"
)

func TestSyntheticKeepsTheShapeOfTheRealDataset(t *testing.T) {
	frozen := day("2026-10-27")
	for name, c := range map[string]struct {
		recipe               Recipe
		asset                store.Asset
		symbol, currency, fx string
		adjusted             bool
		first, last          string
		points               int
	}{
		// 2022-04-15 is a Friday: a weekly series closes on it, holidays aside.
		"an asset, weekly": {Recipe{ID: "ds.a", Asset: "apple", Interval: "1week", From: "2022-04-01", To: "2022-04-30"},
			appleAsset, "AAPL", "USD", "", true, "2022-04-01", "2022-04-29", 5},
		"an asset in euros, daily": {Recipe{ID: "ds.a", Asset: "apple", Currency: "EUR", Interval: "1day", From: "2022-04-15", To: "2022-04-19"},
			appleAsset, "AAPL", "EUR", "ecb", true, "2022-04-15", "2022-04-19", 3},
		"the dollar, monthly": {Recipe{ID: "ds.a", FX: "USD", Interval: "1month", From: "2016-12-30", To: "2017-03-31"},
			store.Asset{}, "USD/EUR", "EUR", "", false, "2016-12-30", "2017-03-31", 4},
		// April 2017 ends on a Sunday: its last weekday is the 28th.
		"a livret, monthly": {Recipe{ID: "ds.a", Livret: true, Deposit: 10000, Interval: "1month", From: "2017-04-01", To: "2017-05-31"},
			store.Asset{}, "", "EUR", "", false, "2017-04-28", "2017-05-31", 2},
	} {
		d, err := Synthetic(c.recipe, c.asset, frozen)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if d.Source != "synthetic" || d.ID != "ds.a" || d.Symbol != c.symbol || d.Currency != c.currency ||
			d.FX != c.fx || d.Adjusted != c.adjusted || d.Interval != c.recipe.Interval || !d.FrozenAt.Equal(frozen) {
			t.Errorf("%s: %+v", name, d)
		}
		if len(d.Points) != c.points || d.Points[0].Date.Format(time.DateOnly) != c.first ||
			d.Points[len(d.Points)-1].Date.Format(time.DateOnly) != c.last {
			t.Errorf("%s: %d points, %v", name, len(d.Points), d.Points)
		}
		for _, p := range d.Points {
			if p.Date.Weekday() == time.Saturday || p.Date.Weekday() == time.Sunday {
				t.Errorf("%s: a weekend close %v", name, p.Date)
			}
			if !decimalNumber.MatchString(p.Value) || p.Value == "0" {
				t.Errorf("%s: value %q", name, p.Value)
			}
		}
	}
}

func TestSyntheticIsTheSameEveryRunAndDiffersByID(t *testing.T) {
	r := Recipe{ID: "ds.a", Asset: "apple", Interval: "1day", From: "2020-01-01", To: "2020-12-31"}
	a, _ := Synthetic(r, appleAsset, day("2026-10-27"))
	again, _ := Synthetic(r, appleAsset, day("2026-10-27"))
	if !bytes.Equal(a.Encode(), again.Encode()) {
		t.Error("two runs differ")
	}
	r.ID = "ds.b"
	b, _ := Synthetic(r, appleAsset, day("2026-10-27"))
	if a.Points[100].Value == b.Points[100].Value && a.Points[200].Value == b.Points[200].Value {
		t.Error("two datasets walk the same way")
	}
}

func TestASyntheticLivretOnlyGrows(t *testing.T) {
	d, _ := Synthetic(Recipe{ID: "ds.l", Livret: true, Deposit: 10000, Interval: "1day", From: "2016-01-01", To: "2016-12-31"},
		store.Asset{}, day("2026-10-27"))
	if d.Points[0].Value != "10000" {
		t.Errorf("starts at the deposit: %s", d.Points[0].Value)
	}
	for i := 1; i < len(d.Points); i++ {
		if rat(d.Points[i].Value).Cmp(rat(d.Points[i-1].Value)) <= 0 {
			t.Fatalf("%v then %v", d.Points[i-1], d.Points[i])
		}
	}
}

func TestSyntheticCash_FlatOrFallingAtPrices(t *testing.T) {
	r := Recipe{ID: "ds.c", Cash: true, Deposit: 10000, Interval: "1month", From: "2016-01-01", To: "2016-12-31"}
	flat, _ := Synthetic(r, store.Asset{}, day("2026-10-27"))
	r.CPI = true
	prices, _ := Synthetic(r, store.Asset{}, day("2026-10-27"))
	if flat.Prices != "" || prices.Prices != "insee" || prices.Source != "synthetic" {
		t.Errorf("provenance: %+v %+v", flat, prices)
	}
	for i, p := range flat.Points {
		if p.Value != "10000" || (i > 0 && rat(prices.Points[i].Value).Cmp(rat(prices.Points[i-1].Value)) >= 0) {
			t.Fatalf("month %d: %v, %v", i, p, prices.Points[i])
		}
	}
}

func TestSyntheticRefuses(t *testing.T) {
	for name, c := range map[string]struct {
		recipe Recipe
		asset  store.Asset
	}{
		"a bad recipe":   {Recipe{ID: "ds.a", Interval: "1day", From: "2022-01-03", To: "2022-01-07"}, store.Asset{}},
		"only a weekend": {Recipe{ID: "ds.a", Asset: "apple", Interval: "1day", From: "2022-01-08", To: "2022-01-09"}, appleAsset},
		"no asset given": {Recipe{ID: "ds.a", Asset: "apple", Interval: "1day", From: "2022-01-03", To: "2022-01-07"}, store.Asset{}},
	} {
		if _, err := Synthetic(c.recipe, c.asset, day("2026-10-27")); err == nil {
			t.Errorf("%s: made up", name)
		}
	}
}

func rat(s string) *big.Rat {
	r, _ := new(big.Rat).SetString(s)
	return r
}
