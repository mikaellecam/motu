// Command logos fetches the company logo of every stock in the catalogue
// into the app's bundle (M9-29), so the app shows them offline and never
// calls the provider itself. ETFs keep their two letters. Reads
// TWELVEDATA_API_KEY from the environment (.env); one provider call per
// stock, paced for the free plan (8 a minute). Logos already in the folder
// are kept, so a run stopped halfway picks up where it was; -force fetches
// them all again.
//
//	logos -out ../app/assets/logos
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"finance-companion/backend/internal/catalogue"
	"finance-companion/backend/internal/provider"
)

// logoSource gives the address of a symbol's logo.
type logoSource interface {
	Logo(ctx context.Context, symbol string) (string, error)
}

func main() {
	key := os.Getenv("TWELVEDATA_API_KEY")
	if key == "" {
		fmt.Fprintln(os.Stderr, "logos: TWELVEDATA_API_KEY is not set (.env)")
		os.Exit(2)
	}
	client := &http.Client{Timeout: 30 * time.Second}
	os.Exit(run(context.Background(), os.Args[1:], provider.NewTwelveData(key), client, os.Stdout, os.Stderr))
}

func run(ctx context.Context, args []string, logos logoSource, client *http.Client, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("logos", flag.ContinueOnError)
	flags.SetOutput(stderr)
	out := flags.String("out", "../app/assets/logos", "the app's logo folder")
	every := flags.Duration("every", 8*time.Second, "pause between provider calls (free plan: 8 a minute)")
	force := flags.Bool("force", false, "fetch the logos already in the folder again")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if err := os.MkdirAll(*out, 0o755); err != nil {
		fmt.Fprintln(stderr, "logos:", err)
		return 1
	}
	count, calls := 0, 0
	for _, a := range catalogue.Assets {
		if a.Type != "stock" {
			continue
		}
		path := filepath.Join(*out, a.ID+".jpg")
		if _, err := os.Stat(path); err == nil && !*force {
			continue
		}
		if calls > 0 {
			select {
			case <-ctx.Done():
				return 1
			case <-time.After(*every):
			}
		}
		calls++
		image, err := fetch(ctx, logos, client, a.ProviderSymbol)
		if err != nil {
			fmt.Fprintf(stderr, "logos: %s: %v\n", a.ID, err)
			return 1
		}
		if err := os.WriteFile(path, image, 0o644); err != nil {
			fmt.Fprintln(stderr, "logos:", err)
			return 1
		}
		count++
	}
	fmt.Fprintf(stdout, "%d logos fetched into %s\n", count, *out)
	return 0
}

// fetch downloads a symbol's logo; anything but an image is refused.
func fetch(ctx context.Context, logos logoSource, client *http.Client, symbol string) ([]byte, error) {
	address, err := logos.Logo(ctx, symbol)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, address, nil)
	if err != nil {
		return nil, err
	}
	res, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	image, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}
	if res.StatusCode != http.StatusOK || !strings.HasPrefix(http.DetectContentType(image), "image/") {
		return nil, fmt.Errorf("%s is not an image (HTTP %d)", address, res.StatusCode)
	}
	return image, nil
}
