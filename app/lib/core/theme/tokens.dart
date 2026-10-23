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

/// A block's three visible faces.
typedef Shades = ({Color top, Color left, Color right});

/// The painted archipelago's own colours, from the art direction (BRIEF
/// §10.2, decided 2026-10-13): the map and the island path's islets only,
/// never a screen or a widget. They draw a place and carry no meaning.
abstract final class MapPalette {
  static const wave = Color(0x8CFFFFFF);

  /// The shallow water round an island; Actions & ETF's is brighter.
  static const halo = Color(0x59FFFFFF);
  static const haloOpen = Color(0x80FFFFFF);

  // Actions & ETF: sand round a grass checker, on dirt; ink edges.
  static const sand = Color(0xFFF4DE9C);
  static const grass = Color(0xFF8ED081);
  static const grassDark = Color(0xFF84C877);
  static const seam = Color(0xFF6FB565);
  static const dirt = (
    top: sand,
    left: Color(0xFFB57B45),
    right: Color(0xFFD79A5E),
  );

  /// Its buildings, left to right; windows lit in the second colour.
  static const buildings = <(Shades, Color)>[
    (
      (
        top: Color(0xFFDCE6FF),
        left: Color(0xFF3F63D1),
        right: Color(0xFF5B82F2),
      ),
      Color(0xFFBCD0FF),
    ),
    (
      (
        top: Color(0xFFFFF1C9),
        left: Color(0xFFE9A92A),
        right: Color(0xFFFFC845),
      ),
      Color(0xFFFFFFFF),
    ),
    (
      (
        top: Color(0xFFFFE0D6),
        left: Color(0xFFE25E3F),
        right: Color(0xFFFF7D5C),
      ),
      Color(0xFFFFB4A0),
    ),
    (
      (
        top: Color(0xFFE3F7F3),
        left: Color(0xFF2FA38A),
        right: Color(0xFF4CC3A9),
      ),
      Color(0xFFA6E5D6),
    ),
    (
      (
        top: Color(0xFFDCE6FF),
        left: Color(0xFF3F63D1),
        right: Color(0xFF5B82F2),
      ),
      Color(0xFFBCD0FF),
    ),
  ];
  static const window = Color(0xFFFFF4C2);

  /// The island path: the planks of a bridge built, the plank route still
  /// ahead on the water, the ring round the current lesson.
  static const plank = (
    top: Color(0xFFD79A5E),
    left: Color(0xFFB57B45),
    right: Color(0xFFB57B45),
  );
  static const route = Color(0x80FFFFFF);
  static const currentRing = Color(0xD9FFFFFF);
  static const flag = Color(0xFFFF7D5C);
  static const leaves = (
    top: Color(0xFF5FC26A),
    left: Color(0xFF33893F),
    right: Color(0xFF46A852),
  );
  static const trunk = (
    top: Color(0xFF9A6A3C),
    left: Color(0xFF6E4824),
    right: Color(0xFF8A5C31),
  );

  // Locked islands: grey stone, slate edges, white clouds.
  static const lockedInk = Color(0xFF56627A);
  static const stone = Color(0xFFE3E7E8);
  static const stoneMid = Color(0xFFD3DCDF);
  static const stoneDark = Color(0xFFCDD6DA);
  static const stoneSeam = Color(0xFFC3CDD1);
  static const stoneSides = (
    top: stone,
    left: Color(0xFF9AA6AC),
    right: Color(0xFFB5C0C5),
  );
  static const block = (
    top: Color(0xFFE3E8EA),
    left: Color(0xFFA3AEB4),
    right: Color(0xFFBAC4C9),
  );
  static const blockDark = (
    top: Color(0xFFCBD3D7),
    left: Color(0xFF87949B),
    right: Color(0xFF9DA9AF),
  );
  static const wall = (
    top: Color(0xFFE3E8EA),
    left: Color(0xFFBAC4C9),
    right: Color(0xFFD3DADD),
  );
  static const wallDark = (
    top: Color(0xFFC9D1D5),
    left: Color(0xFF9AA6AC),
    right: Color(0xFFB0BBC0),
  );

  /// A gable roof: the back slope, the front slope, the gable end.
  static const roof = (
    top: Color(0xFFB5C0C5),
    left: Color(0xFF9AA6AC),
    right: Color(0xFFD3DADD),
  );
  static const stoneTrunk = (
    top: Color(0xFFAAB3B8),
    left: Color(0xFF88929A),
    right: Color(0xFF9AA4A9),
  );
  static const stoneLeaves = (
    top: Color(0xFFC2CCD0),
    left: Color(0xFF9DA9AF),
    right: Color(0xFFB0BBC0),
  );
  static const stoneWindow = Color(0xFFD9DFE2);

  /// A crystal's faces: the lower three, right to left, then the upper.
  static const crystal = [
    Color(0xFFB0BBC0),
    Color(0xFF9AA6AC),
    Color(0xFF9AA6AC),
    Color(0xFFE3E8EA),
    Color(0xFFC9D1D5),
    Color(0xFFB0BBC0),
  ];
  static const cloud = Color(0xFFFFFFFF);
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
