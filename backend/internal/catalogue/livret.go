package catalogue

import "finance-companion/backend/internal/store"

func rate(from, annual string) store.LivretRate {
	return store.LivretRate{ValidFrom: date(from), AnnualRate: annual}
}

// LivretRates is the Livret A rate history, from the rate in force on the
// data floor (2000-01-03). Sources: the rate decisions as listed by
// mes-livrets.fr and selectra.info, which agree.
var LivretRates = []store.LivretRate{
	rate("1999-08-01", "0.0225"),
	rate("2000-07-01", "0.03"),
	rate("2003-08-01", "0.0225"),
	rate("2005-08-01", "0.02"),
	rate("2006-02-01", "0.0225"),
	rate("2006-08-01", "0.0275"),
	rate("2007-08-01", "0.03"),
	rate("2008-02-01", "0.035"),
	rate("2008-08-01", "0.04"),
	rate("2009-02-01", "0.025"),
	rate("2009-05-01", "0.0175"),
	rate("2009-08-01", "0.0125"),
	rate("2010-08-01", "0.0175"),
	rate("2011-02-01", "0.02"),
	rate("2011-08-01", "0.0225"),
	rate("2013-02-01", "0.0175"),
	rate("2013-08-01", "0.0125"),
	rate("2014-08-01", "0.01"),
	rate("2015-08-01", "0.0075"),
	rate("2020-02-01", "0.005"),
	rate("2022-02-01", "0.01"),
	rate("2022-08-01", "0.02"),
	rate("2023-02-01", "0.03"),
	rate("2025-02-01", "0.024"),
	rate("2025-08-01", "0.017"),
	rate("2026-02-01", "0.015"),
	rate("2026-08-01", "0.017"),
}

// LivretCeilings is the deposit ceiling history. The first entry is the
// 100,000 F ceiling converted at 6.55957 F/€, in force on the data floor;
// the euro changeover rounded it to 15,300 €. The two 2012 decrees
// (2012-1056, 2012-1445) raised it twice.
var LivretCeilings = []store.LivretCeiling{
	{ValidFrom: date("1999-08-01"), AmountCents: 1524490},
	{ValidFrom: date("2002-01-01"), AmountCents: 1530000},
	{ValidFrom: date("2012-10-01"), AmountCents: 1912500},
	{ValidFrom: date("2013-01-01"), AmountCents: 2295000},
}
