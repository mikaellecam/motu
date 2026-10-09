import 'package:decimal/decimal.dart';
import 'package:flutter/painting.dart';

import '../../core/money/money.dart';
import '../../core/theme/tokens.dart';

/// Gain, loss or neutral for a figure as it is displayed: an amount rounded
/// to cents, a ratio to the hundredth of a percent (`Formats`). The color
/// always agrees with the sign written next to it.
Color signColor(Decimal value, {bool ratio = false}) {
  final shown = roundHalfEven(value, ratio ? 4 : 2);
  return shown > Decimal.zero
      ? AppColors.gain
      : shown < Decimal.zero
      ? AppColors.loss
      : AppColors.muted;
}
