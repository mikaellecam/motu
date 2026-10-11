import 'package:finance_companion/data/repositories/glossary_repository.dart';
import 'package:finance_companion/domain/companion/rules.dart';

/// Discoveries in memory: [discovered] terms, then what [discover] and
/// [passQuiz] record.
class FakeGlossary implements GlossaryRepository {
  FakeGlossary({Set<String> discovered = const {}})
    : states = {
        for (final id in discovered)
          id: TermProgress(DateTime.utc(2026, 10, 1), quizPassed: false),
      };

  final Map<String, TermProgress> states;
  final opened = <String>[];
  final passed = <String>[];

  @override
  Stream<Map<String, TermProgress>> watch() => Stream.value(states);

  @override
  Future<bool> discover(String termId, DateTime at) async {
    opened.add(termId);
    if (states.containsKey(termId)) return false;
    states[termId] = TermProgress(at, quizPassed: false);
    return true;
  }

  @override
  Future<void> passQuiz(String termId) async => passed.add(termId);

  @override
  Future<Set<CompanionRule>> momentsShown() async => const {};
}
