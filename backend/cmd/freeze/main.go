// Command freeze writes a frozen dataset into a content pack (BRIEF §4.3,
// §9), with its provenance, and records its recipe in the pack's
// datasets.json (ADR-007). One of:
//
//   - -asset: an asset's adjusted closes from the market data provider; with
//     -currency EUR, each converted at the ECB rate of its day (Frankfurter).
//     Reads TWELVEDATA_API_KEY from the environment (.env) and spends one
//     provider credit per 15 years of data.
//
//   - -fx USD: what one dollar was worth in euros (ECB rates).
//
//   - -livret: a Livret A holding of -deposit euros put in on -from, from the
//     rate history of the catalogue.
//
//   - -cash: -deposit euros kept as notes from -from.
//
//     With -cpi, a Livret or cash is restated each month in euros of -from's
//     month, at INSEE's consumer prices (no key): what it buys.
//
//     freeze -pack ../content/packs/actions-etf/1 -id ds.aapl-2022-w \
//     -asset apple -interval 1week -from 2022-01-01 -to 2022-12-31
//
// Or -recipes: every dataset the recipes of a content directory list and its
// packs miss, as git leaves them (a made-up one counts as missing). With
// -synthetic, made-up prices instead, without the provider: for CI only. With
// -prune, a dataset no recipe lists is removed, as after an upgrade dropped
// its recipe (the backend image's start does it).
//
//	freeze -recipes ../content [-synthetic] [-prune]
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"finance-companion/backend/internal/catalogue"
	"finance-companion/backend/internal/content"
	"finance-companion/backend/internal/fx"
	"finance-companion/backend/internal/insee"
	"finance-companion/backend/internal/provider"
	"finance-companion/backend/internal/store"
)

