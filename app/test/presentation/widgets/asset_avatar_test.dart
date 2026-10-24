import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/presentation/widgets/asset_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

Asset asset(String id, String name, AssetType type) => Asset(
  id: id,
  symbol: id.toUpperCase(),
  name: name,
  type: type,
  exchange: Exchange.nasdaq,
  currency: Currency.usd,
  region: 'us',
  listingDate: DateTime.utc(2000),
);

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

  testWidgets('a stock shows its bundled logo, its letters behind it', (
    tester,
  ) async {
    await pumpApp(
      tester,
      Center(child: AssetAvatar(asset('apple', 'Apple', AssetType.stock))),
    );
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.foregroundImage, const AssetImage('assets/logos/apple.jpg'));
    // Shown while it loads, or if it ever went missing.
    expect(find.text('AP'), findsOneWidget);
  });

  testWidgets('an ETF keeps its two letters', (tester) async {
    await pumpApp(
      tester,
      Center(child: AssetAvatar(asset('world', 'ETF Monde', AssetType.etf))),
    );
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.foregroundImage, isNull);
    expect(find.text('MO'), findsOneWidget);
  });
}
