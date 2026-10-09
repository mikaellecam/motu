import 'package:flutter/painting.dart';

/// Color tokens (BRIEF §10.2). Each one has a single meaning: use it only for
/// what its comment says. A screen state (being in a trip…) is shown by
/// content, never by tinting the screen.
abstract final class AppColors {
  /// Text, chunky borders and offset shadows.
  static const ink = Color(0xFF1D2340);

  /// Secondary text.
  static const muted = Color(0xFF4A5670);

  /// Flat borders, dividers, skeleton placeholders.
  static const line = Color(0xFFDDE5EA);

  /// App background.
  static const page = Color(0xFFF4F8FA);

  /// Cards.
  static const surface = Color(0xFFFFFFFF);

  /// Primary actions, main chart line.
  static const primary = Color(0xFF3157E8);

  /// Levels, missions, new notions, companion buttons.
  static const progress = Color(0xFFFFC845);

  /// Alerts and thresholds: drawdowns, automatic stops, validation errors.
  static const alert = Color(0xFFFF7D5C);

  /// Text on or next to [alert] (the fill is too light for text).
  static const alertText = Color(0xFFC23E22);

  /// Gain figures only, always with a + sign.
  static const gain = Color(0xFF167A52);

  /// Loss figures only, always with a − sign.
  static const loss = Color(0xFFC23E22);

  /// World screens background only (map, island path, node player).
  static const sea = Color(0xFF86D9EC);

  /// Allocation bar: the position ranked [rank] by weight (0 = largest) in
  /// [primary], lighter as positions get smaller. Color says "invested";
  /// cash is [line] and the Livret [muted]; the legend names each segment
  /// (decided 2026-10-09).
  static Color allocationShade(int rank) =>
      primary.withValues(alpha: rank >= 4 ? 0.2 : 1 - rank * 0.2);
}

/// 4-pt spacing scale and fixed sizes (BRIEF §10.4).
abstract final class AppSpace {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;

  static const screenPadding = x4;

  /// Minimum touch target, both sides.
  static const minTarget = 44.0;
  static const tabBarHeight = 80.0;
}

/// Shapes of the two component families (BRIEF §10.1).
abstract final class AppShape {
  /// Chunky ("the game is talking to you"): 3 px ink border, offset shadow.
  static const chunkyBorder = 3.0;
  static const chunkyCardRadius = 24.0;
  static const chunkyCardShadow = 6.0;
  static const chunkyButtonRadius = 16.0;
  static const chunkyButtonShadow = 4.0;

  /// Flat ("your money"): 1 px line border, no shadow.
  static const flatBorder = 1.0;
  static const flatCardRadius = 18.0;
  static const flatButtonRadius = 14.0;
}
