# ADR-008: Inflation from INSEE's consumer price index

Status: accepted
Date: 2026-10-28

## Context

Les bases, the second island (milestone M12, canvas « Les bases »), teaches what inflation does to money: what
10 000 € kept as notes from the end of 2015 bought ten years later, and whether a Livret A kept its purchasing
power in 2022. Its lessons need a monthly price index of France, frozen like every dataset (BRIEF §4.3, §9),
and the figure a learner can check: the one the news gives. Twelve Data, the market provider (ADR-004), has no
price index.

## Options considered

### INSEE's consumer price index (IPC)

The index of all households in France, all items, published monthly in INSEE's macro-economic database (BDM):
the figure French news gives, and the one the Livret A's rate formula reads. Keyless (an SDMX web service).
The 2015-based series (idbank 001759970) stopped in December 2025; the 2025-based one (idbank 011814630) runs
from January 1996, so one series covers every window a lesson needs.

### The ECB's harmonised index for France (HICP)

The ECB's data portal, the same institution as the exchange rates the app already uses (Frankfurter). One
unbroken series. But it runs above the figure people hear: 2022 averaged 5.9 % against INSEE's 5.2 %, so a
lesson's figures would disagree with what a learner reads elsewhere.

## Decision

INSEE, chosen by the user on 2026-10-28 (canvas « Les bases », Your calls 1): the figure learners know. The
series is idbank 011814630, base 2025, read through `internal/insee`.

## Consequences

- `cmd/freeze -cpi` restates a Livret A holding (`-livret`) or notes (`-cash`, new) in euros of `-from`'s
  month: each month-end value times the index of that month over the index of its own. The dataset says
  `"prices": "insee"`; its recipe `"cpi": true`. Only monthly, as the index.
- INSEE's data is under the Licence Ouverte 2.0, which allows reuse, commercial included, crediting
  « Source : Insee ». So these datasets could live in git, unlike Twelve Data's (ADR-007). They stay out all
  the same, with every dataset: the app's bundle that holds them is out of git anyway, and their recipes
  rebuild them with no key and no credit (`scripts/fetch-data.sh`, the image's start). CI makes them up
  (`-synthetic`), as the others.
- A lesson drawing them credits « Source : Insee » in its provenance line (M12-5).
- INSEE publishes a month's index in the middle of the next: a window ending on a month not published yet is
  refused (« no INSEE index for 2026-10 »).
