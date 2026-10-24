package api

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"finance-companion/backend/internal/content"
	"finance-companion/backend/internal/jobs"
	"finance-companion/backend/internal/provider"
	"finance-companion/backend/internal/store"
)

func day(s string) time.Time {
	t, _ := time.Parse(time.DateOnly, s)
	return t
}

func newServer(t *testing.T) (*Server, *store.Store) {
	t.Helper()
	db, err := store.Open(filepath.Join(t.TempDir(), "m.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	ctx := context.Background()
	db.UpsertAssets(ctx, []store.Asset{{
		ID: "world", Symbol: "ACWI", Name: "iShares MSCI ACWI ETF", Type: "etf", Exchange: "nasdaq",
		Currency: "USD", Region: "world", ListingDate: day("2008-03-28"), ProviderSymbol: "ACWI",
	}})
	db.UpsertBars(ctx, "world", []store.Bar{
		{Date: day("2026-10-05"), Open: "159.00", High: "160.10", Low: "158.80", Close: "159.95", Volume: 1000},
		{Date: day("2026-10-06"), Open: "160.00", High: "161.00", Low: "159.50", Close: "160.71", Volume: 1200},
	})
	db.SaveSyncState(ctx, store.SyncState{
		AssetID: "world", FirstDate: day("2026-10-05"), LastDate: day("2026-10-06"),
		FetchedAt: time.Date(2026, 10, 6, 21, 30, 0, 0, time.UTC),
	})
	db.UpsertRates(ctx, "USD", "EUR", []store.Rate{{Date: day("2026-10-05"), Rate: "0.89254"}, {Date: day("2026-10-06"), Rate: "0.88739"}})
	db.ReplaceLivret(ctx, []store.LivretRate{{ValidFrom: day("2025-08-01"), AnnualRate: "0.017"}},
		[]store.LivretCeiling{{ValidFrom: day("2013-01-01"), AmountCents: 2295000}})
	return &Server{Store: db, Quotes: jobs.NewQuoteCache(), Now: time.Now}, db
}

func get(t *testing.T, s *Server, path string, header ...string) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	for i := 0; i+1 < len(header); i += 2 {
		req.Header.Set(header[i], header[i+1])
	}
	rec := httptest.NewRecorder()
	s.Handler().ServeHTTP(rec, req)
	var body map[string]any
	json.Unmarshal(rec.Body.Bytes(), &body)
	return rec, body
}

func TestAssets(t *testing.T) {
	s, _ := newServer(t)
	rec, body := get(t, s, "/v1/assets")
	if rec.Code != 200 || rec.Header().Get("Content-Type") != "application/json" {
		t.Fatalf("%d %s", rec.Code, rec.Header())
	}
	a := body["assets"].([]any)[0].(map[string]any)
	if a["id"] != "world" || a["listingDate"] != "2008-03-28" || a["currency"] != "USD" || a["exchange"] != "nasdaq" {
		t.Fatalf("%v", a)
	}
	if _, leaked := a["providerSymbol"]; leaked {
		t.Fatal("the provider symbol stays private")
	}
}

func TestHistory(t *testing.T) {
	s, _ := newServer(t)
	rec, body := get(t, s, "/v1/assets/world/history?from=2026-10-06")
	if rec.Code != 200 {
		t.Fatalf("%d %v", rec.Code, body)
	}
	bars := body["bars"].([]any)
	if len(bars) != 1 || bars[0].(map[string]any)["close"] != "160.71" || body["adjustedAt"] != nil {
		t.Fatalf("%v", body)
	}
	if rec.Header().Get("Last-Modified") != "Tue, 06 Oct 2026 21:30:00 GMT" {
		t.Fatalf("last-modified %s", rec.Header().Get("Last-Modified"))
	}
	_, all := get(t, s, "/v1/assets/world/history")
	if len(all["bars"].([]any)) != 2 {
		t.Fatal("no range: the whole history")
	}
}

func TestHistoryTellsTheAppAboutAReadjustment(t *testing.T) {
	s, db := newServer(t)
	adjusted := time.Date(2026, 10, 7, 21, 30, 0, 0, time.UTC)
	db.SaveSyncState(context.Background(), store.SyncState{
		AssetID: "world", FirstDate: day("2026-10-05"), LastDate: day("2026-10-06"),
		FetchedAt: adjusted, AdjustedAt: adjusted,
	})
	_, body := get(t, s, "/v1/assets/world/history")
	if body["adjustedAt"] != "2026-10-07T21:30:00Z" {
		t.Fatalf("%v", body["adjustedAt"])
	}
}

func TestConditionalRequests(t *testing.T) {
	s, _ := newServer(t)
	rec, _ := get(t, s, "/v1/assets/world/history")
	etag := rec.Header().Get("ETag")
	if etag == "" {
		t.Fatal("no ETag")
	}
	if rec, _ := get(t, s, "/v1/assets/world/history", "If-None-Match", etag); rec.Code != http.StatusNotModified || rec.Body.Len() != 0 {
		t.Fatalf("If-None-Match: %d", rec.Code)
	}
	if rec, _ := get(t, s, "/v1/assets/world/history", "If-None-Match", `"stale"`); rec.Code != 200 {
		t.Fatalf("another ETag: %d", rec.Code)
	}
	if rec, _ := get(t, s, "/v1/assets/world/history", "If-Modified-Since", "Tue, 06 Oct 2026 21:30:00 GMT"); rec.Code != http.StatusNotModified {
		t.Fatalf("If-Modified-Since current: %d", rec.Code)
	}
	if rec, _ := get(t, s, "/v1/assets/world/history", "If-Modified-Since", "Mon, 05 Oct 2026 00:00:00 GMT"); rec.Code != 200 {
		t.Fatalf("If-Modified-Since older: %d", rec.Code)
	}
	// Endpoints without a known date answer If-Modified-Since in full.
	if rec, _ := get(t, s, "/v1/assets", "If-Modified-Since", "Tue, 06 Oct 2026 21:30:00 GMT"); rec.Code != 200 {
		t.Fatalf("assets: %d", rec.Code)
	}
}

func TestErrorsUseTheEnvelope(t *testing.T) {
	s, _ := newServer(t)
	cases := []struct {
		path   string
		status int
		code   string
	}{
		{"/v1/assets/nope/history", 404, "not_found"},
		{"/v1/assets/world/history?from=06/10/2026", 400, "bad_request"},
		{"/v1/assets/world/history?from=2026-10-07&to=2026-10-01", 400, "bad_request"},
		{"/v1/quotes", 400, "bad_request"},
		{"/v1/fx?base=USD", 400, "bad_request"},
		{"/v1/nothing", 404, "not_found"},
	}
	for _, c := range cases {
		rec, body := get(t, s, c.path)
		e, _ := body["error"].(map[string]any)
		if rec.Code != c.status || e["code"] != c.code || e["message"] == "" {
			t.Errorf("%s: %d %v", c.path, rec.Code, body)
		}
	}
}

func TestQuotesFallBackToTheLastClose(t *testing.T) {
	s, _ := newServer(t)
	_, body := get(t, s, "/v1/quotes?ids=world,ghost")
	quotes := body["quotes"].([]any)
	q := quotes[0].(map[string]any)
	if len(quotes) != 1 || q["price"] != "160.71" || q["marketOpen"] != false || q["asOf"] != "2026-10-06T20:00:00Z" {
		t.Fatalf("%v", quotes)
	}
	// A live quote newer than the close wins.
	s.Quotes.Set("world", provider.Quote{Price: "161.20", Currency: "USD", AsOf: time.Date(2026, 10, 7, 15, 0, 0, 0, time.UTC), MarketOpen: true})
	_, body = get(t, s, "/v1/quotes?ids=world")
	q = body["quotes"].([]any)[0].(map[string]any)
	if q["price"] != "161.20" || q["marketOpen"] != true {
		t.Fatalf("%v", q)
	}
	// An old live quote doesn't hide a newer close.
	s.Quotes.Set("world", provider.Quote{Price: "150", Currency: "USD", AsOf: time.Date(2026, 10, 5, 15, 0, 0, 0, time.UTC)})
	_, body = get(t, s, "/v1/quotes?ids=world")
	if body["quotes"].([]any)[0].(map[string]any)["price"] != "160.71" {
		t.Fatal("the newer close wins")
	}
}

func TestFxAndLivret(t *testing.T) {
	s, _ := newServer(t)
	_, body := get(t, s, "/v1/fx?base=usd&quote=eur&from=2026-10-06")
	rates := body["rates"].([]any)
	if body["base"] != "USD" || len(rates) != 1 || rates[0].(map[string]any)["rate"] != "0.88739" {
		t.Fatalf("%v", body)
	}
	_, body = get(t, s, "/v1/livret/rates")
	if body["rates"].([]any)[0].(map[string]any)["annualRate"] != "0.017" ||
		body["ceilings"].([]any)[0].(map[string]any)["amountCents"] != float64(2295000) {
		t.Fatalf("%v", body)
	}
}

func TestCalendar(t *testing.T) {
	s, _ := newServer(t)
	s.Now = func() time.Time { return time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC) }
	rec, body := get(t, s, "/v1/calendar/otc?year=2026")
	holidays := body["holidays"].([]any)
	if rec.Code != http.StatusOK || body["exchange"] != "otc" || body["year"] != float64(2026) ||
		len(holidays) != 10 || holidays[6] != "2026-07-03" {
		t.Fatalf("%d %v", rec.Code, body)
	}
	early := body["earlyCloses"].([]any)
	if len(early) != 2 || early[0].(map[string]any)["date"] != "2026-11-27" || early[1].(map[string]any)["close"] != "13:00" {
		t.Fatalf("early closes: %v", early)
	}
	if _, body := get(t, s, "/v1/calendar/nyse?year=2027"); len(body["earlyCloses"].([]any)) != 1 {
		t.Fatalf("2027: %v", body)
	}
	if rec, _ := get(t, s, "/v1/calendar/otc?year=2026", "If-None-Match", rec.Header().Get("ETag")); rec.Code != http.StatusNotModified {
		t.Fatalf("revalidation: %d", rec.Code)
	}
	for path, status := range map[string]int{
		"/v1/calendar/nyse?year=2027":     http.StatusOK,
		"/v1/calendar/nyse?year=2028":     http.StatusNotFound,
		"/v1/calendar/nasdaq?year=1999":   http.StatusNotFound,
		"/v1/calendar/euronext?year=2025": http.StatusNotFound,
		"/v1/calendar/nyse":               http.StatusBadRequest,
		"/v1/calendar/nyse?year=next":     http.StatusBadRequest,
	} {
		rec, body := get(t, s, path)
		if rec.Code != status || (status != http.StatusOK && body["error"] == nil) {
			t.Errorf("%s: %d %v", path, rec.Code, body)
		}
	}
}

