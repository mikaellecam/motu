import 'package:drift/native.dart';
import 'package:finance_companion/application/learning/content.dart';
import 'package:finance_companion/application/learning/place.dart';
import 'package:finance_companion/application/providers.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/repositories/profile_repository.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Profile knowing(Knowledge k) => Profile(
  goal: Goal.longTerm,
  dropReaction: DropReaction.wait,
  knowledge: k,
  savings: Savings.livret,
);

void main() {
  test('the way starts at the port, past it for those who know ETFs', () {
    expect(startOfWay(null), lesBasesIsland);
    expect(startOfWay(knowing(Knowledge.nothing)), lesBasesIsland);
    expect(startOfWay(knowing(Knowledge.stocks)), lesBasesIsland);
    expect(startOfWay(knowing(Knowledge.etfs)), actionsEtfIsland);
    expect(startOfWay(knowing(Knowledge.alreadyInvesting)), actionsEtfIsland);
  });

  group('Place', () {
    late AppDatabase db;
    late ProfileRepository profiles;
    ProviderContainer container() {
      final c = ProviderContainer(
        overrides: [profileRepositoryProvider.overrideWithValue(profiles)],
      );
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      profiles = ProfileRepository(db);
    });
    tearDown(() => db.close());

    test('first launch: where the way starts, for both answers', () async {
      expect(await container().read(placeProvider.future), (
        island: lesBasesIsland,
        arriving: false,
      ));
      await profiles.save(knowing(Knowledge.etfs));
      expect(
        (await container().read(placeProvider.future)).island,
        actionsEtfIsland,
      );
    });

    test('the island seen last, kept for the next launch', () async {
      await profiles.save(knowing(Knowledge.nothing));
      final first = container();
      await first.read(placeProvider.future);
      await first.read(placeProvider.notifier).visit(actionsEtfIsland);
      expect(await profiles.place(), actionsEtfIsland);
      // Next launch.
      expect(await container().read(placeProvider.future), (
        island: actionsEtfIsland,
        arriving: false,
      ));
    });

    test('a crossing lands, arriving; a place no island has any more is '
        'forgotten', () async {
      await profiles.save(knowing(Knowledge.nothing));
      final c = container();
      await c.read(placeProvider.future);
      await c.read(placeProvider.notifier).sail(actionsEtfIsland);
      expect(c.read(placeProvider).value, (
        island: actionsEtfIsland,
        arriving: true,
      ));
      await profiles.setPlace('atlantis');
      expect(
        (await container().read(placeProvider.future)).island,
        lesBasesIsland,
      );
    });

    test('before the questionnaire, nothing is kept', () async {
      final c = container();
      await c.read(placeProvider.future);
      await c.read(placeProvider.notifier).visit(actionsEtfIsland);
      expect(await profiles.place(), isNull);
    });
  });
}
