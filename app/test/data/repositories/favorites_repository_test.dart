import 'package:drift/native.dart';
import 'package:finance_companion/data/local/database.dart';
import 'package:finance_companion/data/repositories/favorites_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starring toggles, and the stream follows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final favorites = FavoritesRepository(db);
    final at = DateTime.utc(2026, 10, 9);

    expect(await favorites.watch().first, isEmpty);
    final seen = <Set<String>>[];
    final sub = favorites.watch().listen(seen.add);
    addTearDown(sub.cancel);

    expect(await favorites.toggle('apple', at), isTrue);
    expect(await favorites.toggle('asml', at), isTrue);
    expect(await favorites.toggle('apple', at), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen.last, {'asml'});
  });
}
