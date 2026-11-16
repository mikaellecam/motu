import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/sea_chart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, ChartState> states(Set<String> done, {bool aeOpen = false}) => {
    for (final MapEntry(:key, :value) in chartStates(
      done,
      open: {lesBasesIsland: true, actionsEtfIsland: aeOpen},
    ).entries)
      key: value.$1,
  };

  test('nothing done: the port open, every island closed', () {
    expect(states({}), {
      lesBasesIsland: ChartState.open,
      actionsEtfIsland: ChartState.closed,
      tradingIsland: ChartState.closed,
      realEstateIsland: ChartState.closed,
      cryptoIsland: ChartState.closed,
    });
    expect(chartStates({}, open: const {})[actionsEtfIsland]!.$2, [
      'lb.cushion-2020',
    ]);
  });

  test('Actions & ETF as its path says, whatever its gate', () {
    expect(states({}, aeOpen: true)[actionsEtfIsland], ChartState.open);
    expect(
      states({'lb.cushion-2020'})[actionsEtfIsland],
      ChartState.closed,
      reason: 'the path decides, the questionnaire and progress included',
    );
  });

  test('the loan\'s lesson: Immobilier\'s line open, no lessons yet', () {
    expect(states({'lb.loan-cost'})[realEstateIsland], ChartState.soon);
  });

  test(
    'a closed island names what it still waits for, in its gate\'s order',
    () {
      final only = chartStates({'lb.spot-the-scam'}, open: const {});
      expect(only[tradingIsland]!.$1, ChartState.closed);
      expect(only[tradingIsland]!.$2, ['ae.checkpoint-1']);
      expect(only[cryptoIsland]!.$2, ['ae.risk-ladder']);
      final none = chartStates({}, open: const {});
      expect(none[tradingIsland]!.$2, ['lb.spot-the-scam', 'ae.checkpoint-1']);
    },
  );

  test('both gates met: Trading and Crypto soon', () {
    final s = states({'lb.spot-the-scam', 'ae.risk-ladder', 'ae.checkpoint-1'});
    expect(s[tradingIsland], ChartState.soon);
    expect(s[cryptoIsland], ChartState.soon);
  });

  test('the port is always open, its lessons or not', () {
    expect(
      chartStates({}, open: const {})[lesBasesIsland]!.$1,
      ChartState.open,
    );
  });
}
