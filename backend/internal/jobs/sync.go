package jobs

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	"time"

	_ "time/tzdata" // America/New_York without a system tz database (Docker)

	"finance-companion/backend/internal/calendar"
	"finance-companion/backend/internal/fx"
	"finance-companion/backend/internal/provider"
	"finance-companion/backend/internal/store"
)

var newYork = func() *time.Location {
	loc, err := time.LoadLocation("America/New_York")
	if err != nil {
		panic(err)
	}
	return loc
}()

// closeMargin leaves the provider time to publish the day's final bar.
const closeMargin = 30 * time.Minute

// LastClosedSession is the latest New York weekday whose session (16:00, or its
// early close) closed before now, with a margin: a bar of a session still running is never
// stored. Holidays need no care: the provider returns no bar for them.
func LastClosedSession(now time.Time) time.Time {
	local := now.In(newYork)
	day := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, time.UTC)
	if local.Before(calendar.USClose(local).Add(closeMargin)) {
		day = day.AddDate(0, 0, -1)
	}
	for day.Weekday() == time.Saturday || day.Weekday() == time.Sunday {
		day = day.AddDate(0, 0, -1)
	}
	return day
}

// NextDailyRun is the next weekday 17:00 in New York after now: the daily
// append runs once the US session is over.
func NextDailyRun(now time.Time) time.Time {
	local := now.In(newYork)
	run := time.Date(local.Year(), local.Month(), local.Day(), 17, 0, 0, 0, newYork)
	for !run.After(now) || run.Weekday() == time.Saturday || run.Weekday() == time.Sunday {
		run = time.Date(run.Year(), run.Month(), run.Day()+1, 17, 0, 0, 0, newYork)
	}
	return run
}

// Syncer brings each asset's history up to the last closed session, one date
// window of at most Provider.MaxDays (one credit) at a time. Progress is
// saved after every window, so an interrupted run (budget, crash, network)
// resumes where it stopped.
type Syncer struct {
	Store     *store.Store
	Provider  provider.Provider
	Budget    *Budget
	DataFloor time.Time
	Now       func() time.Time
	Log       *slog.Logger
	// Rates, when set, also keeps USD→EUR up to date (no provider credit).
	Rates fx.Source
}

// SyncAll syncs USD→EUR and every asset of the store's catalogue. It stops at the first
// error that would hit every asset (budget, rate limit, cancellation) and
// carries on past errors of a single asset, returning them all.
func (s *Syncer) SyncAll(ctx context.Context) error {
	assets, err := s.Store.Assets(ctx)
	if err != nil {
		return err
	}
	to := LastClosedSession(s.Now())
	var failed []error
	if s.Rates != nil {
		if err := fx.Sync(ctx, s.Store, s.Rates, "USD", "EUR", s.DataFloor, to); err != nil {
			s.Log.Warn("fx sync failed", "err", err)
			failed = append(failed, fmt.Errorf("fx: %w", err))
		}
	}
	for _, asset := range assets {
		err := s.syncAsset(ctx, asset, to)
		switch {
		case err == nil:
		case errors.Is(err, ErrDailyBudget), errors.Is(err, provider.ErrRateLimited), ctx.Err() != nil:
			return errors.Join(append(failed, err)...)
		default:
			s.Log.Warn("sync failed", "asset", asset.ID, "err", err)
			failed = append(failed, fmt.Errorf("%s: %w", asset.ID, err))
		}
	}
	return errors.Join(failed...)
}

