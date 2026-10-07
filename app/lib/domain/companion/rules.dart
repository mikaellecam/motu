import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../analytics/returns.dart';
import '../learning/profile_rules.dart';
import 'events.dart';

/// Teachable moments (BRIEF §4.12). Each describes what happened, never what
/// to do; copy lives in the ARB files, keyed by [id].
enum CompanionRule {
  firstLoss('first_loss', null, ['volatilite', 'horizon-de-placement']),
  positionDrop('position_drop', 30, ['pire-baisse', 'volatilite']),
  portfolioDrawdown('portfolio_drawdown', 30, [
    'pire-baisse',
    'diversification',
  ]),
  concentration('concentration', 14, ['concentration', 'diversification']),
  idleCash('idle_cash', 30, ['liquidites', 'inflation']),
  panicSell('panic_sell', null, ['horizon-de-placement', 'rebond']),
  panicSellFollowUp('panic_sell_followup', null, [
    'rebond',
    'horizon-de-placement',
  ]),
  fxSwing('fx_swing', 30, ['risque-de-change', 'taux-de-change']);

  const CompanionRule(this.id, this.cooldownDays, this.glossary);

  final String id;

  /// Days before the same rule and key may fire again; null for once.
  final int? cooldownDays;

  /// Glossary terms the card links to.
  final List<String> glossary;
}

/// A fired rule: one card. [key] scopes the cooldown (an asset, a sell, or
/// '' for the whole wallet).
final class Moment {
  const Moment(this.rule, this.key, this.date, this.params);

  final CompanionRule rule;
  final String key;
  final DateTime date;

  /// Values the copy needs.
  final Map<String, Object> params;

  CompanionLogEntry get logEntry => CompanionLogEntry(rule, key, date);
}

/// One row of `companion_log` (BRIEF §6.1).
final class CompanionLogEntry {
  const CompanionLogEntry(this.rule, this.key, this.firedAt);
  final CompanionRule rule;
  final String key;
  final DateTime firedAt;
}

/// A panic sell to revisit on [due].
final class FollowUp {
  const FollowUp(this.assetId, this.sellPrice, this.due);
  final String assetId;
  final Price sellPrice;
  final DateTime due;
}

/// The companion's memory of a wallet, one day at a time: prices peaks since
/// purchase, a performance index (contributions excluded), how long cash has
/// been idle, recent P&L, a month of EUR/USD, and panic sells to revisit.
final class CompanionTracker {
  const CompanionTracker._({
    required this.peaks,
    required this.index,
    required this.indexPeak,
    required this.previousValue,
    required this.cashHighSince,
    required this.recentPnl,
    required this.usdRates,
    required this.followUps,
  });

  CompanionTracker.empty()
    : this._(
        peaks: const {},
        index: Decimal.one,
        indexPeak: Decimal.one,
        previousValue: null,
        cashHighSince: null,
        recentPnl: const {},
        usdRates: const [],
        followUps: const {},
      );

  /// Highest price of each open position since it was bought.
  final Map<String, Price> peaks;

  /// Wallet performance, contributions excluded (the TWR growth factor), and
  /// its peak.
  final Decimal index;
  final Decimal indexPeak;
  final Decimal? previousValue;

  /// First day of the current run of cash above the idle threshold.
  final DateTime? cashHighSince;

  /// P&L ratios of the last observations, per asset, newest last.
  final Map<String, List<Decimal>> recentPnl;

  /// EUR per USD by date, about a month of them.
  final List<(DateTime, Decimal)> usdRates;

  /// Panic sells to revisit, by moment key.
  final Map<String, FollowUp> followUps;

