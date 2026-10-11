import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/learning/profile_rules.dart';
import '../providers.dart';
import 'content.dart';
import 'next_step_card.dart' show completionsProvider;

part 'ui_level.g.dart';

/// How much the UI shows (BRIEF §4.15): 1 before the questionnaire, 3 with
/// « Tout afficher dès maintenant », else from the profile and progress on
/// the Actions & ETF path. Again as soon as a lesson is completed.
@riverpod
Future<int> currentUiLevel(Ref ref) async {
  final profiles = ref.watch(profileRepositoryProvider);
  final pack = ref.watch(contentPackProvider(actionsEtfIsland).future)
    ..ignore();
  final done = ref.watch(completionsProvider.future)..ignore();
  if (await profiles.showAll()) return 3;
  final profile = await profiles.load();
  if (profile == null) return 1;
  return uiLevel(
    profile,
    (await pack).path,
    completed: (await done).keys.toSet(),
  );
}
