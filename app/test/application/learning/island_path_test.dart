import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/domain/learning/path.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/lesson_pack.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => decodePack(packJson())),
        contentPackProvider(lesBasesIsland)
            .overrideWith((ref) async => decodePack(emptyBasesJson())),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<IslandPathView> path() async {
    container.listen(islandPathProvider(actionsEtfIsland), (_, _) {});
    return container.read(islandPathProvider(actionsEtfIsland).future);
  }

  List<(String, NodeState)> rows(IslandPathView view) => [
    for (final n in view.nodes) (n.node.id, n.state),
  ];

  test('the path in order, from node 1 before the questionnaire', () async {
    final view = await path();
    expect(view.title.fr, 'Actions & ETF');
    expect(rows(view), [
      ('ae.apple', NodeState.current),
      ('ae.fees', NodeState.locked),
      ('ae.mission', NodeState.locked),
    ]);
    expect(view.done, 0);
  });

  test('a completed node moves the path on', () async {
    await path();
    await container
        .read(profileRepositoryProvider)
        .completeNode(
          'ae.apple',
          answer: 'apple',
          at: DateTime.utc(2026, 10, 11),
        );
    // The completion stream reaches the provider.
    await Future<void>.delayed(Duration.zero);
    final view = await path();
    expect(rows(view).map((r) => r.$2), [
      NodeState.done,
      NodeState.current,
      NodeState.locked,
    ]);
    expect(view.done, 1);
  });

  test('the profile shapes the path', () async {
    await container
        .read(profileRepositoryProvider)
        .save(
          const Profile(
            goal: Goal.longTerm,
            dropReaction: DropReaction.wait,
            knowledge: Knowledge.etfs,
            savings: Savings.currentAccount,
            weeklyTime: WeeklyTime.fifteen,
          ),
        );
    // « Ce qu'est un ETF » starts at node 3: nodes 1 and 2 are skipped.
    expect(rows(await path()).map((r) => r.$2), [
      NodeState.open,
      NodeState.open,
      NodeState.current,
    ]);
  });
}
