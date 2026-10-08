// Package calendar computes exchange holidays: the weekdays without a
// session. Every other weekday trades. Early closes are not modelled.
package calendar

import (
	"slices"
	"time"
)

// FirstYear is the first year served: the data floor's year. Earlier years
// would need closures this file does not list.
const FirstYear = 2000

// Holidays returns an exchange's holidays in year, oldest first, and false
// for an exchange it does not know. Nasdaq and the OTC market follow the
// NYSE calendar.
func Holidays(exchange string, year int) ([]time.Time, bool) {
	switch exchange {
	case "nyse", "nasdaq", "otc":
		return USHolidays(year), true
	}
	return nil, false
}

// closures are the unscheduled full-day NYSE closures since FirstYear. A new
// one (a national day of mourning, a storm) is added here when it happens.
var closures = []string{
	"2001-09-11", "2001-09-12", "2001-09-13", "2001-09-14", // September 11 attacks
	"2004-06-11",               // Ronald Reagan
	"2007-01-02",               // Gerald Ford
	"2012-10-29", "2012-10-30", // Hurricane Sandy
	"2018-12-05", // George H. W. Bush
	"2025-01-09", // Jimmy Carter
}

// USHolidays applies the NYSE holiday rules (Rule 7.2) to year, plus the
// unscheduled closures. A fixed-date holiday on a Sunday moves to Monday and
// one on a Saturday to Friday, except New Year's Day: the Friday before it
// ends the accounting year and stays open.
func USHolidays(year int) []time.Time {
	day := func(month time.Month, d int) time.Time { return time.Date(year, month, d, 0, 0, 0, 0, time.UTC) }
	// nth weekday of the month; n < 0 counts from the month's end.
	nth := func(n int, weekday time.Weekday, month time.Month) time.Time {
		if n < 0 {
			last := day(month+1, 0)
			return last.AddDate(0, 0, -((int(last.Weekday()) - int(weekday) + 7) % 7))
		}
		first := day(month, 1)
		return first.AddDate(0, 0, (int(weekday)-int(first.Weekday())+7)%7+7*(n-1))
	}
	observed := func(d time.Time) time.Time {
		switch d.Weekday() {
		case time.Saturday:
			return d.AddDate(0, 0, -1)
		case time.Sunday:
			return d.AddDate(0, 0, 1)
		}
		return d
	}

	var out []time.Time
	if newYear := day(time.January, 1); newYear.Weekday() != time.Saturday {
		out = append(out, observed(newYear))
	}
	out = append(out,
		nth(3, time.Monday, time.January),  // Martin Luther King Jr. Day
		nth(3, time.Monday, time.February), // Washington's Birthday
		easter(year).AddDate(0, 0, -2),     // Good Friday
		nth(-1, time.Monday, time.May),     // Memorial Day
		observed(day(time.July, 4)),
		nth(1, time.Monday, time.September),  // Labor Day
		nth(4, time.Thursday, time.November), // Thanksgiving
		observed(day(time.December, 25)),
	)
	if year >= 2022 {
		out = append(out, observed(day(time.June, 19))) // Juneteenth
	}
	for _, c := range closures {
		if d, _ := time.Parse(time.DateOnly, c); d.Year() == year {
			out = append(out, d)
		}
	}
	slices.SortFunc(out, time.Time.Compare)
	return out
}

// easter is Easter Sunday in the Gregorian calendar (the anonymous
// algorithm, Meeus 1991).
func easter(year int) time.Time {
	a, b, c := year%19, year/100, year%100
	d, e := b/4, b%4
	f := (b + 8) / 25
	g := (b - f + 1) / 3
	h := (19*a + b - d - g + 15) % 30
	i, k := c/4, c%4
	l := (32 + 2*e + 2*i - h - k) % 7
	m := (a + 11*h + 22*l) / 451
	month := (h + l - 7*m + 114) / 31
	return time.Date(year, time.Month(month), (h+l-7*m+114)%31+1, 0, 0, 0, 0, time.UTC)
}
