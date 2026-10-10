import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../domain/learning/content.dart';
import '../providers.dart';

part 'content.g.dart';

/// The playable island of V1 (BRIEF §4.3).
const actionsEtfIsland = 'actions-etf';

/// The content of [islandId]: bundled, or a newer version once downloaded
/// (ADR-006). Kept for the session; the repository checks once a day.
@Riverpod(keepAlive: true)
Future<ContentPack> contentPack(Ref ref, String islandId) =>
    ref.watch(contentRepositoryProvider).pack(islandId);
