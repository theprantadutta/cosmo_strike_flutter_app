import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database/app_database.dart';
import '../../models/achievement.dart' as model;
import '../../utils/logger.dart';
import '../offline_cache_service.dart';

/// One-time replacement of the pre-3.2 achievement catalog (114 rows
/// inherited from the old catalog — `first_bite`, `foodie_*`, `anaconda`…)
/// with the 72 `cmd_*` commendations.
///
/// For every legacy row in [kLegacyAchievementMap] whose condition is
/// equivalent to (or stricter than) a new commendation, the new row
/// inherits:
/// - `isUnlocked` — OR across every legacy row mapped onto it;
/// - `currentProgress` — max, capped at the new target (= target when
///   unlocked);
/// - `unlockedAt` — earliest;
/// - `rewardClaimed` — true if any UNLOCKED legacy row mapped onto it had
///   its reward claimed, so a reward that was already paid is not paid
///   again under the new id.
/// Legacy rows without an equivalent are dropped. Lifetime-stat
/// commendations that weren't mapped still catch up on the next
/// `AchievementService.evaluateStanding()` from GameStatistics.
///
/// Idempotent: guarded by a SharedPreferences flag; re-running on migrated
/// data is a no-op (no legacy rows left, merges are monotonic). Migrated
/// rows are enqueued for sync so the backend learns the new ids even if its
/// own data migration hasn't run for this user.
const String kLegacyAchievementMigrationFlag =
    'rebrand_v32_achievements_migrated';

/// Legacy achievement id -> new commendation id. Must stay identical to the
/// server remap in `cosmo-strike-dotnet-api/docs/rebrand/sql/achievements.sql`.
const Map<String, String> kLegacyAchievementMap = {
  'half_grand': 'cmd_score_5k',
  'score_sniper': 'cmd_score_5k',
  'classic_5000': 'cmd_score_5k',
  'zen_master': 'cmd_score_5k',
  'smorgasbord': 'cmd_score_5k',
  'hard_mode_god': 'cmd_score_5k',
  'five_digit_club': 'cmd_score_25k',
  'score_tycoon': 'cmd_score_25k',
  'score_god': 'cmd_score_100k',
  'point_hoarder': 'cmd_career_100k',
  'half_million_club': 'cmd_career_100k',
  'point_millionaire': 'cmd_career_1m',
  'decamillionaire': 'cmd_career_10m',
  'first_bite': 'cmd_games_1',
  'first_game': 'cmd_games_1',
  'regular_player': 'cmd_games_10',
  'dedicated_player': 'cmd_games_50',
  'ship_enthusiast': 'cmd_games_50',
  'ship_addict': 'cmd_games_250',
  'ship_veteran': 'cmd_games_250',
  'ship_legend': 'cmd_games_250',
  'endurance': 'cmd_time_120',
  'marathon': 'cmd_time_300',
  'iron_will': 'cmd_time_600',
  'eternal_ship': 'cmd_time_600',
  'time_lord': 'cmd_time_600',
  'quick_player': 'cmd_hours_1',
  'engaged_player': 'cmd_hours_10',
  'hardcore_player': 'cmd_hours_50',
  'ship_obsessed': 'cmd_hours_50',
  'touch_grass': 'cmd_hours_50',
  'famished': 'cmd_run_kills_50',
  'ravenous': 'cmd_run_kills_50',
  'insatiable': 'cmd_run_kills_150',
  'black_hole_stomach': 'cmd_run_kills_150',
  'first_bite_snack': 'cmd_first_contact',
  'hungry_ship': 'cmd_first_contact',
  'foodie_apprentice': 'cmd_first_contact',
  'foodie_pro': 'cmd_hostiles_1k',
  'foodie_master': 'cmd_hostiles_10k',
  'foodie_god': 'cmd_hostiles_50k',
  'combo_master': 'cmd_chain_10',
  'combo_pro': 'cmd_chain_10',
  'combo_god': 'cmd_chain_30',
  'combo_legend': 'cmd_chain_75',
  'perfectionist': 'cmd_perfect_1',
  'untouchable_5': 'cmd_perfect_1',
  'untouchable_20': 'cmd_perfect_10',
  'untouchable_50': 'cmd_perfect_50',
  'daily_three': 'cmd_streak_3',
  'week_warrior': 'cmd_streak_7',
  'classic_initiate': 'cmd_mode_sortie',
  'classic_veteran': 'cmd_mode_sortie',
  'zen_initiate': 'cmd_mode_cruise',
  'survival_pro': 'cmd_mode_holdout',
  'beat_the_clock': 'cmd_mode_blitz',
  'night_owl': 'cmd_night_ops',
};

