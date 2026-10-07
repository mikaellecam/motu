# ADR-004: Twelve Data free plan, US listings only

Status: accepted
Date: 2026-10-08

## Context

BRIEF §8.5 asked to verify Twelve Data's free tier before building the backend: history depth, adjusted
prices, European exchange coverage, and symbols for the §8.4 catalogue. The answer settles the open decisions
§14.5 (provider and `dataFloor`) and §14.6 (catalogue and symbols).

### Findings (probed on 2026-10-07 with a Basic key)

| Question | Finding |
|---|---|
| Plan limits | Basic: 8 credits/min, 800/day, confirmed by `/api_usage`. One credit per symbol per request. |
| History depth (US) | Deep: AAPL from 1980-12-12, KO from 1970, SPY from 1993. Up to 5 000 bars per request. |
| Adjusted prices | Split-adjusted by default (AAPL closes at ~0.95 $ in January 2000, 124.81 $ the day before its 2020 4:1 split). `adjust=all` also adjusts for dividends; `adjust=splits` gives splits only. Both on the free plan. |
| European exchanges | **Not on the free plan.** LVMH (XPAR), CW8 (XPAR) and SAP (XETR) answer *"This symbol is available starting with the Grow or Venture plan"*. Search still lists them. |
| US listings of the same exposures | All available on the free plan, including OTC ADRs (LVMUY, EADSY, LRLCY…). |
| Quotes | `/quote` takes a comma-separated batch, returns last price, timestamp and `is_market_open`. |
| Paid alternative | Grow: 79 $/month (66 $ billed yearly), 55 credits/min, 20+ markets including Euronext. Pro: 229 $/month. |

## Options considered

### Free plan with US listings

The same companies and exposures through US listings: US-listed ETFs for the indices, ADRs for the European
stocks. Costs nothing, verified today. Every instrument is quoted in USD, so the catalogue has no euro-listed
ETF of the kind a French beginner would buy, and every asset carries currency risk.

### Pay for Grow

Keeps the catalogue as designed (Euronext and Xetra listings, EUR prices) and gives 55 credits/min. 79 $ a
month for the project's duration; European history depth could only be checked after subscribing.

### Free plan plus another free source for Europe

US data from Twelve Data, European history from a free site (Stooq…). Two providers to maintain, and unclear
terms for redistributing that data from our backend.

## Decision

**Twelve Data, free plan, US listings only** (chosen by the product owner, 2026-10-08). Exchange rates stay with
Frankfurter (ECB reference rates since 1999-01-04, no key).

- **`dataFloor` = 2000-01-03**: the first trading day of 2000, before the earliest trip preset (Bulle internet,
  2000-03-10). An asset appears in a trip from its first available bar, never before (no lookahead).
- **Adjustment: `adjust=all`** (dividends and splits, i.e. total return). The app has no dividend bookings, so
  split-only prices would silently drop the dividend part of an ETF's return (1–2 % a year for SPY). The
  consequence is shown in the provenance line: historical prices are adjusted, not the prices printed at the time.
- **The world ETF is ACWI** (MSCI All Country World, history from 2008-03-28), not URTH (MSCI World, from
  2012): it is the benchmark, the decomposition's "market" and the "sans rien toucher" counterfactual, and its
  longer history covers the 2008 trip preset.

### Symbol map (29 instruments)

| Catalogue entry (§8.4) | Symbol | Listing | History from |
|---|---|---|---|
| World ETF (MSCI ACWI) | ACWI | Nasdaq | 2008-03-28 |
| S&P 500 ETF | SPY | NYSE Arca | 1993-01-29 |
| Nasdaq 100 ETF | QQQ | Nasdaq | 1999-03-10 |
| Europe ETF (FTSE Developed Europe, replaces Stoxx Europe 600) | VGK | NYSE Arca | 2005-03-10 |
| Emerging markets ETF (MSCI EM) | EEM | NYSE Arca | 2008-01-02 |
| International government bonds (replaces euro government bonds) | BWX | NYSE Arca | 2007-10-11 |
| Aggregate bonds (US; replaces global aggregate) | AGG | NYSE Arca | 2003-09-29 |
| LVMH | LVMUY | OTC (ADR) | 2006-01-27 |
| TotalEnergies | TTE | NYSE (ADR) | 1991-10-25 |
| Airbus | EADSY | OTC (ADR) | 2007-01-09 |
| ASML | ASML | Nasdaq | 1995-03-15 |
| SAP | SAP | NYSE (ADR) | 1995-09-18 |
| Schneider Electric | SBGSY | OTC (ADR) | 2010-01-20 |
| L'Oréal | LRLCY | OTC (ADR) | 2007-04-18 |
| Sanofi | SNY | Nasdaq (ADR) | 2002-07-01 |
| Siemens | SIEGY | OTC (ADR) | 1996-11-18 |
| Novo Nordisk | NVO | NYSE (ADR) | 1981-07-08 |
| Hermès | HESAY | OTC (ADR) | 2011-01-26 |
| BNP Paribas | BNPQY | OTC (ADR) | 2003-06-05 |
| Apple | AAPL | Nasdaq | 1980-12-12 |
| Microsoft | MSFT | Nasdaq | 1986-03-13 |
| Nvidia | NVDA | Nasdaq | 1999-01-22 |
| Amazon | AMZN | Nasdaq | 1997-05-15 |
| Alphabet | GOOGL | Nasdaq | 2004-08-19 |
| Meta | META | Nasdaq | 2012-05-18 |
| Tesla | TSLA | Nasdaq | 2010-06-29 |
| Berkshire Hathaway | BRK.B | NYSE | 1996-05-09 |
| JPMorgan | JPM | NYSE | 1983-12-30 |
| Coca-Cola | KO | NYSE | 1970-01-02 |

"History from" is the provider's first daily bar; the app sees each asset from max(`dataFloor`, that date).

### Credit budget (800/day, 8/min)

- **Backfill** from `dataFloor`: about 6 700 trading days per asset, so two requests of 5 000 bars each,
  about 60 credits for the catalogue, spread over ~8 minutes. Runs once, resumable (M2-3).
- **Daily append** after the US close: 29 credits.
- **Quotes**: one batch every **30 minutes** during the US session (09:30–16:00 New York, 13 batches × 29 =
  377 credits). Every 15 minutes would cost 754 credits and, with the daily append, leave almost nothing for
  retries or content freezes. The app's 15-minute quote TTL (§6.2) stays: it reads the backend's cache.
- Total ≈ 410 credits/day, about half the limit.

## Consequences

- Every asset is in USD. Currency risk is present everywhere, which suits the « Pourquoi ça bouge ? »
  decomposition and node 9 (« Le piège du dollar »), but no asset shows a zero currency component.
- European companies appear through ADRs: a different share class quoted in USD, sometimes a fraction of one
  share (LVMUY is 1/5 of an LVMH share). The asset page has to say so (copy to approve
  with M4-4).
- All listings follow the US calendar and hours, including OTC. The domain `Exchange` enum needs an `otc`
  value (New York hours), and trip days should come from the exchanges actually in the catalogue rather than
  every enum value: follow-up issue M1-12.
- Lessons that name "MSCI World" use the world ETF (ACWI) data; content text says « ETF Monde ».
- Switching to Grow later only changes symbols and listings (data, not code): the provider adapter is the same.
