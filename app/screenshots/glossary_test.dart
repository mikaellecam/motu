import 'dart:io';

import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/glossary.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/core/money/money.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/repositories/glossary_repository.dart';
import 'package:finance_companion/domain/analytics/drawdown.dart';
import 'package:finance_companion/domain/learning/glossary.dart';
import 'package:finance_companion/domain/market/asset.dart';
import 'package:finance_companion/domain/market/market_calendar.dart';
import 'package:finance_companion/presentation/features/glossary/glossary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'screenshot.dart';

// The glossary as the app bundles it (M6-8, draft copy). « Indice » and
// « Action » are discovered, « Diversification » met in a completed lesson.
// The volatility example uses the 2025 daily closes frozen in the pack:
// Apple against the world ETF.

Asset _asset(String id, String name, AssetType type) => Asset(
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
  final pack = decodePack(
    File('assets/packs/actions-etf.json').readAsStringSync(),
  );
  final apple = pack.datasets['ds.aapl-2025-d']!.points;
  final world = pack.datasets['ds.acwi-2025-d']!.points;
  final overrides = <Override>[
    contentPackProvider(actionsEtfIsland).overrideWith((ref) async => pack),
    glossaryProgressProvider.overrideWith(
      (ref) => Stream.value({
        for (final id in ['indice', 'action'])
          id: TermProgress(DateTime.utc(2026, 10, 1), quizPassed: false),
      }),
    ),
    completedNodesProvider.overrideWith(
      (ref) => Stream.value({'ae.apple-vs-world-2022'}),
    ),
    liveExampleProvider.overrideWith(
      (ref, args) async => LiveExampleView(
        kind: args.$1,
        asset: _asset('apple', 'Apple', AssetType.stock),
        figure: liveFigure(args.$1, apple),
        closes: apple,
        world: _asset('world', 'iShares MSCI ACWI ETF', AssetType.etf),
        worldFigure: liveFigure(args.$1, world),
        worldCloses: args.$1 == LiveExample.volatility ? world : const [],
        drawdown: args.$1 == LiveExample.drawdown ? maxDrawdown(apple) : null,
      ),
    ),
  ];

  screenshot(
    'm6-6-glossary',
    const GlossaryScreen(),
    size: const Size(390, 900),
    overrides: overrides,
  );

  screenshot(
    'm6-6-term-sheet',
    const GlossaryScreen(),
    size: const Size(390, 900),
    overrides: overrides,
    act: (tester) async {
      await tester.scrollUntilVisible(
        find.text('Volatilité'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Volatilité'));
      await tester.pumpAndSettle();
    },
  );

  // The worst drop's example: its peak and trough marked (M9-28).
  screenshot(
    'm9-28-term-sheet-drawdown',
    const GlossaryScreen(),
    size: const Size(390, 900),
    overrides: overrides,
    act: (tester) async {
      await tester.scrollUntilVisible(
        find.text('Pire baisse'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Pire baisse'));
      await tester.pumpAndSettle();
    },
  );
}