Future<void> migrateLegacyAchievements(AppDatabase db) async {
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    AppLogger.warning('LegacyAchievementMigration: prefs unavailable: $e');
    return;
  }
  if (prefs.getBool(kLegacyAchievementMigrationFlag) ?? false) return;

  final catalog = {
    for (final a in model.Achievement.getDefaultAchievements()) a.id: a,
  };

  var migrated = 0;
  var dropped = 0;
  try {
    await db.transaction(() async {
      final rows = await db.select(db.achievements).get();
      final byId = {for (final r in rows) r.id: r};
      final legacy = rows.where((r) => !catalog.containsKey(r.id)).toList();
      if (legacy.isEmpty) return;

      // Fold legacy rows into per-commendation aggregates.
      final merged = <String, _Merge>{};
      for (final row in legacy) {
        final newId = kLegacyAchievementMap[row.id];
        final target = newId == null ? null : catalog[newId];
        if (newId == null || target == null) continue;
        merged.putIfAbsent(newId, () => _Merge(target.targetValue)).absorb(row);
      }

      for (final entry in merged.entries) {
        final def = catalog[entry.key]!;
        final m = entry.value;
        final existing = byId[entry.key];
        if (existing != null) m.absorb(existing);
        if (!m.changes(existing)) continue;
        await db.gameDao.upsertAchievement(
          AchievementsCompanion(
            id: Value(def.id),
            name: Value(def.title),
            description: Value(def.description),
            category: Value(def.type.name),
            currentProgress: Value(m.progress),
            targetProgress: Value(def.targetValue),
            isUnlocked: Value(m.unlocked),
            unlockedAt: Value(m.unlockedAt),
            rewardCoins: Value(def.coinReward),
            rewardClaimed: Value(m.claimed),
            iconName: Value(def.icon.codePoint.toString()),
            isSecret: const Value(false),
            lastUpdated: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );
        migrated++;
      }

      dropped = await (db.delete(
        db.achievements,
      )..where((t) => t.id.isNotIn(catalog.keys))).go();
    });
  } catch (e, st) {
    // Leave the flag unset so the next launch retries.
    AppLogger.error('LegacyAchievementMigration failed', e, st);
    return;
  }

  // The service's progress cache is keyed by achievement id; drop it so
  // the next load reads the migrated Drift rows.
  try {
    await OfflineCacheService().invalidateCache('user_achievements');
  } catch (_) {}

  await prefs.setBool(kLegacyAchievementMigrationFlag, true);
  AppLogger.info(
    'LegacyAchievementMigration: $migrated commendations carried over, '
    '$dropped legacy rows removed',
  );
}

class _Merge {
  _Merge(this.target);

  final int target;
  bool unlocked = false;
  bool claimed = false;
  int progress = 0;
  DateTime? unlockedAt;

  void absorb(Achievement row) {
    if (row.isUnlocked) {
      unlocked = true;
      claimed = claimed || row.rewardClaimed;
      final at = row.unlockedAt;
      if (at != null && (unlockedAt == null || at.isBefore(unlockedAt!))) {
        unlockedAt = at;
      }
    }
    final p = row.currentProgress.clamp(0, target);
    if (p > progress) progress = p;
    if (unlocked) progress = target;
  }

  /// Whether writing this aggregate would change [existing].
  bool changes(Achievement? existing) {
    if (existing == null) return unlocked || progress > 0;
    return existing.isUnlocked != unlocked ||
        existing.currentProgress != progress ||
        existing.rewardClaimed != claimed ||
        existing.unlockedAt != unlockedAt;
  }
}