func (s *Syncer) syncAsset(ctx context.Context, asset store.Asset, to time.Time) error {
	state, synced, err := s.Store.SyncState(ctx, asset.ID)
	if err != nil {
		return err
	}
	floor := s.DataFloor
	if asset.ListingDate.After(floor) {
		floor = asset.ListingDate
	}
	from := floor
	if synced {
		// Ask again for the last few stored days (at least one trading day
		// before the last): a dividend or split rewrites every earlier
		// close, a late correction only the latest one.
		from = state.LastDate.AddDate(0, 0, -5)
	}
	check := synced
	for !from.After(to) {
		end := from.AddDate(0, 0, s.Provider.MaxDays()-1)
		if end.After(to) {
			end = to
		}
		if err := s.Budget.Take(ctx, 1); err != nil {
			return err
		}
		bars, err := s.history(ctx, asset.ProviderSymbol, from, end)
		if err != nil {
			return err
		}
		if check {
			check = false
			readjusted, err := s.readjusted(ctx, asset.ID, from, state.LastDate, bars)
			if err != nil {
				return err
			}
			if readjusted {
				s.Log.Info("history re-adjusted, refetching", "asset", asset.ID)
				if err := s.Store.DeleteBars(ctx, asset.ID); err != nil {
					return err
				}
				state = store.SyncState{AssetID: asset.ID, AdjustedAt: s.Now()}
				synced = false
				from = floor
				continue
			}
		}
		if len(bars) > 0 {
			if err := s.Store.UpsertBars(ctx, asset.ID, bars); err != nil {
				return err
			}
			if !synced {
				state.AssetID, state.FirstDate = asset.ID, bars[0].Date
				synced = true
			}
			// The last bar, not the window's end: a day the provider has not
			// published yet is asked again next time.
			state.LastDate = bars[len(bars)-1].Date
			state.FetchedAt = s.Now()
			if err := s.Store.SaveSyncState(ctx, state); err != nil {
				return err
			}
		}
		from = end.AddDate(0, 0, 1)
	}
	return nil
}

// readjusted compares the provider's closes with the stored ones on the days
// from `from` up to, not including, last. Adjusted series are rewritten
// backwards at every dividend and split, so any difference there means every
// stored day is stale. The last day itself may just have been corrected late
// (OTC listings): the upsert takes care of it.
func (s *Syncer) readjusted(ctx context.Context, assetID string, from, last time.Time, fresh []store.Bar) (bool, error) {
	stored, err := s.Store.Bars(ctx, assetID, from, last.AddDate(0, 0, -1))
	if err != nil {
		return false, err
	}
	closes := map[time.Time]string{}
	for _, b := range fresh {
		closes[b.Date] = b.Close
	}
	for _, b := range stored {
		freshClose, ok := closes[b.Date]
		if !ok {
			continue
		}
		a, okA := new(big.Rat).SetString(b.Close)
		f, okF := new(big.Rat).SetString(freshClose)
		if okA && okF && a.Cmp(f) != 0 {
			return true, nil
		}
	}
	return false, nil
}

// history fetches a window. Credits spent outside this process (a manual
// call, a content freeze) can still exhaust the provider's minute: then it
// waits for the next minute and tries once more.
func (s *Syncer) history(ctx context.Context, symbol string, from, to time.Time) ([]store.Bar, error) {
	bars, err := s.Provider.History(ctx, symbol, from, to)
	if !errors.Is(err, provider.ErrRateLimited) {
		return bars, err
	}
	s.Log.Info("provider minute exhausted, waiting", "symbol", symbol)
	if err := s.Budget.Sleep(ctx, time.Minute); err != nil {
		return nil, err
	}
	if err := s.Budget.Take(ctx, 1); err != nil {
		return nil, err
	}
	return s.Provider.History(ctx, symbol, from, to)
}

// RunDaily syncs now, then after every US close, until ctx ends.
func (s *Syncer) RunDaily(ctx context.Context) {
	for {
		if err := s.SyncAll(ctx); err != nil {
			s.Log.Warn("sync incomplete", "err", err)
		} else {
			s.Log.Info("market data up to date", "through", LastClosedSession(s.Now()).Format(time.DateOnly))
		}
		now := s.Now()
		if err := s.Budget.Sleep(ctx, NextDailyRun(now).Sub(now)); err != nil {
			return
		}
	}
}
