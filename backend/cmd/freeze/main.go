// Command freeze writes a frozen dataset into a content pack (BRIEF §4.3,
// §9), with its provenance. One of:
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
//     freeze -pack ../content/packs/actions-etf/1 -id ds.aapl-2022-w \
//     -asset apple -interval 1week -from 2022-01-01 -to 2022-12-31
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"finance-companion/backend/internal/catalogue"
	"finance-companion/backend/internal/content"
	"finance-companion/backend/internal/fx"
	"finance-companion/backend/internal/provider"
	"finance-companion/backend/internal/store"
)

func main() {
	// Only -asset reaches the provider: without a key, it says so.
	var market provider.Provider
	if key := os.Getenv("TWELVEDATA_API_KEY"); key != "" {
		market = provider.NewTwelveData(key)
	}
	os.Exit(run(context.Background(), os.Args[1:], market, fx.NewFrankfurter(), time.Now(), os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, market provider.Provider, rates fx.Source, now time.Time,
	stdout, stderr io.Writer) int {
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
	deposit := flags.Int64("deposit", 10000, "with -livret: euros put in")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	fail := func(format string, a ...any) int {
		fmt.Fprintf(stderr, "freeze: "+format+"\n", a...)
		return 1
	}
	modes := 0
	for _, set := range []bool{*assetID != "", *dollar != "", *livret} {
		if set {
			modes++
		}
	}
	if *pack == "" || *id == "" || *from == "" || *to == "" || modes != 1 {
		fmt.Fprintln(stderr, "freeze: one of -asset, -fx and -livret, with -pack, -id, -from and -to")
		flags.Usage()
		return 2
	}
	if _, err := os.Stat(filepath.Join(*pack, "island.json")); err != nil {
		return fail("%s is not a pack version directory", *pack)
	}
	start, err1 := time.Parse(time.DateOnly, *from)
	end, err2 := time.Parse(time.DateOnly, *to)
	if err1 != nil || err2 != nil {
		return fail("-from and -to are days, YYYY-MM-DD")
	}
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

	var dataset content.Dataset
	var err error
	switch {
	case *livret:
		dataset, err = content.Livret(*id, catalogue.LivretRates, *deposit*100, *interval, start, end, now.UTC())
	case *dollar != "":
		if *dollar != "USD" {
			return fail("-fx: only USD")
		}
		var r []store.Rate
		if r, err = eurUSD(); err == nil {
			dataset, err = content.DollarInEuros(*id, r, *interval, start, end, now.UTC())
		}
	default:
		dataset, err = freezeAsset(ctx, market, *assetID, *id, *interval, start, end, now)
		if err == nil && *currency != "" {
			if *currency != "EUR" {
				return fail("-currency: only EUR")
			}
			var r []store.Rate
			if r, err = eurUSD(); err == nil {
				dataset, err = content.ToEuros(dataset, r)
			}
		}
	}
	if err != nil {
		return fail("%v", err)
	}
	path := filepath.Join(*pack, "datasets", *id+".json")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fail("%v", err)
	}
	if err := os.WriteFile(path, dataset.Encode(), 0o644); err != nil {
		return fail("%v", err)
	}
	fmt.Fprintf(stdout, "freeze: wrote %s (%d points)\n", path, len(dataset.Points))
	return 0
}

// freezeAsset reads an asset's closes from the provider, in windows of its
// longest call.
func freezeAsset(ctx context.Context, market provider.Provider, assetID, id, interval string,
	start, end, now time.Time) (content.Dataset, error) {
	var asset *store.Asset
	for _, a := range catalogue.Assets {
		if a.ID == assetID {
			asset = &a
		}
	}
	if asset == nil {
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
	return content.Freeze(content.Spec{ID: id, Asset: *asset, Interval: interval, From: start, To: end}, bars, now.UTC())
}
