import 'dart:math';

import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';

/// Client-side Daily Directives for pilots without a backend account.
///
/// The backend generates the day's catalog (Hangfire job, one directive per
/// difficulty) and serves it only to authenticated users, so the silent local
/// guest every install starts as never received any. This mirrors the
/// backend's template pool and picks one directive per difficulty, seeded by
/// the LOCAL calendar day so the set is stable across launches and rolls over
/// at local midnight (matching the hub's "RESETS IN" countdown).
///
/// Ids are prefixed [idPrefix] so the service can tell a local set from a
/// backend one: once the pilot signs in, the backend catalog replaces it.
/// The backend's claim mirror accepts any challenge id, so a local set's
/// progress/claims still push fine after sign-in.
class LocalDirectives {
  LocalDirectives._();

  static const String idPrefix = 'local_';

  static bool isLocalId(String id) => id.startsWith(idPrefix);

  /// Keep in sync with `DailyChallengeJobService.ChallengeTemplates`
  /// (cosmo-strike-dotnet-api) so guests and signed-in pilots see the same
  /// kind of orders and rewards.
  static const List<_Template> _templates = [
    // Score
    _Template(ChallengeType.score, ChallengeDifficulty.easy, 'Rookie Pilot',
        'Score 200 points in a single run', 200, 8, 20),
    _Template(ChallengeType.score, ChallengeDifficulty.medium, 'Ace Gunner',
        'Score 500 points in a single run', 500, 15, 35),
    _Template(ChallengeType.score, ChallengeDifficulty.hard, 'Score Commander',
        'Score 1,000 points in a single run', 1000, 30, 60),
    // Kills
    _Template(ChallengeType.enemiesKilled, ChallengeDifficulty.easy,
        'Trigger Warmup', 'Destroy 15 hostiles today', 15, 8, 20),
    _Template(ChallengeType.enemiesKilled, ChallengeDifficulty.medium,
        'Wave Breaker', 'Destroy 30 hostiles today', 30, 15, 35),
    _Template(ChallengeType.enemiesKilled, ChallengeDifficulty.hard,
        'Fleet Shredder', 'Destroy 50 hostiles today', 50, 30, 60),
    // Endurance
    _Template(ChallengeType.survival, ChallengeDifficulty.easy, 'Hold the Line',
        'Stay in the fight for 60 seconds in a single run', 60, 8, 20),
    _Template(ChallengeType.survival, ChallengeDifficulty.medium, 'Dodge Ace',
        'Stay in the fight for 120 seconds in a single run', 120, 15, 35),
    _Template(ChallengeType.survival, ChallengeDifficulty.hard, 'Untouchable',
        'Stay in the fight for 180 seconds in a single run', 180, 30, 60),
    // Sortie count
    _Template(ChallengeType.gamesPlayed, ChallengeDifficulty.easy, 'On Patrol',
        'Fly 2 sorties today', 2, 8, 20),
    _Template(ChallengeType.gamesPlayed, ChallengeDifficulty.medium,
        'Dedicated', 'Fly 5 sorties today', 5, 15, 35),
    _Template(ChallengeType.gamesPlayed, ChallengeDifficulty.hard,
        'Combat Tour', 'Fly 10 sorties today', 10, 30, 60),
    // Modes
    _Template(ChallengeType.gameMode, ChallengeDifficulty.easy,
        'Standard Deployment', 'Fly 1 run in Sortie mode', 1, 8, 20, 'sortie'),
    _Template(ChallengeType.gameMode, ChallengeDifficulty.medium,
        'Pattern Study', 'Fly 2 runs in Cruise mode', 2, 15, 35, 'cruise'),
    _Template(ChallengeType.gameMode, ChallengeDifficulty.hard, 'Redline Run',
        'Fly 3 runs in Afterburn mode', 3, 30, 60, 'afterburn'),
  ];

  static String _dayKey(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// The directives for [day]'s local calendar date: one easy, one medium,
  /// one hard, deterministic for that date.
  static List<DailyChallenge> forDay(DateTime day) {
    final key = _dayKey(day);
    final rng = Random(day.year * 10000 + day.month * 100 + day.day);
    final out = <DailyChallenge>[];
    for (final difficulty in ChallengeDifficulty.values) {
      final pool =
          _templates.where((t) => t.difficulty == difficulty).toList();
      final t = pool[rng.nextInt(pool.length)];
      out.add(DailyChallenge(
        id: '$idPrefix${key}_${difficulty.name}',
        title: t.title,
        description: t.description,
        type: t.type,
        difficulty: difficulty,
        targetValue: t.target,
        coinReward: t.coins,
        xpReward: t.xp,
        requiredGameMode: t.mode,
      ));
    }
    return out;
  }
}

class _Template {
  const _Template(this.type, this.difficulty, this.title, this.description,
      this.target, this.coins, this.xp,
      [this.mode]);
  final ChallengeType type;
  final ChallengeDifficulty difficulty;
  final String title;
  final String description;
  final int target;
  final int coins;
  final int xp;
  final String? mode;
}
