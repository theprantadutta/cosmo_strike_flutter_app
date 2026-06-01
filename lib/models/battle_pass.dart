import 'package:flutter/material.dart';

enum BattlePassRewardType {
  xp,
  coins,
  theme,
  skin,
  trail,
  powerUp,
  tournamentEntry,
  title,
  avatar,
  special;

  String get displayName {
    switch (this) {
      case BattlePassRewardType.xp:
        return 'XP Boost';
      case BattlePassRewardType.coins:
        return 'Coins';
      case BattlePassRewardType.theme:
        return 'Theme';
      case BattlePassRewardType.skin:
        return 'Snake Skin';
      case BattlePassRewardType.trail:
        return 'Trail Effect';
      case BattlePassRewardType.powerUp:
        return 'Power-Up';
      case BattlePassRewardType.tournamentEntry:
        return 'Tournament Entry';
      case BattlePassRewardType.title:
        return 'Player Title';
      case BattlePassRewardType.avatar:
        return 'Avatar';
      case BattlePassRewardType.special:
        return 'Special Reward';
    }
  }

  String get icon {
    switch (this) {
      case BattlePassRewardType.xp:
        return '⭐';
      case BattlePassRewardType.coins:
        return '🪙';
      case BattlePassRewardType.theme:
        return '🎨';
      case BattlePassRewardType.skin:
        return '🐍';
      case BattlePassRewardType.trail:
        return '✨';
      case BattlePassRewardType.powerUp:
        return '⚡';
      case BattlePassRewardType.tournamentEntry:
        return '🏆';
      case BattlePassRewardType.title:
        return '👑';
      case BattlePassRewardType.avatar:
        return '🖼️';
      case BattlePassRewardType.special:
        return '🎁';
    }
  }
}

enum BattlePassTier {
  free,
  premium;

  String get displayName {
    switch (this) {
      case BattlePassTier.free:
        return 'Free';
      case BattlePassTier.premium:
        return 'Premium';
    }
  }

  Color get color {
    switch (this) {
      case BattlePassTier.free:
        return Colors.grey;
      case BattlePassTier.premium:
        return Colors.amber;
    }
  }
}

class BattlePassReward {
  final String id;
  final String name;
  final String description;
  final BattlePassRewardType type;
  final BattlePassTier tier;
  final int quantity;
  final String? itemId; // For specific items like skins, themes
  final String icon;
  final Color color;
  final bool isSpecial; // Highlighted rewards

  const BattlePassReward({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.tier,
    this.quantity = 1,
    this.itemId,
    String? icon,
    Color? color,
    this.isSpecial = false,
  }) : icon = icon ?? '🎁',
       color = color ?? Colors.blue;

  bool get isPremium => tier == BattlePassTier.premium;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'tier': tier.name,
      'quantity': quantity,
      'item_id': itemId,
      'icon': icon,
      'color': color.toARGB32(),
      'is_special': isSpecial,
    };
  }

  factory BattlePassReward.fromJson(Map<String, dynamic> json) {
    return BattlePassReward(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Reward',
      description: json['description'] ?? '',
      type: BattlePassRewardType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => BattlePassRewardType.xp,
      ),
      tier: BattlePassTier.values.firstWhere(
        (t) => t.name == json['tier'],
        orElse: () => BattlePassTier.free,
      ),
      quantity: json['quantity'] ?? 1,
      itemId: json['item_id'],
      icon: json['icon'] ?? '🎁',
      // Tolerate ARGB-int OR "#RRGGBB"/"#AARRGGBB" hex string — backend
      // generator emits int, but season templates / legacy data may pass hex.
      color: BattlePassSeason._parseColor(json['color'], const Color(0xFF2196F3)),
      isSpecial: json['is_special'] ?? false,
    );
  }
}

class BattlePassLevel {
  final int level;
  final int xpRequired;
  final BattlePassReward? freeReward;
  final BattlePassReward? premiumReward;
  final bool isMilestone; // Every 10th level is a milestone with better rewards

