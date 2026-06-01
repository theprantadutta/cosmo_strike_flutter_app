/// Lifetime player-level progression curve — the single source of truth for
/// how total XP maps to a player level. Distinct from the battle-pass season
/// curve (see [BattlePassSeason]): player level is lifetime and never resets.
///
/// Escalating cost: leveling from `level` to `level + 1` costs
/// `500 + (level - 1) * 350` XP, so the per-level cost grows steadily
/// (Lvl 1→2: 500, Lvl 2→3: 850, Lvl 9→10: 3300). Tuned so a level is
/// "earned" — a good game is ~100 XP, so early levels take several games
/// and it ramps from there.
///
/// IMPORTANT: the backend mirrors this exact formula in `PlayerLevel.cs`.
/// Any change here must be applied there too, or the synced level the
/// dashboard shows will diverge from what the app shows.
library;

class PlayerLevel {
  PlayerLevel._();

  /// First real level. XP starts at 0 on level 1.
  static const int minLevel = 1;

  static const int _baseCost = 500;
  static const int _costStep = 350;

  /// XP required to advance FROM [level] to [level] + 1.
  static int costForLevel(int level) {
    final l = level < minLevel ? minLevel : level;
    return _baseCost + (l - minLevel) * _costStep;
  }

  /// Cumulative XP required to *reach* [level] from level 1.
  /// `totalXpToReachLevel(1) == 0`.
  static int totalXpToReachLevel(int level) {
    if (level <= minLevel) return 0;
    // Sum of an arithmetic series of costForLevel(1..level-1).
    final n = level - minLevel; // number of level-ups
    final firstCost = costForLevel(minLevel);
    final lastCost = costForLevel(level - 1);
    return n * (firstCost + lastCost) ~/ 2;
  }

  /// The level a player with [totalXp] lifetime XP has reached.
  static int levelForXp(int totalXp) {
    if (totalXp <= 0) return minLevel;
    var level = minLevel;
    var remaining = totalXp;
    // Cheap forward walk — costs grow, so this converges quickly.
    while (remaining >= costForLevel(level)) {
      remaining -= costForLevel(level);
      level++;
    }
    return level;
  }

  /// XP accumulated *into* the current level (i.e. progress toward the next).
  static int xpIntoLevel(int totalXp) {
    final level = levelForXp(totalXp);
    return totalXp - totalXpToReachLevel(level);
  }

  /// XP required to advance from the current level to the next.
  static int xpForNextLevel(int totalXp) => costForLevel(levelForXp(totalXp));
}

/// Immutable snapshot of a player's lifetime progression. [totalXp] is the
/// source of truth; [level] is derived (and stored/synced for convenience).
class PlayerProgress {
  final int totalXp;
  final int level;

  const PlayerProgress({required this.totalXp, required this.level});

  /// Build from a raw XP total, deriving the level from the curve.
  factory PlayerProgress.fromXp(int totalXp) {
    final xp = totalXp < 0 ? 0 : totalXp;
    return PlayerProgress(totalXp: xp, level: PlayerLevel.levelForXp(xp));
  }

  static const PlayerProgress initial = PlayerProgress(totalXp: 0, level: 1);

  /// XP earned into the current level.
  int get xpIntoLevel => PlayerLevel.xpIntoLevel(totalXp);

  /// XP needed to clear the current level.
  int get xpForNextLevel => PlayerLevel.xpForNextLevel(totalXp);

  /// Fractional progress 0..1 toward the next level (for progress bars).
  double get levelProgress {
    final needed = xpForNextLevel;
    if (needed <= 0) return 0;
    return (xpIntoLevel / needed).clamp(0.0, 1.0);
  }

  PlayerProgress copyWith({int? totalXp, int? level}) => PlayerProgress(
        totalXp: totalXp ?? this.totalXp,
        level: level ?? this.level,
      );
}
