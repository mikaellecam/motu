package provider

import (
	"context"
	"errors"
	"time"
)

// WaitOutRateLimit calls f, and again after wait each time the provider
// refuses it for its rate, tries times at most in all. The command-line tools
// use it: they share the plan's per-minute credits with each other and with a
// running server, so pacing their own calls is not enough. A spent daily
// quota answers the same way; after the last try its error comes back.
func WaitOutRateLimit(ctx context.Context, wait time.Duration, tries int, f func() error) error {
	for try := 1; ; try++ {
		err := f()
		if !errors.Is(err, ErrRateLimited) || try >= tries {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(wait):
		}
	}
}
