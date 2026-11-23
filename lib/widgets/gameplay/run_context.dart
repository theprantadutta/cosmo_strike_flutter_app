import '../../utils/constants.dart' show GameMode;

/// Pure run-context rules shared by the gameplay screen and its overlays,
/// kept free of Flutter/Flame so they are unit-testable.
abstract final class RunContext {
  /// The run's name for every in-run header (level intro, pause, level
  /// clear, game over): a seeded Daily Run and a Sector Cup run are named
  /// as such rather than by the mode they happen to play under.
  static String label({
    required GameMode mode,
    int? dailySeed,
    String? tournamentId,
  }) {
    if (dailySeed != null) return 'Daily Run';
    if (tournamentId != null) return 'Sector Cup';
    return mode.name;
  }

  /// Whether this run opens with the first-run tutorial beats: a Level-1
  /// start while the tutorial is still pending, and never on a competitive
  /// run (Daily Run seed or Sector Cup) — those must fly identically for
  /// everyone on the leaderboard.
  static bool runsTutorial({
    required int startLevel,
    required bool tutorialPending,
    int? dailySeed,
    String? tournamentId,
  }) =>
      startLevel == 1 &&
      tutorialPending &&
      dailySeed == null &&
      tournamentId == null;

  /// Whether losing the last ship may offer the continue. Never during the
  /// onboarding runs ([onboardingRunNumber] is set for runs 1-3): a new
  /// pilot's first deaths go straight to game over so Retry is one tap
  /// away (more day-0 runs is what predicts a day-1 return).
  static bool allowsRevive({int? onboardingRunNumber}) =>
      onboardingRunNumber == null;
}