  const BattlePassLevel({
    required this.level,
    required this.xpRequired,
    this.freeReward,
    this.premiumReward,
    this.isMilestone = false,
  });

  bool get hasRewards => freeReward != null || premiumReward != null;

  int get totalXpRequired {
    // Cumulative sum of (100 + i*50) for i in 0..(level-1)
    // = level*100 + 50*(0+1+...+(level-1)) = level*100 + 25*level*(level-1)
    return (level * 100) + (25 * level * (level - 1));
  }

  Map<String, dynamic> toJson() {
    return {
      'level': level,
      'xp_required': xpRequired,
      'free_reward': freeReward?.toJson(),
      'premium_reward': premiumReward?.toJson(),
      'is_milestone': isMilestone,
    };
  }

  factory BattlePassLevel.fromJson(Map<String, dynamic> json) {
    return BattlePassLevel(
      level: json['level'] ?? 0,
      xpRequired: json['xp_required'] ?? 100,
      freeReward: json['free_reward'] != null
          ? BattlePassReward.fromJson(json['free_reward'])
          : null,
      premiumReward: json['premium_reward'] != null
          ? BattlePassReward.fromJson(json['premium_reward'])
          : null,
      isMilestone: json['is_milestone'] ?? false,
    );
  }
}

class BattlePassSeason {
  final String id;
  final String name;
  final String description;
  final String theme;
  final DateTime startDate;
  final DateTime endDate;
  final List<BattlePassLevel> levels;
  final double price;
  final String bannerImage;
  final Color themeColor;
  final Map<String, dynamic> metadata;