  /// Takes in [s] and returns the tracker for the next day with the moments
  /// that fire today, skipping rules on cooldown in [log].
  (CompanionTracker, List<Moment>) observe(
    DaySnapshot s, {
    required Iterable<CompanionLogEntry> log,
    required MomentThresholds thresholds,
  }) {
    final t = thresholds;
    final moments = <Moment>[];
    void fire(CompanionRule rule, String key, Map<String, Object> params) {
      final repeat = moments.any((m) => m.rule == rule && m.key == key);
      if (!repeat && !_onCooldown(rule, key, s.date, log)) {
        moments.add(Moment(rule, key, s.date, params));
      }
    }

    // Running facts, today included.
    final peaks = {
      for (final h in s.holdings)
        h.assetId: switch (this.peaks[h.assetId]) {
          final peak? when peak > h.price => peak,
          _ => h.price,
        },
    };
    var index = this.index;
    final previous = previousValue;
    if (previous != null && previous > Decimal.zero) {
      index = (index * ratio(s.value - s.flow, previous)).truncate(
        scale: ratioScale,
      );
    }
    final indexPeak = index > this.indexPeak ? index : this.indexPeak;
    final cashHighSince = s.cashWeight > t.idleCash
        ? (this.cashHighSince ?? s.date)
        : null;
    final recentPnl = {
      ...this.recentPnl,
      for (final h in s.holdings)
        if (h.pnlRatio case final pnl?)
          h.assetId: [
            ...?this.recentPnl[h.assetId],
            pnl,
          ].reversed.take(t.panicSellWindow).toList().reversed.toList(),
    };
    final usdRates = [
      ...this.usdRates,
      if (s.usdRate case final rate?) (s.date, rate),
    ];

    // first_loss
    for (final h in s.holdings) {
      if (h.pnlRatio case final pnl? when pnl < t.firstLoss) {
        fire(CompanionRule.firstLoss, '', {'assetId': h.assetId});
      }
    }

    // position_drop
    for (final h in s.holdings) {
      final drop = simpleReturn(peaks[h.assetId]!.value, h.price.value)!;
      if (drop <= t.positionDrop) {
        fire(CompanionRule.positionDrop, h.assetId, {
          'assetId': h.assetId,
          'drop': drop,
        });
      }
    }

    // portfolio_drawdown, on performance so contributions can't hide a fall.
    final drawdown = simpleReturn(indexPeak, index)!;
    if (drawdown <= t.portfolioDrawdown) {
      fire(CompanionRule.portfolioDrawdown, '', {'drawdown': drawdown});
    }

    // concentration: the largest position.
    if (s.holdings.isNotEmpty) {
      final largest = s.holdings.reduce((a, b) => a.weight >= b.weight ? a : b);
      if (largest.weight > t.concentration) {
        fire(CompanionRule.concentration, '', {
          'assetId': largest.assetId,
          'weight': largest.weight,
        });
      }
    }

    // idle_cash
    if (cashHighSince != null &&
        s.date.difference(cashHighSince).inDays > t.idleCashDays) {
      fire(CompanionRule.idleCash, '', {'cashWeight': s.cashWeight});
    }

    // panic_sell, and its follow-up three months later.
    final followUps = {...this.followUps};
    for (final sell in s.sells) {
      final recent = recentPnl[sell.assetId] ?? const <Decimal>[];
      if (recent.any((pnl) => pnl <= t.panicSellDrop)) {
        final key =
            '${sell.assetId}|${s.date.toIso8601String().substring(0, 10)}';
        fire(CompanionRule.panicSell, key, {
          'assetId': sell.assetId,
          'sellPrice': sell.price,
        });
        followUps[key] = FollowUp(
          sell.assetId,
          sell.price,
          DateTime.utc(s.date.year, s.date.month + 3, s.date.day),
        );
      }
    }
    for (final MapEntry(:key, value: f) in [...followUps.entries]) {
      final now = s.date.isBefore(f.due) ? null : s.priceOf(f.assetId);
      if (now == null) continue;
      fire(CompanionRule.panicSellFollowUp, key, {
        'assetId': f.assetId,
        'sellPrice': f.sellPrice,
        'priceNow': now,
        'change': simpleReturn(f.sellPrice.value, now.value)!,
      });
      followUps.remove(key);
    }

    // fx_swing: against the rate on or before the same day last month.
    final monthAgo = DateTime.utc(s.date.year, s.date.month - 1, s.date.day);
    final past = usdRates.where((r) => !r.$1.isAfter(monthAgo)).lastOrNull;
    if (s.usdRate case final rate? when past != null) {
      final move = simpleReturn(past.$2, rate)!.abs();
      final exposure = s.holdings
          .where((h) => h.price.currency == Currency.usd)
          .fold(Decimal.zero, (sum, h) => sum + h.weight);
      if (move > t.fxSwingMove && exposure > t.fxSwingExposure) {
        fire(CompanionRule.fxSwing, '', {'move': move, 'exposure': exposure});
      }
    }

    final next = CompanionTracker._(
      peaks: peaks,
      index: index,
      indexPeak: indexPeak,
      previousValue: s.value,
      cashHighSince: cashHighSince,
      recentPnl: {for (final h in s.holdings) h.assetId: ?recentPnl[h.assetId]},
      // Keep the latest rate at or before a month ago, and everything after.
      usdRates: [?past, ...usdRates.where((r) => r.$1.isAfter(monthAgo))],
      followUps: followUps,
    );
    return (next, moments);
  }
}

bool _onCooldown(
  CompanionRule rule,
  String key,
  DateTime date,
  Iterable<CompanionLogEntry> log,
) => log.any(
  (e) =>
      e.rule == rule &&
      e.key == key &&
      (rule.cooldownDays == null ||
          date.difference(e.firedAt).inDays < rule.cooldownDays!),
);
