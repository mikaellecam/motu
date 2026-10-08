// Package provider fetches market data from an external API behind an
// interface, so jobs and handlers can be tested with Fake.
package provider

import (
	"context"
	"errors"
	"time"

	"finance-companion/backend/internal/store"
)

// Provider returns adjusted daily bars and latest quotes.
type Provider interface {
	// History returns every bar of symbol dated from `from` to `to`, both
	// included, oldest first. The range spans at most MaxDays calendar days.
	// No bar in the range is not an error.
	History(ctx context.Context, symbol string, from, to time.Time) ([]store.Bar, error)

	// MaxDays is the longest range one History call may cover.
	MaxDays() int

	// Quotes returns the latest quote of each symbol it knows.
	Quotes(ctx context.Context, symbols []string) (map[string]Quote, error)
}

// Quote is a symbol's latest price.
type Quote struct {
	Price      string // exact decimal
	Currency   string
	AsOf       time.Time
	MarketOpen bool
}

var (
	// ErrRateLimited means the provider refused the call for exceeding its rate.
	ErrRateLimited = errors.New("provider: rate limited")
	// ErrNotAvailable means the symbol is unknown or not in the plan.
	ErrNotAvailable = errors.New("provider: symbol not available")
)
