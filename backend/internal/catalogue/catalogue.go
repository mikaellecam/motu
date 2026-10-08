// Package catalogue is the V1 instrument list (BRIEF §8.4, ADR-004): US
// listings on the provider's free plan. Ids are stable and name the exposure
// or company, not the ticker, so a provider or listing change keeps them.
package catalogue

import (
	"time"

	"finance-companion/backend/internal/store"
)

func date(s string) time.Time {
	t, err := time.Parse(time.DateOnly, s)
	if err != nil {
		panic(err)
	}
	return t
}

func asset(id, symbol, name, kind, exchange, region, since string) store.Asset {
	return store.Asset{
		ID: id, Symbol: symbol, Name: name, Type: kind, Exchange: exchange,
		Currency: "USD", Region: region, ListingDate: date(since), ProviderSymbol: symbol,
	}
}

// Assets is the catalogue. ListingDate is the provider's first daily bar.
var Assets = []store.Asset{
	asset("world", "ACWI", "iShares MSCI ACWI ETF", "etf", "nasdaq", "world", "2008-03-28"),
	asset("sp500", "SPY", "SPDR S&P 500 ETF Trust", "etf", "nyse", "us", "1993-01-29"),
	asset("nasdaq100", "QQQ", "Invesco QQQ Trust", "etf", "nasdaq", "us", "1999-03-10"),
	asset("europe", "VGK", "Vanguard FTSE Europe ETF", "etf", "nyse", "europe", "2005-03-10"),
	asset("emerging", "EEM", "iShares MSCI Emerging Markets ETF", "etf", "nyse", "emerging", "2009-07-21"),
	asset("intl-bonds", "BWX", "SPDR Bloomberg International Treasury Bond ETF", "etf", "nyse", "world", "2007-10-11"),
	asset("us-bonds", "AGG", "iShares Core U.S. Aggregate Bond ETF", "etf", "nyse", "us", "2003-09-29"),

	asset("lvmh", "LVMUY", "LVMH", "stock", "otc", "europe", "2006-01-27"),
	asset("totalenergies", "TTE", "TotalEnergies", "stock", "nyse", "europe", "1991-10-25"),
	asset("airbus", "EADSY", "Airbus", "stock", "otc", "europe", "2007-01-09"),
	asset("asml", "ASML", "ASML", "stock", "nasdaq", "europe", "1995-03-15"),
	asset("sap", "SAP", "SAP", "stock", "nyse", "europe", "1995-09-18"),
	asset("schneider", "SBGSY", "Schneider Electric", "stock", "otc", "europe", "2010-01-20"),
	asset("loreal", "LRLCY", "L'Oréal", "stock", "otc", "europe", "2007-04-18"),
	asset("sanofi", "SNY", "Sanofi", "stock", "nasdaq", "europe", "2002-07-01"),
	asset("siemens", "SIEGY", "Siemens", "stock", "otc", "europe", "1996-11-18"),
	asset("novo-nordisk", "NVO", "Novo Nordisk", "stock", "nyse", "europe", "1981-07-08"),
	asset("hermes", "HESAY", "Hermès", "stock", "otc", "europe", "2011-01-26"),
	asset("bnp-paribas", "BNPQY", "BNP Paribas", "stock", "otc", "europe", "2003-06-05"),

	asset("apple", "AAPL", "Apple", "stock", "nasdaq", "us", "1980-12-12"),
	asset("microsoft", "MSFT", "Microsoft", "stock", "nasdaq", "us", "1986-03-13"),
	asset("nvidia", "NVDA", "Nvidia", "stock", "nasdaq", "us", "1999-01-22"),
	asset("amazon", "AMZN", "Amazon", "stock", "nasdaq", "us", "1997-05-15"),
	asset("alphabet", "GOOGL", "Alphabet", "stock", "nasdaq", "us", "2004-08-19"),
	asset("meta", "META", "Meta", "stock", "nasdaq", "us", "2012-05-18"),
	asset("tesla", "TSLA", "Tesla", "stock", "nasdaq", "us", "2010-06-29"),
	asset("berkshire", "BRK.B", "Berkshire Hathaway", "stock", "nyse", "us", "1996-05-09"),
	asset("jpmorgan", "JPM", "JPMorgan Chase", "stock", "nyse", "us", "1983-12-30"),
	asset("coca-cola", "KO", "Coca-Cola", "stock", "nyse", "us", "1970-01-02"),
}
