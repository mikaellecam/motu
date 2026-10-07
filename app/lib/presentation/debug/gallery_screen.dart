import 'package:flutter/material.dart';

import '../../core/failure.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_states.dart';
import '../../core/widgets/chunky.dart';

/// Every base component in both families, for visual review. Developer tool:
/// headings are component and token names, not user copy.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sample = l10n.app_title;
    final lastUpdated = DateTime(2026, 10, 7, 17, 35);
    void noop() {}

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.screenPadding),
          children: [
            const _Heading('Colors'),
            const Wrap(
              spacing: AppSpace.x2,
              runSpacing: AppSpace.x2,
              children: [
                _Swatch('ink', AppColors.ink),
                _Swatch('muted', AppColors.muted),
                _Swatch('line', AppColors.line),
                _Swatch('page', AppColors.page),
                _Swatch('surface', AppColors.surface),
                _Swatch('primary', AppColors.primary),
                _Swatch('progress', AppColors.progress),
                _Swatch('alert', AppColors.alert),
                _Swatch('alertText', AppColors.alertText),
                _Swatch('gain', AppColors.gain),
                _Swatch('loss', AppColors.loss),
                _Swatch('sea', AppColors.sea),
              ],
            ),
            const _Heading('Type'),
            for (final (name, style) in [
              ('display', AppText.display),
              ('title', AppText.title),
              ('titleSmall', AppText.titleSmall),
              ('body', AppText.body),
              ('bodyStrong', AppText.bodyStrong),
              ('label', AppText.label),
              ('caption', AppText.caption),
              ('figureLarge', AppText.figureLarge),
              ('figure', AppText.figure),
            ])
              Text('$name · $sample · 0123456789', style: style),
            const _Heading('Chunky'),
            ChunkyCard(child: Text(sample, style: AppText.titleSmall)),
            const SizedBox(height: AppSpace.x4),
            ChunkyButton(label: l10n.common_retry, onPressed: noop),
            const SizedBox(height: AppSpace.x3),
            ChunkyButton(
              label: l10n.common_retry,
              onPressed: noop,
              kind: ChunkyButtonKind.progress,
            ),
            const SizedBox(height: AppSpace.x3),
            ChunkyButton(label: l10n.common_retry, onPressed: null),
            const _Heading('Flat'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.x4),
                child: Text(sample, style: AppText.bodyStrong),
              ),
            ),
            const SizedBox(height: AppSpace.x4),
            FilledButton(onPressed: noop, child: Text(l10n.common_retry)),
            const SizedBox(height: AppSpace.x2),
            OutlinedButton(onPressed: noop, child: Text(l10n.common_retry)),
            const SizedBox(height: AppSpace.x2),
            TextButton(onPressed: noop, child: Text(l10n.common_retry)),
            const SizedBox(height: AppSpace.x2),
            FilledButton(onPressed: null, child: Text(l10n.common_retry)),
            const _Heading('AsyncSkeleton'),
            const AsyncSkeleton(),
            const _Heading('StaleBanner'),
            StaleBanner(lastUpdated: lastUpdated, offline: true, onRetry: noop),
            const SizedBox(height: AppSpace.x2),
            StaleBanner(
              lastUpdated: lastUpdated,
              offline: false,
              onRetry: noop,
            ),
            const _Heading('ErrorView'),
            for (final failure in [
              const NetworkFailure(),
              const RateLimitedFailure(Duration(seconds: 30)),
              const NotFoundFailure(),
              DataUnavailableFailure(DateTime(2008, 9, 15)),
              const StorageFailure(),
              const ValidationFailure('debug'),
            ])
              Card(
                margin: const EdgeInsets.only(bottom: AppSpace.x2),
                child: ErrorView(failure: failure, onRetry: noop),
              ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.x6, bottom: AppSpace.x3),
    child: Text(text, style: AppText.title),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color);

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.all(Radius.circular(AppSpace.x2)),
          border: Border.all(color: AppColors.line),
        ),
      ),
      Text(name, style: AppText.caption),
    ],
  );
}