func TestTooManyRequestsCarriesRetryAfter(t *testing.T) {
	s, _ := newServer(t)
	now := time.Date(2026, 10, 7, 12, 0, 0, 0, time.UTC)
	s.Now = func() time.Time { return now }
	s.RequestsPerMinute = 2
	get(t, s, "/v1/assets")
	now = now.Add(20 * time.Second)
	get(t, s, "/v1/assets")
	rec, body := get(t, s, "/v1/assets")
	if rec.Code != http.StatusTooManyRequests || rec.Header().Get("Retry-After") != "40" ||
		body["error"].(map[string]any)["code"] != "rate_limited" {
		t.Fatalf("%d %s %v", rec.Code, rec.Header().Get("Retry-After"), body)
	}
	now = now.Add(40 * time.Second)
	if rec, _ := get(t, s, "/v1/assets"); rec.Code != 200 {
		t.Fatalf("a minute after the first: %d", rec.Code)
	}
}

func TestLargeBodiesAreGzipped(t *testing.T) {
	s, db := newServer(t)
	var bars []store.Bar
	for i := 1; i <= 30; i++ {
		bars = append(bars, store.Bar{
			Date: day(fmt.Sprintf("2026-09-%02d", i)), Open: "159.00", High: "160.10", Low: "158.80", Close: "159.95", Volume: 1000,
		})
	}
	db.UpsertBars(context.Background(), "world", bars)
	path := "/v1/assets/world/history"

	plain, want := get(t, s, path)
	if plain.Header().Get("Content-Encoding") != "" || len(want["bars"].([]any)) != 32 {
		t.Fatalf("plain: %v %d", plain.Header(), len(want["bars"].([]any)))
	}

	zipped, _ := get(t, s, path, "Accept-Encoding", "br, gzip")
	h := zipped.Header()
	if h.Get("Content-Encoding") != "gzip" || h.Get("Vary") != "Accept-Encoding" {
		t.Fatalf("headers: %v", h)
	}
	if h.Get("ETag") == plain.Header().Get("ETag") || !strings.HasSuffix(h.Get("ETag"), `-gz"`) {
		t.Fatalf("etags: %s vs %s", h.Get("ETag"), plain.Header().Get("ETag"))
	}
	r, err := gzip.NewReader(bytes.NewReader(zipped.Body.Bytes()))
	if err != nil {
		t.Fatal(err)
	}
	unzipped, _ := io.ReadAll(r)
	if !bytes.Equal(unzipped, plain.Body.Bytes()) {
		t.Fatal("the gzipped body differs from the plain one")
	}
	if zipped.Body.Len() >= plain.Body.Len()/3 {
		t.Errorf("gzip saved little: %d of %d bytes", zipped.Body.Len(), plain.Body.Len())
	}

	if rec, _ := get(t, s, path, "Accept-Encoding", "gzip", "If-None-Match", h.Get("ETag")); rec.Code != http.StatusNotModified {
		t.Fatalf("gzip revalidation: %d", rec.Code)
	}
	if rec, _ := get(t, s, path, "Accept-Encoding", "gzip;q=0"); rec.Header().Get("Content-Encoding") != "" {
		t.Fatal("q=0 refuses gzip")
	}
	if rec, _ := get(t, s, "/v1/livret/rates", "Accept-Encoding", "gzip"); rec.Header().Get("Content-Encoding") != "" {
		t.Fatal("a small body stays plain")
	}
}

