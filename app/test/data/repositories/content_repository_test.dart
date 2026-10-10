import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/remote/backend_api.dart';
import 'package:finance_companion/data/repositories/content_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_backend.dart';

final bundledJson = File('assets/packs/actions-etf.json').readAsStringSync();

/// The bundled pack at another [version], with node 1 renamed.
String version(int version, {String title = 'Nouveau titre'}) {
  final json = jsonDecode(bundledJson) as Map<String, dynamic>;
  json['island']['version'] = version;
  json['nodes'][0]['title']['fr'] = title;
  return jsonEncode(json);
}

void main() {
  late AppDatabase db;
  late FakeBackend backend;
  late WallClock wall;
  late String bundled;

  ContentRepository repo() => ContentRepository(
    db,
    BackendApi('http://backend.test', adapter: backend),
    bundled: (id) async => id == 'actions-etf' ? bundled : throw StateError(id),
    wallClock: wall,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    backend = FakeBackend();
    wall = WallClock(DateTime.utc(2026, 10, 10, 9));
    bundled = bundledJson;
  });
  tearDown(() => db.close());

  test('offline on first launch: the bundled pack', () async {
    backend.offline = true;
    final pack = await repo().pack('actions-etf');
    expect(pack.version, 1);
    expect(pack.nodes, hasLength(12));
  });

  test(
    'a newer version is fetched, cached, and kept after a restart',
    () async {
      backend.packs['actions-etf'] = {2: version(2)};
      final pack = await repo().pack('actions-etf');
      expect(pack.version, 2);
      expect(pack.nodes.first.title.fr, 'Nouveau titre');
      expect(backend.to('/v1/content/packs/actions-etf/2'), hasLength(1));

      backend.offline = true;
      wall.t = wall.t.add(const Duration(days: 3));
      expect((await repo().pack('actions-etf')).version, 2);
    },
  );

  test('the manifest is checked at most once a day', () async {
    final r = repo();
    await r.pack('actions-etf');
    await r.pack('actions-etf');
    expect(
      backend.to('/v1/content/manifest'),
      hasLength(1),
      reason: 'on the bundle',
    );

    backend.packs['actions-etf'] = {2: version(2)};
    wall.t = wall.t.add(const Duration(hours: 23));
    expect((await r.pack('actions-etf')).version, 1);
    wall.t = wall.t.add(const Duration(hours: 2));
    expect((await r.pack('actions-etf')).version, 2);
    expect(backend.to('/v1/content/manifest'), hasLength(2));

    // Cached now: the row carries when it was checked, across restarts.
    wall.t = wall.t.add(const Duration(hours: 1));
    await repo().pack('actions-etf');
    expect(backend.to('/v1/content/manifest'), hasLength(2));
  });

  test(
    'a corrupt cached pack falls back to the bundled one, and goes',
    () async {
      await db.marketDao.saveContentPack(
        ContentPacksCompanion.insert(
          islandId: 'actions-etf',
          version: 2,
          json: '{"island": broken',
          checkedAt: wall.t,
        ),
      );
      backend.offline = true;
      expect((await repo().pack('actions-etf')).version, 1);
      expect(await db.marketDao.contentPack('actions-etf'), isNull);
    },
  );

  test('a corrupt download is not kept', () async {
    backend.packs['actions-etf'] = {
      2: version(2).replaceFirst('"fr":"Nouveau titre"', '"fr":""'),
    };
    expect((await repo().pack('actions-etf')).version, 1);
    expect(await db.marketDao.contentPack('actions-etf'), isNull);
  });

  test('a cache older than a newer app bundle gives way to it', () async {
    backend.packs['actions-etf'] = {2: version(2)};
    await repo().pack('actions-etf');
    // The app updates and ships version 3.
    bundled = version(3, title: 'Titre v3');
    final pack = await repo().pack('actions-etf');
    expect(pack.version, 3);
    expect(pack.nodes.first.title.fr, 'Titre v3');
  });
}
