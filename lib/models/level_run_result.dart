/// Per-level outcome of a single campaign run. The Flame game emits one of
/// these for every level the run touched (cleared or died on); the
/// StageProgressDao merges them into the persistent per-stage bests.
class LevelRunResult {
  /// 1-based campaign level number.
  final int stageId;

  /// True if the level's boss was defeated this run.
  final bool cleared;

  /// Score earned within this level (not the run's cumulative score).
  final int score;

  /// Seconds spent inside this level.
  final int timeSeconds;

  /// Furthest wave reached within this level.
  final int waveReached;

  /// True if the player took zero damage across this level (only
  /// meaningful when [cleared] is true).
  final bool noHit;

  const LevelRunResult({
    required this.stageId,
    required this.cleared,
    required this.score,
    required this.timeSeconds,
    required this.waveReached,
    required this.noHit,
  });

  @override
  String toString() =>
      'LevelRunResult(L$stageId cleared=$cleared score=$score '
      'time=${timeSeconds}s wave=$waveReached noHit=$noHit)';
}

/// What changed in persistent stage progress after merging one
/// [LevelRunResult] — drives end-of-run reward bonuses and the
/// "LEVEL N+1 UNLOCKED" / star-gain flourishes on the overlays.
class StageClearOutcome {
  final int stageId;
  final bool firstClear;
  final int starsBefore;
  final int starsAfter;
  final bool unlockedNextStage;

  const StageClearOutcome({
    required this.stageId,
    required this.firstClear,
    required this.starsBefore,
    required this.starsAfter,
    required this.unlockedNextStage,
  });

  int get starsGained =>
      starsAfter > starsBefore ? starsAfter - starsBefore : 0;
}
