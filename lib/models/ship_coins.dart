import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

enum CoinEarningSource {
  gameCompleted,

  /// Persisted as 'foodEaten' (pre-3.2 wire value) — see [wireName].
  enemyDestroyed,
  scoreMilestone,
  dailyChallenge,
  achievementUnlocked,
  tournamentReward,
  dailyLogin,
  watchedAd,
  levelUp,
  perfectGame,
  longSurvival,
  multiplayer,
  battlePassReward,
  purchase;

  String get displayName {
    switch (this) {
      case CoinEarningSource.gameCompleted:
        return 'Sortie Complete';
      case CoinEarningSource.enemyDestroyed:
        return 'Enemy Destroyed';
      case CoinEarningSource.scoreMilestone:
        return 'Score Milestone';
      case CoinEarningSource.dailyChallenge:
        return 'Daily Directive';
      case CoinEarningSource.achievementUnlocked:
        return 'Commendation';
      case CoinEarningSource.tournamentReward:
        return 'Sector Cup Reward';
      case CoinEarningSource.dailyLogin:
        return 'Supply Drop';
      case CoinEarningSource.watchedAd:
        return 'Watched Ad';
      case CoinEarningSource.levelUp:
        return 'Rank Up';
      case CoinEarningSource.perfectGame:
        return 'Flawless Run';
      case CoinEarningSource.longSurvival:
        return 'Long Haul';
      case CoinEarningSource.multiplayer:
        return 'Multiplayer';
      case CoinEarningSource.battlePassReward:
        return 'Frontline Reward';
      case CoinEarningSource.purchase:
        return 'Purchased';
    }
  }

  IconData get icon {
    switch (this) {
      case CoinEarningSource.gameCompleted:
        return Symbols.rocket_launch_rounded;
      case CoinEarningSource.enemyDestroyed:
        return Symbols.target_rounded;
      case CoinEarningSource.scoreMilestone:
        return Symbols.flag_rounded;
      case CoinEarningSource.dailyChallenge:
        return Symbols.assignment_rounded;
      case CoinEarningSource.achievementUnlocked:
        return Symbols.military_tech_rounded;
      case CoinEarningSource.tournamentReward:
        return Symbols.emoji_events_rounded;
      case CoinEarningSource.dailyLogin:
        return Symbols.inventory_2_rounded;
      case CoinEarningSource.watchedAd:
        return Symbols.play_circle_rounded;
      case CoinEarningSource.levelUp:
        return Symbols.keyboard_double_arrow_up_rounded;
      case CoinEarningSource.perfectGame:
        return Symbols.verified_rounded;
      case CoinEarningSource.longSurvival:
        return Symbols.timer_rounded;
      case CoinEarningSource.multiplayer:
        return Symbols.group_rounded;
      case CoinEarningSource.battlePassReward:
        return Symbols.workspace_premium_rounded;
      case CoinEarningSource.purchase:
        return Symbols.paid_rounded;
    }
  }

  /// Persisted / synced identifier. Stable across the 3.2 rename:
  /// [enemyDestroyed] keeps its pre-3.2 wire value 'foodEaten' so existing
  /// Drift rows, daily-cap lookups and backend transactions still match.
  String get wireName =>
      this == CoinEarningSource.enemyDestroyed ? 'foodEaten' : name;

  /// Parse a [wireName] (or the enum identifier); null when unknown.
  static CoinEarningSource? fromWire(String? raw) {
    if (raw == null) return null;
    for (final s in CoinEarningSource.values) {
      if (s.wireName == raw || s.name == raw) return s;
    }
    return null;
  }

