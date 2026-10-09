/// Whether the market data on screen is current (BRIEF §6.3, §6.4): the only
/// thing the UI learns about where its data came from.
sealed class CacheStatus {
  const CacheStatus();
}

/// The last price fetch succeeded, or none was needed.
final class Fresh extends CacheStatus {
  const Fresh();
}

/// Online, but the last price fetch failed: the cache stands in, as of
/// [lastUpdated].
final class Stale extends CacheStatus {
  const Stale(this.lastUpdated);
  final DateTime lastUpdated;

  @override
  bool operator ==(Object other) =>
      other is Stale && other.lastUpdated.isAtSameMomentAs(lastUpdated);

  @override
  int get hashCode => lastUpdated.millisecondsSinceEpoch.hashCode;
}

/// The device has no connection. [lastUpdated] is the last price fetch that
/// succeeded; null when prices were never fetched.
final class Offline extends CacheStatus {
  const Offline(this.lastUpdated);
  final DateTime? lastUpdated;

  @override
  bool operator ==(Object other) =>
      other is Offline &&
      (other.lastUpdated == null
          ? lastUpdated == null
          : lastUpdated != null &&
                other.lastUpdated!.isAtSameMomentAs(lastUpdated!));

  @override
  int get hashCode => lastUpdated?.millisecondsSinceEpoch.hashCode ?? 0;
}
