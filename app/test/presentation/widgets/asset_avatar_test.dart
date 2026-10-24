import 'package:finance_companion/presentation/widgets/asset_avatar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one word: its first two letters', () {
    expect(assetInitials('Apple'), 'AP');
    expect(assetInitials('Amazon'), 'AM');
    expect(assetInitials('Airbus'), 'AI');
    expect(assetInitials('ASML'), 'AS');
    expect(assetInitials('Hermès'), 'HE');
  });

  test('two words or more: their initials, « ETF » left out', () {
    expect(assetInitials('Coca-Cola'), 'CC');
    expect(assetInitials("L'Oréal"), 'LO');
    expect(assetInitials('BNP Paribas'), 'BP');
    expect(assetInitials('ETF Monde'), 'MO');
    expect(assetInitials('ETF S&P 500'), 'SP');
    expect(assetInitials('ETF Pays émergents'), 'PÉ');
  });

  test('a name of one letter, or none, still gives something', () {
    expect(assetInitials('X'), 'X');
    expect(assetInitials('ETF'), 'ET');
    expect(assetInitials('500'), '50');
    expect(assetInitials(''), '');
  });
}