  int getBaseAmount() {
    switch (this) {
      case CoinEarningSource.gameCompleted:
        return 1;
      case CoinEarningSource.enemyDestroyed:
        return 0; // Removed to reduce economy inflation
      case CoinEarningSource.scoreMilestone:
        return 2;
      case CoinEarningSource.dailyChallenge:
        return 10;
      case CoinEarningSource.achievementUnlocked:
        return 8;
      case CoinEarningSource.tournamentReward:
        return 30;
      case CoinEarningSource.dailyLogin:
        return 5;
      case CoinEarningSource.watchedAd:
        return 8;
      case CoinEarningSource.levelUp:
        return 3;
      case CoinEarningSource.perfectGame:
        return 5;
      case CoinEarningSource.longSurvival:
        return 3;
      case CoinEarningSource.multiplayer:
        return 3;
      case CoinEarningSource.battlePassReward:
        return 8;
      case CoinEarningSource.purchase:
        return 0; // Variable based on purchase
    }
  }
}

enum CoinSpendingCategory {
  powerUps,
  cosmetics,
  boosts,
  tournamentEntries,
  battlePassTiers,
  extraLives,
  themes;

  String get displayName {
    switch (this) {
      case CoinSpendingCategory.powerUps:
        return 'Tactical Gear';
      case CoinSpendingCategory.cosmetics:
        return 'Cosmetics';
      case CoinSpendingCategory.boosts:
        return 'Boosts';
      case CoinSpendingCategory.tournamentEntries:
        return 'Cup Passes';
      case CoinSpendingCategory.battlePassTiers:
        return 'Frontline Tiers';
      case CoinSpendingCategory.extraLives:
        return 'Revives';
      case CoinSpendingCategory.themes:
        return 'Sectors';
    }
  }

  IconData get icon {
    switch (this) {
      case CoinSpendingCategory.powerUps:
        return Symbols.bolt_rounded;
      case CoinSpendingCategory.cosmetics:
        return Symbols.rocket_rounded;
      case CoinSpendingCategory.boosts:
        return Symbols.speed_rounded;
      case CoinSpendingCategory.tournamentEntries:
        return Symbols.confirmation_number_rounded;
      case CoinSpendingCategory.battlePassTiers:
        return Symbols.trending_up_rounded;
      case CoinSpendingCategory.extraLives:
        return Symbols.favorite_rounded;
      case CoinSpendingCategory.themes:
        return Symbols.public_rounded;
    }
  }
}

class CoinTransaction {
  final String id;
  final int amount;
  final bool isEarned; // true for earning, false for spending
  final CoinEarningSource? earningSource;
  final CoinSpendingCategory? spendingCategory;
  final String? itemName;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  const CoinTransaction({
    required this.id,
    required this.amount,
    required this.isEarned,
    this.earningSource,
    this.spendingCategory,
    this.itemName,
    required this.timestamp,
    this.metadata = const {},
  });

  String get displayAmount => isEarned ? '+$amount' : '-$amount';

  String get description {
    if (isEarned) {
      final source = earningSource?.displayName ?? 'Unknown';
      return itemName != null ? '$source: $itemName' : source;
    } else {
      final category = spendingCategory?.displayName ?? 'Unknown';
      return itemName != null ? '$category: $itemName' : category;
    }
  }

  IconData get icon {
    if (isEarned) {
      return earningSource?.icon ?? Symbols.paid_rounded;
    } else {
      return spendingCategory?.icon ?? Symbols.shopping_bag_rounded;
    }
  }

  Color get amountColor => isEarned ? Colors.green : Colors.red;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'is_earned': isEarned,
      'earning_source': earningSource?.wireName,
      'spending_category': spendingCategory?.name,
      'item_name': itemName,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory CoinTransaction.fromJson(Map<String, dynamic> json) {
    return CoinTransaction(
      id: json['id'],
      amount: json['amount'],
      isEarned: json['is_earned'],
      earningSource: json['earning_source'] != null
          ? (CoinEarningSource.fromWire(json['earning_source'] as String?) ??
              CoinEarningSource.gameCompleted)
          : null,
      spendingCategory: json['spending_category'] != null
          ? CoinSpendingCategory.values.firstWhere(
              (c) => c.name == json['spending_category'],
              orElse: () => CoinSpendingCategory.powerUps,
            )
          : null,
      itemName: json['item_name'],
      timestamp: DateTime.parse(json['timestamp']),
      metadata: json['metadata'] ?? {},
    );
  }
}

