import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Wire/storage category of a commendation. The enum names are persisted
/// (Drift `achievements.category`) and mirror the backend
/// `AchievementCategory` (Score/Games/Survival/Special/Streak/General), so
/// they stay as-is; the player-facing grouping is [CommendationCategory].
enum AchievementType { score, games, streak, survival, special, general }

/// Rarity, mapped 1:1 to the backend `AchievementTier`
/// (Bronze/Silver/Gold/Platinum/Diamond). Player-facing names come from
/// [Achievement.rarityName]: Service / Bronze Star / Silver Star /
/// Gold Star / Nova.
enum AchievementRarity { common, rare, epic, legendary, diamond }

/// Player-facing commendation groups (UI only — never persisted).
enum CommendationCategory {
  combat,
  precision,
  campaign,
  endurance,
  service,
  modes,
  feats;

  String get label => switch (this) {
    CommendationCategory.combat => 'Combat',
    CommendationCategory.precision => 'Precision',
    CommendationCategory.campaign => 'Campaign',
    CommendationCategory.endurance => 'Endurance',
    CommendationCategory.service => 'Service',
    CommendationCategory.modes => 'Modes',
    CommendationCategory.feats => 'Feats',
  };
}

/// The tracked stat a commendation compares against its [Achievement.targetValue].
/// `run*` metrics are single-run bests (progress = best run so far); the
/// rest are lifetime / standing values. Evaluated by
/// `AchievementService.evaluateRun` / `evaluateStanding`.
enum CommendationMetric {
  // Single run (from the finished run's GameResult).
  runScore,
  runKills,
  runBosses,
  runChain,
  runGrazes,
  runWipes,
  runDuration,
  runLevelsCleared,
  runUpgrades,
  flawlessCampaign,
  nightOps,

  // Lifetime (GameStatistics after the run is folded in).
  totalScore,
  totalKills,
  totalBosses,
  totalMissiles,
  totalGrazes,
  totalOverdrives,
  totalWipes,
  totalGames,
  totalPlayTime,
  noHitClears,
  victories,
  revives,
  dailyRuns,
  cupRuns,
  dayStreak,
  gamesInMode,
  distinctModes,

  // Standing state (Drift campaign progress / Hangar).
  campaignLevels,
  campaignStars,
  hangarLevels;

  bool get isPerRun => index <= CommendationMetric.nightOps.index;
}

/// Everything a finished run contributes to commendations that isn't
/// already folded into lifetime GameStatistics.
class RunCommendationStats {
  const RunCommendationStats({
    required this.gameMode,
    required this.score,
    required this.kills,
    required this.bosses,
    required this.maxChain,
    required this.grazes,
    required this.formationWipes,
    required this.durationSeconds,
    required this.levelsCleared,
    required this.upgradesDrafted,
    required this.flawlessCampaign,
    required this.endedAt,
  });

  /// Mode wire name (`sortie`, `knifeEdge`…). Legacy spellings are accepted.
  final String gameMode;
  final int score;
  final int kills;
  final int bosses;
  final int maxChain;
  final int grazes;
  final int formationWipes;
  final int durationSeconds;
  final int levelsCleared;
  final int upgradesDrafted;

  /// All 12 campaign levels cleared in this run without taking a hit.
  final bool flawlessCampaign;
  final DateTime endedAt;
}

