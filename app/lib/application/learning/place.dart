import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/learning/profile.dart';
import '../../domain/learning/profile_rules.dart';
import '../providers.dart';
import 'content.dart';

part 'place.g.dart';

/// Where the way starts (BRIEF §4.1, M12-7): the port, or Actions & ETF for
/// those the questionnaire sends past Les bases. Before it, the port.
String startOfWay(Profile? profile) =>
    profile != null && skipsTheBasics(profile)
    ? actionsEtfIsland
    : lesBasesIsland;

/// The island the app shows up close (M13-6): where the user was last time,
/// else where the way starts. [arriving] once a crossing lands there.
@Riverpod(keepAlive: true)
class Place extends _$Place {
  @override
  Future<({String island, bool arriving})> build() async {
    final profiles = ref.watch(profileRepositoryProvider);
    final saved = await profiles.place();
    return (
      island: saved != null && playableIslands.contains(saved)
          ? saved
          : startOfWay(await profiles.load()),
      arriving: false,
    );
  }

  /// [island] seen up close: the app opens there next time.
  Future<void> visit(String island) => _go(island, arriving: false);

  /// A crossing to [island] (M13-5): it shows up close from its pier.
  Future<void> sail(String island) => _go(island, arriving: true);

  Future<void> _go(String island, {required bool arriving}) async {
    if (state.value case (island: final at, arriving: _)
        when at == island && !arriving) {
      return;
    }
    state = AsyncData((island: island, arriving: arriving));
    await ref.read(profileRepositoryProvider).setPlace(island);
  }
}