class DailyLoginBonus {
  final int day;
  final int coins;
  final String? bonusItem;
  final bool isCollected;
  final DateTime? collectedAt;

  const DailyLoginBonus({
    required this.day,
    required this.coins,
    this.bonusItem,
    required this.isCollected,
    this.collectedAt,
  });

  /// Get the current week number since epoch (2024-01-01)
  static int get currentWeekNumber {
    final today = DateTime.now();
    final daysSinceEpoch = today.difference(DateTime(2024, 1, 1)).inDays;
    return daysSinceEpoch ~/ 7;
  }

  /// Get the current day in the 7-day cycle (1-7)
  static int get currentStreakDay {
    final today = DateTime.now();
    final daysSinceEpoch = today.difference(DateTime(2024, 1, 1)).inDays;
    return (daysSinceEpoch % 7) + 1;
  }

  bool get isAvailable {
    // Check if it's the current day in the login streak
    if (day != currentStreakDay) return false;

    // If never collected, it's available
    if (!isCollected || collectedAt == null) return true;

    // Check if the bonus was collected in the current week
    // If collected in a previous week, it should be available again
    final collectedDaysSinceEpoch =
        collectedAt!.difference(DateTime(2024, 1, 1)).inDays;
    final collectedWeekNumber = collectedDaysSinceEpoch ~/ 7;

    // If collected in a different week, it's available
    return collectedWeekNumber != currentWeekNumber;
  }

  /// Check if this bonus was collected in the current week
  bool get wasCollectedThisWeek {
    if (!isCollected || collectedAt == null) return false;

    final collectedDaysSinceEpoch =
        collectedAt!.difference(DateTime(2024, 1, 1)).inDays;
    final collectedWeekNumber = collectedDaysSinceEpoch ~/ 7;

    return collectedWeekNumber == currentWeekNumber;
  }

  String get displayReward {
    final coinText = '$coins coins';
    return bonusItem != null ? '$coinText + $bonusItem' : coinText;
  }

  DailyLoginBonus copyWith({bool? isCollected, DateTime? collectedAt}) {
    return DailyLoginBonus(
      day: day,
      coins: coins,
      bonusItem: bonusItem,
      isCollected: isCollected ?? this.isCollected,
      collectedAt: collectedAt ?? this.collectedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day': day,
      'coins': coins,
      'bonus_item': bonusItem,
      'is_collected': isCollected,
      'collected_at': collectedAt?.toIso8601String(),
    };
  }

  factory DailyLoginBonus.fromJson(Map<String, dynamic> json) {
    return DailyLoginBonus(
      day: json['day'],
      coins: json['coins'],
      bonusItem: json['bonus_item'],
      isCollected: json['is_collected'] ?? false,
      collectedAt: json['collected_at'] != null
          ? DateTime.parse(json['collected_at'])
          : null,
    );
  }

  static List<DailyLoginBonus> getWeeklyBonuses() {
    return [
      const DailyLoginBonus(day: 1, coins: 2, isCollected: false),
      const DailyLoginBonus(day: 2, coins: 3, isCollected: false),
      const DailyLoginBonus(
        day: 3,
        coins: 4,
        bonusItem: 'Afterburner Gear',
        isCollected: false,
      ),
      const DailyLoginBonus(day: 4, coins: 5, isCollected: false),
      const DailyLoginBonus(
        day: 5,
        coins: 6,
        bonusItem: '2× XP Boost',
        isCollected: false,
      ),
      const DailyLoginBonus(day: 6, coins: 7, isCollected: false),
      const DailyLoginBonus(
        day: 7,
        coins: 10,
        bonusItem: 'Premium Sector (1 day)',
        isCollected: false,
      ),
    ];
  }
}

