/// The five onboarding answers (BRIEF §4.1). They choose a starting point and
/// thresholds, never assets to buy.
final class Profile {
  const Profile({
    required this.goal,
    required this.dropReaction,
    required this.knowledge,
    required this.savings,
    required this.weeklyTime,
  });

  /// Q1 « Pourquoi veux-tu investir ? »
  final Goal goal;

  /// Q2 « Ton portefeuille perd 20 % en un mois. Tu fais quoi ? »
  final DropReaction dropReaction;

  /// Q3 « Tu sais déjà… »
  final Knowledge knowledge;

  /// Q4 « Où est ton épargne aujourd'hui ? »
  final Savings savings;

  /// Q5 « Combien de temps par semaine ? »
  final WeeklyTime weeklyTime;
}

enum Goal { under3Years, from3To8Years, longTerm, discovering }

enum DropReaction { sellAll, wait, buyMore, dontKnow }

enum Knowledge { nothing, stocks, etfs, alreadyInvesting }

enum Savings { livret, currentAccount, invested, none }

enum WeeklyTime { five, fifteen, thirtyPlus }
