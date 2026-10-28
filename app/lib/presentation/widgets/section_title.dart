import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';

/// A money screen's section title (M9-22, art direction): in Baloo, above its
/// flat card, so a screen reads by its sections rather than as a column of
/// identical cards.
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.top = 0,
    this.line,
    this.leading,
  });

  final String title;

  /// Room above it, for a title that opens a section among others.
  final double top;

  /// A line under the title saying what the section holds.
  final String? line;

  /// Drawn before the title and its line: what the section holds, as a
  /// small scene (Explore's, M11-5).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(header: true, child: Text(title, style: AppText.titleSmall)),
        if (line case final line?)
          Text(line, style: AppText.caption.copyWith(color: AppColors.muted)),
      ],
    );
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: AppSpace.x2),
      child: switch (leading) {
        null => words,
        final leading => Row(
          children: [
            leading,
            const SizedBox(width: AppSpace.x3),
            Expanded(child: words),
          ],
        ),
      },
    );
  }
}

/// [child] under its [title].
class TitledSection extends StatelessWidget {
  const TitledSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [SectionTitle(title), child],
  );
}