class CoinPurchaseOption {
  final String id;
  final String name;
  final int coins;
  final double price;
  final int bonusCoins;
  final String description;
  final bool isPopular;
  final bool isBestValue;

  const CoinPurchaseOption({
    required this.id,
    required this.name,
    required this.coins,
    required this.price,
    this.bonusCoins = 0,
    required this.description,
    this.isPopular = false,
    this.isBestValue = false,
  });

  int get totalCoins => coins + bonusCoins;
  double get coinsPerDollar => totalCoins / price;

  String get displayCoins =>
      bonusCoins > 0 ? '$coins + $bonusCoins bonus' : '$coins credits';

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'coins': coins,
      'price': price,
      'bonus_coins': bonusCoins,
      'description': description,
      'is_popular': isPopular,
      'is_best_value': isBestValue,
    };
  }

  factory CoinPurchaseOption.fromJson(Map<String, dynamic> json) {
    return CoinPurchaseOption(
      id: json['id'],
      name: json['name'],
      coins: json['coins'],
      price: json['price'].toDouble(),
      bonusCoins: json['bonus_coins'] ?? 0,
      description: json['description'],
      isPopular: json['is_popular'] ?? false,
      isBestValue: json['is_best_value'] ?? false,
    );
  }

  /// Credit Caches — IDs are the store product suffixes (`ProductIds`).
  static const List<CoinPurchaseOption> availableOptions = [
    CoinPurchaseOption(
      id: 'credits_cache',
      name: 'Credit Cache',
      coins: 120,
      price: 0.99,
      description: 'A small top-up for your next requisition',
    ),
    CoinPurchaseOption(
      id: 'credits_crate',
      name: 'Credit Crate',
      coins: 600,
      bonusCoins: 50,
      price: 4.99,
      description: 'A field crate with bonus credits',
      isPopular: true,
    ),
    CoinPurchaseOption(
      id: 'credits_vault',
      name: 'Credit Vault',
      coins: 1300,
      bonusCoins: 200,
      price: 9.99,
      description: 'Best rate for regular pilots',
      isBestValue: true,
    ),
    CoinPurchaseOption(
      id: 'credits_reserve',
      name: 'Fleet Reserve',
      coins: 2800,
      bonusCoins: 600,
      price: 19.99,
      description: 'A full fleet reserve with the biggest bonus',
    ),
  ];
}

class CoinBalance {
  final int total;
  final int earned;
  final int spent;
  final int purchased;
  final DateTime lastUpdated;

  const CoinBalance({
    required this.total,
    required this.earned,
    required this.spent,
    required this.purchased,
    required this.lastUpdated,
  });

  int get lifetime => earned + purchased;
  double get spendingRatio => lifetime > 0 ? spent / lifetime : 0.0;

  CoinBalance copyWith({
    int? total,
    int? earned,
    int? spent,
    int? purchased,
    DateTime? lastUpdated,
  }) {
    return CoinBalance(
      total: total ?? this.total,
      earned: earned ?? this.earned,
      spent: spent ?? this.spent,
      purchased: purchased ?? this.purchased,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'earned': earned,
      'spent': spent,
      'purchased': purchased,
      'last_updated': lastUpdated.toIso8601String(),
    };
  }

  factory CoinBalance.fromJson(Map<String, dynamic> json) {
    return CoinBalance(
      total: json['total'] ?? 0,
      earned: json['earned'] ?? 0,
      spent: json['spent'] ?? 0,
      purchased: json['purchased'] ?? 0,
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }

  static CoinBalance get initial => CoinBalance(
    total: 50, // Starting coins for new users
    earned: 50,
    spent: 0,
    purchased: 0,
    lastUpdated: DateTime.now(),
  );
}
