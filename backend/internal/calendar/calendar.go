// Package calendar computes exchange holidays, the weekdays without a
// session, and early closes, the sessions that end before the regular close.
// Every other weekday trades regular hours.
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

// EarlyClose is a session that ends before the regular close, at Close in
// the exchange's local time ("13:00").
type EarlyClose struct {
	Date  time.Time
	Close string
}

// EarlyCloses returns an exchange's early closes in year, oldest first, and
// false for an exchange it does not know.
func EarlyCloses(exchange string, year int) ([]EarlyClose, bool) {
	switch exchange {
	case "nyse", "nasdaq", "otc":
		return USEarlyCloses(year), true
	}
	return nil, false
}

// earlyCloses are the NYSE early closes from FirstYear to listedTo, New York
// time, from pandas_market_calendars 5.5 (its NYSE calendar follows the
// NYSE's own history of closings), checked against exchange_calendars 4.13
// (XNYS) and, from 2026, nyse.com. They differ on 2005-06-01 only, which
// exchange_calendars leaves out.
var earlyCloses = []string{
	"2000-07-03 13:00", "2000-11-24 13:00",
	"2001-07-03 13:00", "2001-11-23 13:00", "2001-12-24 13:00",
	"2002-07-05 13:00", "2002-11-29 13:00", "2002-12-24 13:00", // 5 July: before 2013, a Thursday 4 July closed early the day after
	"2003-07-03 13:00", "2003-11-28 13:00", "2003-12-24 13:00", "2003-12-26 13:00", // ad hoc: not in 2008, 2014 or 2025
	"2004-11-26 13:00",
	"2005-06-01 15:56", "2005-11-25 13:00", // 1 June: a systems problem
	"2006-07-03 13:00", "2006-11-24 13:00",
	"2007-07-03 13:00", "2007-11-23 13:00", "2007-12-24 13:00",
	"2008-07-03 13:00", "2008-11-28 13:00", "2008-12-24 13:00",
	"2009-11-27 13:00", "2009-12-24 13:00",
	"2010-11-26 13:00",
	"2011-11-25 13:00",
	"2012-07-03 13:00", "2012-11-23 13:00", "2012-12-24 13:00",
	"2013-07-03 13:00", "2013-11-29 13:00", "2013-12-24 13:00",
	"2014-07-03 13:00", "2014-11-28 13:00", "2014-12-24 13:00",
	"2015-11-27 13:00", "2015-12-24 13:00",
	"2016-11-25 13:00",
	"2017-07-03 13:00", "2017-11-24 13:00",
	"2018-07-03 13:00", "2018-11-23 13:00", "2018-12-24 13:00",
	"2019-07-03 13:00", "2019-11-29 13:00", "2019-12-24 13:00",
	"2020-11-27 13:00", "2020-12-24 13:00",
	"2021-11-26 13:00",
	"2022-11-25 13:00",
	"2023-07-03 13:00", "2023-11-24 13:00",
	"2024-07-03 13:00", "2024-11-29 13:00", "2024-12-24 13:00",
	"2025-07-03 13:00", "2025-11-28 13:00", "2025-12-24 13:00",
	"2026-11-27 13:00", "2026-12-24 13:00",
	"2027-11-26 13:00",
	"2028-07-03 13:00", "2028-11-24 13:00",
}

// listedTo is the last year of earlyCloses: the last one nyse.com publishes.
const listedTo = 2028

// USEarlyCloses lists the NYSE early closes of year; after listedTo, it
// applies earlyCloseRule.
func USEarlyCloses(year int) []EarlyClose {
	if year > listedTo {
		return earlyCloseRule(year)
	}
	var out []EarlyClose
	for _, e := range earlyCloses {
		if d, _ := time.Parse(time.DateOnly, e[:10]); d.Year() == year {
			out = append(out, EarlyClose{d, e[11:]})
		}
	}
	return out
}

// earlyCloseRule is the sources' rule since 2013: 13:00 on 3 July and
// 24 December when they fall Monday to Thursday, and on the day after
// Thanksgiving.
func earlyCloseRule(year int) []EarlyClose {
	var out []EarlyClose
	for _, d := range []time.Time{date(year, time.July, 3), date(year, time.December, 24)} {
		if d.Weekday() >= time.Monday && d.Weekday() <= time.Thursday {
			out = append(out, EarlyClose{d, "13:00"})
		}
	}
	out = append(out, EarlyClose{nth(year, 4, time.Thursday, time.November).AddDate(0, 0, 1), "13:00"})
	slices.SortFunc(out, func(a, b EarlyClose) int { return a.Date.Compare(b.Date) })
	return out
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
	day := func(month time.Month, d int) time.Time { return date(year, month, d) }
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
		nth(year, 3, time.Monday, time.January),  // Martin Luther King Jr. Day
		nth(year, 3, time.Monday, time.February), // Washington's Birthday
		easter(year).AddDate(0, 0, -2),           // Good Friday
		nth(year, -1, time.Monday, time.May),     // Memorial Day
		observed(day(time.July, 4)),
		nth(year, 1, time.Monday, time.September),  // Labor Day
		nth(year, 4, time.Thursday, time.November), // Thanksgiving
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

func date(year int, month time.Month, d int) time.Time {
	return time.Date(year, month, d, 0, 0, 0, 0, time.UTC)
}

// nth is the nth weekday of the month; n < 0 counts from the month's end.
func nth(year, n int, weekday time.Weekday, month time.Month) time.Time {
	if n < 0 {
		last := date(year, month+1, 0)
		return last.AddDate(0, 0, -((int(last.Weekday()) - int(weekday) + 7) % 7))
	}
	first := date(year, month, 1)
	return first.AddDate(0, 0, (int(weekday)-int(first.Weekday())+7)%7+7*(n-1))
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
