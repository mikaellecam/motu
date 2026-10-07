/// Exactly one live wallet (today's prices), any number of trips (BRIEF §4.5).
enum WalletKind { live, trip }

enum WalletStatus {
  /// Running.
  active,

  /// A stop condition fired; waiting for the user's decision.
  stopped,

  /// Trip over: summary available.
  finished,
}
