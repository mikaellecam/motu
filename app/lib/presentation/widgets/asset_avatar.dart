import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../domain/market/asset.dart';

/// The round mark standing for an asset in lists. Decorative: the name
/// next to it says the same. A stock shows its company's logo, bundled with
/// the app (M9-29); an ETF, or a logo that could not load, its two letters.
class AssetAvatar extends StatelessWidget {
  const AssetAvatar(this.asset, {super.key});

  final Asset asset;

  /// Where a stock's logo is bundled (`go run ./cmd/logos` fetches them).
  static String? logoOf(Asset asset) =>
      asset.type == AssetType.stock ? 'assets/logos/${asset.id}.jpg' : null;

  @override
  Widget build(BuildContext context) {
    final logo = logoOf(asset);
    return ExcludeSemantics(
      // A thin ring, so a white logo still reads as a disc.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          border: Border.fromBorderSide(BorderSide(color: AppColors.line)),
        ),
        child: CircleAvatar(
          radius: AppSpace.x5,
          backgroundColor: AppColors.line,
          foregroundColor: AppColors.ink,
          foregroundImage: logo == null ? null : AssetImage(logo),
          // Missing: the letters underneath stay.
          onForegroundImageError: logo == null ? null : (_, _) {},
          child: Text(
            assetInitials(asset.name),
            style: AppText.label.copyWith(color: AppColors.ink),
          ),
        ),
      ),
    );
  }
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
