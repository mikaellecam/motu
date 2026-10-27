package provider

import (
	"context"
	"errors"
	"testing"
	"time"
)

// failing fails its first n calls with err, then succeeds.
func failing(n int, err error) (func() error, *int) {
	calls := 0
	return func() error {
		calls++
		if calls <= n {
			return err
		}
		return nil
	}, &calls
}

func TestWaitOutRateLimitTriesAgainAfterTheWait(t *testing.T) {
	call, calls := failing(2, ErrRateLimited)
	start := time.Now()
	if err := WaitOutRateLimit(context.Background(), 20*time.Millisecond, 3, call); err != nil {
		t.Fatal(err)
	}
	if *calls != 3 || time.Since(start) < 40*time.Millisecond {
		t.Errorf("%d calls in %v", *calls, time.Since(start))
	}
}

func TestWaitOutRateLimitGivesUp(t *testing.T) {
	// A spent daily quota answers the same way: after the tries, its error comes back.
	call, calls := failing(10, ErrRateLimited)
	if err := WaitOutRateLimit(context.Background(), time.Millisecond, 3, call); !errors.Is(err, ErrRateLimited) || *calls != 3 {
		t.Errorf("%d calls: %v", *calls, err)
	}
}

func TestWaitOutRateLimitLeavesOtherErrorsAlone(t *testing.T) {
	call, calls := failing(1, ErrNotAvailable)
	if err := WaitOutRateLimit(context.Background(), time.Millisecond, 3, call); !errors.Is(err, ErrNotAvailable) || *calls != 1 {
		t.Errorf("%d calls: %v", *calls, err)
	}
}

func TestWaitOutRateLimitStopsWhenCancelled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	call, calls := failing(1, ErrRateLimited)
	if err := WaitOutRateLimit(ctx, time.Hour, 3, call); !errors.Is(err, context.Canceled) || *calls != 1 {
		t.Errorf("%d calls: %v", *calls, err)
	}
}
