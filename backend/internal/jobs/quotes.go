package jobs

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"finance-companion/backend/internal/provider"
	"finance-companion/backend/internal/store"
)

// QuoteCache holds the latest live quote of each asset, by asset id.
type QuoteCache struct {
	mu     sync.RWMutex
	quotes map[string]provider.Quote
}

func NewQuoteCache() *QuoteCache { return &QuoteCache{quotes: map[string]provider.Quote{}} }

func (c *QuoteCache) Get(assetID string) (provider.Quote, bool) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	q, ok := c.quotes[assetID]
	return q, ok
}

func (c *QuoteCache) Set(assetID string, q provider.Quote) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.quotes[assetID] = q
}

// InSession is true during the US regular session (weekdays 09:30–16:00 New
// York). Holidays are not known here; the provider reports them closed.
func InSession(now time.Time) bool {
	local := now.In(newYork)
	if local.Weekday() == time.Saturday || local.Weekday() == time.Sunday {
		return false
	}
	open := time.Date(local.Year(), local.Month(), local.Day(), 9, 30, 0, 0, newYork)
	close := time.Date(local.Year(), local.Month(), local.Day(), 16, 0, 0, 0, newYork)
	return !local.Before(open) && local.Before(close)
}

// NextSessionOpen is the next weekday 09:30 New York after now.
func NextSessionOpen(now time.Time) time.Time {
	local := now.In(newYork)
	open := time.Date(local.Year(), local.Month(), local.Day(), 9, 30, 0, 0, newYork)
	for !open.After(now) || open.Weekday() == time.Saturday || open.Weekday() == time.Sunday {
		open = time.Date(open.Year(), open.Month(), open.Day()+1, 9, 30, 0, 0, newYork)
	}
	return open
}

// QuoteInterval: one refresh of the catalogue every 30 minutes during the
// session fits the free plan's daily credits (ADR-004).
const QuoteInterval = 30 * time.Minute

// QuoteRefresher keeps QuoteCache fresh during the US session. Outside it,
// the API serves the last close and no credit is spent.
type QuoteRefresher struct {
	Store    *store.Store
	Provider provider.Provider
	Budget   *Budget
	Cache    *QuoteCache
	Now      func() time.Time
	Log      *slog.Logger
}

// Refresh asks for every asset's quote, in batches no larger than the
// per-minute budget (one credit per symbol).
func (q *QuoteRefresher) Refresh(ctx context.Context) error {
	assets, err := q.Store.Assets(ctx)
	if err != nil {
		return err
	}
	idBySymbol := map[string]string{}
	var symbols []string
	for _, a := range assets {
		idBySymbol[a.ProviderSymbol] = a.ID
		symbols = append(symbols, a.ProviderSymbol)
	}
	for len(symbols) > 0 {
		batch := symbols[:min(len(symbols), q.Budget.PerMinute)]
		symbols = symbols[len(batch):]
		if err := q.Budget.Take(ctx, len(batch)); err != nil {
			return err
		}
		quotes, err := q.Provider.Quotes(ctx, batch)
		if err != nil {
			return err
		}
		for symbol, quote := range quotes {
			q.Cache.Set(idBySymbol[symbol], quote)
		}
	}
	return nil
}

// Run refreshes every QuoteInterval during sessions until ctx ends.
func (q *QuoteRefresher) Run(ctx context.Context) {
	for {
		now := q.Now()
		wait := NextSessionOpen(now).Sub(now)
		if InSession(now) {
			if err := q.Refresh(ctx); err != nil {
				q.Log.Warn("quote refresh failed", "err", err)
			}
			wait = QuoteInterval
		}
		if err := q.Budget.Sleep(ctx, wait); err != nil {
			return
		}
	}
}