func main() {
	// Only -asset reaches the provider: without a key, it says so.
	var market provider.Provider
	if key := os.Getenv("TWELVEDATA_API_KEY"); key != "" {
		market = provider.NewTwelveData(key)
	}
	os.Exit(run(context.Background(), os.Args[1:], market, fx.NewFrankfurter(), insee.New(), time.Now(),
		os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, market provider.Provider, rates fx.Source, prices insee.Source,
	now time.Time, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("freeze", flag.ContinueOnError)
	flags.SetOutput(stderr)
	pack := flags.String("pack", "", "pack version directory, e.g. ../content/packs/actions-etf/1")
	id := flags.String("id", "", "dataset id, e.g. ds.aapl-2022-w")
	assetID := flags.String("asset", "", "catalogue asset id, e.g. apple")
	interval := flags.String("interval", "1day", fmt.Sprintf("one of %v", content.Intervals))
	from := flags.String("from", "", "first day, YYYY-MM-DD")
	to := flags.String("to", "", "last day, YYYY-MM-DD")
	currency := flags.String("currency", "", "with -asset: EUR converts the closes at ECB rates")
	dollar := flags.String("fx", "", "USD: what one dollar was worth in euros")
	livret := flags.Bool("livret", false, "a Livret A holding of -deposit euros put in on -from")
	cash := flags.Bool("cash", false, "-deposit euros kept as notes from -from")
	deposit := flags.Int64("deposit", 10000, "with -livret or -cash: euros put in")
	cpi := flags.Bool("cpi", false, "with -livret or -cash: in euros of -from's month, at INSEE consumer prices")
	recipes := flags.String("recipes", "", "content directory: freeze the datasets its recipes list and its packs miss")
	synthetic := flags.Bool("synthetic", false, "with -recipes: made-up prices, without the provider (CI only)")
	prune := flags.Bool("prune", false, "with -recipes: remove the datasets no recipe lists")
	every := flags.Duration("every", 8*time.Second, "with -recipes: pause between provider calls (free plan: 8 a minute)")
	retry := flags.Duration("retry", 65*time.Second, "with -recipes: after the provider's per-minute limit, wait this long and try again")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	fail := func(format string, a ...any) int {
		fmt.Fprintf(stderr, "freeze: "+format+"\n", a...)
		return 1
	}
	if *recipes != "" {
		if market != nil {
			market = &paced{Provider: market, every: *every, retry: *retry}
		}
		return runRecipes(ctx, *recipes, *synthetic, *prune, market, rates, prices, now, stdout, stderr)
	}
	if *synthetic || *prune {
		fmt.Fprintln(stderr, "freeze: -synthetic and -prune go with -recipes")
		return 2
	}
	modes := 0
	for _, set := range []bool{*assetID != "", *dollar != "", *livret, *cash} {
		if set {
			modes++
		}
	}
	if *pack == "" || *id == "" || *from == "" || *to == "" || modes != 1 {
		fmt.Fprintln(stderr, "freeze: one of -asset, -fx, -livret and -cash, with -pack, -id, -from and -to")
		flags.Usage()
		return 2
	}
	if _, err := os.Stat(filepath.Join(*pack, "island.json")); err != nil {
		return fail("%s is not a pack version directory", *pack)
	}
	if _, err1 := time.Parse(time.DateOnly, *from); err1 != nil {
		return fail("-from and -to are days, YYYY-MM-DD")
	}
	if _, err2 := time.Parse(time.DateOnly, *to); err2 != nil {
		return fail("-from and -to are days, YYYY-MM-DD")
	}
	if *dollar != "" && *dollar != "USD" {
		return fail("-fx: only USD")
	}
	if *currency != "" && *currency != "EUR" {
		return fail("-currency: only EUR")
	}
	recipe := content.Recipe{ID: *id, Asset: *assetID, Currency: *currency, FX: *dollar, Livret: *livret,
		Cash: *cash, CPI: *cpi, Interval: *interval, From: *from, To: *to}
	if *livret || *cash {
		recipe.Deposit = *deposit
	}
	if p := recipe.Problem(); p != "" {
		return fail("%s", p)
	}

	dataset, err := freezeRecipe(ctx, recipe, market, rates, prices, now)
	if err != nil {
		return fail("%v", err)
	}
	path, err := write(*pack, dataset)
	if err != nil {
		return fail("%v", err)
	}
	if err := content.WriteRecipe(*pack, recipe); err != nil {
		return fail("%v", err)
	}
	fmt.Fprintf(stdout, "freeze: wrote %s (%d points), its recipe in %s\n", path, len(dataset.Points), content.RecipesFile)
	return 0
}

// runRecipes freezes, in every pack version under dir, each dataset its
// recipes list and git left out: a missing file, or a made-up one unless
// [synthetic] makes them up too. [prune] removes the datasets no recipe lists.
func runRecipes(ctx context.Context, dir string, synthetic, prune bool, market provider.Provider, rates fx.Source,
	prices insee.Source, now time.Time, stdout, stderr io.Writer) int {
	fail := func(format string, a ...any) int {
		fmt.Fprintf(stderr, "freeze: "+format+"\n", a...)
		return 1
	}
	refs, err := content.Find(dir)
	if err != nil {
		return fail("%v", err)
	}
	written := 0
	for _, ref := range refs {
		recipes, err := content.ReadRecipes(ref.Dir)
		if err != nil {
			return fail("%s/%d: %s: %v", ref.Island, ref.Version, content.RecipesFile, err)
		}
		for _, r := range recipes {
			if p := r.Problem(); p != "" {
				return fail("%s/%d: %s: %s", ref.Island, ref.Version, r.ID, p)
			}
			if source, ok := sourceOf(filepath.Join(ref.Dir, "datasets", r.ID+".json")); ok &&
				(synthetic || source != "synthetic") {
				continue
			}
			var dataset content.Dataset
			if synthetic {
				asset, _ := catalogueAsset(r.Asset)
				dataset, err = content.Synthetic(r, asset, now.UTC())
			} else {
				dataset, err = freezeRecipe(ctx, r, market, rates, prices, now)
			}
			if err != nil {
				return fail("%s/%d: %v", ref.Island, ref.Version, err)
			}
			path, err := write(ref.Dir, dataset)
			if err != nil {
				return fail("%v", err)
			}
			fmt.Fprintf(stdout, "freeze: wrote %s (%d points)\n", path, len(dataset.Points))
			written++
		}
		if prune {
			if err := pruneDatasets(ref.Dir, recipes, stdout); err != nil {
				return fail("%v", err)
			}
		}
	}
	fmt.Fprintf(stdout, "freeze: %d datasets written\n", written)
	return 0
}

// pruneDatasets removes the pack's datasets that none of its recipes list.
func pruneDatasets(packDir string, recipes []content.Recipe, stdout io.Writer) error {
	listed := map[string]bool{}
	for _, r := range recipes {
		listed[r.ID+".json"] = true
	}
	entries, err := os.ReadDir(filepath.Join(packDir, "datasets"))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".json" || listed[e.Name()] {
			continue
		}
		path := filepath.Join(packDir, "datasets", e.Name())
		if err := os.Remove(path); err != nil {
			return err
		}
		fmt.Fprintf(stdout, "freeze: removed %s (no recipe)\n", path)
	}
	return nil
}

// sourceOf reads the source of the dataset at path; false when there is none
// to read.
func sourceOf(path string) (string, bool) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	var head struct {
		Source string `json:"source"`
	}
	if json.Unmarshal(raw, &head) != nil {
		return "", false
	}
	return head.Source, true
}

