package content

import (
	"fmt"
	"math/big"
	"slices"
	"time"

	"finance-companion/backend/internal/store"
)

// Series that are not an asset's closes: an asset in euros, the dollar in
// euros, a Livret A deposit (M6-8), cash, and what a Livret or cash buys
// (M12-2). Each is computed from published figures, ECB rates, the Livret A
// rate history or INSEE's consumer prices, never hand-typed.

type dated struct {
	date  time.Time
	value *big.Rat
}

// ratesOf parses rates, oldest first; each must be positive.
func ratesOf(rates []store.Rate) ([]dated, error) {
	out := make([]dated, 0, len(rates))
	for _, r := range rates {
		v, ok := new(big.Rat).SetString(r.Rate)
		if !ok || v.Sign() <= 0 {
			return nil, fmt.Errorf("rate %q of %s is not positive", r.Rate, r.Date.Format(time.DateOnly))
		}
		out = append(out, dated{r.Date, v})
	}
	slices.SortFunc(out, func(a, b dated) int { return a.date.Compare(b.date) })
	return out, nil
}

// on is the latest entry dated on or before day; nil when none.
func on(history []dated, day time.Time) *big.Rat {
	var found *big.Rat
	for _, h := range history {
		if h.date.After(day) {
			break
		}
		found = h.value
	}
	return found
}

// ToEuros converts a USD dataset at the ECB rate of each point's day, or the
// last one published before it. eurUSD are dollars per euro.
func ToEuros(d Dataset, eurUSD []store.Rate) (Dataset, error) {
	switch d.Currency {
	case "EUR":
		return Dataset{}, fmt.Errorf("%s is already in EUR", d.ID)
	case "USD":
	default:
		return Dataset{}, fmt.Errorf("%s: only USD converts to EUR, not %s", d.ID, d.Currency)
	}
	rates, err := ratesOf(eurUSD)
	if err != nil {
		return Dataset{}, err
	}
	out := d
	out.Points = make([]Point, 0, len(d.Points))
	for _, p := range d.Points {
		rate := on(rates, p.Date)
		if rate == nil {
			return Dataset{}, fmt.Errorf("no EUR/USD rate on or before %s", p.Date.Format(time.DateOnly))
		}
		value, ok := new(big.Rat).SetString(p.Value)
		if !ok {
			return Dataset{}, fmt.Errorf("close %q is not a number", p.Value)
		}
		out.Points = append(out.Points, Point{p.Date, decimal6(value.Quo(value, rate))})
	}
	out.Currency, out.FX = "EUR", "ecb"
	return out, nil
}

// DollarInEuros is what one dollar was worth in euros on each ECB day in
// [from, to], kept at interval.
func DollarInEuros(id string, eurUSD []store.Rate, interval string, from, to, frozenAt time.Time) (Dataset, error) {
	if err := checkRange(interval, from, to); err != nil {
		return Dataset{}, err
	}
	rates, err := ratesOf(eurUSD)
	if err != nil {
		return Dataset{}, err
	}
	var daily []Point
	for _, r := range rates {
		if !r.date.Before(from) && !r.date.After(to) {
			daily = append(daily, Point{r.date, decimal6(new(big.Rat).Inv(r.value))})
		}
	}
	if len(daily) == 0 {
		return Dataset{}, fmt.Errorf("no EUR/USD rate between %s and %s", from.Format(time.DateOnly), to.Format(time.DateOnly))
	}
	return Dataset{
		ID: id, Source: "ecb", Symbol: "USD/EUR", Currency: "EUR", Interval: interval,
		From: from, To: to, FrozenAt: frozenAt, Points: bucket(daily, interval),
	}, nil
}

// Livret is a Livret A holding depositCents put in on from, valued at the end
// of each day as the app values it (BRIEF §4.11): deposits earn from the next
// fortnight, each fortnight earns rate / 24 at the rate of its first day and
// counts once the clock is past its last day, the year's interest is credited
// to the cent (half-even) on 31 December; value = balance + interest not yet
// credited.
func Livret(id string, history []store.LivretRate, depositCents int64, interval string, from, to, frozenAt time.Time) (Dataset, error) {
	if err := checkRange(interval, from, to); err != nil {
		return Dataset{}, err
	}
	if depositCents <= 0 {
		return Dataset{}, fmt.Errorf("deposit %d cents is not positive", depositCents)
	}
	var rates []dated
	for _, r := range history {
		v, ok := new(big.Rat).SetString(r.AnnualRate)
		if !ok || v.Sign() < 0 {
			return Dataset{}, fmt.Errorf("Livret A rate %q is not a rate", r.AnnualRate)
		}
		rates = append(rates, dated{r.ValidFrom, v})
	}
	slices.SortFunc(rates, func(a, b dated) int { return a.date.Compare(b.date) })

	balance := big.NewRat(depositCents, 100)
	accrued, eligible := new(big.Rat), new(big.Rat)
	fortnight := fortnightStart(from)
	var daily []Point
	for day := from; !day.After(to); day = day.AddDate(0, 0, 1) {
		for fortnightEnd(fortnight).Before(day) {
			rate := on(rates, fortnight)
			if rate == nil {
				return Dataset{}, fmt.Errorf("no Livret A rate on %s", fortnight.Format(time.DateOnly))
			}
			earned := new(big.Rat).Mul(eligible, rate)
			accrued.Add(accrued, earned.Quo(earned, big.NewRat(24, 1)))
			end := fortnightEnd(fortnight)
			if end.Month() == time.December && end.Day() == 31 {
				balance.Add(balance, cents(accrued))
				accrued.SetInt64(0)
			}
			fortnight = end.AddDate(0, 0, 1)
			eligible.Set(balance)
		}
		if on(rates, fortnight) == nil {
			return Dataset{}, fmt.Errorf("no Livret A rate on %s", fortnight.Format(time.DateOnly))
		}
		daily = append(daily, Point{day, decimal6(new(big.Rat).Add(balance, accrued))})
	}
	return Dataset{
		ID: id, Source: "livret-a", Currency: "EUR", Interval: interval,
		From: from, To: to, FrozenAt: frozenAt, Points: bucket(daily, interval),
	}, nil
}

