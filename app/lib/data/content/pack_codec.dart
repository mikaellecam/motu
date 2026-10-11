import 'dart:convert';

import 'package:decimal/decimal.dart';

import '../../domain/learning/content.dart';
import '../../domain/learning/node.dart';

/// Reads a content pack: one JSON document `{island, nodes, datasets,
/// glossary}` (ADR-006). Throws [FormatException] on anything the app cannot
/// use: a missing field, a text without both languages, an unknown node type,
/// or a reference to a node, dataset or term the pack does not hold. Such a
/// pack is corrupt: the caller falls back to the bundled one.
ContentPack decodePack(String source) {
  final root = _map(jsonDecode(source), 'pack');
  final island = _map(root['island'], 'island');
  final nodes = {
    for (final n in _list(root['nodes'], 'nodes')) _node(_map(n, 'node')),
  };
  final byId = {for (final n in nodes) n.id: n};
  final datasets = {
    for (final d in _list(root['datasets'], 'datasets'))
      _string(_map(d, 'dataset')['id'], 'dataset id'): _dataset(
        _map(d, 'dataset'),
      ),
  };
  final glossary = {
    for (final t in _list(root['glossary'], 'glossary'))
      _string(_map(t, 'term')['id'], 'term id'): _term(_map(t, 'term')),
  };

  final path = [
    for (final id in _list(island['nodes'], 'island nodes'))
      byId[_string(id, 'island node')] ??
          (throw FormatException('island lists an unknown node: $id')),
  ];
  for (final node in path) {
    for (final id in node.datasets) {
      if (!datasets.containsKey(id)) {
        throw FormatException('${node.id} draws an unknown dataset: $id');
      }
    }
    for (final id in node.glossary) {
      if (!glossary.containsKey(id)) {
        throw FormatException('${node.id} links an unknown term: $id');
      }
    }
  }
  for (final term in glossary.values) {
    for (final id in term.related) {
      if (!glossary.containsKey(id)) {
        throw FormatException('${term.id} relates to an unknown term: $id');
      }
    }
  }

  return ContentPack(
    id: _string(island['id'], 'island id'),
    version: _int(island['version'], 'island version'),
    title: _localized(island['title'], 'island title'),
    nodes: path,
    datasets: datasets,
    glossary: glossary,
  );
}

const _nodeFields = {
  'id',
  'type',
  'title',
  'status',
  'glossary',
  'datasets',
  'bridge',
  'covers',
};

NodeContent _node(Map<String, Object?> json) {
  final id = _string(json['id'], 'node id');
  final type = _string(json['type'], '$id type');
  return NodeContent(
    id: id,
    type: NodeType.values.firstWhere(
      (t) => t.json == type,
      orElse: () => throw FormatException('$id has an unknown type: $type'),
    ),
    title: _localized(json['title'], '$id title'),
    status: switch (json['status']) {
      'draft' => ContentStatus.draft,
      'published' => ContentStatus.published,
      final other => throw FormatException('$id has an unknown status: $other'),
    },
    glossary: _strings(json['glossary'] ?? const [], '$id glossary'),
    datasets: _strings(json['datasets'] ?? const [], '$id datasets'),
    bridge: switch (json['bridge']) {
      null => null,
      final Object bridge => TripBridge(
        _date(_map(bridge, '$id bridge')['date'], '$id bridge date'),
        difficulty: switch (_map(bridge, '$id bridge')['difficulty']) {
          null => null,
          final Object d => _string(d, '$id bridge difficulty'),
        },
      ),
    },
    covers: switch (json['covers']) {
      null => null,
      final Object covers => _period(_map(covers, '$id covers'), id),
    },
    payload: {
      for (final e in json.entries)
        if (!_nodeFields.contains(e.key)) e.key: e.value,
    },
  );
}

Dataset _dataset(Map<String, Object?> json) {
  final id = _string(json['id'], 'dataset id');
  return Dataset(
    id: id,
    source: _string(json['source'], '$id source'),
    adjusted: json['adjusted'] is bool
        ? json['adjusted']! as bool
        : throw FormatException('$id: adjusted is not a boolean'),
    currency: _string(json['currency'], '$id currency'),
    interval: _string(json['interval'], '$id interval'),
    frozenAt: _date(json['frozen_at'], '$id frozen_at'),
    points: [
      for (final p in _list(json['points'], '$id points'))
        switch (p) {
          [final String date, final num value] => (
            _date(date, '$id point'),
            // JSON numbers come in as doubles; their shortest form gives the
            // frozen digits back.
            Decimal.parse(value.toString()),
          ),
          _ => throw FormatException('$id: a point is not [date, value]'),
        },
    ],
  );
}

GlossaryTerm _term(Map<String, Object?> json) {
  final id = _string(json['id'], 'term id');
  return GlossaryTerm(
    id: id,
    title: _localized(json['title'], '$id title'),
    short: _localized(json['short'], '$id short'),
    body: _localized(json['body'], '$id body'),
    related: _strings(json['related'] ?? const [], '$id related'),
    liveExample: json['live_example'] == null
        ? null
        : _map(json['live_example'], '$id live_example'),
    quiz: [
      for (final q in _list(json['quiz'] ?? const [], '$id quiz'))
        _map(q, '$id quiz question'),
    ],
  );
}

Map<String, Object?> _map(Object? value, String what) => value is Map
    ? value.cast<String, Object?>()
    : throw FormatException('$what is not an object');

List<Object?> _list(Object? value, String what) =>
    value is List ? value : throw FormatException('$what is not a list');

String _string(Object? value, String what) =>
    value is String && value.isNotEmpty
    ? value
    : throw FormatException('$what is missing');

int _int(Object? value, String what) =>
    value is int ? value : throw FormatException('$what is not an integer');

List<String> _strings(Object? value, String what) => [
  for (final v in _list(value, what)) _string(v, what),
];

Localized _localized(Object? value, String what) {
  final map = _map(value, what);
  return Localized(
    _string(map['fr'], '$what (fr)'),
    _string(map['en'], '$what (en)'),
  );
}

DateTime _date(Object? value, String what) {
  final text = _string(value, what);
  final parsed = DateTime.tryParse(text);
  if (parsed == null) throw FormatException('$what is not a date: $text');
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

Period _period(Map<String, Object?> json, String id) {
  final from = _date(json['from'], '$id covers from');
  final to = _date(json['to'], '$id covers to');
  if (to.isBefore(from)) throw FormatException('$id covers an empty period');
  return Period(from, to);
}
