import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';

/// The round initials standing for an asset in lists. Decorative: the name
/// next to it says the same.
class AssetAvatar extends StatelessWidget {
  const AssetAvatar(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CircleAvatar(
      radius: AppSpace.x5,
      backgroundColor: AppColors.line,
      foregroundColor: AppColors.ink,
      child: Text(
        assetInitials(name),
        style: AppText.label.copyWith(color: AppColors.ink),
      ),
    ),
  );
}

/// Two letters for an asset (M9-22), so that Apple and Airbus differ: the
/// initials of its name's first two words, « ETF » left out, or the first two
/// letters of a single word. Only letters count (« S&P 500 » is « SP »).
String assetInitials(String name) {
  final words = [
    for (final w in name.split(RegExp(r'[^\p{L}0-9]+', unicode: true)))
      if (w.isNotEmpty) w,
  ];
  final named = [
    for (final w in words)
      if (w.toUpperCase() != 'ETF' &&
          w.contains(RegExp(r'\p{L}', unicode: true)))
        w,
  ];
  final picked = named.isNotEmpty ? named : words;
  if (picked.isEmpty) return '';
  final initials = picked.length > 1
      ? '${picked[0].characters.first}${picked[1].characters.first}'
      : picked[0].characters.take(2).toString();
  return initials.toUpperCase();
}