// write puts the dataset in the pack's datasets folder and returns its path.
func write(packDir string, dataset content.Dataset) (string, error) {
	path := filepath.Join(packDir, "datasets", dataset.ID+".json")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return "", err
	}
	return path, os.WriteFile(path, dataset.Encode(), 0o644)
}

// freezeRecipe follows the recipe: real data from the provider, the ECB, the
// Livret A rate history or INSEE.
func freezeRecipe(ctx context.Context, r content.Recipe, market provider.Provider, rates fx.Source,
	prices insee.Source, now time.Time) (content.Dataset, error) {
	start, _ := time.Parse(time.DateOnly, r.From)
	end, _ := time.Parse(time.DateOnly, r.To)
	// ECB rates around the range: the one before its first day included.
	eurUSD := func() ([]store.Rate, error) {
		var all []store.Rate
		for chunk := start.AddDate(0, 0, -10); !chunk.After(end); chunk = chunk.AddDate(5, 0, 0) {
			last := chunk.AddDate(5, 0, -1)
			if last.After(end) {
				last = end
			}
			got, err := rates.Rates(ctx, "EUR", "USD", chunk, last)
			if err != nil {
				return nil, err
			}
			all = append(all, got...)
		}
		return all, nil
	}

	switch {
	case r.Livret, r.Cash:
		held, err := content.Cash(r.ID, r.Deposit*100, r.Interval, start, end, now.UTC())
		if r.Livret {
			held, err = content.Livret(r.ID, catalogue.LivretRates, r.Deposit*100, r.Interval, start, end, now.UTC())
		}
		if err != nil || !r.CPI {
			return held, err
		}
		index, err := prices.ConsumerPrices(ctx, start, end)
		if err != nil {
			return content.Dataset{}, err
		}
		return content.InEurosOf(held, index)
	case r.FX != "":
		rs, err := eurUSD()
		if err != nil {
			return content.Dataset{}, err
		}
		return content.DollarInEuros(r.ID, rs, r.Interval, start, end, now.UTC())
	}
	dataset, err := freezeAsset(ctx, market, r.Asset, r.ID, r.Interval, start, end, now)
	if err != nil || r.Currency == "" {
		return dataset, err
	}
	rs, err := eurUSD()
	if err != nil {
		return content.Dataset{}, err
	}
	return content.ToEuros(dataset, rs)
}

func catalogueAsset(id string) (store.Asset, bool) {
	for _, a := range catalogue.Assets {
		if a.ID == id {
			return a, true
		}
	}
	return store.Asset{}, false
}

// freezeAsset reads an asset's closes from the provider, in windows of its
// longest call.
func freezeAsset(ctx context.Context, market provider.Provider, assetID, id, interval string,
	start, end, now time.Time) (content.Dataset, error) {
	asset, ok := catalogueAsset(assetID)
	if !ok {
		return content.Dataset{}, fmt.Errorf("%q is not a catalogue asset", assetID)
	}
	if market == nil {
		return content.Dataset{}, fmt.Errorf("TWELVEDATA_API_KEY is not set (backend/.env)")
	}

	// The provider caps the range of one call.
	var bars []store.Bar
	for chunk := start; !chunk.After(end); chunk = chunk.AddDate(0, 0, market.MaxDays()) {
		last := chunk.AddDate(0, 0, market.MaxDays()-1)
		if last.After(end) {
			last = end
		}
		got, err := market.History(ctx, asset.ProviderSymbol, chunk, last)
		if err != nil {
			return content.Dataset{}, fmt.Errorf("%s: %w", asset.ProviderSymbol, err)
		}
		bars = append(bars, got...)
	}
	return content.Freeze(content.Spec{ID: id, Asset: asset, Interval: interval, From: start, To: end}, bars, now.UTC())
}

// paced waits [every] between two History calls, so that freezing every
// recipe stays within the plan's credits per minute. Others spend those
// credits too (cmd/logos, a running server): a call refused for the rate
// waits [retry] and goes again, three tries in all.
type paced struct {
	provider.Provider
	every, retry time.Duration
	calls        int
}

func (p *paced) History(ctx context.Context, symbol string, from, to time.Time) ([]store.Bar, error) {
	if p.calls > 0 {
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(p.every):
		}
	}
	p.calls++
	var bars []store.Bar
	err := provider.WaitOutRateLimit(ctx, p.retry, 3, func() (err error) {
		bars, err = p.Provider.History(ctx, symbol, from, to)
		return err
	})
	return bars, err
}
