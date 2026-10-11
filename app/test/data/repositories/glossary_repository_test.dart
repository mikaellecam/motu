import 'package:drift/native.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/repositories/glossary_repository.dart';
import 'package:finance_companion/domain/companion/rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late GlossaryRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = GlossaryRepository(db);
  });
  tearDown(() => db.close());

  final first = DateTime.utc(2026, 10, 11, 9);

  test('the first open discovers a term; later ones do not', () async {
    expect(await repo.discover('etf', first), isTrue);
    expect(
      await repo.discover('etf', first.add(const Duration(days: 1))),
      isFalse,
    );
    final states = await repo.watch().first;
    expect(states['etf']!.discoveredAt, first);
    expect(states['etf']!.quizPassed, isFalse);
  });

  test('a passed quiz is kept', () async {
    await repo.discover('etf', first);
    await repo.passQuiz('etf');
    expect((await repo.watch().first)['etf']!.quizPassed, isTrue);
  });

  test('every change reaches the watchers', () async {
    final seen = <Set<String>>[];
    final sub = repo.watch().listen((s) => seen.add(s.keys.toSet()));
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await repo.discover('indice', first);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(seen.first, isEmpty);
    expect(seen.last, {'indice'});
  });

  test('the companion moments shown, across wallets', () async {
    expect(await repo.momentsShown(), isEmpty);
    await db.customStatement(
      "INSERT INTO wallets (id, kind, name, start_date, status, params, created_at, breached_stops) "
      "VALUES ('live', 'live', 'live', '2026-10-01', 'active', '{}', '2026-10-01', '[]')",
    );
    for (final rule in [
      CompanionRule.firstLoss,
      CompanionRule.fxSwing,
      CompanionRule.firstLoss,
    ]) {
      await db.customStatement(
        "INSERT INTO companion_log (wallet_id, rule, key, fired_at, params) "
        "VALUES ('live', '${rule.name}', '', '2026-10-05', '{}')",
      );
    }
    expect(await repo.momentsShown(), {
      CompanionRule.firstLoss,
      CompanionRule.fxSwing,
    });
  });
}
