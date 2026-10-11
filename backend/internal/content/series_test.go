package content

import (
	"strings"
	"testing"
	"time"

	"finance-companion/backend/internal/store"
)

// EUR→USD rates: dollars per euro, ECB business days only.
func eurUSD(pairs ...string) []store.Rate {
	var out []store.Rate
	for i := 0; i+1 < len(pairs); i += 2 {
		out = append(out, store.Rate{Date: day(pairs[i]), Rate: pairs[i+1]})
	}
	return out
}

func TestToEuros_EachCloseAtTheRateOfItsDayOrTheLastBefore(t *testing.T) {
	d, err := Freeze(spec("1day", "2022-01-03", "2022-01-05"), bars(
		"2022-01-03", "182", "2022-01-04", "180", "2022-01-05", "175",
	), day("2026-10-11"))
	if err != nil {
		t.Fatal(err)
	}
	// No rate on the 4th: the 3rd's applies.
	eur, err := ToEuros(d, eurUSD("2021-12-31", "1.1326", "2022-01-03", "1.1355", "2022-01-05", "1.1279"))
	if err != nil {
		t.Fatal(err)
	}
	// 182 / 1.1355, 180 / 1.1355, 175 / 1.1279, six decimals.
	if got := points(t, eur); got != "2022-01-03=160.281814 2022-01-04=158.520476 2022-01-05=155.155599" {
		t.Errorf("points: %s", got)
	}
	if eur.Currency != "EUR" || eur.FX != "ecb" || eur.Asset != "apple" || eur.Source != "twelvedata" {
		t.Errorf("provenance: %+v", eur)
	}
}

func TestToEuros_Refuses(t *testing.T) {
	d, _ := Freeze(spec("1day", "2022-01-03", "2022-01-03"), bars("2022-01-03", "182"), day("2026-10-11"))
	if _, err := ToEuros(d, eurUSD("2022-01-04", "1.13")); err == nil || !strings.Contains(err.Error(), "no EUR/USD rate on or before 2022-01-03") {
		t.Errorf("no rate before: %v", err)
	}
	if _, err := ToEuros(d, eurUSD("2022-01-03", "0")); err == nil {
		t.Error("a zero rate")
	}
	d.Currency = "EUR"
	if _, err := ToEuros(d, eurUSD("2022-01-03", "1.13")); err == nil || !strings.Contains(err.Error(), "already in EUR") {
		t.Errorf("already in euros: %v", err)
	}
}

func TestDollarInEuros_OneOverTheRate_MonthEnds(t *testing.T) {
	d, err := DollarInEuros("ds.usd", eurUSD(
		"2016-12-30", "1.0541", "2017-01-02", "1.0465", "2017-01-31", "1.0755", "2017-02-28", "1.0597",
	), "1month", day("2016-12-30"), day("2017-02-28"), day("2026-10-11"))
	if err != nil {
		t.Fatal(err)
	}
	if got := points(t, d); got != "2016-12-30=0.948677 2017-01-31=0.9298 2017-02-28=0.943663" {
		t.Errorf("points: %s", got)
	}
	if d.Source != "ecb" || d.Asset != "" || d.Symbol != "USD/EUR" || d.Currency != "EUR" || d.Adjusted {
		t.Errorf("provenance: %+v", d)
	}
}

var livretRates = []store.LivretRate{
	{ValidFrom: day("2015-08-01"), AnnualRate: "0.0075"},
	{ValidFrom: day("2020-02-01"), AnnualRate: "0.005"},
}

func TestLivret_FortnightsEarnRateOver24_CreditedOn31December(t *testing.T) {
	// 10 000 € on 31 December 2015 earn from 1 January: 3,125 € a fortnight
	// at 0,75 %. A fortnight counts once the clock is past its last day.
	d, err := Livret("ds.livret", livretRates, 1000000, "1month", day("2015-12-31"), day("2017-01-31"), day("2026-10-11"))
	if err != nil {
		t.Fatal(err)
	}
	got := strings.Fields(points(t, d))
	want := map[int]string{
		0:  "2015-12-31=10000",
		1:  "2016-01-31=10003.125",
		12: "2016-12-31=10071.875",
		// 75 € credited, then 1–15 January earns on 10 075 €.
		13: "2017-01-31=10078.148438",
	}
	if len(got) != 14 {
		t.Fatalf("%d points: %v", len(got), got)
	}
	for i, w := range want {
		if got[i] != w {
			t.Errorf("point %d: %s, want %s", i, got[i], w)
		}
	}
	if d.Source != "livret-a" || d.Asset != "" || d.Currency != "EUR" || d.Adjusted || d.Interval != "1month" {
		t.Errorf("provenance: %+v", d)
	}
}

func TestLivret_DepositMidFortnightWaits_RateOfTheFortnightsFirstDay(t *testing.T) {
	// In on 10 January: earns from the 16th. 0,5 % from 1 February 2020.
	d, err := Livret("ds.livret", livretRates, 1000000, "1day", day("2020-01-10"), day("2020-02-17"), day("2026-10-11"))
	if err != nil {
		t.Fatal(err)
	}
	at := map[string]string{}
	for _, p := range d.Points {
		at[p.Date.Format(time.DateOnly)] = p.Value
	}
	for date, want := range map[string]string{
		"2020-01-10": "10000",
		"2020-01-31": "10000",     // 16–31 January still open
		"2020-02-01": "10003.125", // closed at 0,75 %
		"2020-02-16": "10005.208333",
	} {
		if at[date] != want {
			t.Errorf("%s: %s, want %s", date, at[date], want)
		}
	}
}

func TestLivret_Refuses(t *testing.T) {
	if _, err := Livret("x", livretRates, 1000000, "1month", day("2015-01-01"), day("2015-12-31"), day("2026-10-11")); err == nil ||
		!strings.Contains(err.Error(), "no Livret A rate") {
		t.Errorf("before the history: %v", err)
	}
	if _, err := Livret("x", livretRates, 0, "1month", day("2016-01-01"), day("2016-12-31"), day("2026-10-11")); err == nil {
		t.Error("nothing deposited")
	}
}

func TestEncode_OmitsWhatADatasetIsNotOf_AndNamesTheRates(t *testing.T) {
	d, _ := Livret("ds.livret", livretRates, 1000000, "1month", day("2015-12-31"), day("2016-01-31"), day("2026-10-11"))
	text := string(d.Encode())
	if strings.Contains(text, `"asset"`) || strings.Contains(text, `"symbol"`) || strings.Contains(text, `"fx"`) {
		t.Errorf("livret:\n%s", text)
	}
	a, _ := Freeze(spec("1day", "2022-01-03", "2022-01-03"), bars("2022-01-03", "182"), day("2026-10-11"))
	eur, _ := ToEuros(a, eurUSD("2022-01-03", "1.1355"))
	if text := string(eur.Encode()); !strings.Contains(text, `"fx": "ecb"`) || !strings.Contains(text, `"asset": "apple"`) {
		t.Errorf("converted:\n%s", text)
	}
}