  const BattlePassSeason({
    required this.id,
    required this.name,
    required this.description,
    required this.theme,
    required this.startDate,
    required this.endDate,
    required this.levels,
    required this.price,
    this.bannerImage = '',
    this.themeColor = Colors.purple,
    this.metadata = const {},
  });

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startDate) && now.isBefore(endDate);
  }

  bool get hasEnded => DateTime.now().isAfter(endDate);
  bool get hasStarted => DateTime.now().isAfter(startDate);

  Duration get timeRemaining {
    if (hasEnded) return Duration.zero;
    return endDate.difference(DateTime.now());
  }

  int get daysRemaining => timeRemaining.inDays;
  int get maxLevel => levels.length;

  BattlePassLevel? getLevelData(int level) {
    if (level < 1 || level > levels.length) return null;
    return levels[level - 1];
  }

  int getXpForLevel(int level) {
    final levelData = getLevelData(level);
    return levelData?.xpRequired ?? 0;
  }

  int getTotalXpForLevel(int level) {
    int totalXp = 0;
    for (int i = 1; i <= level && i <= levels.length; i++) {
      totalXp += getXpForLevel(i);
    }
    return totalXp;
  }

  int getLevelFromXp(int totalXp) {
    int currentLevel = 1;
    int xpAccumulated = 0;

    for (int i = 1; i <= levels.length; i++) {
      xpAccumulated += getXpForLevel(i);
      if (totalXp >= xpAccumulated) {
        currentLevel = i + 1;
      } else {
        break;
      }
    }

    return currentLevel.clamp(1, maxLevel);
  }

  List<BattlePassReward> getUnlockedRewards(int currentLevel, bool hasPremium) {
    final rewards = <BattlePassReward>[];

    for (int i = 1; i <= currentLevel && i <= levels.length; i++) {
      final levelData = levels[i - 1];

      // Add free rewards
      if (levelData.freeReward != null) {
        rewards.add(levelData.freeReward!);
      }

      // Add premium rewards if user has premium
      if (hasPremium && levelData.premiumReward != null) {
        rewards.add(levelData.premiumReward!);
      }
    }

    return rewards;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'theme': theme,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'levels': levels.map((l) => l.toJson()).toList(),
      'price': price,
      'banner_image': bannerImage,
      'theme_color': themeColor.toARGB32(),
      'metadata': metadata,
    };
  }

  factory BattlePassSeason.fromJson(Map<String, dynamic> json) {
    return BattlePassSeason(
      id: json['id'] ?? 'unknown',
      name: json['name'] ?? 'Season',
      description: json['description'] ?? '',
      theme: json['theme'] ?? 'default',
      startDate: DateTime.tryParse(json['start_date'] ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(json['end_date'] ?? json['endDate'] ?? '') ??
          DateTime.now().add(const Duration(days: 60)),
      levels: json['levels'] != null
          ? (json['levels'] as List)
              .map((l) => BattlePassLevel.fromJson(l as Map<String, dynamic>))
              .toList()
          : [],
      price: json['price']?.toDouble() ?? 9.99,
      bannerImage: json['banner_image'] ?? '',
      // Backend serializes ThemeColor as a "#AARRGGBB" hex string (from the
      // BattlePassSeason entity column); legacy / sample seasons may pass an
      // already-packed ARGB int. Tolerate either.
      themeColor: _parseColor(json['theme_color'], const Color(0xFF9C27B0)),
      metadata: json['metadata'] ?? {},
    );
  }

  static Color _parseColor(dynamic raw, Color fallback) {
    if (raw == null) return fallback;
    if (raw is int) return Color(raw);
    if (raw is String && raw.isNotEmpty) {
      var s = raw.startsWith('#') ? raw.substring(1) : raw;
      // "RRGGBB" → assume opaque alpha.
      if (s.length == 6) s = 'FF$s';
      final parsed = int.tryParse(s, radix: 16);
      if (parsed != null) return Color(parsed);
    }
    return fallback;
  }

  // Create a sample season for testing/demo
  static BattlePassSeason createSampleSeason() {
    final now = DateTime.now();
    final startDate = now.subtract(const Duration(days: 5));
    final endDate = now.add(const Duration(days: 60));

    final levels = <BattlePassLevel>[];

    for (int i = 1; i <= 100; i++) {
      final isMilestone = i % 10 == 0;
      final xpRequired = 100 + ((i - 1) * 50); // 0-indexed: level 1→100, level 2→150, etc.

      BattlePassReward? freeReward;
      BattlePassReward? premiumReward;

      // Create rewards based on level
      if (i % 5 == 0) {
        // Free rewards every 5 levels
        final freeType = _getRewardTypeForLevel(i, false);
        final freeQty = _getQuantityForLevel(i, false);
        freeReward = BattlePassReward(
          id: 'free_$i',
          name: _getRewardName(i, freeType, false, freeQty),
          description: _getRewardDescription(freeType, false),
          type: freeType,
          tier: BattlePassTier.free,
          quantity: freeQty,
          icon: freeType.icon,
          itemId: _getItemIdForReward(i, freeType, false),
        );
      }

      if (i % 3 == 0) {
        // Premium rewards every 3 levels
        final premType = _getRewardTypeForLevel(i, true);
        final premQty = _getQuantityForLevel(i, true);
        premiumReward = BattlePassReward(
          id: 'premium_$i',
          name: _getRewardName(i, premType, true, premQty),
          description: _getRewardDescription(premType, true),
          type: premType,
          tier: BattlePassTier.premium,
          quantity: premQty,
          isSpecial: isMilestone,
          icon: premType.icon,
          color: Colors.amber,
          itemId: _getItemIdForReward(i, premType, true),
        );
      }

      levels.add(
        BattlePassLevel(
          level: i,
          xpRequired: xpRequired,
          freeReward: freeReward,
          premiumReward: premiumReward,
          isMilestone: isMilestone,
        ),
      );
    }

    return BattlePassSeason(
      id: 'season_1',
      name: 'Cosmic Serpent Season',
      description: 'Explore the cosmos with exclusive space-themed rewards',
      theme: 'cosmic',
      startDate: startDate,
      endDate: endDate,
      levels: levels,
      price: 9.99,
      bannerImage: 'assets/images/battle_pass_cosmic_banner.png',
      themeColor: const Color(0xFF4B0082),
      metadata: {
        'featured_skins': ['galaxy', 'cosmic', 'crystal'],
        'featured_themes': ['space', 'cyberpunk'],
        'special_events': ['cosmic_tournament', 'starlight_challenge'],
      },
    );
  }

  static BattlePassRewardType _getRewardTypeForLevel(
    int level,
    bool isPremium,
  ) {
    if (level % 50 == 0) return BattlePassRewardType.special;
    if (level % 25 == 0) {
      return isPremium ? BattlePassRewardType.skin : BattlePassRewardType.title;
    }
    if (level % 20 == 0) return BattlePassRewardType.theme;
    if (level % 15 == 0) return BattlePassRewardType.trail;
    if (level % 10 == 0) {
      return isPremium
          ? BattlePassRewardType.powerUp
          : BattlePassRewardType.tournamentEntry;
    }
    if (level % 7 == 0) return BattlePassRewardType.coins;
    return BattlePassRewardType.xp;
  }

  static int _getQuantityForLevel(int level, bool isPremium) {
    if (level % 50 == 0) return 1; // Special rewards
    if (level % 25 == 0) return 1; // Skins/themes
    if (level % 10 == 0) return isPremium ? 3 : 1; // Milestone rewards
    if (level % 5 == 0) return isPremium ? 100 : 50; // Coins
    return isPremium ? 25 : 15; // XP
  }

  static const _freeRewardNames = <BattlePassRewardType, List<String>>{
    BattlePassRewardType.xp: ['XP Boost', 'Star Dust', 'Energy Pack'],
    BattlePassRewardType.coins: ['50 Coins', '75 Coins', '100 Coins'],
    BattlePassRewardType.tournamentEntry: ['Bronze Entry', 'Silver Entry'],
    BattlePassRewardType.title: ['Stargazer', 'Voyager'],
    BattlePassRewardType.theme: ['Nebula Theme'],
    BattlePassRewardType.trail: ['Stardust Trail'],
    BattlePassRewardType.special: ['Legendary Crate'],
  };

  static const _premiumRewardNames = <BattlePassRewardType, List<String>>{
    BattlePassRewardType.xp: ['Mega XP', 'Cosmic Charge', 'Nova Burst'],
    BattlePassRewardType.coins: ['200 Coins', '350 Coins', '500 Coins'],
    BattlePassRewardType.skin: ['Galaxy Skin', 'Crystal Serpent'],
    BattlePassRewardType.trail: ['Neon Trail', 'Plasma Wake', 'Cosmic Aura'],
    BattlePassRewardType.theme: ['Cyberpunk Theme', 'Crystal Theme'],
    BattlePassRewardType.powerUp: ['Speed Boost', 'Score Shield', 'Ghost Mode'],
    BattlePassRewardType.special: ['Season Trophy', 'Cosmic Crown'],
    BattlePassRewardType.title: ['Cosmic Legend', 'Star Commander'],
  };

  static String _getRewardName(
    int level,
    BattlePassRewardType type,
    bool isPremium,
    int quantity,
  ) {
    final names = isPremium
        ? _premiumRewardNames[type]
        : _freeRewardNames[type];
    if (names != null && names.isNotEmpty) {
      return names[(level ~/ 5) % names.length];
    }
    // Fallback: use type display name with quantity
    if (quantity > 1) return '${type.displayName} x$quantity';
    return type.displayName;
  }

  static String _getRewardDescription(BattlePassRewardType type, bool isPremium) {
    final prefix = isPremium ? 'Exclusive premium' : 'Free';
    return '$prefix ${type.displayName.toLowerCase()} reward';
  }

  /// Maps cosmetic reward types to actual item IDs from the catalog.
  /// Returns null for non-cosmetic rewards (coins, XP, etc.) that don't need
  /// an itemId to be claimed.
  static String? _getItemIdForReward(
    int level,
    BattlePassRewardType type,
    bool isPremium,
  ) {
    switch (type) {
      case BattlePassRewardType.skin:
        const skins = ['galaxy', 'cosmic', 'crystal', 'golden', 'rainbow'];
        return skins[(level ~/ 25) % skins.length];
      case BattlePassRewardType.trail:
        const trails = [
          'trail_cosmic', 'trail_neon', 'trail_crystal',
          'trail_particle', 'trail_rainbow',
        ];
        return trails[(level ~/ 15) % trails.length];
      case BattlePassRewardType.theme:
        const themes = ['space', 'cyberpunk', 'crystal', 'ocean'];
        return themes[(level ~/ 20) % themes.length];
      case BattlePassRewardType.powerUp:
        const powerUps = ['speed_boost', 'score_shield', 'ghost_mode'];
        return powerUps[(level ~/ 10) % powerUps.length];
      default:
        return null; // XP, coins, titles, tournament entries, specials
    }
  }
}

