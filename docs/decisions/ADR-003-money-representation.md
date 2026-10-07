# ADR-003: Money as integer cents, quantities as fixed point, prices as Decimal

Status: accepted
Date: 2026-10-07

## Context

The app computes with money everywhere: cash and fees, order fills, valuations, P&L, returns, DCA, Livret
interest, FX conversion (`BRIEF.md` §7). Requirements:

- A wallet's cash is the sum of its ledger and must be exact: starting cash minus buys plus sells minus fees
  must equal what the screen shows, to the cent, forever.
- Prices and FX rates have more precision than cents (EUR/USD `1.0876`, a price of `177.5700`).
- Fractional shares go down to 6 decimals (§4.6).
- Amounts in different currencies must never be added by mistake (an Apple price is in USD, the wallet in EUR).
- Rounding happens half-even, in one well-defined place (§7).
- The school brief asks for unit tests on these calculations, including edge cases.

## Options considered

### `double` everywhere

Simple and fast, but binary floating point cannot represent most decimal amounts: `0.1 + 0.2 != 0.3`. Errors
accumulate across thousands of ledger rows and trip days, equality checks become fragile, and every
comparison needs a tolerance. Not acceptable for money.

### Integer cents everywhere

Exact sums and comparisons. But prices and FX rates need more than two decimals, and `quantity × price × rate`
needs precision in the intermediate product; forcing cents on them loses information at every step.

### `Decimal` everywhere

Exact decimal arithmetic with arbitrary scale. But division is rational (`1 / 3` does not terminate, so a
scale must be chosen anyway), ledger amounts would carry arbitrary scales, and on its own it does not stop
adding EUR to USD.

### A money package (`money2`)

A complete model with currencies and allocation. Not on the §5.4 dependency list, and its formatting would
compete with our French formatting rules (`core/l10n/formats.dart`).

### Three types, one per kind of quantity

`Money` = integer minor units + currency; `Quantity` = integer millionths (fixed point, 6 decimals); `Price`
and FX rates = `Decimal`. Each value uses the representation that matches how it behaves.

## Decision

Three types:

| Type | Representation | Used for |
|---|---|---|
| `Money` | `int` minor units (cents) + `Currency` | Cash, ledger entries, fees, booked amounts, daily wallet values |
| `Quantity` | `int` millionths of a unit | Shares held and traded |
| `Price` | `Decimal` + `Currency` | Quotes and price bars |
| FX rate | `Decimal`, dated | Currency conversion through `FxService` |

Computation rules:

- Arithmetic between `Money` values of different currencies throws a typed error. Converting currencies goes
  through `FxService` with a dated rate (CLAUDE.md rule 5).
- Products and ratios (`quantity × price × rate`, returns, weights) are computed in `Decimal`, with ratios
  carried to 10 significant digits (§7). They are not rounded along the way.
- A `Decimal` becomes `Money` only when it is **booked**: a fill's cost or proceeds, a fee, credited interest,
  the end-of-day wallet value written to `wallet_values`. Booking rounds half-even to the cent, exactly once,
  as a broker statement does.
- Everything else (valuations, P&L, returns, weights) stays `Decimal` and is rounded half-even only when
  displayed, by `Formats` (`roundHalfEven`). This is what "round only at the presentation edge" means for
  values that are never stored.
- `double` is never used for money, quantities, prices or rates. Doubles appear in two places only: chart
  coordinates, after all computation is done, and statistics that need logarithms or square roots
  (volatility, §7.7). Those take `Decimal` inputs, describe how a price moved, and never feed back into an
  amount.

## Consequences

- Ledgers sum exactly, and the cash shown always equals the sum of the stored rows.
- Mixing currencies fails loudly in tests instead of silently producing a wrong total.
- Booking is the one place where sub-cent amounts disappear; its rounding is tested with half-way cases
  (`0.005` → `0.00`, `0.015` → `0.02`).
- Unit tests cover zero and negative amounts, amounts smaller than fees, quantity limits (6 decimals) and
  currency mismatch (CLAUDE.md guardrails).
- `Decimal` arithmetic is slower than `double`. At our scale (a few thousand operations per trip day) this is
  not measurable.
- Depends on `decimal`, already on the §5.4 list.
