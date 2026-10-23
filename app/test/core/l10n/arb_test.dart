import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The two languages (M9-2): every French key has its English, with the same
/// placeholders, in English typography.
void main() {
  Map<String, Object?> read(String locale) =>
      jsonDecode(File('lib/core/l10n/app_$locale.arb').readAsStringSync())
          as Map<String, Object?>;
  final fr = read('fr');
  final en = read('en');
  final keys = [
    for (final k in fr.keys)
      if (!k.startsWith('@')) k,
  ];

  test('the same keys in both', () {
    expect({
      for (final k in en.keys)
        if (!k.startsWith('@')) k,
    }, keys.toSet());
  });

  test('every placeholder in both', () {
    for (final key in keys) {
      final meta = fr['@$key'] as Map<String, Object?>?;
      final names = (meta?['placeholders'] as Map<String, Object?>?)?.keys;
      for (final name in names ?? const <String>[]) {
        expect(en[key], contains('{$name'), reason: '$key: {$name}');
      }
    }
  });

  test('English typography: no narrow space, no guillemets', () {
    for (final key in keys) {
      final value = en[key]! as String;
      expect(value, isNot(contains(' ')), reason: key);
      expect(value, isNot(contains('«')), reason: key);
    }
  });

  test('English that reads like the French is meant to', () {
    // Names, symbols, patterns and words both languages share.
    const shared = {
      'app_title',
      'asset_eur_equivalent',
      'asset_volatility_figure',
      'dca_gain',
      'exchange_euronext',
      'exchange_nasdaq',
      'exchange_nyse',
      'exchange_otc',
      'glossary_row_semantics',
      'island_crypto',
      'island_node_caption',
      'island_node_semantics',
      'island_trading',
      'livret_title',
      'map_island_progress',
      'node_type_mission',
      'order_coach_term',
      'order_quick_max',
      'order_row_detail',
      'order_type_stop',
      'region_europe',
      'settings_language_en',
      'settings_language_fr',
      'settings_simulation',
      'wallet_allocation_livret',
      'wallet_benchmark_livret',
      'wallet_period_month',
      'wallet_period_quarter',
      'wallet_positions_title',
      'wizard_preset_covid',
    };
    final same = {
      for (final k in keys)
        if (fr[k] == en[k]) k,
    };
    expect(same.difference(shared), isEmpty);
  });
}
