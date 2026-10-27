package content

import (
	"errors"
	"fmt"
	"hash/fnv"
	"math/rand/v2"
	"time"

	"finance-companion/backend/internal/store"
)

// Synthetic makes up the dataset of [r] (ADR-007) for CI, which has no
// provider key: the shape of the real one (id, asset, currency, interval,
// range, the last weekday of each period) over a walk seeded by its id,
// "synthetic" as its source. contentcheck -release refuses it. [asset] is
// the catalogue's asset when r freezes one.
func Synthetic(r Recipe, asset store.Asset, frozenAt time.Time) (Dataset, error) {
	if p := r.Problem(); p != "" {
		return Dataset{}, errors.New(p)
	}
	if r.Asset != "" && asset.ID != r.Asset {
		return Dataset{}, fmt.Errorf("%s: asset %q not given", r.ID, r.Asset)
	}
	from, _ := time.Parse(time.DateOnly, r.From)
	to, _ := time.Parse(time.DateOnly, r.To)

	// Values in ten-thousandths; each weekday moves by a step in ten-thousandths of the value.
	d := Dataset{ID: r.ID, Source: "synthetic", Currency: "EUR", Interval: r.Interval, From: from, To: to,
		FrozenAt: frozenAt}
	value, low, high := int64(100_0000), int64(-150), int64(156)
	switch {
	case r.Asset != "":
		d.Asset, d.Symbol, d.Adjusted, d.Currency = asset.ID, asset.ProviderSymbol, true, asset.Currency
		if r.Currency == "EUR" {
			d.Currency, d.FX = "EUR", "ecb"
		}
	case r.FX != "":
		d.Symbol = "USD/EUR"
		value, low, high = 9000, -40, 40
	case r.Livret:
		value, low, high = r.Deposit*10000, 1, 1
	}

	seed := fnv.New64a()
	seed.Write([]byte(r.ID))
	walk := rand.New(rand.NewPCG(seed.Sum64(), 0))
	var daily []Point
	for day := from; !day.After(to); day = day.AddDate(0, 0, 1) {
		if day.Weekday() == time.Saturday || day.Weekday() == time.Sunday {
			continue
		}
		if len(daily) > 0 {
			value = value * (10000 + low + walk.Int64N(high-low+1)) / 10000
		}
		daily = append(daily, Point{day, trimZeros(fmt.Sprintf("%d.%04d", value/10000, value%10000))})
	}
	if len(daily) == 0 {
		return Dataset{}, fmt.Errorf("%s: no weekday between %s and %s", r.ID, r.From, r.To)
	}
	d.Points = bucket(daily, r.Interval)
	return d, nil
}
