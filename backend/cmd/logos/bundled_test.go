//go:build realdata

// The fetched logos stay out of git (ADR-007), so this runs where they are:
// go test -tags realdata ./cmd/logos/ (after scripts/fetch-data.sh).
package main

import (
	"os"
	"path/filepath"
	"testing"

	"finance-companion/backend/internal/catalogue"
)

// The app bundles a logo for every stock of the catalogue: one added to the
// catalogue without its logo fails here (run scripts/fetch-data.sh).
func TestEveryStockHasABundledLogo(t *testing.T) {
	for _, a := range catalogue.Assets {
		if a.Type != "stock" {
			continue
		}
		if _, err := os.Stat(filepath.Join("..", "..", "..", "app", "assets", "logos", a.ID+".jpg")); err != nil {
			t.Errorf("%s: no bundled logo: scripts/fetch-data.sh", a.ID)
		}
	}
}
