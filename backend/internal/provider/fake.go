package provider

import (
	"context"
	"fmt"
	"sync"
	"time"

	"finance-companion/backend/internal/store"
)

// Fake is an in-memory Provider for tests.
//
// FailFrom(n, err) fails every call from the n-th on.
type Fake struct {
	mu        sync.Mutex
	Bars      map[string][]store.Bar // ascending
	QuoteData map[string]Quote
	Window    int // MaxDays; 5475 when zero
	// Fail, when set, may fail call number n (from 1).
	Fail  func(n int) error
	Calls int
	// Unavailable symbols answer ErrNotAvailable.
	Unavailable map[string]bool
}

func NewFake() *Fake {
	return &Fake{Bars: map[string][]store.Bar{}, QuoteData: map[string]Quote{}}
}

func (f *Fake) MaxDays() int {
	if f.Window == 0 {
		return 15 * 365
	}
	return f.Window
}

func (f *Fake) call() error {
	f.Calls++
	if f.Fail != nil {
		return f.Fail(f.Calls)
	}
	return nil
}

func (f *Fake) History(_ context.Context, symbol string, from, to time.Time) ([]store.Bar, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if err := f.call(); err != nil {
		return nil, err
	}
	if f.Unavailable[symbol] {
		return nil, ErrNotAvailable
	}
	if days := int(to.Sub(from).Hours()/24) + 1; days > f.MaxDays() {
		return nil, fmt.Errorf("fake: range of %d days over MaxDays %d", days, f.MaxDays())
	}
	var bars []store.Bar
	for _, b := range f.Bars[symbol] {
		if !b.Date.Before(from) && !b.Date.After(to) {
			bars = append(bars, b)
		}
	}
	return bars, nil
}

func (f *Fake) Quotes(_ context.Context, symbols []string) (map[string]Quote, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if err := f.call(); err != nil {
		return nil, err
	}
	quotes := map[string]Quote{}
	for _, s := range symbols {
		if q, ok := f.QuoteData[s]; ok {
			quotes[s] = q
		}
	}
	return quotes, nil
}

// FailFrom fails call n and every call after it with err.
func FailFrom(n int, err error) func(int) error {
	return func(call int) error {
		if call >= n {
			return err
		}
		return nil
	}
}
