package provider

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"finance-companion/backend/internal/store"
)

// TwelveData is the Twelve Data adapter (ADR-004): daily bars adjusted for
// splits and dividends, batch quotes. One credit per symbol per call.
type TwelveData struct {
	BaseURL string
	APIKey  string
	HTTP    *http.Client
}

func NewTwelveData(apiKey string) *TwelveData {
	return &TwelveData{
		BaseURL: "https://api.twelvedata.com",
		APIKey:  apiKey,
		HTTP:    &http.Client{Timeout: 30 * time.Second},
	}
}

// maxBars is the most bars one call returns. Twelve Data keeps the *latest*
// bars of the range, whatever the order, so a range must never hold more.
const maxBars = 5000

// MaxDays: 15 years hold about 3 800 trading days, well under maxBars.
func (t *TwelveData) MaxDays() int { return 15 * 365 }

// apiError is the error body Twelve Data sends, with HTTP 200 or 4xx.
type apiError struct {
	Status  string `json:"status"`
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (e apiError) Error() string { return fmt.Sprintf("twelvedata %d: %s", e.Code, e.Message) }

func (e apiError) err() error {
	switch e.Code {
	case http.StatusTooManyRequests:
		return fmt.Errorf("%w: %s", ErrRateLimited, e.Message)
	case http.StatusNotFound, http.StatusForbidden:
		return fmt.Errorf("%w: %s", ErrNotAvailable, e.Message)
	}
	return fmt.Errorf("provider: twelvedata %d: %s", e.Code, e.Message)
}

// get calls an endpoint and returns its body, whatever the HTTP status:
// errors come as JSON too. A body with "status": "error" becomes an error.
func (t *TwelveData) get(ctx context.Context, path string, query url.Values) ([]byte, error) {
	query.Set("apikey", t.APIKey)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, t.BaseURL+path+"?"+query.Encode(), nil)
	if err != nil {
		return nil, err
	}
	res, err := t.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	body, err := io.ReadAll(res.Body)
	if err != nil {
		return nil, err
	}
	var e apiError
	if json.Unmarshal(body, &e) == nil && e.Status == "error" {
		return nil, e
	}
	return body, nil
}

func (t *TwelveData) History(ctx context.Context, symbol string, from, to time.Time) ([]store.Bar, error) {
	body, err := t.get(ctx, "/time_series", url.Values{
		"symbol":     {symbol},
		"interval":   {"1day"},
		"start_date": {from.Format(time.DateOnly)},
		// end_date is exclusive.
		"end_date":   {to.AddDate(0, 0, 1).Format(time.DateOnly)},
		"outputsize": {strconv.Itoa(maxBars)},
		"order":      {"asc"},
		"adjust":     {"all"},
	})
	if e, ok := err.(apiError); ok {
		if strings.Contains(e.Message, "No data is available") {
			return nil, nil
		}
		return nil, e.err()
	}
	if err != nil {
		return nil, err
	}
	var series struct {
		Values []struct {
			Datetime, Open, High, Low, Close, Volume string
		} `json:"values"`
	}
	if err := json.Unmarshal(body, &series); err != nil {
		return nil, fmt.Errorf("provider: %s: %w", symbol, err)
	}
	bars := make([]store.Bar, 0, len(series.Values))
	for _, v := range series.Values {
		date, err := time.Parse(time.DateOnly, v.Datetime[:min(len(v.Datetime), 10)])
		if err != nil {
			return nil, fmt.Errorf("provider: %s: bad date %q", symbol, v.Datetime)
		}
		volume, _ := strconv.ParseInt(v.Volume, 10, 64) // some funds report none
		bars = append(bars, store.Bar{Date: date, Open: v.Open, High: v.High, Low: v.Low, Close: v.Close, Volume: volume})
	}
	return bars, nil
}

type tdQuote struct {
	Status       string `json:"status"`
	Close        string `json:"close"`
	Currency     string `json:"currency"`
	Timestamp    int64  `json:"timestamp"`
	LastQuoteAt  int64  `json:"last_quote_at"`
	IsMarketOpen bool   `json:"is_market_open"`
}

func (t *TwelveData) Quotes(ctx context.Context, symbols []string) (map[string]Quote, error) {
	body, err := t.get(ctx, "/quote", url.Values{"symbol": {strings.Join(symbols, ",")}})
	if e, ok := err.(apiError); ok {
		return nil, e.err()
	}
	if err != nil {
		return nil, err
	}
	raw := map[string]tdQuote{}
	if len(symbols) == 1 {
		// One symbol: a single object instead of a map.
		var q tdQuote
		err = json.Unmarshal(body, &q)
		raw[symbols[0]] = q
	} else {
		err = json.Unmarshal(body, &raw)
	}
	if err != nil {
		return nil, fmt.Errorf("provider: quotes: %w", err)
	}
	quotes := make(map[string]Quote, len(raw))
	for symbol, q := range raw {
		if q.Status == "error" {
			continue // unknown or not in the plan: the caller sees it missing
		}
		at := q.LastQuoteAt
		if at == 0 {
			at = q.Timestamp
		}
		quotes[symbol] = Quote{Price: q.Close, Currency: q.Currency, AsOf: time.Unix(at, 0).UTC(), MarketOpen: q.IsMarketOpen}
	}
	return quotes, nil
}