/// Length of the consecutive-day streak ending today (or yesterday, so a
/// streak isn't shown as broken before today's first run). Reads the
/// GameStatistics `dailyPlayTime` map and accepts both zero-padded
/// (`2026-01-05`) and legacy unpadded (`2026-1-5`) day keys.
int consecutiveDayStreak(Map<String, int> dailyPlayTime, {DateTime? now}) {
  final played = <DateTime>{};
  for (final e in dailyPlayTime.entries) {
    if (e.value <= 0) continue;
    final parts = e.key.split('-');
    if (parts.length != 3) continue;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) continue;
    played.add(DateTime(y, m, d));
  }
  if (played.isEmpty) return 0;
  final today = now ?? DateTime.now();
  var day = DateTime(today.year, today.month, today.day);
  if (!played.contains(day)) {
    day = DateTime(day.year, day.month, day.day - 1);
  }
  var streak = 0;
  while (played.contains(day)) {
    streak++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

class Achievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final AchievementType type;
  final CommendationCategory category;
  final CommendationMetric metric;
  final AchievementRarity rarity;
  final int targetValue;
  final int points;
  final bool isUnlocked;
  final DateTime? unlockedAt;
  final int currentProgress;

  /// True once the reward (credits) for this unlock has been granted.
  /// Independent of [isUnlocked]: a commendation can be unlocked locally
  /// but unclaimed until the reward credit lands.
  final bool rewardClaimed;

  /// Backend-side XP reward. Defaults match the seeded backend catalog
  /// (SeedAchievementsCommandHandler); keep both lists identical.
  final int xpReward;

  /// Credit reward (internal name stays `coin`).
  final int coinReward;

  /// Mode filter as a GameMode wire name (`sortie`, `knifeEdge`…). When set,
  /// `run*` metrics only count runs flown in this mode and
  /// [CommendationMetric.gamesInMode] counts this mode's runs. Mirrors the
  /// backend `GameModeFilter`; compared case/legacy-insensitively via
  /// `GameMode.tryFromWire`.
  final String? gameModeFilter;

  /// Difficulty filter (unused by the current catalog; kept for the wire).
  final String? difficultyFilter;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.type,
    this.category = CommendationCategory.feats,
    this.metric = CommendationMetric.totalGames,
    required this.rarity,
    required this.targetValue,
    required this.points,
    this.isUnlocked = false,
    this.unlockedAt,
    this.currentProgress = 0,
    this.rewardClaimed = false,
    this.xpReward = 0,
    this.coinReward = 0,
    this.gameModeFilter,
    this.difficultyFilter,
  });

  Achievement copyWith({
    String? id,
    String? title,
    String? description,
    IconData? icon,
    AchievementType? type,
    CommendationCategory? category,
    CommendationMetric? metric,
    AchievementRarity? rarity,
    int? targetValue,
    int? points,
    bool? isUnlocked,
    DateTime? unlockedAt,
    int? currentProgress,
    bool? rewardClaimed,
    int? xpReward,
    int? coinReward,
    String? gameModeFilter,
    String? difficultyFilter,
  }) {
    return Achievement(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      type: type ?? this.type,
      category: category ?? this.category,
      metric: metric ?? this.metric,
      rarity: rarity ?? this.rarity,
      targetValue: targetValue ?? this.targetValue,
      points: points ?? this.points,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      unlockedAt: unlockedAt ?? this.unlockedAt,
      currentProgress: currentProgress ?? this.currentProgress,
      rewardClaimed: rewardClaimed ?? this.rewardClaimed,
      xpReward: xpReward ?? this.xpReward,
      coinReward: coinReward ?? this.coinReward,
      gameModeFilter: gameModeFilter ?? this.gameModeFilter,
      difficultyFilter: difficultyFilter ?? this.difficultyFilter,
    );
  }

  double get progressPercentage {
    if (targetValue == 0) return isUnlocked ? 1.0 : 0.0;
    return (currentProgress / targetValue).clamp(0.0, 1.0);
  }

  Color get rarityColor {
    switch (rarity) {
      case AchievementRarity.common:
        return const Color(0xFF9A9AA3);
      case AchievementRarity.rare:
        return const Color(0xFFD9A066);
      case AchievementRarity.epic:
        return const Color(0xFFC9D3E0);
      case AchievementRarity.legendary:
        return const Color(0xFFFFD58A);
      case AchievementRarity.diamond:
        return const Color(0xFF7CF5FF);
    }
  }

  String get rarityName {
    switch (rarity) {
      case AchievementRarity.common:
        return 'Service';
      case AchievementRarity.rare:
        return 'Bronze Star';
      case AchievementRarity.epic:
        return 'Silver Star';
      case AchievementRarity.legendary:
        return 'Gold Star';
      case AchievementRarity.diamond:
        return 'Nova';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type.name,
      'rarity': rarity.name,
      'targetValue': targetValue,
      'points': points,
      'isUnlocked': isUnlocked,
      'unlockedAt': unlockedAt?.toIso8601String(),
      'currentProgress': currentProgress,
      'rewardClaimed': rewardClaimed,
      'xpReward': xpReward,
      'coinReward': coinReward,
    };
  }

  /// Rebuilds a commendation from JSON. Catalog metadata (icon, category,
  /// metric, filters) always comes from [getDefaultAchievements] when the id
  /// is known — only progress fields are taken from the payload.
  factory Achievement.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    Achievement? catalog;
    for (final a in getDefaultAchievements()) {
      if (a.id == id) {
        catalog = a;
        break;
      }
    }
    final base =
        catalog ??
        Achievement(
          id: id,
          title: json['title'] ?? '',
          description: json['description'] ?? '',
          icon: Symbols.military_tech_rounded,
          type: AchievementType.values.firstWhere(
            (e) => e.name == json['type'],
            orElse: () => AchievementType.general,
          ),
          rarity: AchievementRarity.values.firstWhere(
            (e) => e.name == json['rarity'],
            orElse: () => AchievementRarity.common,
          ),
          targetValue: json['targetValue'] ?? 0,
          points: json['points'] ?? 0,
          xpReward: json['xpReward'] ?? 0,
          coinReward: json['coinReward'] ?? 0,
        );
    return base.copyWith(
      isUnlocked: json['isUnlocked'] ?? false,
      unlockedAt: json['unlockedAt'] != null
          ? DateTime.tryParse(json['unlockedAt'].toString())
          : null,
      currentProgress: json['currentProgress'] ?? 0,
      rewardClaimed: json['rewardClaimed'] ?? false,
    );
  }

  /// The 72 commendations. IDs, targets and rewards MUST match the backend
  /// seed (SeedAchievementsCommandHandler) exactly — the server
  /// auto-evaluates the Score/Time/kill/play-time/games rows from score
  /// submissions and accepts client unlocks for the rest by id.
  static List<Achievement> getDefaultAchievements() {
    return [
      // ---- Combat ----
      const Achievement(
        id: 'cmd_first_contact',
        title: 'First Contact',
        description: 'Destroy your first hostile.',
        icon: Symbols.my_location_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.totalKills,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 10,
        xpReward: 10,
        coinReward: 5,
      ),
      const Achievement(
        id: 'cmd_hostiles_1k',
        title: 'Line Breaker',
        description: 'Destroy 1,000 hostiles.',
        icon: Symbols.target_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.totalKills,
        rarity: AchievementRarity.rare,
        targetValue: 1000,
        points: 75,
        xpReward: 75,
        coinReward: 40,
      ),
      const Achievement(
        id: 'cmd_hostiles_10k',
        title: 'Fleet Breaker',
        description: 'Destroy 10,000 hostiles.',
        icon: Symbols.crisis_alert_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.totalKills,
        rarity: AchievementRarity.epic,
        targetValue: 10000,
        points: 175,
        xpReward: 175,
        coinReward: 90,
      ),
      const Achievement(
        id: 'cmd_hostiles_50k',
        title: 'Armada Breaker',
        description: 'Destroy 50,000 hostiles.',
        icon: Symbols.blur_on_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.totalKills,
        rarity: AchievementRarity.diamond,
        targetValue: 50000,
        points: 400,
        xpReward: 400,
        coinReward: 200,
      ),
      const Achievement(
        id: 'cmd_run_kills_50',
        title: 'Hot Barrel',
        description: 'Destroy 50 hostiles in a single run.',
        icon: Symbols.local_fire_department_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.runKills,
        rarity: AchievementRarity.common,
        targetValue: 50,
        points: 25,
        xpReward: 25,
        coinReward: 12,
      ),
      const Achievement(
        id: 'cmd_run_kills_150',
        title: 'Kill Box',
        description: 'Destroy 150 hostiles in a single run.',
        icon: Symbols.whatshot_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.runKills,
        rarity: AchievementRarity.epic,
        targetValue: 150,
        points: 100,
        xpReward: 100,
        coinReward: 50,
      ),
      const Achievement(
        id: 'cmd_boss_first',
        title: 'Giant Slayer',
        description: 'Bring down your first boss.',
        icon: Symbols.skull_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.totalBosses,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 25,
        xpReward: 25,
        coinReward: 12,
      ),
      const Achievement(
        id: 'cmd_boss_10',
        title: 'Capital Hunter',
        description: 'Bring down 10 bosses.',
        icon: Symbols.swords_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.totalBosses,
        rarity: AchievementRarity.rare,
        targetValue: 10,
        points: 75,
        xpReward: 75,
        coinReward: 40,
      ),
      const Achievement(
        id: 'cmd_boss_50',
        title: 'Dreadnought Breaker',
        description: 'Bring down 50 bosses.',
        icon: Symbols.military_tech_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.totalBosses,
        rarity: AchievementRarity.legendary,
        targetValue: 50,
        points: 250,
        xpReward: 250,
        coinReward: 125,
      ),
      const Achievement(
        id: 'cmd_run_bosses_3',
        title: 'Triple Takedown',
        description: 'Bring down 3 bosses in a single run.',
        icon: Symbols.destruction_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.runBosses,
        rarity: AchievementRarity.epic,
        targetValue: 3,
        points: 125,
        xpReward: 125,
        coinReward: 60,
      ),
      const Achievement(
        id: 'cmd_missile_500',
        title: 'Ordnance Officer',
        description: 'Fire 500 missiles.',
        icon: Symbols.rocket_rounded,
        type: AchievementType.special,
        category: CommendationCategory.combat,
        metric: CommendationMetric.totalMissiles,
        rarity: AchievementRarity.rare,
        targetValue: 500,
        points: 50,
        xpReward: 50,
        coinReward: 25,
      ),
      // ---- Precision ----
      const Achievement(
        id: 'cmd_chain_10',
        title: 'Chain Reaction',
        description: 'Build a 10-kill chain.',
        icon: Symbols.link_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.runChain,
        rarity: AchievementRarity.common,
        targetValue: 10,
        points: 20,
        xpReward: 20,
        coinReward: 10,
      ),
      const Achievement(
        id: 'cmd_chain_30',
        title: 'Rolling Thunder',
        description: 'Build a 30-kill chain.',
        icon: Symbols.bolt_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.runChain,
        rarity: AchievementRarity.rare,
        targetValue: 30,
        points: 50,
        xpReward: 50,
        coinReward: 25,
      ),
      const Achievement(
        id: 'cmd_chain_75',
        title: 'Unbroken',
        description: 'Build a 75-kill chain.',
        icon: Symbols.electric_bolt_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.runChain,
        rarity: AchievementRarity.epic,
        targetValue: 75,
        points: 125,
        xpReward: 125,
        coinReward: 60,
      ),
      const Achievement(
        id: 'cmd_chain_150',
        title: 'Endless Chain',
        description: 'Build a 150-kill chain.',
        icon: Symbols.flash_on_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.runChain,
        rarity: AchievementRarity.legendary,
        targetValue: 150,
        points: 250,
        xpReward: 250,
        coinReward: 125,
      ),
      const Achievement(
        id: 'cmd_graze_first',
        title: 'Close Shave',
        description: 'Graze an enemy shot.',
        icon: Symbols.air_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.totalGrazes,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 10,
        xpReward: 10,
        coinReward: 5,
      ),
      const Achievement(
        id: 'cmd_graze_1000',
        title: 'Paint Scraper',
        description: 'Graze 1,000 enemy shots.',
        icon: Symbols.motion_blur_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.totalGrazes,
        rarity: AchievementRarity.rare,
        targetValue: 1000,
        points: 75,
        xpReward: 75,
        coinReward: 40,
      ),
      const Achievement(
        id: 'cmd_graze_5000',
        title: 'Skin of Your Teeth',
        description: 'Graze 5,000 enemy shots.',
        icon: Symbols.cyclone_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.totalGrazes,
        rarity: AchievementRarity.epic,
        targetValue: 5000,
        points: 175,
        xpReward: 175,
        coinReward: 90,
      ),
      const Achievement(
        id: 'cmd_run_graze_60',
        title: 'Needle Threader',
        description: 'Graze 60 shots in a single run.',
        icon: Symbols.tornado_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.runGrazes,
        rarity: AchievementRarity.epic,
        targetValue: 60,
        points: 125,
        xpReward: 125,
        coinReward: 60,
      ),
      const Achievement(
        id: 'cmd_overdrive_first',
        title: 'Overdrive Online',
        description: 'Trigger Overdrive.',
        icon: Symbols.speed_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.totalOverdrives,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 15,
        xpReward: 15,
        coinReward: 8,
      ),
      const Achievement(
        id: 'cmd_overdrive_100',
        title: 'Redline Reactor',
        description: 'Trigger Overdrive 100 times.',
        icon: Symbols.all_out_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.totalOverdrives,
        rarity: AchievementRarity.rare,
        targetValue: 100,
        points: 75,
        xpReward: 75,
        coinReward: 40,
      ),
      const Achievement(
        id: 'cmd_wipe_first',
        title: 'Clean Sweep',
        description: 'Wipe out a full formation.',
        icon: Symbols.grid_view_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.totalWipes,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 15,
        xpReward: 15,
        coinReward: 8,
      ),
      const Achievement(
        id: 'cmd_wipe_250',
        title: 'Formation Breaker',
        description: 'Wipe out 250 formations.',
        icon: Symbols.scatter_plot_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.totalWipes,
        rarity: AchievementRarity.epic,
        targetValue: 250,
        points: 150,
        xpReward: 150,
        coinReward: 75,
      ),
      const Achievement(
        id: 'cmd_run_wipe_10',
        title: 'Total Coverage',
        description: 'Wipe out 10 formations in a single run.',
        icon: Symbols.grain_rounded,
        type: AchievementType.special,
        category: CommendationCategory.precision,
        metric: CommendationMetric.runWipes,
        rarity: AchievementRarity.rare,
        targetValue: 10,
        points: 60,
        xpReward: 60,
        coinReward: 30,
      ),
      // ---- Campaign ----
      const Achievement(
        id: 'cmd_level_1',
        title: 'Wheels Up',
        description: 'Clear your first campaign level.',
        icon: Symbols.flight_takeoff_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.campaignLevels,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 15,
        xpReward: 15,
        coinReward: 8,
      ),
      const Achievement(
        id: 'cmd_levels_3',
        title: 'Belt Secured',
        description: 'Clear 3 campaign levels.',
        icon: Symbols.flag_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.campaignLevels,
        rarity: AchievementRarity.common,
        targetValue: 3,
        points: 30,
        xpReward: 30,
        coinReward: 15,
      ),
      const Achievement(
        id: 'cmd_levels_6',
        title: 'Halfway Home',
        description: 'Clear 6 campaign levels.',
        icon: Symbols.explore_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.campaignLevels,
        rarity: AchievementRarity.rare,
        targetValue: 6,
        points: 75,
        xpReward: 75,
        coinReward: 40,
      ),
      const Achievement(
        id: 'cmd_levels_12',
        title: 'Campaign Complete',
        description: 'Clear all 12 campaign levels.',
        icon: Symbols.sports_score_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.campaignLevels,
        rarity: AchievementRarity.legendary,
        targetValue: 12,
        points: 250,
        xpReward: 250,
        coinReward: 125,
      ),
      const Achievement(
        id: 'cmd_stars_12',
        title: 'Decorated',
        description: 'Earn 12 campaign stars.',
        icon: Symbols.star_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.campaignStars,
        rarity: AchievementRarity.rare,
        targetValue: 12,
        points: 60,
        xpReward: 60,
        coinReward: 30,
      ),
      const Achievement(
        id: 'cmd_stars_24',
        title: 'Highly Decorated',
        description: 'Earn 24 campaign stars.',
        icon: Symbols.hotel_class_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.campaignStars,
        rarity: AchievementRarity.epic,
        targetValue: 24,
        points: 150,
        xpReward: 150,
        coinReward: 75,
      ),
      const Achievement(
        id: 'cmd_stars_36',
        title: 'Full Constellation',
        description: 'Earn all 36 campaign stars.',
        icon: Symbols.auto_awesome_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.campaignStars,
        rarity: AchievementRarity.diamond,
        targetValue: 36,
        points: 400,
        xpReward: 400,
        coinReward: 200,
      ),
      const Achievement(
        id: 'cmd_perfect_1',
        title: 'Untouched',
        description: 'Clear a level without taking a hit.',
        icon: Symbols.shield_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.noHitClears,
        rarity: AchievementRarity.rare,
        targetValue: 1,
        points: 50,
        xpReward: 50,
        coinReward: 25,
      ),
      const Achievement(
        id: 'cmd_perfect_10',
        title: 'Ghost Pilot',
        description: 'Clear 10 levels without taking a hit.',
        icon: Symbols.verified_user_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.noHitClears,
        rarity: AchievementRarity.epic,
        targetValue: 10,
        points: 125,
        xpReward: 125,
        coinReward: 60,
      ),
      const Achievement(
        id: 'cmd_perfect_50',
        title: 'Phantom',
        description: 'Clear 50 levels without taking a hit.',
        icon: Symbols.health_and_safety_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.noHitClears,
        rarity: AchievementRarity.legendary,
        targetValue: 50,
        points: 300,
        xpReward: 300,
        coinReward: 150,
      ),
      const Achievement(
        id: 'cmd_victory_1',
        title: 'Victory Roll',
        description: 'Bring down the campaign\'s final boss.',
        icon: Symbols.emoji_events_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.victories,
        rarity: AchievementRarity.epic,
        targetValue: 1,
        points: 150,
        xpReward: 150,
        coinReward: 75,
      ),
      const Achievement(
        id: 'cmd_victory_10',
        title: 'Hero of the Line',
        description: 'Bring down the campaign\'s final boss 10 times.',
        icon: Symbols.workspace_premium_rounded,
        type: AchievementType.special,
        category: CommendationCategory.campaign,
        metric: CommendationMetric.victories,
        rarity: AchievementRarity.diamond,
        targetValue: 10,
        points: 400,
        xpReward: 400,
        coinReward: 200,
      ),
      // ---- Endurance ----
      const Achievement(
        id: 'cmd_time_120',
        title: 'Holding Pattern',
        description: 'Stay in the fight for 2 minutes in a single run.',
        icon: Symbols.timer_rounded,
        type: AchievementType.survival,
        category: CommendationCategory.endurance,
        metric: CommendationMetric.runDuration,
        rarity: AchievementRarity.common,
        targetValue: 120,
        points: 15,
        xpReward: 15,
        coinReward: 8,
      ),
      const Achievement(
        id: 'cmd_time_300',
        title: 'Long Patrol',
        description: 'Stay in the fight for 5 minutes in a single run.',
        icon: Symbols.hourglass_top_rounded,
        type: AchievementType.survival,
        category: CommendationCategory.endurance,
        metric: CommendationMetric.runDuration,
        rarity: AchievementRarity.rare,
        targetValue: 300,
        points: 50,
        xpReward: 50,
        coinReward: 25,
      ),
      const Achievement(
        id: 'cmd_time_600',
        title: 'Iron Hull',
        description: 'Stay in the fight for 10 minutes in a single run.',
        icon: Symbols.avg_time_rounded,
        type: AchievementType.survival,
        category: CommendationCategory.endurance,
        metric: CommendationMetric.runDuration,
        rarity: AchievementRarity.epic,
        targetValue: 600,
        points: 125,
        xpReward: 125,
        coinReward: 60,
      ),
      const Achievement(
        id: 'cmd_hours_1',
        title: 'Flight Hours',
        description: 'Log 1 hour of flight time.',
        icon: Symbols.schedule_rounded,
        type: AchievementType.general,
        category: CommendationCategory.endurance,
        metric: CommendationMetric.totalPlayTime,
        rarity: AchievementRarity.common,
        targetValue: 3600,
        points: 25,
        xpReward: 25,
        coinReward: 10,
      ),
      const Achievement(
        id: 'cmd_hours_10',
        title: 'Seasoned Flyer',
        description: 'Log 10 hours of flight time.',
        icon: Symbols.history_rounded,
        type: AchievementType.general,
        category: CommendationCategory.endurance,
        metric: CommendationMetric.totalPlayTime,
        rarity: AchievementRarity.rare,
        targetValue: 36000,
        points: 75,
        xpReward: 75,
        coinReward: 40,
      ),
      const Achievement(
        id: 'cmd_hours_50',
        title: 'Long-Range Veteran',
        description: 'Log 50 hours of flight time.',
        icon: Symbols.all_inclusive_rounded,
        type: AchievementType.general,
        category: CommendationCategory.endurance,
        metric: CommendationMetric.totalPlayTime,
        rarity: AchievementRarity.legendary,
        targetValue: 180000,
        points: 250,
        xpReward: 250,
        coinReward: 125,
      ),
      const Achievement(
        id: 'cmd_revive_first',
        title: 'Second Wind',
        description: 'Revive and get back in the fight.',
        icon: Symbols.ecg_heart_rounded,
        type: AchievementType.special,
        category: CommendationCategory.endurance,
        metric: CommendationMetric.revives,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 15,
        xpReward: 15,
        coinReward: 8,
      ),
      // ---- Service ----
      const Achievement(
        id: 'cmd_games_1',
        title: 'Enlisted',
        description: 'Fly your first run.',
        icon: Symbols.rocket_launch_rounded,
        type: AchievementType.games,
        category: CommendationCategory.service,
        metric: CommendationMetric.totalGames,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 10,
        xpReward: 10,
        coinReward: 5,
      ),
      const Achievement(
        id: 'cmd_games_10',
        title: 'Squadron Regular',
        description: 'Fly 10 runs.',
        icon: Symbols.flight_rounded,
        type: AchievementType.games,
        category: CommendationCategory.service,
        metric: CommendationMetric.totalGames,
        rarity: AchievementRarity.common,
        targetValue: 10,
        points: 25,
        xpReward: 25,
        coinReward: 10,
      ),
      const Achievement(
        id: 'cmd_games_50',
        title: 'Line Pilot',
        description: 'Fly 50 runs.',
        icon: Symbols.badge_rounded,
        type: AchievementType.games,
        category: CommendationCategory.service,
        metric: CommendationMetric.totalGames,
        rarity: AchievementRarity.rare,
        targetValue: 50,
        points: 50,
        xpReward: 50,
        coinReward: 25,
      ),
      const Achievement(
        id: 'cmd_games_250',
        title: 'Veteran Pilot',
        description: 'Fly 250 runs.',
        icon: Symbols.trending_up_rounded,
        type: AchievementType.games,
        category: CommendationCategory.service,
        metric: CommendationMetric.totalGames,
        rarity: AchievementRarity.epic,
        targetValue: 250,
        points: 150,
        xpReward: 150,
        coinReward: 75,
      ),
      const Achievement(
        id: 'cmd_streak_3',
        title: 'On Station',
        description: 'Fly on 3 days in a row.',
        icon: Symbols.today_rounded,
        type: AchievementType.streak,
        category: CommendationCategory.service,
        metric: CommendationMetric.dayStreak,
        rarity: AchievementRarity.rare,
        targetValue: 3,
        points: 50,
        xpReward: 50,
        coinReward: 25,
      ),
      const Achievement(
        id: 'cmd_streak_7',
        title: 'Tour of Duty',
        description: 'Fly on 7 days in a row.',
        icon: Symbols.calendar_month_rounded,
        type: AchievementType.streak,
        category: CommendationCategory.service,
        metric: CommendationMetric.dayStreak,
        rarity: AchievementRarity.epic,
        targetValue: 7,
        points: 125,
        xpReward: 125,
        coinReward: 60,
      ),
      const Achievement(
        id: 'cmd_streak_30',
        title: 'Standing Watch',
        description: 'Fly on 30 days in a row.',
        icon: Symbols.event_repeat_rounded,
        type: AchievementType.streak,
        category: CommendationCategory.service,
        metric: CommendationMetric.dayStreak,
        rarity: AchievementRarity.legendary,
        targetValue: 30,
        points: 300,
        xpReward: 300,
        coinReward: 150,
      ),
      const Achievement(
        id: 'cmd_daily_1',
        title: 'Daily Orders',
        description: 'Fly a Daily Run.',
        icon: Symbols.radar_rounded,
        type: AchievementType.special,
        category: CommendationCategory.service,
        metric: CommendationMetric.dailyRuns,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 20,
        xpReward: 20,
        coinReward: 10,
      ),
      const Achievement(
        id: 'cmd_cup_1',
        title: 'Cup Contender',
        description: 'Fly a run in a Sector Cup.',
        icon: Symbols.trophy_rounded,
        type: AchievementType.special,
        category: CommendationCategory.service,
        metric: CommendationMetric.cupRuns,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 20,
        xpReward: 20,
        coinReward: 10,
      ),
      const Achievement(
        id: 'cmd_hangar_1',
        title: 'Retrofit',
        description: 'Install your first Hangar upgrade.',
        icon: Symbols.build_rounded,
        type: AchievementType.special,
        category: CommendationCategory.service,
        metric: CommendationMetric.hangarLevels,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 15,
        xpReward: 15,
        coinReward: 8,
      ),
      const Achievement(
        id: 'cmd_hangar_25',
        title: 'Fully Refit',
        description: 'Max out every Hangar upgrade.',
        icon: Symbols.precision_manufacturing_rounded,
        type: AchievementType.special,
        category: CommendationCategory.service,
        metric: CommendationMetric.hangarLevels,
        rarity: AchievementRarity.legendary,
        targetValue: 25,
        points: 250,
        xpReward: 250,
        coinReward: 125,
      ),
      // ---- Modes ----
      const Achievement(
        id: 'cmd_mode_sortie',
        title: 'Sortie Wings',
        description: 'Complete 10 Sortie runs.',
        icon: Symbols.rocket_launch_rounded,
        type: AchievementType.games,
        category: CommendationCategory.modes,
        metric: CommendationMetric.gamesInMode,
        rarity: AchievementRarity.common,
        targetValue: 10,
        points: 25,
        xpReward: 25,
        coinReward: 12,
        gameModeFilter: 'sortie',
      ),
      const Achievement(
        id: 'cmd_mode_cruise',
        title: 'Cruise Control',
        description: 'Complete 10 Cruise runs.',
        icon: Symbols.explore_rounded,
        type: AchievementType.games,
        category: CommendationCategory.modes,
        metric: CommendationMetric.gamesInMode,
        rarity: AchievementRarity.common,
        targetValue: 10,
        points: 25,
        xpReward: 25,
        coinReward: 12,
        gameModeFilter: 'cruise',
      ),
      const Achievement(
        id: 'cmd_mode_afterburn',
        title: 'Burn Rate',
        description: 'Stay in the fight for 3 minutes in Afterburn.',
        icon: Symbols.local_fire_department_rounded,
        type: AchievementType.survival,
        category: CommendationCategory.modes,
        metric: CommendationMetric.runDuration,
        rarity: AchievementRarity.rare,
        targetValue: 180,
        points: 60,
        xpReward: 60,
        coinReward: 30,
        gameModeFilter: 'afterburn',
      ),
      const Achievement(
        id: 'cmd_mode_swarm',
        title: 'Hold the Line',
        description: 'Destroy 150 hostiles in a single Swarm run.',
        icon: Symbols.hive_rounded,
        type: AchievementType.special,
        category: CommendationCategory.modes,
        metric: CommendationMetric.runKills,
        rarity: AchievementRarity.rare,
        targetValue: 150,
        points: 60,
        xpReward: 60,
        coinReward: 30,
        gameModeFilter: 'swarm',
      ),
      const Achievement(
        id: 'cmd_mode_holdout',
        title: 'Last Hull Standing',
        description: 'Stay in the fight for 5 minutes in Holdout.',
        icon: Symbols.shield_rounded,
        type: AchievementType.survival,
        category: CommendationCategory.modes,
        metric: CommendationMetric.runDuration,
        rarity: AchievementRarity.epic,
        targetValue: 300,
        points: 100,
        xpReward: 100,
        coinReward: 50,
        gameModeFilter: 'holdout',
      ),
      const Achievement(
        id: 'cmd_mode_blitz',
        title: 'Full Clock',
        description: 'Fly the full 3 minutes in Blitz.',
        icon: Symbols.timer_rounded,
        type: AchievementType.survival,
        category: CommendationCategory.modes,
        metric: CommendationMetric.runDuration,
        rarity: AchievementRarity.rare,
        targetValue: 180,
        points: 75,
        xpReward: 75,
        coinReward: 35,
        gameModeFilter: 'blitz',
      ),
      const Achievement(
        id: 'cmd_mode_overload',
        title: 'Controlled Chaos',
        description: 'Destroy 100 hostiles in a single Overload run.',
        icon: Symbols.bolt_rounded,
        type: AchievementType.special,
        category: CommendationCategory.modes,
        metric: CommendationMetric.runKills,
        rarity: AchievementRarity.rare,
        targetValue: 100,
        points: 60,
        xpReward: 60,
        coinReward: 30,
        gameModeFilter: 'overload',
      ),
      const Achievement(
        id: 'cmd_mode_knife_edge',
        title: 'Edge Walker',
        description: 'Clear a level in Knife Edge.',
        icon: Symbols.target_rounded,
        type: AchievementType.special,
        category: CommendationCategory.modes,
        metric: CommendationMetric.runLevelsCleared,
        rarity: AchievementRarity.epic,
        targetValue: 1,
        points: 125,
        xpReward: 125,
        coinReward: 60,
        gameModeFilter: 'knifeEdge',
      ),
      const Achievement(
        id: 'cmd_modes_all',
        title: 'Full Spectrum',
        description: 'Fly a run in all 8 modes.',
        icon: Symbols.filter_tilt_shift_rounded,
        type: AchievementType.general,
        category: CommendationCategory.modes,
        metric: CommendationMetric.distinctModes,
        rarity: AchievementRarity.rare,
        targetValue: 8,
        points: 75,
        xpReward: 75,
        coinReward: 40,
      ),
      // ---- Feats ----
      const Achievement(
        id: 'cmd_score_5k',
        title: 'Bounty Hunter',
        description: 'Score 5,000 in a single run.',
        icon: Symbols.paid_rounded,
        type: AchievementType.score,
        category: CommendationCategory.feats,
        metric: CommendationMetric.runScore,
        rarity: AchievementRarity.common,
        targetValue: 5000,
        points: 20,
        xpReward: 20,
        coinReward: 10,
      ),
      const Achievement(
        id: 'cmd_score_25k',
        title: 'Big Game',
        description: 'Score 25,000 in a single run.',
        icon: Symbols.monetization_on_rounded,
        type: AchievementType.score,
        category: CommendationCategory.feats,
        metric: CommendationMetric.runScore,
        rarity: AchievementRarity.rare,
        targetValue: 25000,
        points: 60,
        xpReward: 60,
        coinReward: 30,
      ),
      const Achievement(
        id: 'cmd_score_100k',
        title: 'Top of the Board',
        description: 'Score 100,000 in a single run.',
        icon: Symbols.stars_rounded,
        type: AchievementType.score,
        category: CommendationCategory.feats,
        metric: CommendationMetric.runScore,
        rarity: AchievementRarity.legendary,
        targetValue: 100000,
        points: 250,
        xpReward: 250,
        coinReward: 125,
      ),
      const Achievement(
        id: 'cmd_career_100k',
        title: 'Paid in Full',
        description: 'Earn 100,000 points across all runs.',
        icon: Symbols.savings_rounded,
        type: AchievementType.score,
        category: CommendationCategory.feats,
        metric: CommendationMetric.totalScore,
        rarity: AchievementRarity.common,
        targetValue: 100000,
        points: 25,
        xpReward: 25,
        coinReward: 10,
      ),
      const Achievement(
        id: 'cmd_career_1m',
        title: 'Million-Point Pilot',
        description: 'Earn 1,000,000 points across all runs.',
        icon: Symbols.stacked_line_chart_rounded,
        type: AchievementType.score,
        category: CommendationCategory.feats,
        metric: CommendationMetric.totalScore,
        rarity: AchievementRarity.epic,
        targetValue: 1000000,
        points: 150,
        xpReward: 150,
        coinReward: 75,
      ),
      const Achievement(
        id: 'cmd_career_10m',
        title: 'Living Legend',
        description: 'Earn 10,000,000 points across all runs.',
        icon: Symbols.diamond_rounded,
        type: AchievementType.score,
        category: CommendationCategory.feats,
        metric: CommendationMetric.totalScore,
        rarity: AchievementRarity.diamond,
        targetValue: 10000000,
        points: 500,
        xpReward: 500,
        coinReward: 250,
      ),
      const Achievement(
        id: 'cmd_flawless_campaign',
        title: 'Flawless',
        description:
            'Clear all 12 levels in a single run without taking a hit.',
        icon: Symbols.new_releases_rounded,
        type: AchievementType.special,
        category: CommendationCategory.feats,
        metric: CommendationMetric.flawlessCampaign,
        rarity: AchievementRarity.diamond,
        targetValue: 1,
        points: 500,
        xpReward: 500,
        coinReward: 250,
      ),
      const Achievement(
        id: 'cmd_night_ops',
        title: 'Night Ops',
        description: 'Finish a run between midnight and 5 AM.',
        icon: Symbols.nightlight_rounded,
        type: AchievementType.special,
        category: CommendationCategory.feats,
        metric: CommendationMetric.nightOps,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 20,
        xpReward: 20,
        coinReward: 10,
      ),
      const Achievement(
        id: 'cmd_full_draft',
        title: 'Fully Loaded',
        description: 'Draft 8 upgrades in a single run.',
        icon: Symbols.upgrade_rounded,
        type: AchievementType.special,
        category: CommendationCategory.feats,
        metric: CommendationMetric.runUpgrades,
        rarity: AchievementRarity.epic,
        targetValue: 8,
        points: 125,
        xpReward: 125,
        coinReward: 60,
      ),
    ];
  }
}
