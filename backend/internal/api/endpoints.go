package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"finance-companion/backend/internal/calendar"
	"finance-companion/backend/internal/content"
	"finance-companion/backend/internal/store"
)

// JSON shapes. Prices and rates are exact decimal strings (the app never
// parses money into floating point); dates are YYYY-MM-DD, instants RFC 3339.

type assetJSON struct {
	ID          string `json:"id"`
	Symbol      string `json:"symbol"`
	Name        string `json:"name"`
	Type        string `json:"type"`
	Exchange    string `json:"exchange"`
	Currency    string `json:"currency"`
	Region      string `json:"region"`
	ListingDate string `json:"listingDate"`
}

type barJSON struct {
	Date   string `json:"date"`
	Open   string `json:"open"`
	High   string `json:"high"`
	Low    string `json:"low"`
	Close  string `json:"close"`
	Volume int64  `json:"volume"`
}

type quoteJSON struct {
	AssetID    string    `json:"assetId"`
	Price      string    `json:"price"`
	Currency   string    `json:"currency"`
	AsOf       time.Time `json:"asOf"`
	MarketOpen bool      `json:"marketOpen"`
}

func date(t time.Time) string { return t.Format(time.DateOnly) }

// dateParam reads an optional YYYY-MM-DD query parameter.
func dateParam(r *http.Request, name string, fallback time.Time) (time.Time, error) {
	v := r.URL.Query().Get(name)
	if v == "" {
		return fallback, nil
	}
	t, err := time.Parse(time.DateOnly, v)
	if err != nil {
		return time.Time{}, badRequest(name + " must be YYYY-MM-DD")
	}
	return t, nil
}

var (
	beginning = time.Date(1900, 1, 1, 0, 0, 0, 0, time.UTC)
	end       = time.Date(2999, 12, 31, 0, 0, 0, 0, time.UTC)
)

func dateRange(r *http.Request) (from, to time.Time, err error) {
	if from, err = dateParam(r, "from", beginning); err != nil {
		return
	}
	if to, err = dateParam(r, "to", end); err != nil {
		return
	}
	if from.After(to) {
		err = badRequest("from is after to")
	}
	return
}

func (s *Server) assets(r *http.Request) (response, error) {
	assets, err := s.Store.Assets(r.Context())
	if err != nil {
		return response{}, err
	}
	out := make([]assetJSON, 0, len(assets))
	for _, a := range assets {
		out = append(out, assetJSON{a.ID, a.Symbol, a.Name, a.Type, a.Exchange, a.Currency, a.Region, date(a.ListingDate)})
	}
	return response{body: map[string]any{"assets": out}}, nil
}

// history serves adjusted daily bars, oldest first. adjustedAt is the last
// full refetch after a dividend or split: when it moves, the app drops its
// cached history of the asset (BRIEF §6.2).
func (s *Server) history(r *http.Request) (response, error) {
	id := r.PathValue("id")
	asset, err := s.Store.Asset(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		return response{}, apiError{http.StatusNotFound, "not_found", "unknown asset " + id}
	}
	if err != nil {
		return response{}, err
	}
	from, to, err := dateRange(r)
	if err != nil {
		return response{}, err
	}
	bars, err := s.Store.Bars(r.Context(), id, from, to)
	if err != nil {
		return response{}, err
	}
	state, _, err := s.Store.SyncState(r.Context(), id)
	if err != nil {
		return response{}, err
	}
	out := make([]barJSON, 0, len(bars))
	for _, b := range bars {
		out = append(out, barJSON{date(b.Date), b.Open, b.High, b.Low, b.Close, b.Volume})
	}
	var adjustedAt *time.Time
	if !state.AdjustedAt.IsZero() {
		adjustedAt = &state.AdjustedAt
	}
	lastModified := state.FetchedAt
	if state.AdjustedAt.After(lastModified) {
		lastModified = state.AdjustedAt
	}
	return response{
		body: map[string]any{
			"assetId": id, "currency": asset.Currency, "adjustedAt": adjustedAt, "bars": out,
		},
		lastModified: lastModified,
	}, nil
}

