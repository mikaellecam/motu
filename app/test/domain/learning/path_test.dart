import 'package:finance_companion/domain/learning/node.dart';
import 'package:finance_companion/domain/learning/path.dart';
import 'package:finance_companion/domain/learning/profile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'learning_test.dart' show island, profile;

// The island: 1 predict, 2 toy, 3 mission, 4 predict, 5 decision, 6 sort,
// 7 toy, 8 mission, 9 predict, 10 puzzle, 11 mission, 12 checkpoint.

/// The states in path order, one letter each: d(one), c(urrent), o(pen),
/// l(ocked).
String states(Profile? p, Set<String> completed) =>
    pathStates(p, island, completed).map((s) => s.name[0]).join();

Set<String> done(List<int> numbers) => {
  for (final n in numbers) island[n - 1].id,
};

void main() {
  test('a first visit: node 1 to play, the rest locked', () {
    expect(states(profile(), {}), 'clllllllllll');
  });

  test('done nodes, then the current one, then locked', () {
    expect(states(profile(), done([1])), 'dcllllllllll');
  });

  test('a pending mission does not lock what follows (decided 2026-10-11)', () {
    // Node 3 is a mission: current, and node 4 opens; node 5 waits for 4.
    expect(states(profile(), done([1, 2])), 'ddcollllllll');
    // Missions 3, 8 and 11 pending, every lesson up to 10 done: 12 opens.
    expect(states(profile(), done([1, 2, 4, 5, 6, 7, 9, 10])), 'ddcddddoddoo');
  });

  test('nodes skipped at onboarding stay open (decided 2026-10-11)', () {
    // « J'investis déjà » starts at node 4.
    final investing = profile(knowledge: Knowledge.alreadyInvesting);
    expect(states(investing, {}), 'ooocllllllll');
    expect(states(investing, done([2, 4])), 'ododclllllll');
  });

  test('Livret savings put node 1 first, then the starting node', () {
    // « Ce qu'est un ETF » starts at node 3, a mission: node 4 is open too.
    final p = profile(knowledge: Knowledge.etfs, savings: Savings.livret);
    expect(states(p, {}), 'cooollllllll');
    expect(states(p, done([1])), 'docollllllll');
  });

  test('everything done: no current node', () {
    final all = done([for (var i = 1; i <= 12; i++) i]);
    expect(states(profile(), all), 'dddddddddddd');
    expect(currentNode(profile(), island, all), isNull);
  });

  test('before the questionnaire: the path from node 1', () {
    expect(states(null, done([1])), 'dcllllllllll');
  });

  test('an empty path has no state', () {
    expect(pathStates(profile(), const <IslandNode>[], const {}), isEmpty);
    expect(currentNode(profile(), const <IslandNode>[], const {}), isNull);
  });

  test('the current node follows the next-step order', () {
    expect(currentNode(profile(), island, done([1]))!.id, 'ae.fees-toy');
    expect(
      currentNode(
        profile(knowledge: Knowledge.alreadyInvesting),
        island,
        done([for (var i = 4; i <= 12; i++) i]),
      )!.id,
      'ae.livret-vs-etf',
      reason: 'the skipped nodes come last',
    );
  });
}