class UserBattlePass {
  final String userId;
  final String seasonId;
  final bool hasPremium;
  final int currentLevel;
  final int currentXp;
  final DateTime purchaseDate;
  final List<String> claimedRewards;
  final Map<String, dynamic> progress;

  const UserBattlePass({
    required this.userId,
    required this.seasonId,
    required this.hasPremium,
    required this.currentLevel,
    required this.currentXp,
    required this.purchaseDate,
    this.claimedRewards = const [],
    this.progress = const {},
  });

  bool isRewardClaimed(String rewardId) {
    return claimedRewards.contains(rewardId);
  }

  int getXpForNextLevel(BattlePassSeason season) {
    if (currentLevel >= season.maxLevel) return 0;
    final nextLevelData = season.getLevelData(currentLevel + 1);
    return nextLevelData?.xpRequired ?? 0;
  }

  double getLevelProgress(BattlePassSeason season) {
    final xpForNext = getXpForNextLevel(season);
    if (xpForNext == 0) return 1.0;

    final totalXpForCurrentLevel = season.getTotalXpForLevel(currentLevel);
    final xpIntoCurrentLevel = currentXp - totalXpForCurrentLevel;
    return (xpIntoCurrentLevel / xpForNext).clamp(0.0, 1.0);
  }

  UserBattlePass copyWith({
    bool? hasPremium,
    int? currentLevel,
    int? currentXp,
    List<String>? claimedRewards,
    Map<String, dynamic>? progress,
  }) {
    return UserBattlePass(
      userId: userId,
      seasonId: seasonId,
      hasPremium: hasPremium ?? this.hasPremium,
      currentLevel: currentLevel ?? this.currentLevel,
      currentXp: currentXp ?? this.currentXp,
      purchaseDate: purchaseDate,
      claimedRewards: claimedRewards ?? this.claimedRewards,
      progress: progress ?? this.progress,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'season_id': seasonId,
      'has_premium': hasPremium,
      'current_level': currentLevel,
      'current_xp': currentXp,
      'purchase_date': purchaseDate.toIso8601String(),
      'claimed_rewards': claimedRewards,
      'progress': progress,
    };
  }

