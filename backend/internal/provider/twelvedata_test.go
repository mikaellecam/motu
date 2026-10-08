package provider

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"finance-companion/backend/internal/store"
)

func day(s string) time.Time {
	t, _ := time.Parse(time.DateOnly, s)
	return t
}

// serve answers every request with body (and status), recording the query.
func serve(t *testing.T, status int, body string) (*TwelveData, *url.Values) {
	t.Helper()
	var query url.Values
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		query = r.URL.Query()
		query.Set("path", r.URL.Path)
		w.WriteHeader(status)
		w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	td := NewTwelveData("secret")
	td.BaseURL = srv.URL
	return td, &query
}

func TestHistoryAsksForAdjustedAscendingDaysToIncluded(t *testing.T) {
	td, query := serve(t, 200, `{"meta":{},"values":[
		{"datetime":"2026-10-01","open":"86.31000","high":"86.35","low":"84.62","close":"85.15000","volume":"1364300"},
		{"datetime":"2026-10-02","open":"85.95","high":"86.05","low":"84.73","close":"85.21","volume":""}],"status":"ok"}`)
	bars, err := td.History(context.Background(), "LVMUY", day("2026-10-01"), day("2026-10-06"))
	if err != nil {
		t.Fatal(err)
	}
	q := *query
	want := map[string]string{
		"path": "/time_series", "symbol": "LVMUY", "interval": "1day", "start_date": "2026-10-01",
		"end_date":   "2026-10-07", // exclusive, so the 6th is included
		"outputsize": "5000", "order": "asc", "adjust": "all", "apikey": "secret",
	}
	for k, v := range want {
		if q.Get(k) != v {
			t.Errorf("%s = %q, want %q", k, q.Get(k), v)
		}
	}
	if len(bars) != 2 || !bars[0].Date.Equal(day("2026-10-01")) || bars[0].Close != "85.15000" || bars[0].Volume != 1364300 {
		t.Fatalf("bars: %+v", bars)
	}
	if bars[1].Volume != 0 {
		t.Fatalf("missing volume: %d", bars[1].Volume)
	}
}

func TestHistoryWithoutDataIsEmpty(t *testing.T) {
	td, _ := serve(t, 400, `{"code":400,"message":"No data is available on the specified dates. Try setting different start/end dates.","status":"error"}`)
	bars, err := td.History(context.Background(), "AAPL", day("2026-10-10"), day("2026-10-11"))
	if err != nil || len(bars) != 0 {
		t.Fatalf("%v %v", bars, err)
	}
}

func TestErrorsAreTyped(t *testing.T) {
	cases := []struct {
		status int
		body   string
		want   error
	}{
		{429, `{"code":429,"message":"You have run out of API credits for the current minute.","status":"error"}`, ErrRateLimited},
		{200, `{"code":429,"message":"You have run out of API credits for the day.","status":"error"}`, ErrRateLimited},
		{404, `{"code":404,"message":"This symbol is available starting with the Grow or Venture plan.","status":"error"}`, ErrNotAvailable},
	}
	for _, c := range cases {
		td, _ := serve(t, c.status, c.body)
		if _, err := td.History(context.Background(), "MC", day("2026-10-01"), day("2026-10-02")); !errors.Is(err, c.want) {
			t.Errorf("%s: %v", c.body, err)
		}
		if _, err := td.Quotes(context.Background(), []string{"MC"}); !errors.Is(err, c.want) {
			t.Errorf("quotes %s: %v", c.body, err)
		}
	}
	td, _ := serve(t, 500, `{"code":500,"message":"boom","status":"error"}`)
	if _, err := td.History(context.Background(), "X", day("2026-10-01"), day("2026-10-02")); err == nil ||
		errors.Is(err, ErrRateLimited) || errors.Is(err, ErrNotAvailable) {
		t.Fatalf("other errors stay generic: %v", err)
	}
	td, _ = serve(t, 502, `<html>bad gateway</html>`)
	if _, err := td.History(context.Background(), "X", day("2026-10-01"), day("2026-10-02")); err == nil {
		t.Fatal("a non-JSON body is an error")
	}
}

func TestQuotesSingleAndBatch(t *testing.T) {
	td, query := serve(t, 200, `{"symbol":"ACWI","close":"160.71","currency":"USD","timestamp":1791379800,"is_market_open":false}`)
	quotes, err := td.Quotes(context.Background(), []string{"ACWI"})
	if err != nil {
		t.Fatal(err)
	}
	if q := quotes["ACWI"]; q.Price != "160.71" || q.Currency != "USD" || q.MarketOpen || !q.AsOf.Equal(time.Unix(1791379800, 0)) {
		t.Fatalf("single: %+v", quotes)
	}
	if (*query).Get("path") != "/quote" {
		t.Fatalf("path %s", (*query).Get("path"))
	}

	td, query = serve(t, 200, `{
		"ACWI":{"close":"160.71","currency":"USD","timestamp":1791379800,"last_quote_at":1791403200,"is_market_open":true},
		"MC":{"code":404,"message":"not in plan","status":"error"}}`)
	quotes, err = td.Quotes(context.Background(), []string{"ACWI", "MC"})
	if err != nil {
		t.Fatal(err)
	}
	if (*query).Get("symbol") != "ACWI,MC" {
		t.Fatalf("symbols %s", (*query).Get("symbol"))
	}
	if len(quotes) != 1 || !quotes["ACWI"].MarketOpen || !quotes["ACWI"].AsOf.Equal(time.Unix(1791403200, 0)) {
		t.Fatalf("batch: %+v", quotes)
	}
}

func TestFakeServesWholeWindowsAndFails(t *testing.T) {
	f := NewFake()
	f.Window = 7
	for _, d := range []string{"2026-10-01", "2026-10-02", "2026-10-05"} {
		f.Bars["X"] = append(f.Bars["X"], storeBar(d))
	}
	bars, err := f.History(context.Background(), "X", day("2026-10-01"), day("2026-10-07"))
	if err != nil || len(bars) != 3 || f.MaxDays() != 7 {
		t.Fatalf("window: %+v %v", bars, err)
	}
	if _, err := f.History(context.Background(), "X", day("2026-10-01"), day("2026-10-08")); err == nil {
		t.Fatal("a range over MaxDays is refused")
	}
	f.Fail = FailFrom(2, ErrRateLimited)
	if _, err := f.Quotes(context.Background(), []string{"X"}); !errors.Is(err, ErrRateLimited) {
		t.Fatalf("fail after: %v", err)
	}
}

func storeBar(date string) store.Bar { return store.Bar{Date: day(date), Close: "1"} }
