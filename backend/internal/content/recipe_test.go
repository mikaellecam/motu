package content

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestARecipeSaysHowToFreezeItsDataset(t *testing.T) {
	for name, c := range map[string]struct {
		recipe Recipe
		want   string
	}{
		"an asset":             {Recipe{ID: "ds.a", Asset: "apple", Interval: "1week", From: "2022-01-01", To: "2022-12-31"}, ""},
		"an asset in euros":    {Recipe{ID: "ds.a", Asset: "coca-cola", Currency: "EUR", Interval: "1week", From: "2017-01-01", To: "2017-12-31"}, ""},
		"the dollar":           {Recipe{ID: "ds.a", FX: "USD", Interval: "1week", From: "2017-01-01", To: "2017-12-31"}, ""},
		"a livret":             {Recipe{ID: "ds.a", Livret: true, Deposit: 10000, Interval: "1month", From: "2015-12-31", To: "2026-09-30"}, ""},
		"cash":                 {Recipe{ID: "ds.a", Cash: true, Deposit: 10000, Interval: "1month", From: "2015-12-31", To: "2025-12-31"}, ""},
		"cash at prices":       {Recipe{ID: "ds.a", Cash: true, Deposit: 10000, CPI: true, Interval: "1month", From: "2015-12-31", To: "2025-12-31"}, ""},
		"a livret at prices":   {Recipe{ID: "ds.a", Livret: true, Deposit: 10000, CPI: true, Interval: "1month", From: "2021-12-31", To: "2024-12-31"}, ""},
		"cash, no deposit":     {Recipe{ID: "ds.a", Cash: true, Interval: "1month", From: "2016-01-01", To: "2016-12-31"}, "deposit is not positive"},
		"an asset at prices":   {Recipe{ID: "ds.a", Asset: "apple", CPI: true, Interval: "1month", From: "2022-01-01", To: "2022-12-31"}, "cpi goes with cash or livret"},
		"prices, by the week":  {Recipe{ID: "ds.a", Cash: true, Deposit: 10, CPI: true, Interval: "1week", From: "2022-01-03", To: "2022-02-07"}, "cpi: only 1month"},
		"no id":                {Recipe{Asset: "apple", Interval: "1day", From: "2022-01-03", To: "2022-01-07"}, "id is empty"},
		"no kind":              {Recipe{ID: "ds.a", Interval: "1day", From: "2022-01-03", To: "2022-01-07"}, "one of asset, fx, livret and cash"},
		"two kinds":            {Recipe{ID: "ds.a", Asset: "apple", Livret: true, Deposit: 1, Interval: "1day", From: "2022-01-03", To: "2022-01-07"}, "one of asset, fx, livret and cash"},
		"another currency":     {Recipe{ID: "ds.a", Asset: "apple", Currency: "GBP", Interval: "1day", From: "2022-01-03", To: "2022-01-07"}, "currency: only EUR"},
		"a currency, no asset": {Recipe{ID: "ds.a", FX: "USD", Currency: "EUR", Interval: "1day", From: "2022-01-03", To: "2022-01-07"}, "currency goes with asset"},
		"another dollar":       {Recipe{ID: "ds.a", FX: "GBP", Interval: "1day", From: "2022-01-03", To: "2022-01-07"}, "fx: only USD"},
		"a livret, no deposit": {Recipe{ID: "ds.a", Livret: true, Interval: "1month", From: "2016-01-01", To: "2016-12-31"}, "deposit is not positive"},
		"a deposit, no livret": {Recipe{ID: "ds.a", Asset: "apple", Deposit: 10, Interval: "1day", From: "2022-01-03", To: "2022-01-07"}, "deposit goes with livret or cash"},
		"an unknown interval":  {Recipe{ID: "ds.a", Asset: "apple", Interval: "1hour", From: "2022-01-03", To: "2022-01-07"}, `interval "1hour"`},
		"a bad day":            {Recipe{ID: "ds.a", Asset: "apple", Interval: "1day", From: "03/01/2022", To: "2022-01-07"}, `from "03/01/2022" is not a day`},
		"backwards":            {Recipe{ID: "ds.a", Asset: "apple", Interval: "1day", From: "2022-01-07", To: "2022-01-03"}, "after to"},
	} {
		if got := c.recipe.Problem(); (c.want == "") != (got == "") || !strings.Contains(got, c.want) {
			t.Errorf("%s: problem %q, want %q", name, got, c.want)
		}
	}
}

func TestWriteRecipeAddsOrReplacesByID(t *testing.T) {
	dir := t.TempDir()
	recipes, err := ReadRecipes(dir)
	if err != nil || recipes != nil {
		t.Fatalf("no file yet: %v %v", recipes, err)
	}
	b := Recipe{ID: "ds.b", FX: "USD", Interval: "1week", From: "2017-01-01", To: "2017-12-31"}
	a := Recipe{ID: "ds.a", Asset: "apple", Interval: "1week", From: "2022-01-01", To: "2022-12-31"}
	for _, r := range []Recipe{b, a} {
		if err := WriteRecipe(dir, r); err != nil {
			t.Fatal(err)
		}
	}
	a.To = "2022-06-30"
	if err := WriteRecipe(dir, a); err != nil {
		t.Fatal(err)
	}
	recipes, err = ReadRecipes(dir)
	if err != nil || len(recipes) != 2 || recipes[0] != a || recipes[1] != b {
		t.Errorf("sorted by id, the second write replaced the first: %+v %v", recipes, err)
	}
	raw, _ := os.ReadFile(filepath.Join(dir, RecipesFile))
	if want := `[
  {"id":"ds.a","asset":"apple","interval":"1week","from":"2022-01-01","to":"2022-06-30"},
  {"id":"ds.b","fx":"USD","interval":"1week","from":"2017-01-01","to":"2017-12-31"}
]
`; string(raw) != want {
		t.Errorf("one recipe per line:\n%s", raw)
	}
}

func TestReadRecipesRefusesWhatItCannotRead(t *testing.T) {
	for name, body := range map[string]string{
		"not JSON":         "[",
		"not a list":       `{"id": "ds.a"}`,
		"an unknown field": `[{"id": "ds.a", "asset": "apple", "symbol": "AAPL"}]`,
	} {
		dir := t.TempDir()
		os.WriteFile(filepath.Join(dir, RecipesFile), []byte(body), 0o644)
		if _, err := ReadRecipes(dir); err == nil {
			t.Errorf("%s: read", name)
		}
	}
}
