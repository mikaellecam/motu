import 'package:flutter/material.dart';

import 'tokens.dart';

/// Text styles (BRIEF §10.3). Baloo 2 ExtraBold for display and titles, Figtree
/// for body and numbers. Every Figtree style uses tabular figures so columns of
/// numbers line up. Colors come from the theme, not from these styles.
abstract final class AppText {
  static TextStyle _baloo(double size) => TextStyle(
    fontFamily: 'Baloo2',
    fontSize: size,
    height: 1.15,
    fontWeight: FontWeight.w800,
    fontVariations: const [FontVariation.weight(800)],
  );

  static TextStyle _figtree(double size, int weight, {double height = 1.35}) =>
      TextStyle(
        fontFamily: 'Figtree',
        // Glyphs Figtree lacks (≈) come from the other bundled font, so they
        // render offline and the same on every device.
        fontFamilyFallback: const ['Baloo2'],
        fontSize: size,
        height: height,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
        fontVariations: [FontVariation.weight(weight.toDouble())],
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static final display = _baloo(32);
  static final title = _baloo(24);
  static final titleSmall = _baloo(19);

  static final body = _figtree(16, 400);
  static final bodyStrong = _figtree(16, 600);
  static final label = _figtree(14, 600);
  static final caption = _figtree(13, 400);

  /// Large amounts: wallet value, asset price.
  static final figureLarge = _figtree(32, 700, height: 1.1);

  /// Amounts in rows and tiles.
  static final figure = _figtree(16, 600);
}

ThemeData appTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.surface,
    secondary: AppColors.progress,
    onSecondary: AppColors.ink,
    // Selected segments and chips are a choice, not progress: neutral.
    secondaryContainer: AppColors.line,
    onSecondaryContainer: AppColors.ink,
    error: AppColors.alertText,
    onError: AppColors.surface,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.line,
    outlineVariant: AppColors.line,
  );
  final textTheme = TextTheme(
    displayLarge: AppText.display,
    displayMedium: AppText.display,
    displaySmall: AppText.display,
    headlineLarge: AppText.title,
    headlineMedium: AppText.title,
    headlineSmall: AppText.title,
    titleLarge: AppText.titleSmall,
    titleMedium: AppText.bodyStrong,
    titleSmall: AppText.label,
    bodyLarge: AppText.body,
    bodyMedium: AppText.body,
    bodySmall: AppText.caption,
    labelLarge: AppText.label,
    labelMedium: AppText.label,
    labelSmall: AppText.caption,
  ).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

  const flatButtonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppShape.flatButtonRadius)),
  );
  const flatButtonSize = Size(AppSpace.minTarget, 48);

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.page,
    fontFamily: 'Figtree',
    fontFamilyFallback: const ['Baloo2'],
    textTheme: textTheme,
    dividerColor: AppColors.line,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    // No tint when content scrolls under the bar (§10.2: no decorative
    // color).
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.page,
      surfaceTintColor: AppColors.page,
      scrolledUnderElevation: 0,
    ),
    // The selected tab is a place, not progress: neutral tokens only.
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.line,
      surfaceTintColor: AppColors.surface,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(AppShape.flatCardRadius),
        ),
        side: BorderSide(color: AppColors.line, width: AppShape.flatBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: flatButtonSize,
        shape: flatButtonShape,
        textStyle: AppText.label,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: flatButtonSize,
        shape: flatButtonShape,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
        textStyle: AppText.label,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(AppSpace.minTarget, AppSpace.minTarget),
        textStyle: AppText.label,
      ),
    ),
  );
}
