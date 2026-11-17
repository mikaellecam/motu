import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/cache_status.dart';
import '../../core/widgets/async_states.dart';

/// The [StaleBanner] of screens that show prices: shown while offline or
/// after a failed refresh, with when the prices were last updated; nothing
/// while they are fresh.
class CacheStatusBanner extends ConsumerWidget {
  const CacheStatusBanner({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The backend is tried again at once, even mid-pause (M13-18).
    final retry = onRetry == null
        ? null
        : () {
            ref.read(backendRetryProvider)();
            onRetry!();
          };
    return switch (ref.watch(cacheStatusProvider).value) {
      Stale(:final lastUpdated) => StaleBanner(
        lastUpdated: lastUpdated,
        offline: false,
        onRetry: retry,
      ),
      Offline(lastUpdated: final lastUpdated?) => StaleBanner(
        lastUpdated: lastUpdated,
        offline: true,
        onRetry: retry,
      ),
      // Fresh, still loading, or offline with nothing ever fetched (the
      // screen shows its error instead).
      _ => const SizedBox.shrink(),
    };
  }
}