  factory UserBattlePass.fromJson(Map<String, dynamic> json) {
    return UserBattlePass(
      userId: json['user_id'],
      seasonId: json['season_id'],
      hasPremium: json['has_premium'] ?? false,
      currentLevel: json['current_level'] ?? 1,
      currentXp: json['current_xp'] ?? 0,
      purchaseDate: DateTime.parse(json['purchase_date']),
      claimedRewards: List<String>.from(json['claimed_rewards'] ?? []),
      progress: json['progress'] ?? {},
    );
  }
}

// XP sources and amounts
class BattlePassXpSource {
  static const Map<String, int> xpAmounts = {
    'game_completed': 5,
    'score_milestone_100': 3,
    'score_milestone_500': 10,
    'score_milestone_1000': 20,
    'daily_game': 15,
    'achievement_unlocked_common': 8,
    'achievement_unlocked_rare': 15,
    'achievement_unlocked_epic': 30,
    'achievement_unlocked_legendary': 60,
    'multiplayer_win': 20,
    'multiplayer_participation': 8,
    'tournament_participation': 35,
    'tournament_win': 75,
    'power_up_collected': 1,
    'survival_60s': 10,
    'survival_300s': 35,
    'daily_challenge': 20,
    'weekly_challenge': 50,
  };

  static int getXpForAction(String action, [int multiplier = 1]) {
    return (xpAmounts[action] ?? 0) * multiplier;
  }
}
