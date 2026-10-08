// Package fx fetches ECB reference rates from Frankfurter (no key), which the
// backend caches and serves (BRIEF §8.3).
package fx

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"

	"finance-companion/backend/internal/store"
)

type Frankfurter struct {
	BaseURL string
	HTTP    *http.Client
}

func NewFrankfurter() *Frankfurter {
	return &Frankfurter{BaseURL: "https://api.frankfurter.dev/v1", HTTP: &http.Client{Timeout: 30 * time.Second}}
}

// Rates returns the daily rates of base→quote (units of quote per base) from
// from to to. Frankfurter may add the last rate before from.
func (f *Frankfurter) Rates(ctx context.Context, base, quote string, from, to time.Time) ([]store.Rate, error) {
	u := fmt.Sprintf("%s/%s..%s?%s", f.BaseURL, from.Format(time.DateOnly), to.Format(time.DateOnly),
		url.Values{"base": {base}, "symbols": {quote}}.Encode())
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	res, err := f.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fx: frankfurter HTTP %d", res.StatusCode)
	}
	var body struct {
		Rates map[string]map[string]json.Number `json:"rates"`
	}
	dec := json.NewDecoder(res.Body)
	dec.UseNumber() // keep the published digits exactly
	if err := dec.Decode(&body); err != nil {
		return nil, fmt.Errorf("fx: frankfurter: %w", err)
	}
	rates := make([]store.Rate, 0, len(body.Rates))
	for date, byQuote := range body.Rates {
		d, err := time.Parse(time.DateOnly, date)
		if err != nil {
			return nil, fmt.Errorf("fx: bad date %q", date)
		}
		if r, ok := byQuote[quote]; ok {
			rates = append(rates, store.Rate{Date: d, Rate: r.String()})
		}
	}
	return rates, nil
}

// Source is what Sync needs from Frankfurter.
type Source interface {
	Rates(ctx context.Context, base, quote string, from, to time.Time) ([]store.Rate, error)
}

// Sync stores base→quote rates from the day after the last stored one (or
// from floor) to to, five years per request.
func Sync(ctx context.Context, db *store.Store, src Source, base, quote string, floor, to time.Time) error {
	from := floor
	if last, ok, err := db.LastRateDate(ctx, base, quote); err != nil {
		return err
	} else if ok {
		from = last.AddDate(0, 0, 1)
	}
	for !from.After(to) {
		end := from.AddDate(5, 0, -1)
		if end.After(to) {
			end = to
		}
		rates, err := src.Rates(ctx, base, quote, from, end)
		if err != nil {
			return err
		}
		if err := db.UpsertRates(ctx, base, quote, rates); err != nil {
			return err
		}
		from = end.AddDate(0, 0, 1)
	}
	return nil
}