// quotes serves each requested asset's latest price: the live quote while
// one is newer than the last close, else the last close (16:00 New York of
// its day, market closed). Unknown ids are left out.
func (s *Server) quotes(r *http.Request) (response, error) {
	raw := r.URL.Query().Get("ids")
	if raw == "" {
		return response{}, badRequest("ids is required")
	}
	out := []quoteJSON{}
	for _, id := range strings.Split(raw, ",") {
		asset, err := s.Store.Asset(r.Context(), id)
		if errors.Is(err, store.ErrNotFound) {
			continue
		}
		if err != nil {
			return response{}, err
		}
		var close *quoteJSON
		if last, ok, err := s.Store.LastBarDate(r.Context(), id); err != nil {
			return response{}, err
		} else if ok {
			bars, err := s.Store.Bars(r.Context(), id, last, last)
			if err != nil {
				return response{}, err
			}
			close = &quoteJSON{id, bars[0].Close, asset.Currency, closeOf(last), false}
		}
		if live, ok := s.Quotes.Get(id); ok && (close == nil || live.AsOf.After(close.AsOf)) {
			out = append(out, quoteJSON{id, live.Price, live.Currency, live.AsOf, live.MarketOpen})
		} else if close != nil {
			out = append(out, *close)
		}
	}
	return response{body: map[string]any{"quotes": out}}, nil
}

var newYork = func() *time.Location {
	loc, err := time.LoadLocation("America/New_York")
	if err != nil {
		panic(err)
	}
	return loc
}()

// closeOf is the instant a US session closes on day.
func closeOf(day time.Time) time.Time {
	return time.Date(day.Year(), day.Month(), day.Day(), 16, 0, 0, 0, newYork).UTC()
}

func (s *Server) fx(r *http.Request) (response, error) {
	q := r.URL.Query()
	base, quote := strings.ToUpper(q.Get("base")), strings.ToUpper(q.Get("quote"))
	if base == "" || quote == "" {
		return response{}, badRequest("base and quote are required")
	}
	from, to, err := dateRange(r)
	if err != nil {
		return response{}, err
	}
	rates, err := s.Store.Rates(r.Context(), base, quote, from, to)
	if err != nil {
		return response{}, err
	}
	out := make([]map[string]string, 0, len(rates))
	for _, rate := range rates {
		out = append(out, map[string]string{"date": date(rate.Date), "rate": rate.Rate})
	}
	return response{body: map[string]any{"base": base, "quote": quote, "rates": out}}, nil
}

func (s *Server) livret(r *http.Request) (response, error) {
	rates, ceilings, err := s.Store.Livret(r.Context())
	if err != nil {
		return response{}, err
	}
	outRates := make([]map[string]string, 0, len(rates))
	for _, rate := range rates {
		outRates = append(outRates, map[string]string{"validFrom": date(rate.ValidFrom), "annualRate": rate.AnnualRate})
	}
	outCeilings := make([]map[string]any, 0, len(ceilings))
	for _, c := range ceilings {
		outCeilings = append(outCeilings, map[string]any{"validFrom": date(c.ValidFrom), "amountCents": c.AmountCents})
	}
	return response{body: map[string]any{"rates": outRates, "ceilings": outCeilings}}, nil
}

// calendar serves an exchange's holidays in a year: every other weekday
// trades. Years run from the data floor's to next year's; later ones would
// miss closures not yet announced.
func (s *Server) calendar(r *http.Request) (response, error) {
	exchange := r.PathValue("exchange")
	year, err := strconv.Atoi(r.URL.Query().Get("year"))
	if err != nil {
		return response{}, badRequest("year must be a number, as in year=2025")
	}
	holidays, ok := calendar.Holidays(exchange, year)
	if !ok {
		return response{}, apiError{http.StatusNotFound, "not_found", "unknown exchange " + exchange}
	}
	if year < calendar.FirstYear || year > s.Now().Year()+1 {
		return response{}, apiError{http.StatusNotFound, "not_found",
			fmt.Sprintf("no calendar for %d (served: %d to next year)", year, calendar.FirstYear)}
	}
	out := make([]string, 0, len(holidays))
	for _, d := range holidays {
		out = append(out, date(d))
	}
	return response{body: map[string]any{"exchange": exchange, "year": year, "holidays": out}}, nil
}

// contentManifest is the latest published version of each island (ADR-006).
func (s *Server) contentManifest(*http.Request) (response, error) {
	packs := []content.Latest{}
	if s.Content != nil {
		packs = s.Content.Manifest()
	}
	return response{body: map[string]any{"packs": packs}}, nil
}

// contentPack is one published version's document. A version is immutable,
// so its ETag never changes.
func (s *Server) contentPack(r *http.Request) (response, error) {
	version, err := strconv.Atoi(r.PathValue("version"))
	if err != nil {
		return response{}, badRequest("version must be a number, as in /v1/content/packs/actions-etf/1")
	}
	if s.Content != nil {
		if doc, ok := s.Content.Document(r.PathValue("islandId"), version); ok {
			return response{body: json.RawMessage(doc)}, nil
		}
	}
	return response{}, apiError{http.StatusNotFound, "not_found", "no such content pack"}
}
