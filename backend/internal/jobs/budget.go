// Package jobs keeps the store's market data up to date within the
// provider's credit budget: the first backfill and the daily append.
package jobs

import (
	"context"
	"errors"
	"sync"
	"time"
)

// ErrDailyBudget means today's credits are spent; the work resumes tomorrow.
var ErrDailyBudget = errors.New("jobs: daily credit budget spent")

// Budget spreads provider credits: at most PerMinute in any 60 seconds and
// PerDay per UTC day (the provider's reset). Now and Sleep are injectable for
// tests.
type Budget struct {
	PerMinute, PerDay int
	Now               func() time.Time
	Sleep             func(ctx context.Context, d time.Duration) error

	mu     sync.Mutex
	recent []time.Time
	day    string
	used   int
}

func NewBudget(perMinute, perDay int) *Budget {
	return &Budget{PerMinute: perMinute, PerDay: perDay, Now: time.Now, Sleep: sleep}
}

func sleep(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

// Take waits until n credits fit in the minute window, or fails with
// ErrDailyBudget when they don't fit in today's.
func (b *Budget) Take(ctx context.Context, n int) error {
	for {
		b.mu.Lock()
		now := b.Now().UTC()
		if day := now.Format(time.DateOnly); day != b.day {
			b.day, b.used = day, 0
		}
		if b.used+n > b.PerDay {
			b.mu.Unlock()
			return ErrDailyBudget
		}
		for len(b.recent) > 0 && now.Sub(b.recent[0]) >= time.Minute {
			b.recent = b.recent[1:]
		}
		if len(b.recent)+n <= b.PerMinute {
			for range n {
				b.recent = append(b.recent, now)
			}
			b.used += n
			b.mu.Unlock()
			return nil
		}
		wait := b.recent[0].Add(time.Minute).Sub(now)
		b.mu.Unlock()
		if err := b.Sleep(ctx, wait); err != nil {
			return err
		}
	}
}
