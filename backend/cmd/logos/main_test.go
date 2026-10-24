package main

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"finance-companion/backend/internal/catalogue"
)

// jpeg is enough of a JPEG for content sniffing.
var jpeg = []byte("\xff\xd8\xff\xe0\x00\x10JFIF\x00")

type fakeLogos map[string]string

func (f fakeLogos) Logo(_ context.Context, symbol string) (string, error) { return f[symbol], nil }

func TestEachStockGetsItsLogoAndEtfsKeepTheirLetters(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/not-an-image" {
			w.Write([]byte("<html>"))
			return
		}
		w.Write(jpeg)
	}))
	defer srv.Close()
	logos := fakeLogos{}
	for _, a := range catalogue.Assets {
		logos[a.ProviderSymbol] = srv.URL + "/" + a.ID
	}
	out := t.TempDir()
	var stdout, stderr bytes.Buffer
	if code := run(context.Background(), []string{"-out", out, "-every", "0"}, logos, srv.Client(), &stdout, &stderr); code != 0 {
		t.Fatalf("exit %d: %s", code, stderr.String())
	}
	for _, a := range catalogue.Assets {
		got, err := os.ReadFile(filepath.Join(out, a.ID+".jpg"))
		if a.Type == "etf" {
			if err == nil {
				t.Errorf("%s is an ETF: no logo", a.ID)
			}
			continue
		}
		if !bytes.Equal(got, jpeg) {
			t.Errorf("%s: %v", a.ID, err)
		}
	}

	// Something that is not an image is refused, not written.
	logos[catalogue.Assets[len(catalogue.Assets)-1].ProviderSymbol] = srv.URL + "/not-an-image"
	if code := run(context.Background(), []string{"-out", t.TempDir(), "-every", "0"}, logos, srv.Client(), io.Discard, &stderr); code == 0 {
		t.Fatal("a page that is not an image must fail")
	}
	if !strings.Contains(stderr.String(), "not an image") {
		t.Fatalf("says why: %s", stderr.String())
	}
}

// The app bundles a logo for every stock of the catalogue: one added to the
// catalogue without its logo fails here (run the tool, commit the file).
func TestEveryStockHasABundledLogo(t *testing.T) {
	for _, a := range catalogue.Assets {
		if a.Type != "stock" {
			continue
		}
		if _, err := os.Stat(filepath.Join("..", "..", "..", "app", "assets", "logos", a.ID+".jpg")); err != nil {
			t.Errorf("%s: no bundled logo: go run ./cmd/logos", a.ID)
		}
	}
}
