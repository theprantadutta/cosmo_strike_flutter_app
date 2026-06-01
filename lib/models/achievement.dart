import 'package:flutter/material.dart';

enum AchievementType { score, games, streak, survival, special, general }

// Maps to backend AchievementTier (Bronze/Silver/Gold/Platinum/Diamond).
// `diamond` is the apex tier for genuinely rare unlocks (Score God,
// Decamillionaire, Dreadnought, Touch Grass, etc.).
enum AchievementRarity { common, rare, epic, legendary, diamond }

class Achievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final AchievementType type;
  final AchievementRarity rarity;
  final int targetValue;
  final int points;
  final bool isUnlocked;
  final DateTime? unlockedAt;
  final int currentProgress;
  /// True once the backend has granted the XP + coin reward for this
  /// unlock. Independent of [isUnlocked]: an achievement can be unlocked
  /// locally but unclaimed until the next online sync flushes a POST to
  /// /achievements/claim. Used to drive the auto-claim flow and to gate
  /// the "Claim" UX surface.
  final bool rewardClaimed;
  /// Backend-side XP reward credited to User.Experience by the claim
  /// endpoint. Distinct from the frontend BattlePass XP buffered on unlock.
  /// Defaults match the seeded backend catalog; sync overlays the
  /// authoritative values from GetUserAchievementsQuery.
  final int xpReward;
  /// Backend-side coin reward credited to User.Coins by the claim endpoint.
  final int coinReward;
  /// Per-game mode filter. When set, the local Score/Time/Survival check
  /// only unlocks this achievement if the finished game was in this mode.
  /// Mirrors AchievementAutoEvaluator's `a.game_mode_filter` guard so
  /// offline reveals match server evaluation exactly (no phantom unlocks
  /// for mode-gated rows like classic_1000 firing on a Zen run).
  /// Stored as the lowercase Dart enum name (`classic`, `zen`, `survival`,
  /// `speedChallenge`, `multiFood`, `timeAttack`, `powerUpMadness`,
  /// `perfectGame`) so case-insensitive comparison to GameState.gameMode
  /// works out of the box.
  final String? gameModeFilter;
  /// Per-game difficulty filter — analogous to [gameModeFilter] but for
  /// the Difficulty enum (`easy`, `normal`, `hard`).
  final String? difficultyFilter;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.type,
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
        return Colors.grey;
      case AchievementRarity.rare:
        return Colors.blue;
      case AchievementRarity.epic:
        return Colors.purple;
      case AchievementRarity.legendary:
        return Colors.orange;
      case AchievementRarity.diamond:
        return Colors.cyanAccent;
    }
  }

  String get rarityName {
    switch (rarity) {
      case AchievementRarity.common:
        return 'Common';
      case AchievementRarity.rare:
        return 'Rare';
      case AchievementRarity.epic:
        return 'Epic';
      case AchievementRarity.legendary:
        return 'Legendary';
      case AchievementRarity.diamond:
        return 'Diamond';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'iconCodePoint': icon.codePoint,
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

  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      icon: IconData(
        // ignore: non_const_argument_for_const_parameter
        json['iconCodePoint'] ?? Icons.star.codePoint,
        fontFamily: 'MaterialIcons',
      ),
      type: AchievementType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AchievementType.score,
      ),
      rarity: AchievementRarity.values.firstWhere(
        (e) => e.name == json['rarity'],
        orElse: () => AchievementRarity.common,
      ),
      targetValue: json['targetValue'] ?? 0,
      points: json['points'] ?? 0,
      isUnlocked: json['isUnlocked'] ?? false,
      unlockedAt: json['unlockedAt'] != null
          ? DateTime.parse(json['unlockedAt'])
          : null,
      currentProgress: json['currentProgress'] ?? 0,
      rewardClaimed: json['rewardClaimed'] ?? false,
      xpReward: json['xpReward'] ?? 0,
      coinReward: json['coinReward'] ?? 0,
    );
  }

  static List<Achievement> getDefaultAchievements() {
    // XP / coin rewards mirror SeedAchievementsCommandHandler so the UI
    // shows accurate values before the first backend sync. Backend remains
    // authoritative — _updateAchievementsFromBackend overlays server values
    // when they arrive.
    return [
      // Score Achievements (IDs match backend)
      const Achievement(
        id: 'first_bite',
        title: 'First Blood',
        description: 'Score your first point',
        icon: Icons.star,
        type: AchievementType.score,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 10,
        xpReward: 10,
        coinReward: 5,
      ),
      const Achievement(
        id: 'getting_started',
        title: 'Getting Started',
        description: 'Score 100 points',
        icon: Icons.emoji_events,
        type: AchievementType.score,
        rarity: AchievementRarity.common,
        targetValue: 100,
        points: 25,
        xpReward: 25,
        coinReward: 10,
      ),
      const Achievement(
        id: 'high_scorer',
        title: 'High Scorer',
        description: 'Score 500 points in a single game',
        icon: Icons.trending_up,
        type: AchievementType.score,
        rarity: AchievementRarity.rare,
        targetValue: 500,
        points: 50,
        xpReward: 50,
        coinReward: 25,
      ),
      const Achievement(
        id: 'master_scorer',
        title: 'Master Scorer',
        description: 'Score 1000 points in a single game',
        icon: Icons.military_tech,
        type: AchievementType.score,
        rarity: AchievementRarity.epic,
        targetValue: 1000,
        points: 100,
        xpReward: 100,
        coinReward: 50,
      ),
      const Achievement(
        id: 'legendary_scorer',
        title: 'Legendary Scorer',
        description: 'Score 2000 points in a single game',
        icon: Icons.diamond,
        type: AchievementType.score,
        rarity: AchievementRarity.legendary,
        targetValue: 2000,
        points: 200,
        xpReward: 200,
        coinReward: 100,
      ),

      // Games Played Achievements (IDs match backend)
      const Achievement(
        id: 'first_game',
        title: 'First Game',
        description: 'Play your first game',
        icon: Icons.play_arrow,
        type: AchievementType.games,
        rarity: AchievementRarity.common,
        targetValue: 1,
        points: 10,
        xpReward: 10,
        coinReward: 5,
      ),
      const Achievement(
        id: 'regular_player',
        title: 'Regular Player',
        description: 'Play 10 games',
        icon: Icons.videogame_asset,
        type: AchievementType.games,
        rarity: AchievementRarity.common,
        targetValue: 10,
        points: 25,
        xpReward: 25,
        coinReward: 10,
      ),
      const Achievement(
        id: 'dedicated_player',
        title: 'Dedicated Player',
        description: 'Play 50 games',
        icon: Icons.sports_esports,
        type: AchievementType.games,
        rarity: AchievementRarity.rare,
        targetValue: 50,
        points: 50,
        xpReward: 50,
        coinReward: 25,
      ),
      const Achievement(
        id: 'snake_enthusiast',
        title: 'Pilot Enthusiast',
        description: 'Play 100 games',
        icon: Icons.gamepad,
        type: AchievementType.games,
        rarity: AchievementRarity.epic,
        targetValue: 100,
        points: 100,
        xpReward: 100,
        coinReward: 50,
      ),
      const Achievement(
        id: 'snake_addict',
        title: 'Combat Addict',
        description: 'Play 500 games',
        icon: Icons.sports_esports,
        type: AchievementType.games,
        rarity: AchievementRarity.legendary,
        targetValue: 500,
        points: 250,
        xpReward: 250,
        coinReward: 125,
      ),

      // Survival Achievements (IDs match backend)
      const Achievement(
        id: 'survivor',
        title: 'Survivor',
        description: 'Survive for 60 seconds',
        icon: Icons.timer,
        type: AchievementType.survival,
        rarity: AchievementRarity.common,
        targetValue: 60,
        points: 15,
        xpReward: 15,
        coinReward: 8,
      ),
      const Achievement(
        id: 'endurance',
        title: 'Endurance',
        description: 'Survive for 2 minutes',
        icon: Icons.schedule,
        type: AchievementType.survival,
        rarity: AchievementRarity.rare,
        targetValue: 120,
        points: 30,
        xpReward: 30,
        coinReward: 15,
      ),
      const Achievement(
        id: 'marathon',
        title: 'Marathon',
        description: 'Survive for 5 minutes',
        icon: Icons.hourglass_full,
        type: AchievementType.survival,
        rarity: AchievementRarity.epic,
        targetValue: 300,
        points: 75,
        xpReward: 75,
        coinReward: 40,
      ),

      // Special Achievements
      const Achievement(
        id: 'no_walls',
        title: 'Evasive Maneuvers',
        description: 'Play 5 games without crashing into asteroids',
        icon: Icons.shield,
        type: AchievementType.special,
        rarity: AchievementRarity.rare,
        targetValue: 5,
        points: 60,
        xpReward: 60,
        coinReward: 30,
      ),
      const Achievement(
        id: 'speedster',
        title: 'Speedster',
        description: 'Reach level 10 (max speed)',
        icon: Icons.speed,
        type: AchievementType.special,
        rarity: AchievementRarity.epic,
        targetValue: 10,
        points: 80,
        xpReward: 80,
        coinReward: 40,
      ),
      const Achievement(
        id: 'perfectionist',
        title: 'Perfectionist',
        description: 'Complete a game without taking damage',
        icon: Icons.verified,
        type: AchievementType.special,
        rarity: AchievementRarity.epic,
        targetValue: 1,
        points: 90,
        xpReward: 90,
        coinReward: 45,
      ),
      const Achievement(
        id: 'all_food_types',
        title: 'Full Arsenal',
        description: 'Destroy all 3 enemy types in a single game',
        icon: Icons.restaurant,
        type: AchievementType.special,
        rarity: AchievementRarity.rare,
        targetValue: 1,
        points: 40,
        xpReward: 40,
        coinReward: 20,
      ),

      // ============================================================
      // A. Single-Game Score (5 NEW)
      // ============================================================
      const Achievement(id: 'half_grand', title: 'Half Grand', description: 'Score 5,000 in a single game', icon: Icons.looks_5, type: AchievementType.score, rarity: AchievementRarity.legendary, targetValue: 5000, points: 250, xpReward: 250, coinReward: 125),
      const Achievement(id: 'score_sniper', title: 'Score Sniper', description: 'Score 10,000 in a single game', icon: Icons.my_location, type: AchievementType.score, rarity: AchievementRarity.legendary, targetValue: 10000, points: 350, xpReward: 350, coinReward: 175),
      const Achievement(id: 'five_digit_club', title: 'Five-Digit Club', description: 'Score 25,000 in a single game', icon: Icons.format_list_numbered, type: AchievementType.score, rarity: AchievementRarity.diamond, targetValue: 25000, points: 400, xpReward: 400, coinReward: 200),
      const Achievement(id: 'score_tycoon', title: 'Score Tycoon', description: 'Score 50,000 in a single game', icon: Icons.attach_money, type: AchievementType.score, rarity: AchievementRarity.diamond, targetValue: 50000, points: 450, xpReward: 450, coinReward: 225),
      const Achievement(id: 'score_god', title: 'Score God', description: 'Score 100,000 in a single game', icon: Icons.auto_awesome, type: AchievementType.score, rarity: AchievementRarity.diamond, targetValue: 100000, points: 500, xpReward: 500, coinReward: 250),

      // ============================================================
      // B. Lifetime Total Score (5 NEW)
      // ============================================================
      const Achievement(id: 'point_collector', title: 'Point Collector', description: 'Accumulate 10,000 points lifetime', icon: Icons.savings, type: AchievementType.score, rarity: AchievementRarity.common, targetValue: 10000, points: 25, xpReward: 25, coinReward: 10),
      const Achievement(id: 'point_hoarder', title: 'Point Hoarder', description: 'Accumulate 100,000 points lifetime', icon: Icons.account_balance, type: AchievementType.score, rarity: AchievementRarity.rare, targetValue: 100000, points: 75, xpReward: 75, coinReward: 40),
      const Achievement(id: 'half_million_club', title: 'Half Million Club', description: 'Accumulate 500,000 points lifetime', icon: Icons.paid, type: AchievementType.score, rarity: AchievementRarity.epic, targetValue: 500000, points: 150, xpReward: 150, coinReward: 75),
      const Achievement(id: 'point_millionaire', title: 'Point Millionaire', description: 'Accumulate 1,000,000 points lifetime', icon: Icons.monetization_on, type: AchievementType.score, rarity: AchievementRarity.legendary, targetValue: 1000000, points: 300, xpReward: 300, coinReward: 150),
      const Achievement(id: 'decamillionaire', title: 'Decamillionaire', description: 'Accumulate 10,000,000 points lifetime', icon: Icons.diamond, type: AchievementType.score, rarity: AchievementRarity.diamond, targetValue: 10000000, points: 500, xpReward: 500, coinReward: 250),

      // ============================================================
      // C. Games Played (2 NEW)
      // ============================================================
      const Achievement(id: 'snake_veteran', title: 'Ace Veteran', description: 'Play 1,000 games', icon: Icons.military_tech, type: AchievementType.games, rarity: AchievementRarity.legendary, targetValue: 1000, points: 350, xpReward: 350, coinReward: 175),
      const Achievement(id: 'snake_legend', title: 'Pilot Legend', description: 'Play 5,000 games', icon: Icons.workspace_premium, type: AchievementType.games, rarity: AchievementRarity.diamond, targetValue: 5000, points: 500, xpReward: 500, coinReward: 250),

      // ============================================================
      // D. Single-Game Survival (3 NEW)
      // ============================================================
      const Achievement(id: 'iron_will', title: 'Iron Will', description: 'Survive 10 minutes in a single game', icon: Icons.fitness_center, type: AchievementType.survival, rarity: AchievementRarity.legendary, targetValue: 600, points: 150, xpReward: 150, coinReward: 75),
      const Achievement(id: 'eternal_snake', title: 'Eternal Pilot', description: 'Survive 20 minutes in a single game', icon: Icons.all_inclusive, type: AchievementType.survival, rarity: AchievementRarity.diamond, targetValue: 1200, points: 250, xpReward: 250, coinReward: 125),
      const Achievement(id: 'time_lord', title: 'Time Lord', description: 'Survive 30 minutes in a single game', icon: Icons.hourglass_top, type: AchievementType.survival, rarity: AchievementRarity.diamond, targetValue: 1800, points: 400, xpReward: 400, coinReward: 200),

      // ============================================================
      // E. Single-Game Enemies Destroyed (6 NEW)
      // ============================================================
      const Achievement(id: 'first_bite_snack', title: 'First Kills', description: 'Destroy 5 enemies in one game', icon: Icons.lunch_dining, type: AchievementType.special, rarity: AchievementRarity.common, targetValue: 5, points: 15, xpReward: 15, coinReward: 8),
      const Achievement(id: 'hungry_snake', title: 'Trigger Happy', description: 'Destroy 20 enemies in one game', icon: Icons.ramen_dining, type: AchievementType.special, rarity: AchievementRarity.common, targetValue: 20, points: 25, xpReward: 25, coinReward: 12),
      const Achievement(id: 'famished', title: 'Sharpshooter', description: 'Destroy 50 enemies in one game', icon: Icons.dining, type: AchievementType.special, rarity: AchievementRarity.rare, targetValue: 50, points: 50, xpReward: 50, coinReward: 25),
      const Achievement(id: 'ravenous', title: 'Onslaught', description: 'Destroy 100 enemies in one game', icon: Icons.set_meal, type: AchievementType.special, rarity: AchievementRarity.epic, targetValue: 100, points: 100, xpReward: 100, coinReward: 50),
      const Achievement(id: 'insatiable', title: 'Annihilator', description: 'Destroy 200 enemies in one game', icon: Icons.fastfood, type: AchievementType.special, rarity: AchievementRarity.legendary, targetValue: 200, points: 200, xpReward: 200, coinReward: 100),
      const Achievement(id: 'black_hole_stomach', title: 'Void Devourer', description: 'Destroy 500 enemies in one game', icon: Icons.blur_on, type: AchievementType.special, rarity: AchievementRarity.diamond, targetValue: 500, points: 350, xpReward: 350, coinReward: 175),

      // ============================================================
      // F. Lifetime Kills (4 NEW)
      // ============================================================
      const Achievement(id: 'foodie_apprentice', title: 'Gunner Apprentice', description: 'Destroy 100 enemies lifetime', icon: Icons.egg, type: AchievementType.special, rarity: AchievementRarity.common, targetValue: 100, points: 25, xpReward: 25, coinReward: 10),
      const Achievement(id: 'foodie_pro', title: 'Gunner Pro', description: 'Destroy 1,000 enemies lifetime', icon: Icons.local_dining, type: AchievementType.special, rarity: AchievementRarity.rare, targetValue: 1000, points: 75, xpReward: 75, coinReward: 40),
      const Achievement(id: 'foodie_master', title: 'Gunner Master', description: 'Destroy 10,000 enemies lifetime', icon: Icons.restaurant_menu, type: AchievementType.special, rarity: AchievementRarity.epic, targetValue: 10000, points: 175, xpReward: 175, coinReward: 90),
      const Achievement(id: 'foodie_god', title: 'War God', description: 'Destroy 50,000 enemies lifetime', icon: Icons.icecream, type: AchievementType.special, rarity: AchievementRarity.diamond, targetValue: 50000, points: 350, xpReward: 350, coinReward: 175),

      // ============================================================
      // G. Lifetime Play Time (5 NEW)
      // ============================================================
      const Achievement(id: 'quick_player', title: 'Quick Player', description: 'Play for 1 hour total', icon: Icons.schedule, type: AchievementType.general, rarity: AchievementRarity.common, targetValue: 3600, points: 25, xpReward: 25, coinReward: 10),
      const Achievement(id: 'engaged_player', title: 'Engaged Player', description: 'Play for 10 hours total', icon: Icons.watch_later, type: AchievementType.general, rarity: AchievementRarity.rare, targetValue: 36000, points: 75, xpReward: 75, coinReward: 40),
      const Achievement(id: 'hardcore_player', title: 'Hardcore Player', description: 'Play for 50 hours total', icon: Icons.self_improvement, type: AchievementType.general, rarity: AchievementRarity.epic, targetValue: 180000, points: 175, xpReward: 175, coinReward: 90),
      const Achievement(id: 'snake_obsessed', title: 'Combat Obsessed', description: 'Play for 100 hours total', icon: Icons.psychology, type: AchievementType.general, rarity: AchievementRarity.legendary, targetValue: 360000, points: 300, xpReward: 300, coinReward: 150),
      const Achievement(id: 'touch_grass', title: 'Touch Grass', description: 'Play for 250 hours total — maybe step outside?', icon: Icons.grass, type: AchievementType.general, rarity: AchievementRarity.diamond, targetValue: 900000, points: 500, xpReward: 500, coinReward: 250),

      // ============================================================
      // H. Player Level (5 NEW)
      // ============================================================
      const Achievement(id: 'level_5', title: 'Apprentice', description: 'Reach Level 5', icon: Icons.trending_up, type: AchievementType.general, rarity: AchievementRarity.common, targetValue: 5, points: 25, xpReward: 25, coinReward: 10),
      const Achievement(id: 'level_10', title: 'Journeyman', description: 'Reach Level 10', icon: Icons.stars, type: AchievementType.general, rarity: AchievementRarity.rare, targetValue: 10, points: 50, xpReward: 50, coinReward: 25),
      const Achievement(id: 'level_25', title: 'Expert', description: 'Reach Level 25', icon: Icons.verified_user, type: AchievementType.general, rarity: AchievementRarity.epic, targetValue: 25, points: 150, xpReward: 150, coinReward: 75),
      const Achievement(id: 'level_50', title: 'Master', description: 'Reach Level 50', icon: Icons.shield, type: AchievementType.general, rarity: AchievementRarity.legendary, targetValue: 50, points: 300, xpReward: 300, coinReward: 150),
      const Achievement(id: 'level_100', title: 'Grandmaster', description: 'Reach Level 100', icon: Icons.auto_awesome, type: AchievementType.general, rarity: AchievementRarity.diamond, targetValue: 100, points: 500, xpReward: 500, coinReward: 250),

      // ============================================================
      // I. Game Mode — CLASSIC (4 NEW)
      // ============================================================
      const Achievement(id: 'classic_initiate', title: 'Classic Initiate', description: 'Finish 10 Classic-mode games', icon: Icons.videogame_asset, type: AchievementType.games, rarity: AchievementRarity.common, targetValue: 10, points: 25, xpReward: 25, coinReward: 12, gameModeFilter: 'classic'),
      const Achievement(id: 'classic_veteran', title: 'Classic Veteran', description: 'Finish 100 Classic-mode games', icon: Icons.sports_esports, type: AchievementType.games, rarity: AchievementRarity.epic, targetValue: 100, points: 125, xpReward: 125, coinReward: 60, gameModeFilter: 'classic'),
      const Achievement(id: 'classic_1000', title: 'Classic Connoisseur', description: 'Score 1,000 in Classic mode', icon: Icons.emoji_events, type: AchievementType.score, rarity: AchievementRarity.rare, targetValue: 1000, points: 60, xpReward: 60, coinReward: 30, gameModeFilter: 'classic'),
      const Achievement(id: 'classic_5000', title: 'Classic Maestro', description: 'Score 5,000 in Classic mode', icon: Icons.military_tech, type: AchievementType.score, rarity: AchievementRarity.legendary, targetValue: 5000, points: 200, xpReward: 200, coinReward: 100, gameModeFilter: 'classic'),

      // ============================================================
      // J. Game Mode — ZEN (3 NEW)
      // ============================================================
      const Achievement(id: 'zen_initiate', title: 'Zen Initiate', description: 'Finish 10 Zen games', icon: Icons.spa, type: AchievementType.games, rarity: AchievementRarity.common, targetValue: 10, points: 25, xpReward: 25, coinReward: 12, gameModeFilter: 'zen'),
      const Achievement(id: 'zen_garden', title: 'Zen Garden', description: 'Score 500 in Zen mode', icon: Icons.local_florist, type: AchievementType.score, rarity: AchievementRarity.rare, targetValue: 500, points: 50, xpReward: 50, coinReward: 25, gameModeFilter: 'zen'),
      const Achievement(id: 'zen_master', title: 'Zen Master', description: 'Score 5,000 in Zen mode', icon: Icons.self_improvement, type: AchievementType.score, rarity: AchievementRarity.epic, targetValue: 5000, points: 150, xpReward: 150, coinReward: 75, gameModeFilter: 'zen'),

      // ============================================================
      // K. Game Mode — SPEED CHALLENGE (3 NEW)
      // ============================================================
      const Achievement(id: 'speed_initiate', title: 'Need For Speed', description: 'Finish 10 Speed Challenge games', icon: Icons.speed, type: AchievementType.games, rarity: AchievementRarity.common, targetValue: 10, points: 25, xpReward: 25, coinReward: 12, gameModeFilter: 'speedChallenge'),
      const Achievement(id: 'speedrunner', title: 'Speedrunner', description: 'Score 500 in Speed Challenge', icon: Icons.directions_run, type: AchievementType.score, rarity: AchievementRarity.rare, targetValue: 500, points: 60, xpReward: 60, coinReward: 30, gameModeFilter: 'speedChallenge'),
      const Achievement(id: 'lightning', title: 'Lightning', description: 'Score 2,000 in Speed Challenge', icon: Icons.bolt, type: AchievementType.score, rarity: AchievementRarity.epic, targetValue: 2000, points: 150, xpReward: 150, coinReward: 75, gameModeFilter: 'speedChallenge'),

      // ============================================================
      // L. Game Mode — ONSLAUGHT (3 NEW)
      // ============================================================
      const Achievement(id: 'multifood_initiate', title: 'Warzone', description: 'Finish 10 Onslaught games', icon: Icons.rice_bowl, type: AchievementType.games, rarity: AchievementRarity.common, targetValue: 10, points: 25, xpReward: 25, coinReward: 12, gameModeFilter: 'onslaught'),
      const Achievement(id: 'buffet', title: 'Barrage', description: 'Score 1,000 in Onslaught', icon: Icons.kitchen, type: AchievementType.score, rarity: AchievementRarity.rare, targetValue: 1000, points: 60, xpReward: 60, coinReward: 30, gameModeFilter: 'onslaught'),
      const Achievement(id: 'smorgasbord', title: 'Bombardment', description: 'Score 5,000 in Onslaught', icon: Icons.tapas, type: AchievementType.score, rarity: AchievementRarity.epic, targetValue: 5000, points: 150, xpReward: 150, coinReward: 75, gameModeFilter: 'onslaught'),

      // ============================================================
      // M. Game Mode — SURVIVAL (3 NEW)
      // ============================================================
      const Achievement(id: 'survival_initiate', title: 'Survival Initiate', description: 'Finish 10 Survival games', icon: Icons.favorite, type: AchievementType.games, rarity: AchievementRarity.common, targetValue: 10, points: 25, xpReward: 25, coinReward: 12, gameModeFilter: 'survival'),
      const Achievement(id: 'survival_pro', title: 'Survival Pro', description: 'Survive 5 minutes in Survival mode', icon: Icons.health_and_safety, type: AchievementType.survival, rarity: AchievementRarity.epic, targetValue: 300, points: 100, xpReward: 100, coinReward: 50, gameModeFilter: 'survival'),
      const Achievement(id: 'last_snake_standing', title: 'Last Ship Standing', description: 'Score 2,500 in Survival', icon: Icons.shield_moon, type: AchievementType.score, rarity: AchievementRarity.legendary, targetValue: 2500, points: 200, xpReward: 200, coinReward: 100, gameModeFilter: 'survival'),

      // ============================================================
      // N. Game Mode — TIME ATTACK (3 NEW)
      // ============================================================
      const Achievement(id: 'timeattack_initiate', title: 'Time Attacker', description: 'Finish 10 TimeAttack games', icon: Icons.timer, type: AchievementType.games, rarity: AchievementRarity.common, targetValue: 10, points: 25, xpReward: 25, coinReward: 12, gameModeFilter: 'timeAttack'),
      const Achievement(id: 'beat_the_clock', title: 'Beat the Clock', description: 'Survive the full 3-minute TimeAttack', icon: Icons.alarm_on, type: AchievementType.survival, rarity: AchievementRarity.rare, targetValue: 180, points: 75, xpReward: 75, coinReward: 35, gameModeFilter: 'timeAttack'),
      const Achievement(id: 'timeattack_master', title: 'TimeAttack Master', description: 'Score 3,000 in TimeAttack', icon: Icons.av_timer, type: AchievementType.score, rarity: AchievementRarity.epic, targetValue: 3000, points: 150, xpReward: 150, coinReward: 75, gameModeFilter: 'timeAttack'),

      // ============================================================
      // O. Difficulty-Gated (6 NEW)
      // ============================================================
      const Achievement(id: 'hard_mode_hero', title: 'Hard Mode Hero', description: 'Score 500 on Hard difficulty', icon: Icons.fitness_center, type: AchievementType.score, rarity: AchievementRarity.rare, targetValue: 500, points: 75, xpReward: 75, coinReward: 35, difficultyFilter: 'hard'),
      const Achievement(id: 'hard_mode_master', title: 'Hard Mode Master', description: 'Score 2,000 on Hard difficulty', icon: Icons.military_tech, type: AchievementType.score, rarity: AchievementRarity.epic, targetValue: 2000, points: 150, xpReward: 150, coinReward: 75, difficultyFilter: 'hard'),
      const Achievement(id: 'hard_mode_god', title: 'Hard Mode God', description: 'Score 5,000 on Hard difficulty', icon: Icons.whatshot, type: AchievementType.score, rarity: AchievementRarity.diamond, targetValue: 5000, points: 300, xpReward: 300, coinReward: 150, difficultyFilter: 'hard'),
      const Achievement(id: 'hard_veteran', title: 'Hard Veteran', description: 'Finish 50 games on Hard difficulty', icon: Icons.shield, type: AchievementType.games, rarity: AchievementRarity.epic, targetValue: 50, points: 125, xpReward: 125, coinReward: 60, difficultyFilter: 'hard'),
      const Achievement(id: 'no_easy_way', title: 'No Easy Way', description: 'Finish 100 games on Hard difficulty', icon: Icons.gpp_good, type: AchievementType.games, rarity: AchievementRarity.legendary, targetValue: 100, points: 200, xpReward: 200, coinReward: 100, difficultyFilter: 'hard'),
      const Achievement(id: 'hardcore_for_life', title: 'Hardcore for Life', description: 'Finish 500 games on Hard difficulty', icon: Icons.local_fire_department, type: AchievementType.games, rarity: AchievementRarity.diamond, targetValue: 500, points: 400, xpReward: 400, coinReward: 200, difficultyFilter: 'hard'),

      // ============================================================
      // P. Combo (5 NEW)
      // ============================================================
      const Achievement(id: 'combo_starter', title: 'Combo Starter', description: 'Hit a 5x combo in a single game', icon: Icons.filter_5, type: AchievementType.special, rarity: AchievementRarity.common, targetValue: 5, points: 20, xpReward: 20, coinReward: 10),
      const Achievement(id: 'combo_master', title: 'Combo Master', description: 'Hit a 10x combo in a single game', icon: Icons.filter_9_plus, type: AchievementType.special, rarity: AchievementRarity.rare, targetValue: 10, points: 50, xpReward: 50, coinReward: 25),
      const Achievement(id: 'combo_pro', title: 'Combo Pro', description: 'Hit a 20x combo in a single game', icon: Icons.flash_on, type: AchievementType.special, rarity: AchievementRarity.epic, targetValue: 20, points: 100, xpReward: 100, coinReward: 50),
      const Achievement(id: 'combo_god', title: 'Combo God', description: 'Hit a 50x combo in a single game', icon: Icons.rocket_launch, type: AchievementType.special, rarity: AchievementRarity.legendary, targetValue: 50, points: 250, xpReward: 250, coinReward: 125),
      const Achievement(id: 'combo_legend', title: 'Combo Legend', description: 'Hit a 100x combo in a single game', icon: Icons.auto_awesome_motion, type: AchievementType.special, rarity: AchievementRarity.diamond, targetValue: 100, points: 500, xpReward: 500, coinReward: 250),

      // ============================================================
      // Q. Stage Progress (5 NEW)
      // ============================================================
      const Achievement(id: 'growing_snake', title: 'Rising Star', description: 'Reach stage 20', icon: Icons.trending_up, type: AchievementType.special, rarity: AchievementRarity.common, targetValue: 20, points: 20, xpReward: 20, coinReward: 10),
      const Achievement(id: 'big_snake', title: 'Deep Striker', description: 'Reach stage 50', icon: Icons.straighten, type: AchievementType.special, rarity: AchievementRarity.rare, targetValue: 50, points: 50, xpReward: 50, coinReward: 25),
      const Achievement(id: 'huge_snake', title: 'Frontline Pilot', description: 'Reach stage 100', icon: Icons.open_in_full, type: AchievementType.special, rarity: AchievementRarity.epic, targetValue: 100, points: 100, xpReward: 100, coinReward: 50),
      const Achievement(id: 'massive_snake', title: 'Vanguard', description: 'Reach stage 200', icon: Icons.expand, type: AchievementType.special, rarity: AchievementRarity.legendary, targetValue: 200, points: 200, xpReward: 200, coinReward: 100),
      const Achievement(id: 'anaconda', title: 'Dreadnought', description: 'Reach stage 500', icon: Icons.all_inclusive, type: AchievementType.special, rarity: AchievementRarity.diamond, targetValue: 500, points: 400, xpReward: 400, coinReward: 200),

      // ============================================================
      // R. Power-Ups (8 NEW)
      // ============================================================
      const Achievement(id: 'first_power_up', title: 'Power Up!', description: 'Collect your first power-up', icon: Icons.bolt, type: AchievementType.special, rarity: AchievementRarity.common, targetValue: 1, points: 15, xpReward: 15, coinReward: 8),
      const Achievement(id: 'power_player', title: 'Power Player', description: 'Collect 10 power-ups lifetime', icon: Icons.electric_bolt, type: AchievementType.special, rarity: AchievementRarity.common, targetValue: 10, points: 25, xpReward: 25, coinReward: 12),
      const Achievement(id: 'power_hungry', title: 'Power Hungry', description: 'Collect 50 power-ups lifetime', icon: Icons.battery_charging_full, type: AchievementType.special, rarity: AchievementRarity.rare, targetValue: 50, points: 60, xpReward: 60, coinReward: 30),
      const Achievement(id: 'power_addict', title: 'Power Addict', description: 'Collect 200 power-ups lifetime', icon: Icons.offline_bolt, type: AchievementType.special, rarity: AchievementRarity.epic, targetValue: 200, points: 150, xpReward: 150, coinReward: 75),
      const Achievement(id: 'power_master', title: 'Power Master', description: 'Collect 1,000 power-ups lifetime', icon: Icons.electric_meter, type: AchievementType.special, rarity: AchievementRarity.diamond, targetValue: 1000, points: 350, xpReward: 350, coinReward: 175),
      const Achievement(id: 'variety_pack', title: 'Variety Pack', description: 'Collect each of the 4 power-up types at least once', icon: Icons.auto_awesome, type: AchievementType.special, rarity: AchievementRarity.rare, targetValue: 4, points: 75, xpReward: 75, coinReward: 40),
      const Achievement(id: 'speed_demon', title: 'Speed Demon', description: 'Collect 25 Speed Boost power-ups', icon: Icons.directions_run, type: AchievementType.special, rarity: AchievementRarity.rare, targetValue: 25, points: 50, xpReward: 50, coinReward: 25),
      const Achievement(id: 'immortal_streak', title: 'Immortal Streak', description: 'Collect 25 Invincibility power-ups', icon: Icons.shield, type: AchievementType.special, rarity: AchievementRarity.rare, targetValue: 25, points: 50, xpReward: 50, coinReward: 25),

      // ============================================================
      // S. Enemy Type Variety (2 NEW)
      // ============================================================
      const Achievement(id: 'special_diet', title: 'Elite Hunter', description: 'Destroy 50 elite enemies lifetime', icon: Icons.cake, type: AchievementType.special, rarity: AchievementRarity.rare, targetValue: 50, points: 60, xpReward: 60, coinReward: 30),
      const Achievement(id: 'bonus_hunter', title: 'Bounty Hunter', description: 'Destroy 100 bonus targets lifetime', icon: Icons.redeem, type: AchievementType.special, rarity: AchievementRarity.epic, targetValue: 100, points: 100, xpReward: 100, coinReward: 50),

      // ============================================================
      // T. Perfection / No-Hit (3 NEW)
      // ============================================================
      const Achievement(id: 'untouchable_5', title: 'Untouchable', description: 'Complete 5 perfect games (no hits, 30s+)', icon: Icons.verified, type: AchievementType.special, rarity: AchievementRarity.epic, targetValue: 5, points: 100, xpReward: 100, coinReward: 50),
      const Achievement(id: 'untouchable_20', title: 'Flawless', description: 'Complete 20 perfect games', icon: Icons.diamond, type: AchievementType.special, rarity: AchievementRarity.legendary, targetValue: 20, points: 200, xpReward: 200, coinReward: 100),
      const Achievement(id: 'untouchable_50', title: 'Untouchable Legend', description: 'Complete 50 perfect games', icon: Icons.workspace_premium, type: AchievementType.special, rarity: AchievementRarity.diamond, targetValue: 50, points: 400, xpReward: 400, coinReward: 200),

      // ============================================================
      // U. Streaks / Daily (5 NEW)
      // ============================================================
      const Achievement(id: 'hot_streak', title: 'Hot Streak', description: '5 consecutive games scoring >0 and lasting 30s+', icon: Icons.whatshot, type: AchievementType.streak, rarity: AchievementRarity.rare, targetValue: 5, points: 50, xpReward: 50, coinReward: 25),
      const Achievement(id: 'on_fire', title: 'On Fire', description: '10-game streak (30s+ each)', icon: Icons.local_fire_department, type: AchievementType.streak, rarity: AchievementRarity.epic, targetValue: 10, points: 100, xpReward: 100, coinReward: 50),
      const Achievement(id: 'unstoppable', title: 'Unstoppable', description: '25-game streak (30s+ each)', icon: Icons.speed, type: AchievementType.streak, rarity: AchievementRarity.legendary, targetValue: 25, points: 250, xpReward: 250, coinReward: 125),
      const Achievement(id: 'daily_three', title: 'Daily Player', description: 'Play on 3 consecutive days', icon: Icons.calendar_today, type: AchievementType.streak, rarity: AchievementRarity.rare, targetValue: 3, points: 50, xpReward: 50, coinReward: 25),
      const Achievement(id: 'week_warrior', title: 'Week Warrior', description: 'Play on 7 consecutive days', icon: Icons.event_available, type: AchievementType.streak, rarity: AchievementRarity.epic, targetValue: 7, points: 125, xpReward: 125, coinReward: 60),

      // ============================================================
      // V. In-Game Level (3 NEW)
      // ============================================================
      const Achievement(id: 'velocity', title: 'Velocity', description: 'Reach in-game level 15 in one game', icon: Icons.fast_forward, type: AchievementType.special, rarity: AchievementRarity.epic, targetValue: 15, points: 120, xpReward: 120, coinReward: 60),
      const Achievement(id: 'mach_speed', title: 'Mach Speed', description: 'Reach in-game level 20 in one game', icon: Icons.rocket, type: AchievementType.special, rarity: AchievementRarity.legendary, targetValue: 20, points: 200, xpReward: 200, coinReward: 100),
      const Achievement(id: 'cosmic_snake', title: 'Cosmic Ace', description: 'Reach in-game level 25 in one game', icon: Icons.satellite_alt, type: AchievementType.special, rarity: AchievementRarity.diamond, targetValue: 25, points: 300, xpReward: 300, coinReward: 150),

      // ============================================================
      // W. Variety / Exploration (3 NEW)
      // ============================================================
      const Achievement(id: 'mode_explorer', title: 'Mode Explorer', description: 'Play at least one game in 3 distinct modes', icon: Icons.explore, type: AchievementType.general, rarity: AchievementRarity.common, targetValue: 3, points: 30, xpReward: 30, coinReward: 15),
      const Achievement(id: 'all_mode_player', title: 'All-Mode Player', description: 'Play at least one game in every mode (6 modes)', icon: Icons.travel_explore, type: AchievementType.general, rarity: AchievementRarity.epic, targetValue: 6, points: 150, xpReward: 150, coinReward: 75),
      const Achievement(id: 'difficulty_explorer', title: 'Difficulty Explorer', description: 'Play games on all 3 difficulties', icon: Icons.tune, type: AchievementType.general, rarity: AchievementRarity.rare, targetValue: 3, points: 50, xpReward: 50, coinReward: 25),

      // ============================================================
      // X. Time-of-Day / Special (3 NEW)
      // ============================================================
      const Achievement(id: 'night_owl', title: 'Night Owl', description: 'Finish a game between midnight and 5 AM', icon: Icons.nightlight, type: AchievementType.special, rarity: AchievementRarity.common, targetValue: 1, points: 25, xpReward: 25, coinReward: 12),
      const Achievement(id: 'early_bird', title: 'Early Bird', description: 'Finish a game between 5 and 8 AM', icon: Icons.wb_twilight, type: AchievementType.special, rarity: AchievementRarity.common, targetValue: 1, points: 25, xpReward: 25, coinReward: 12),
      const Achievement(id: 'weekend_warrior', title: 'Weekend Warrior', description: 'Finish 10 games on weekends', icon: Icons.weekend, type: AchievementType.special, rarity: AchievementRarity.rare, targetValue: 10, points: 50, xpReward: 50, coinReward: 25),
    ];
  }
}
