import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/glossary.dart';
import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/application/learning/missions.dart';
import 'package:finance_companion/application/learning/node_player.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/data/content/pack_codec.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/domain/learning/path.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/lesson_pack.dart';
import '../../fakes/second_island.dart';

// Several islands (M12-1): a lesson or a term of any island's pack.

void main() {
  late AppDatabase db;
  late ProviderContainer c;
  final actionsEtf = decodePack(packJson());
  final bases = decodePack(secondIslandJson());

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        contentPackProvider(actionsEtfIsland)
            .overrideWith((_) async => actionsEtf),
        contentPackProvider(lesBasesIsland).overrideWith((_) async => bases),
        contentPacksProvider.overrideWith((_) async => [actionsEtf, bases]),
      ],
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<T> read<T>(ProviderListenable<Future<T>> provider) {
    c.listen(provider, (_, _) {});
    return c.read(provider);
  }

  test('every playable island has its pack, in order', () async {
    final container = ProviderContainer(
      overrides: [
        contentPackProvider(actionsEtfIsland)
            .overrideWith((_) async => actionsEtf),
        contentPackProvider(lesBasesIsland)
            .overrideWith((ref) async => decodePack(emptyBasesJson())),
      ],
    );
    addTearDown(container.dispose);
    final packs = await container.read(contentPacksProvider.future);
    expect([for (final p in packs) p.id], playableIslands);
  });

  test('a lesson of another island, its terms from every island', () async {
    expect(
      (await read(islandNodeProvider('lb.last').future)).title.fr,
      "Point d'étape",
    );
    final mission = await read(missionViewProvider('lb.mission').future);
    expect(mission.node.title.fr, 'Range ton matelas');
    expect(
      mission.terms.keys,
      containsAll(['pouvoir-d-achat', 'diversification']),
    );
  });

  test(
    'a term of any island opens its sheet; the glossary lists them all',
    () async {
      final sheet = await read(termSheetProvider('pouvoir-d-achat').future);
      expect(sheet.term.title.fr, "Pouvoir d'achat");
      expect(
        sheet.terms.keys,
        containsAll(['pouvoir-d-achat', 'diversification']),
      );
      expect((await read(glossaryIndexProvider('fr').future)).total, 2);
    },
  );

  test('the questionnaire starts Actions & ETF only: another island starts '
      'at its first lesson', () async {
    await c
        .read(profileRepositoryProvider)
        .save(
          const Profile(
            goal: Goal.longTerm,
            dropReaction: DropReaction.wait,
            knowledge: Knowledge.etfs,
            savings: Savings.livret,
            weeklyTime: WeeklyTime.fifteen,
          ),
        );
    final path = await read(islandPathProvider('les-bases').future);
    expect(
      [for (final n in path.nodes) n.state],
      [NodeState.current, NodeState.locked, NodeState.locked],
    );
  });
}
