// Command freeze writes a frozen dataset into a content pack (BRIEF §4.3,
// §9): an asset's adjusted closes from the market data provider, with their
// provenance. It reads TWELVEDATA_API_KEY from the environment (.env) and
// spends one provider credit per 15 years of data.
//
//	freeze -pack ../content/packs/actions-etf/1 -id ds.aapl-2022-w \
//	  -asset apple -interval 1week -from 2022-01-01 -to 2022-12-31
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
	"finance-companion/backend/internal/provider"
	"finance-companion/backend/internal/store"
)

func main() {
	key := os.Getenv("TWELVEDATA_API_KEY")
	if key == "" {
		fmt.Fprintln(os.Stderr, "freeze: TWELVEDATA_API_KEY is not set (backend/.env)")
		os.Exit(2)
	}
	os.Exit(run(context.Background(), os.Args[1:], provider.NewTwelveData(key), time.Now(), os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, market provider.Provider, now time.Time, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("freeze", flag.ContinueOnError)
	flags.SetOutput(stderr)
	pack := flags.String("pack", "", "pack version directory, e.g. ../content/packs/actions-etf/1")
	id := flags.String("id", "", "dataset id, e.g. ds.aapl-2022-w")
	assetID := flags.String("asset", "", "catalogue asset id, e.g. apple")
	interval := flags.String("interval", "1day", fmt.Sprintf("one of %v", content.Intervals))
	from := flags.String("from", "", "first day, YYYY-MM-DD")
	to := flags.String("to", "", "last day, YYYY-MM-DD")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	fail := func(format string, a ...any) int {
		fmt.Fprintf(stderr, "freeze: "+format+"\n", a...)
		return 1
	}
	if *pack == "" || *id == "" || *assetID == "" || *from == "" || *to == "" {
		flags.Usage()
		return 2
	}
	if _, err := os.Stat(filepath.Join(*pack, "island.json")); err != nil {
		return fail("%s is not a pack version directory", *pack)
	}
	var asset *store.Asset
	for _, a := range catalogue.Assets {
		if a.ID == *assetID {
			asset = &a
		}
	}
	if asset == nil {
		return fail("%q is not a catalogue asset", *assetID)
	}
	start, err1 := time.Parse(time.DateOnly, *from)
	end, err2 := time.Parse(time.DateOnly, *to)
	if err1 != nil || err2 != nil {
		return fail("-from and -to are days, YYYY-MM-DD")
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
			return fail("%s: %v", asset.ProviderSymbol, err)
		}
		bars = append(bars, got...)
	}
	dataset, err := content.Freeze(content.Spec{
		ID: *id, Asset: *asset, Interval: *interval, From: start, To: end,
	}, bars, now.UTC())
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
