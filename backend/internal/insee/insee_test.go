package insee

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func day(s string) time.Time {
	d, _ := time.Parse(time.DateOnly, s)
	return d
}

func TestConsumerPrices_EachMonthOnItsFirstDay_OldestFirst(t *testing.T) {
	reply, err := os.ReadFile("testdata/cpi.xml")
	if err != nil {
		t.Fatal(err)
	}
	var asked string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		asked = r.URL.String()
		w.Write(reply)
	}))
	defer server.Close()

	got, err := (&INSEE{BaseURL: server.URL, HTTP: server.Client()}).ConsumerPrices(context.Background(),
		day("2015-12-31"), day("2016-02-29"))
	if err != nil {
		t.Fatal(err)
	}
	if asked != "/data/SERIES_BDM/011814630?endPeriod=2016-02&startPeriod=2015-12" {
		t.Errorf("asked %s", asked)
	}
	var months []string
	for _, r := range got {
		months = append(months, r.Date.Format(time.DateOnly)+" "+r.Rate)
	}
	if strings.Join(months, ", ") != "2015-12-01 82.71, 2016-01-01 81.92, 2016-02-01 82.13" {
		t.Errorf("index: %v", months)
	}
}

func TestConsumerPrices_Refuses(t *testing.T) {
	for name, c := range map[string]struct {
		status int
		body   string
		want   string
	}{
		"an HTTP error":  {http.StatusServiceUnavailable, "", "HTTP 503"},
		"no observation": {http.StatusOK, `<message:StructureSpecificData xmlns:message="m"><message:DataSet/></message:StructureSpecificData>`, "no index between 2015-12 and 2016-02"},
		"not a number":   {http.StatusOK, `<D><DataSet><Series><Obs TIME_PERIOD="2016-01" OBS_VALUE="n/a"/></Series></DataSet></D>`, `"n/a"`},
		"not a month":    {http.StatusOK, `<D><DataSet><Series><Obs TIME_PERIOD="2016-Q1" OBS_VALUE="82"/></Series></DataSet></D>`, `"2016-Q1"`},
	} {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(c.status)
			w.Write([]byte(c.body))
		}))
		_, err := (&INSEE{BaseURL: server.URL, HTTP: server.Client()}).ConsumerPrices(context.Background(),
			day("2015-12-31"), day("2016-02-29"))
		server.Close()
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: %v, want %q", name, err, c.want)
		}
	}
}
