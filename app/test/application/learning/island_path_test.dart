import 'dart:io';

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

  setUp(() async {
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
    // Les bases' fifth lesson done: Actions & ETF's lessons are open (M12-7).
    await container
        .read(profileRepositoryProvider)
        .completeNode('lb.cushion-2020', at: DateTime.utc(2026, 10, 1));
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('closed until Les bases\' fifth lesson: every lesson locked, the one '
      'it waits for named (M12-7)', () async {
    final fresh = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(
          AppDatabase(NativeDatabase.memory()),
        ),
        contentPackProvider(actionsEtfIsland)
            .overrideWith((ref) async => decodePack(packJson())),
        contentPackProvider(lesBasesIsland).overrideWith(
          (ref) async => decodePack(
            File('assets/packs/les-bases.json').readAsStringSync(),
          ),
        ),
      ],
    );
    addTearDown(fresh.dispose);
    fresh.listen(islandPathProvider(actionsEtfIsland), (_, _) {});
    final view = await fresh.read(islandPathProvider(actionsEtfIsland).future);
    expect(view.open, isFalse);
    expect(view.opensAfter!.fr, 'Février 2020\u202f: et ton matelas\u202f?');
    expect({for (final n in view.nodes) n.state}, {NodeState.locked});
    // Les bases itself is open from its first lesson.
    fresh.listen(islandPathProvider(lesBasesIsland), (_, _) {});
    final bases = await fresh.read(islandPathProvider(lesBasesIsland).future);
    expect((bases.open, bases.nodes.first.state), (true, NodeState.current));
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
