import 'dart:convert';

import 'package:decimal/decimal.dart';

import '../../domain/learning/checkpoint.dart';
import '../../domain/learning/content.dart';
import '../../domain/learning/decision.dart';
import '../../domain/learning/glossary.dart';
import '../../domain/learning/missions.dart';
import '../../domain/learning/node.dart';
import '../../domain/learning/puzzle.dart';
import '../../domain/learning/reveal.dart';
import '../../domain/learning/sort.dart';
import '../../domain/learning/toys.dart';

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
    asset: switch (json['asset']) {
      null => null,
      final Object a => _string(a, '$id asset'),
    },
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
    forYou: switch (json['for_you']) {
      null => null,
      final Object v => _localized(v, '$id for_you'),
    },
    liveExample: switch (json['live_example']) {
      null => null,
      final Object v =>
        LiveExample.values
            .where((e) => e.name == _map(v, '$id live_example')['widget'])
            .firstOrNull,
    },
    quiz: [
      for (final q in _list(json['quiz'] ?? const [], '$id quiz'))
        _question(_map(q, '$id quiz question'), id),
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

/// The payload of a `predict_reveal` [node] of [pack] (BRIEF §4.3): the
/// question and its choices, one of them the answer, the curves of datasets
/// the node draws, and optionally the amount they start from and the live
/// variant (only `compare_returns` is known).
PredictReveal decodePredictReveal(NodeContent node, ContentPack pack) {
  final id = node.id;
  final json = node.payload;
  final choices = [
    for (final c in _list(json['choices'], '$id choices'))
      RevealChoice(
        _string(_map(c, '$id choice')['id'], '$id choice id'),
        _localized(_map(c, '$id choice')['label'], '$id choice label'),
      ),
  ];
  final answer = _string(json['answer'], '$id answer');
  if (!choices.any((c) => c.id == answer)) {
    throw FormatException('$id: the answer $answer is not a choice');
  }
  final series = [
    for (final s in _list(json['series'], '$id series'))
      RevealSeries(
        _drawn(node, pack, _string(_map(s, '$id series')['dataset'], id)),
        _localized(_map(s, '$id series')['label'], '$id series label'),
      ),
  ];
  if (series.isEmpty) throw FormatException('$id draws no curve');
  final invested = switch (json['invested']) {
    null => null,
    final Object v => _positive(v, '$id invested'),
  };
  final live = switch (json['live_variant']) {
    null => null,
    final Object v => _map(v, '$id live_variant'),
  };
  return PredictReveal(
    question: _localized(json['question'], '$id question'),
    choices: choices,
    answer: answer,
    series: series,
    explanation: _localized(json['explanation'], '$id explanation'),
    invested: invested,
    liveVariant: live != null && live['widget'] == 'compare_returns'
        ? LiveVariant(_string(live['period'], '$id live period'))
        : null,
  );
}

/// The payload of a `toy` [node] of [pack] (BRIEF §4.3): a known formula, a
/// slider for each of its inputs and no other, and optionally the dataset
/// whose past average seeds the `return` slider.
Toy decodeToy(NodeContent node, ContentPack pack) {
  final id = node.id;
  final json = node.payload;
  final name = _string(json['formula'], '$id formula');
  final formula = ToyFormula.values.firstWhere(
    (f) => f.json == name,
    orElse: () => throw FormatException('$id has an unknown formula: $name'),
  );
  final controls = [
    for (final c in _list(json['controls'], '$id controls'))
      _control(_map(c, '$id control'), id),
  ];
  final ids = [for (final c in controls) c.id]..sort();
  if (ids.join(',') != ([...formula.inputs]..sort()).join(',')) {
    throw FormatException(
      '$id: ${formula.json} reads ${formula.inputs}, not $ids',
    );
  }
  final from = switch (json['return_from']) {
    null => null,
    final Object v => _map(v, '$id return_from'),
  };
  return Toy(
    formula: formula,
    controls: controls,
    intro: _localized(json['intro'], '$id intro'),
    explanation: _localized(json['explanation'], '$id explanation'),
    returnFrom: from == null
        ? null
        : PastReturn(
            _drawn(node, pack, _string(from['dataset'], '$id return_from')),
            _localized(from['label'], '$id return_from label'),
          ),
  );
}

ToyControl _control(Map<String, Object?> json, String node) {
  final id = _string(json['id'], '$node control id');
  final what = '$node $id';
  final control = ToyControl(
    id: id,
    label: _localized(json['label'], '$what label'),
    min: _decimal(json['min'], '$what min'),
    max: _decimal(json['max'], '$what max'),
    step: _positive(json['step'], '$what step'),
    initial: _decimal(json['default'], '$what default'),
  );
  if (control.min > control.max ||
      control.initial < control.min ||
      control.initial > control.max) {
    throw FormatException('$what: min ≤ default ≤ max');
  }
  return control;
}

/// [dataset] when [node] draws it and [pack] holds it.
String _drawn(NodeContent node, ContentPack pack, String dataset) =>
    node.datasets.contains(dataset) && pack.datasets.containsKey(dataset)
    ? dataset
    : throw FormatException('${node.id} does not draw $dataset');

Decimal _decimal(Object? value, String what) => value is num
    ? Decimal.parse(value.toString())
    : throw FormatException('$what is not a number');

Decimal _positive(Object? value, String what) {
  final number = _decimal(value, what);
  return number > Decimal.zero
      ? number
      : throw FormatException('$what is not above zero');
}

/// The payload of a `decision` [node] (BRIEF §4.3): the moment and its
/// context, the curve (a dataset the node draws, with points before and
/// after the moment), the amount at stake, and two or more choices, each
/// with an upside, a downside and the share it keeps invested (0 to 1).
DecisionNode decodeDecision(NodeContent node, ContentPack pack) {
  final id = node.id;
  final json = node.payload;
  final moment = _date(json['moment'], '$id moment');
  final series = _map(json['series'], '$id series');
  final dataset = _drawn(node, pack, _string(series['dataset'], '$id series'));
  final (before, after) = splitAt(pack.datasets[dataset]!.points, moment);
  if (before.isEmpty || after.length < 2) {
    throw FormatException('$id: $moment is not inside $dataset');
  }
  final choices = [
    for (final c in _list(json['choices'], '$id choices'))
      _decisionChoice(_map(c, '$id choice'), id),
  ];
  if (choices.length < 2) throw FormatException('$id offers no choice');
  return DecisionNode(
    context: _localized(json['context'], '$id context'),
    moment: moment,
    dataset: dataset,
    seriesLabel: _localized(series['label'], '$id series label'),
    choices: choices,
    invested: _positive(json['invested'], '$id invested'),
    explanation: _localized(json['explanation'], '$id explanation'),
  );
}

DecisionChoice _decisionChoice(Map<String, Object?> json, String node) {
  final id = _string(json['id'], '$node choice id');
  final kept = _decimal(json['kept'], '$node $id kept');
  if (kept < Decimal.zero || kept > Decimal.one) {
    throw FormatException('$node $id: kept is a share from 0 to 1');
  }
  return DecisionChoice(
    id: id,
    label: _localized(json['label'], '$node $id label'),
    upside: _localized(json['upside'], '$node $id upside'),
    downside: _localized(json['downside'], '$node $id downside'),
    kept: kept,
  );
}

/// The payload of a `sort` [node] (BRIEF §4.3): what the two ends of the
/// scale mean, and two or more distinct items, each with either a fixed
/// value or a daily dataset the node draws (ranked by its volatility).
SortNode decodeSort(NodeContent node, ContentPack pack) {
  final id = node.id;
  final json = node.payload;
  final scale = _map(json['scale'], '$id scale');
  final items = [
    for (final i in _list(json['items'], '$id items'))
      _sortItem(_map(i, '$id item'), node, pack),
  ];
  if (items.length < 2) throw FormatException('$id has nothing to sort');
  if ({for (final i in items) i.id}.length != items.length) {
    throw FormatException('$id lists an item twice');
  }
  return SortNode(
    prompt: _localized(json['prompt'], '$id prompt'),
    low: _localized(scale['low'], '$id scale low'),
    high: _localized(scale['high'], '$id scale high'),
    items: items,
    explanation: _localized(json['explanation'], '$id explanation'),
  );
}

SortItem _sortItem(
  Map<String, Object?> json,
  NodeContent node,
  ContentPack pack,
) {
  final id = _string(json['id'], '${node.id} item id');
  final dataset = json['dataset'];
  final value = json['value'];
  if ((dataset == null) == (value == null)) {
    throw FormatException('${node.id} $id: a dataset or a value');
  }
  return SortItem(
    id,
    _localized(json['label'], '${node.id} $id label'),
    dataset: dataset == null ? null : _daily(node, pack, dataset),
    value: value == null ? null : _decimal(value, '${node.id} $id value'),
  );
}

/// The payload of a `build_puzzle` [node] (BRIEF §4.3): assets on daily
/// datasets the node draws, each with its region; the rules (a volatility
/// cap, optionally a minimum of assets and of regions it can reach); and
/// the weight step, which divides 100 %.
PuzzleNode decodePuzzle(NodeContent node, ContentPack pack) {
  final id = node.id;
  final json = node.payload;
  final assets = [
    for (final a in _list(json['assets'], '$id assets'))
      PuzzleAsset(
        _daily(node, pack, _map(a, '$id asset')['dataset']),
        _localized(_map(a, '$id asset')['label'], '$id asset label'),
        _string(_map(a, '$id asset')['region'], '$id asset region'),
      ),
  ];
  final rules = _map(json['rules'], '$id rules');
  int? count(String key) => switch (rules[key]) {
    null => null,
    final Object v => _int(v, '$id $key'),
  };
  final minAssets = count('min_assets');
  final minRegions = count('min_regions');
  if ((minAssets ?? 0) > assets.length ||
      (minRegions ?? 0) > {for (final a in assets) a.region}.length) {
    throw FormatException('$id asks for more than it offers');
  }
  final step = _positive(json['step'], '$id step');
  if (step > Decimal.one || Decimal.one % step != Decimal.zero) {
    throw FormatException('$id: the step does not divide 100 %');
  }
  return PuzzleNode(
    prompt: _localized(json['prompt'], '$id prompt'),
    assets: assets,
    rules: PuzzleRules(
      maxVolatility: _positive(rules['max_volatility'], '$id max_volatility'),
      minAssets: minAssets,
      minRegions: minRegions,
    ),
    step: step,
    explanation: _localized(json['explanation'], '$id explanation'),
  );
}

/// The payload of a `checkpoint` [node] (BRIEF §4.3): questions, each with
/// choices, the right one among them, and optionally an explanation.
Checkpoint decodeCheckpoint(NodeContent node, ContentPack pack) {
  final id = node.id;
  final questions = [
    for (final q in _list(node.payload['questions'], '$id questions'))
      _question(_map(q, '$id question'), id),
  ];
  if (questions.isEmpty) throw FormatException('$id asks nothing');
  return Checkpoint(questions);
}

QuizQuestion _question(Map<String, Object?> json, String node) {
  final choices = [
    for (final c in _list(json['choices'], '$node choices'))
      RevealChoice(
        _string(_map(c, '$node choice')['id'], '$node choice id'),
        _localized(_map(c, '$node choice')['label'], '$node choice label'),
      ),
  ];
  final answer = _string(json['answer'], '$node answer');
  if (!choices.any((c) => c.id == answer)) {
    throw FormatException('$node: the answer $answer is not a choice');
  }
  return QuizQuestion(
    question: _localized(json['question'], '$node question'),
    choices: choices,
    answer: answer,
    explanation: switch (json['explanation']) {
      null => null,
      final Object e => _localized(e, '$node explanation'),
    },
  );
}

/// A daily dataset [node] draws: volatility needs daily closes.
String _daily(NodeContent node, ContentPack pack, Object? dataset) {
  final id = _drawn(node, pack, _string(dataset, '${node.id} dataset'));
  if (pack.datasets[id]!.interval != '1day') {
    throw FormatException('${node.id}: $id is not daily');
  }
  return id;
}

/// The payload of a `mission` [node] (BRIEF §4.3): its goal, and where in
/// the sandbox it is done (`explorer` or `wallet`).
MissionNode decodeMission(NodeContent node, ContentPack pack) {
  final id = node.id;
  final place = _string(node.payload['go'], '$id go');
  return MissionNode(
    _localized(node.payload['goal'], '$id goal'),
    MissionPlace.values.firstWhere(
      (p) => p.name == place,
      orElse: () =>
          throw FormatException('$id goes to an unknown place: $place'),
    ),
  );
}
