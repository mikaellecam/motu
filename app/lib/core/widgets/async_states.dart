import 'package:flutter/material.dart';

import '../failure.dart';
import '../l10n/app_localizations.dart';
import '../l10n/formats.dart';
import '../theme/tokens.dart';
import 'chunky.dart';

/// Loading placeholder: [lines] bars that pulse until data arrives. Shown
/// only on first load; a refresh keeps the previous data on screen instead.
class AsyncSkeleton extends StatefulWidget {
  const AsyncSkeleton({super.key, this.lines = 3});

  final int lines;

  @override
  State<AsyncSkeleton> createState() => _AsyncSkeletonState();
}

class _AsyncSkeletonState extends State<AsyncSkeleton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.4,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Screen readers hear « Chargement… », not empty bars (M9-3).
    return Semantics(
      label: AppLocalizations.of(context).common_loading,
      liveRegion: true,
      excludeSemantics: true,
      child: FadeTransition(
        opacity: _pulse,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.lines; i++)
              FractionallySizedBox(
                // The last bar is shorter, like the end of a paragraph.
                widthFactor: i == widget.lines - 1 && widget.lines > 1 ? .6 : 1,
                child: Container(
                  height: AppSpace.x4,
                  margin: const EdgeInsets.only(bottom: AppSpace.x3),
                  decoration: const BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppSpace.x1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Copy for a [failure], in the current locale.
String failureMessage(BuildContext context, Failure failure) {
  final l10n = AppLocalizations.of(context);
  return switch (failure) {
    NetworkFailure() => l10n.failure_network,
    RateLimitedFailure(:final retryAfter) => l10n.failure_rate_limited(
      // Round up: "try again in 0 s" would be wrong.
      (retryAfter.inMilliseconds / 1000).ceil(),
    ),
    NotFoundFailure() => l10n.failure_not_found,
    DataUnavailableFailure(:final asOf) => l10n.failure_data_unavailable(
      _formats(context).date(asOf),
    ),
    StorageFailure() => l10n.failure_storage,
    ServerFailure() => l10n.failure_unexpected,
    // Forms show validation failures next to their fields; reaching a
    // full-screen error with one is a bug.
    ValidationFailure() => l10n.failure_unexpected,
  };
}

Formats _formats(BuildContext context) =>
    Formats(Localizations.localeOf(context).languageCode);

/// Full-area error state with an optional retry.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.screenPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ExcludeSemantics(
            child: Icon(
              Icons.error_outline,
              color: AppColors.alertText,
              size: AppSpace.x8,
            ),
          ),
          const SizedBox(height: AppSpace.x3),
          Text(
            failureMessage(context, failure),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpace.x4),
            ChunkyButton(
              label: AppLocalizations.of(context).common_retry,
              kind: ChunkyButtonKind.secondary,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// Tells the user the data on screen is not fresh: [offline], or online but
/// the last refresh failed. Always shows when that data was last updated.
class StaleBanner extends StatelessWidget {
  const StaleBanner({
    super.key,
    required this.lastUpdated,
    required this.offline,
    this.onRetry,
  });

  final DateTime lastUpdated;
  final bool offline;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final formats = _formats(context);
    final local = lastUpdated.toLocal();
    final date = formats.date(local);
    final time = formats.time(local);

    return Card(
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpace.x4, right: AppSpace.x1),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                offline ? Icons.cloud_off_outlined : Icons.schedule,
                color: AppColors.muted,
                size: AppSpace.x5,
              ),
            ),
            const SizedBox(width: AppSpace.x3),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.x3),
                child: Text(
                  offline
                      ? l10n.cache_offline_banner(date, time)
                      : l10n.cache_stale_banner(date, time),
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: Text(l10n.common_retry)),
          ],
        ),
      ),
    );
  }
}