func TestContentPacks(t *testing.T) {
	s, _ := newServer(t)
	// actions-etf: version 1 published, version 2 still a draft.
	root := t.TempDir()
	for version, status := range map[string]string{"1": "published", "2": "draft"} {
		dir := filepath.Join(root, "packs", "actions-etf", version)
		os.MkdirAll(filepath.Join(dir, "nodes"), 0o755)
		os.WriteFile(filepath.Join(dir, "island.json"), []byte(`{"id": "actions-etf", "version": `+version+`,
			"title": {"fr": "Actions & ETF", "en": "Stocks & ETFs"}, "nodes": ["ae.fees"]}`), 0o644)
		os.WriteFile(filepath.Join(dir, "nodes", "ae.fees.json"), []byte(`{"id": "ae.fees", "type": "toy",
			"status": "`+status+`", "title": {"fr": "Les frais", "en": "Fees"}}`), 0o644)
	}
	library, errs := content.Load(root)
	if len(errs) != 1 {
		t.Fatalf("the draft version is left out: %v", errs)
	}
	s.Content = library

	rec, body := get(t, s, "/v1/content/manifest")
	packs, _ := body["packs"].([]any)
	if rec.Code != http.StatusOK || len(packs) != 1 ||
		packs[0].(map[string]any)["islandId"] != "actions-etf" || packs[0].(map[string]any)["version"] != float64(1) {
		t.Fatalf("manifest: %d %v", rec.Code, body)
	}

	rec, body = get(t, s, "/v1/content/packs/actions-etf/1")
	island, _ := body["island"].(map[string]any)
	if rec.Code != http.StatusOK || island["title"].(map[string]any)["fr"] != "Actions & ETF" || len(body["nodes"].([]any)) != 1 {
		t.Fatalf("pack: %d %v", rec.Code, body)
	}
	if rec, _ := get(t, s, "/v1/content/packs/actions-etf/1", "If-None-Match", rec.Header().Get("ETag")); rec.Code != http.StatusNotModified {
		t.Errorf("revalidation: %d", rec.Code)
	}
	for path, status := range map[string]int{
		"/v1/content/packs/actions-etf/2":  http.StatusNotFound,
		"/v1/content/packs/budget/1":       http.StatusNotFound,
		"/v1/content/packs/actions-etf/v1": http.StatusBadRequest,
	} {
		if rec, body := get(t, s, path); rec.Code != status || body["error"] == nil {
			t.Errorf("%s: %d %v", path, rec.Code, body)
		}
	}

	// A server started without content publishes none.
	s.Content = nil
	if rec, body := get(t, s, "/v1/content/manifest"); rec.Code != http.StatusOK || len(body["packs"].([]any)) != 0 {
		t.Errorf("no content: %d %v", rec.Code, body)
	}
}
