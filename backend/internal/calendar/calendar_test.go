package calendar

import (
	"slices"
	"testing"
	"time"
)

func dates(t *testing.T, days []time.Time) []string {
	t.Helper()
	out := make([]string, len(days))
	for i, d := range days {
		out[i] = d.Format(time.DateOnly)
	}
	return out
}

func TestUSHolidays(t *testing.T) {
	cases := map[int][]string{
		// NYSE's published list.
		2025: {"2025-01-01", "2025-01-09", "2025-01-20", "2025-02-17", "2025-04-18", "2025-05-26",
			"2025-06-19", "2025-07-04", "2025-09-01", "2025-11-27", "2025-12-25"},
		// July 4 on a Saturday closes the Friday before.
		2026: {"2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25", "2026-06-19",
			"2026-07-03", "2026-09-07", "2026-11-26", "2026-12-25"},
		// Christmas on a Saturday closes Friday the 24th; New Year's Day 2022
		// on a Saturday closes nothing in 2021. No Juneteenth before 2022.
		2021: {"2021-01-01", "2021-01-18", "2021-02-15", "2021-04-02", "2021-05-31", "2021-07-05",
			"2021-09-06", "2021-11-25", "2021-12-24"},
		// Juneteenth on a Sunday closes the Monday after.
		2022: {"2022-01-17", "2022-02-21", "2022-04-15", "2022-05-30", "2022-06-20", "2022-07-04",
			"2022-09-05", "2022-11-24", "2022-12-26"},
		// The week after 9/11.
		2001: {"2001-01-01", "2001-01-15", "2001-02-19", "2001-04-13", "2001-05-28", "2001-07-04",
			"2001-09-03", "2001-09-11", "2001-09-12", "2001-09-13", "2001-09-14", "2001-11-22",
			"2001-12-25"},
		// Hurricane Sandy.
		2012: {"2012-01-02", "2012-01-16", "2012-02-20", "2012-04-06", "2012-05-28", "2012-07-04",
			"2012-09-03", "2012-10-29", "2012-10-30", "2012-11-22", "2012-12-25"},
	}
	for year, want := range cases {
		if got := dates(t, USHolidays(year)); !slices.Equal(got, want) {
			t.Errorf("%d:\n got %v\nwant %v", year, got, want)
		}
	}
}

func TestUSHolidaysAreWeekdays(t *testing.T) {
	for year := FirstYear; year <= 2040; year++ {
		for _, d := range USHolidays(year) {
			if d.Year() != year || d.Weekday() == time.Saturday || d.Weekday() == time.Sunday {
				t.Errorf("%d: %s", year, d.Format(time.DateOnly))
			}
		}
	}
}

func TestEaster(t *testing.T) {
	for year, want := range map[int]string{2000: "2000-04-23", 2008: "2008-03-23", 2011: "2011-04-24", 2038: "2038-04-25"} {
		if got := easter(year).Format(time.DateOnly); got != want {
			t.Errorf("%d: got %s, want %s", year, got, want)
		}
	}
}

func TestExchanges(t *testing.T) {
	for _, e := range []string{"nyse", "nasdaq", "otc"} {
		if got, ok := Holidays(e, 2025); !ok || !slices.Equal(got, USHolidays(2025)) {
			t.Errorf("%s does not follow the NYSE holidays", e)
		}
	}
	if _, ok := Holidays("euronext", 2025); ok {
		t.Error("euronext is served")
	}
}

func early(days []EarlyClose) []string {
	out := make([]string, len(days))
	for i, e := range days {
		out[i] = e.Date.Format(time.DateOnly) + " " + e.Close
	}
	return out
}

func TestUSEarlyCloses(t *testing.T) {
	cases := map[int][]string{
		// 4 July on a Thursday before 2013 closes early on Friday the 5th,
		// not on the 3rd.
		2002: {"2002-07-05 13:00", "2002-11-29 13:00", "2002-12-24 13:00"},
		// Christmas on a Thursday: the 26th closed early too, ad hoc.
		2003: {"2003-07-03 13:00", "2003-11-28 13:00", "2003-12-24 13:00", "2003-12-26 13:00"},
		// 3 July on a Saturday, 24 December on a Friday (a holiday): only the
		// day after Thanksgiving.
		2004: {"2004-11-26 13:00"},
		// A systems problem stopped trading at 15:56.
		2005: {"2005-06-01 15:56", "2005-11-25 13:00"},
		// Christmas on a Thursday, no ad hoc close on the 26th.
		2008: {"2008-07-03 13:00", "2008-11-28 13:00", "2008-12-24 13:00"},
		// From 2013, 4 July on a Thursday closes early on Wednesday the 3rd.
		2013: {"2013-07-03 13:00", "2013-11-29 13:00", "2013-12-24 13:00"},
		// 3 July on a Saturday, 24 December on a Friday.
		2021: {"2021-11-26 13:00"},
		// NYSE's published lists.
		2025: {"2025-07-03 13:00", "2025-11-28 13:00", "2025-12-24 13:00"},
		2026: {"2026-11-27 13:00", "2026-12-24 13:00"}, // 3 July on a Friday is a holiday
		2027: {"2027-11-26 13:00"},
		2028: {"2028-07-03 13:00", "2028-11-24 13:00"}, // 24 December on a Sunday
		// The rule, as exchange_calendars applies it.
		2029: {"2029-07-03 13:00", "2029-11-23 13:00", "2029-12-24 13:00"},
		2032: {"2032-11-26 13:00"},
	}
	for year, want := range cases {
		if got := early(USEarlyCloses(year)); !slices.Equal(got, want) {
			t.Errorf("%d:\n got %v\nwant %v", year, got, want)
		}
	}
	n := 0
	for year := FirstYear; year <= listedTo; year++ {
		n += len(USEarlyCloses(year))
	}
	if n != len(earlyCloses) || n != 64 {
		t.Errorf("%d early closes from %d to %d, %d listed", n, FirstYear, listedTo, len(earlyCloses))
	}
}

func TestEarlyCloseRuleMatchesTheListSince2013(t *testing.T) {
	for year := 2013; year <= listedTo; year++ {
		if got, want := early(earlyCloseRule(year)), early(USEarlyCloses(year)); !slices.Equal(got, want) {
			t.Errorf("%d:\n rule %v\n list %v", year, got, want)
		}
	}
}

func TestUSEarlyClosesAreSessions(t *testing.T) {
	for year := FirstYear; year <= 2040; year++ {
		holidays := USHolidays(year)
		for i, e := range USEarlyCloses(year) {
			at, err := time.Parse("15:04", e.Close)
			if e.Date.Year() != year || e.Date.Weekday() == time.Saturday || e.Date.Weekday() == time.Sunday ||
				slices.ContainsFunc(holidays, e.Date.Equal) || err != nil || at.Hour() >= 16 ||
				(i > 0 && !e.Date.After(USEarlyCloses(year)[i-1].Date)) {
				t.Errorf("%d: %v", year, e)
			}
		}
	}
}

func TestEarlyClosesExchanges(t *testing.T) {
	for _, e := range []string{"nyse", "nasdaq", "otc"} {
		if got, ok := EarlyCloses(e, 2025); !ok || !slices.Equal(got, USEarlyCloses(2025)) {
			t.Errorf("%s does not follow the NYSE early closes", e)
		}
	}
	if _, ok := EarlyCloses("euronext", 2025); ok {
		t.Error("euronext is served")
	}
}
