import 'package:decimal/decimal.dart';

import 'node.dart';

/// A text in both app languages (BRIEF §4.3: every text field has both).
final class Localized {
  const Localized(this.fr, this.en);
  final String fr;
  final String en;

  /// The text in [languageCode]; French unless English is asked for.
  String of(String languageCode) => languageCode == 'en' ? en : fr;
}

/// Agent-drafted text stays `draft` until it is validated (BRIEF §9).
enum ContentStatus { draft, published }

/// One node of an island, as its pack describes it. [payload] holds the
/// fields of its type (question, choices…), read by that type's player.
final class NodeContent {
  const NodeContent({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    this.glossary = const [],
    this.datasets = const [],
    this.payload = const {},
  });

  final String id;
  final NodeType type;
  final Localized title;
  final ContentStatus status;

  /// Glossary terms the node links to.
  final List<String> glossary;

  /// Ids of the frozen datasets it draws.
  final List<String> datasets;
  final Map<String, Object?> payload;
}

/// Prices frozen for a lesson by `cmd/freeze`, never hand-typed (§4.3).
final class Dataset {
  const Dataset({
    required this.id,
    required this.source,
    required this.adjusted,
    required this.currency,
    required this.interval,
    required this.frozenAt,
    required this.points,
  });

  final String id;
  final String source;
  final bool adjusted;
  final String currency;
  final String interval;
  final DateTime frozenAt;
  final List<(DateTime, Decimal)> points;
}

/// A glossary entry (BRIEF §4.4). [liveExample] and [quiz] are read by the
/// glossary sheet.
final class GlossaryTerm {
  const GlossaryTerm({
    required this.id,
    required this.title,
    required this.short,
    required this.body,
    this.related = const [],
    this.liveExample,
    this.quiz = const [],
  });

  final String id;
  final Localized title;

  /// One line.
  final Localized short;
  final Localized body;
  final List<String> related;
  final Map<String, Object?>? liveExample;
  final List<Map<String, Object?>> quiz;
}

/// An island's content at one version: its path of nodes, their datasets
/// and the glossary they use (ADR-006).
final class ContentPack {
  const ContentPack({
    required this.id,
    required this.version,
    required this.title,
    required this.nodes,
    required this.datasets,
    required this.glossary,
  });

  final String id;
  final int version;
  final Localized title;

  /// In path order.
  final List<NodeContent> nodes;
  final Map<String, Dataset> datasets;
  final Map<String, GlossaryTerm> glossary;

  /// The path the learning rules walk (next step, UI level).
  List<IslandNode> get path => [
    for (final n in nodes) IslandNode(n.id, n.type),
  ];
}
