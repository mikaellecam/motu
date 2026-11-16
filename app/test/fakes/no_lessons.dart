import 'package:finance_companion/application/learning/island_path.dart';
import 'package:finance_companion/domain/learning/content.dart';
import 'package:finance_companion/domain/learning/node.dart';
import 'package:finance_companion/domain/learning/path.dart';

/// Actions & ETF before its first lesson: one to do, one locked. A wallet's
/// island stands all grown whatever the lessons (M13-1).
const noLessonsDone = IslandPathView(
  Localized('Actions & ETF', 'Stocks & ETFs'),
  [
    PathNode(
      NodeContent(
        id: 'ae.livret-vs-etf',
        type: NodeType.predictReveal,
        title: Localized('Livret ou ETF ?', 'Livret or ETF?'),
        status: ContentStatus.published,
      ),
      NodeState.current,
    ),
    PathNode(
      NodeContent(
        id: 'ae.fees-toy',
        type: NodeType.toy,
        title: Localized('Le jouet des frais', 'The fees toy'),
        status: ContentStatus.published,
      ),
      NodeState.locked,
    ),
  ],
);