// Cash is depositCents kept as notes from from to to: the same euros at the
// end of each period, beside what they buy ([InEurosOf]).
func Cash(id string, depositCents int64, interval string, from, to, frozenAt time.Time) (Dataset, error) {
	if err := checkRange(interval, from, to); err != nil {
		return Dataset{}, err
	}
	if depositCents <= 0 {
		return Dataset{}, fmt.Errorf("deposit %d cents is not positive", depositCents)
	}
	value := decimal6(big.NewRat(depositCents, 100))
	var daily []Point
	for day := from; !day.After(to); day = day.AddDate(0, 0, 1) {
		daily = append(daily, Point{day, value})
	}
	return Dataset{
		ID: id, Source: "cash", Currency: "EUR", Interval: interval,
		From: from, To: to, FrozenAt: frozenAt, Points: bucket(daily, interval),
	}, nil
}

// InEurosOf restates d, a monthly series in euros, in euros of its first
// month: each point times the index of that month over the index of its own
// (INSEE's, by month, each dated on its first day). What the money buys.
func InEurosOf(d Dataset, index []store.Rate) (Dataset, error) {
	if d.Interval != "1month" {
		return Dataset{}, fmt.Errorf("%s: only a monthly series, as INSEE's index", d.ID)
	}
	if d.Currency != "EUR" {
		return Dataset{}, fmt.Errorf("%s: only euros, not %s", d.ID, d.Currency)
	}
	months, err := ratesOf(index)
	if err != nil {
		return Dataset{}, err
	}
	of := func(p Point) (*big.Rat, error) {
		month := time.Date(p.Date.Year(), p.Date.Month(), 1, 0, 0, 0, 0, time.UTC)
		for _, m := range months {
			if m.date.Equal(month) {
				return m.value, nil
			}
		}
		return nil, fmt.Errorf("no INSEE index for %s", month.Format("2006-01"))
	}
	if len(d.Points) == 0 {
		return Dataset{}, fmt.Errorf("%s has no point", d.ID)
	}
	base, err := of(d.Points[0])
	if err != nil {
		return Dataset{}, err
	}
	out := d
	out.Points = make([]Point, 0, len(d.Points))
	for _, p := range d.Points {
		idx, err := of(p)
		if err != nil {
			return Dataset{}, err
		}
		value, ok := new(big.Rat).SetString(p.Value)
		if !ok {
			return Dataset{}, fmt.Errorf("value %q is not a number", p.Value)
		}
		value.Mul(value, base)
		out.Points = append(out.Points, Point{p.Date, decimal6(value.Quo(value, idx))})
	}
	out.Prices = "insee"
	return out, nil
}

func fortnightStart(d time.Time) time.Time {
	if d.Day() <= 15 {
		return time.Date(d.Year(), d.Month(), 1, 0, 0, 0, 0, time.UTC)
	}
	return time.Date(d.Year(), d.Month(), 16, 0, 0, 0, 0, time.UTC)
}

func fortnightEnd(start time.Time) time.Time {
	if start.Day() <= 15 {
		return time.Date(start.Year(), start.Month(), 15, 0, 0, 0, 0, time.UTC)
	}
	// Day 0 of next month is the last day of this one.
	return time.Date(start.Year(), start.Month()+1, 0, 0, 0, 0, 0, time.UTC)
}

// roundHalfEven rounds r (positive) to a multiple of 1/scale.
func roundHalfEven(r *big.Rat, scale int64) *big.Int {
	num := new(big.Int).Mul(r.Num(), big.NewInt(scale))
	q, rem := new(big.Int).QuoRem(num, r.Denom(), new(big.Int))
	switch new(big.Int).Mul(rem, big.NewInt(2)).Cmp(r.Denom()) {
	case 1:
		q.Add(q, big.NewInt(1))
	case 0:
		if q.Bit(0) == 1 {
			q.Add(q, big.NewInt(1))
		}
	}
	return q
}

// cents is r booked to the cent.
func cents(r *big.Rat) *big.Rat {
	return new(big.Rat).SetFrac(roundHalfEven(r, 100), big.NewInt(100))
}

// decimal6 writes r (positive) with six decimals at most.
func decimal6(r *big.Rat) string {
	q := roundHalfEven(r, 1_000_000).String()
	for len(q) < 7 {
		q = "0" + q
	}
	return trimZeros(q[:len(q)-6] + "." + q[len(q)-6:])
}
