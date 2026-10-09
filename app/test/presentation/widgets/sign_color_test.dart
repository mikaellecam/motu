import 'package:decimal/decimal.dart';
import 'package:finance_companion/core/theme/tokens.dart';
import 'package:finance_companion/presentation/widgets/sign_color.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Decimal d(String s) => Decimal.parse(s);

  test('amounts: the cent decides', () {
    expect(signColor(d('0.01')), AppColors.gain);
    expect(signColor(d('0.004')), AppColors.muted);
    expect(signColor(d('-0.006')), AppColors.loss);
  });

  test('ratios: the hundredth of a percent decides, like the text', () {
    // +0,40 % is written with a plus: it must be green.
    expect(signColor(d('0.004'), ratio: true), AppColors.gain);
    expect(signColor(d('0.00004'), ratio: true), AppColors.muted);
    expect(signColor(d('-0.0001'), ratio: true), AppColors.loss);
  });
}
