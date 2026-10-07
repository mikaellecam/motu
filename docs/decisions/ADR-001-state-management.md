# ADR-001: Riverpod for state management

Status: accepted
Date: 2026-10-07

## Context

- Every asynchronous screen must show its initial, loading, data, error and refreshing states explicitly, and
  a refresh must keep the previous data on screen (school brief §7, `BRIEF.md` §5.3).
- Business state is shared across screens: the live wallet's positions drive the wallet screen, the asset
  page, the order sheet *and* the building heights on the map (§4.2).
- The same screens run against different clocks. A trip wallet sees the market as of its simulated date, the
  live wallet as of today (§5.2). State must be scoped per wallet, keyed by `walletId`.
- Errors must reach the UI as typed `Failure`s, never strings (CLAUDE.md rule 6).
- Business logic must stay out of widgets and be testable without pumping widgets (§12).
- The report must explain where state lives and what happens when a widget rebuilds (school brief §12).

## Options considered

### `setState` and `InheritedWidget`

No dependency, and the mechanism every other option builds on. But state lives inside widgets: sharing the
wallet between the map and the wallet screen means lifting it to a common ancestor and threading it down.
There is no built-in model for loading/error/refresh, so each screen re-implements it. Testing a calculation
that feeds a screen requires building that screen.

### Provider

Dependency injection on top of `InheritedWidget`. Better than raw `InheritedWidget`, but lookups depend on the
widget tree: a provider read from the wrong place fails at runtime (`ProviderNotFoundException`), and
parameterised state ("the wallet with this id") needs manual scoping in the tree. Its author now recommends
Riverpod as its successor.

### Bloc / Cubit

Explicit states and events with strong conventions and excellent testability (`bloc_test`). The cost is
ceremony: a state class (often a sealed hierarchy for loading/data/error) and, for Bloc, an event class per
feature. Loading/error/refresh are modelled by hand in each cubit. Scoping per wallet is done by placing
`BlocProvider`s in the widget tree, which ties state lifetime to navigation.

### Riverpod (with `riverpod_generator`)

Providers are global declarations, independent of the widget tree, checked at compile time. Async providers
expose `AsyncValue` (loading / data / error, with the previous value kept while reloading), which is exactly
the set of states the brief requires. `family` providers take parameters, so "this wallet's clock" is a
provider keyed by `walletId`. Any provider can be overridden in a `ProviderContainer`, so notifiers are tested
with fake repositories and no widgets. Costs: a code-generation step (`build_runner`) and concepts to learn
(`ref.watch` vs `ref.read`, auto-dispose).

## Decision

Riverpod, with code generation. It is the only option where the three hard requirements come built in rather
than hand-written per screen: the async state model (`AsyncValue`), per-wallet scoping (`family`), and testing
without widgets (overrides).

## Consequences

- **Where state lives:** in providers and notifiers in `app/lib/application/`, one notifier per screen-level
  concern. The domain layer stays pure Dart and knows nothing about Riverpod; the data layer is reached only
  through repository providers.
- **What a rebuild does:** a widget rebuild re-reads providers with `ref.watch`; it never recreates or
  refetches them. Providers live as long as something listens (auto-dispose frees them afterwards). `build`
  methods only render; fetching happens in notifiers. `AnimationController`s are UI state and live in
  `State` objects, disposed with them.
- **Errors and loading** propagate as `AsyncValue`. Screens render them through the shared `AsyncSkeleton`,
  `ErrorView` and `StaleBanner` widgets; a failed refresh shows the previous data with a banner, not a spinner.
- **Trips:** every market-data provider used by a wallet screen is a family keyed by `walletId`, built from
  that wallet's `SimulationClock`, so the no-lookahead rule (CLAUDE.md rule 3) is enforced once, at the
  provider boundary.
- **Tests:** notifier tests use `ProviderContainer` with overridden repositories (§12).
- Adds `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator` and `build_runner`, all on the §5.4
  list, when the first notifier lands.
