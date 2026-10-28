// Package insee reads France's consumer price index from INSEE's macro-economic
// database (BDM, no key; ADR-008): the monthly index cmd/freeze restates a
// series in euros of its first month with (BRIEF §4.3).
package insee

import (
	"context"
	"encoding/xml"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"slices"
	"time"

	"finance-companion/backend/internal/store"
)

// Series is the consumer price index, base 2025, of all households in France,
// all items (« Ensemble des ménages - France - Ensemble »): monthly, from
// January 1996, the figure French news gives.
const Series = "011814630"

// Source is where the index comes from: INSEE, or a fake in tests.
type Source interface {
	ConsumerPrices(ctx context.Context, from, to time.Time) ([]store.Rate, error)
}

type INSEE struct {
	BaseURL string
	HTTP    *http.Client
}

func New() *INSEE {
	return &INSEE{BaseURL: "https://api.insee.fr/series/BDM/V1", HTTP: &http.Client{Timeout: 60 * time.Second}}
}

var number = regexp.MustCompile(`^\d+(\.\d+)?$`)

// ConsumerPrices is the index of each month from from's to to's, each dated on
// its month's first day, oldest first, digits as published.
func (c *INSEE) ConsumerPrices(ctx context.Context, from, to time.Time) ([]store.Rate, error) {
	first, last := from.Format("2006-01"), to.Format("2006-01")
	u := fmt.Sprintf("%s/data/SERIES_BDM/%s?%s", c.BaseURL, Series,
		url.Values{"startPeriod": {first}, "endPeriod": {last}}.Encode())
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	res, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("insee: HTTP %d", res.StatusCode)
	}
	var body struct {
		Obs []struct {
			Period string `xml:"TIME_PERIOD,attr"`
			Value  string `xml:"OBS_VALUE,attr"`
		} `xml:"DataSet>Series>Obs"`
	}
	if err := xml.NewDecoder(res.Body).Decode(&body); err != nil {
		return nil, fmt.Errorf("insee: %w", err)
	}
	if len(body.Obs) == 0 {
		return nil, fmt.Errorf("insee: no index between %s and %s", first, last)
	}
	out := make([]store.Rate, 0, len(body.Obs))
	for _, o := range body.Obs {
		month, err := time.Parse("2006-01", o.Period)
		if err != nil {
			return nil, fmt.Errorf("insee: period %q is not a month", o.Period)
		}
		if !number.MatchString(o.Value) {
			return nil, fmt.Errorf("insee: index %q of %s is not a number", o.Value, o.Period)
		}
		out = append(out, store.Rate{Date: month, Rate: o.Value})
	}
	slices.SortFunc(out, func(a, b store.Rate) int { return a.Date.Compare(b.Date) })
	return out, nil
}
