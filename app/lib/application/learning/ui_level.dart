import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/learning/profile_rules.dart';
import '../providers.dart';

part 'ui_level.g.dart';

/// How much the UI shows (BRIEF §4.15): 1 before the questionnaire, 3 with
/// « Tout afficher dès maintenant », else from the profile and progress.
// ponytail: no island path until content packs load (M6-1), so levels 2–3
// come from the profile only for now.
@riverpod
Future<int> currentUiLevel(Ref ref) async {
  final profiles = ref.watch(profileRepositoryProvider);
  if (await profiles.showAll()) return 3;
  final profile = await profiles.load();
  if (profile == null) return 1;
  return uiLevel(profile, const [], completed: await profiles.completedNodes());
}
