import 'package:flutter/material.dart';

enum CoinEarningSource {
  gameCompleted,
  foodEaten,
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
        return 'Game Completed';
      case CoinEarningSource.foodEaten:
        return 'Enemy Destroyed';
      case CoinEarningSource.scoreMilestone:
        return 'Score Milestone';
      case CoinEarningSource.dailyChallenge:
        return 'Daily Challenge';
      case CoinEarningSource.achievementUnlocked:
        return 'Achievement Unlocked';
      case CoinEarningSource.tournamentReward:
        return 'Tournament Reward';
      case CoinEarningSource.dailyLogin:
        return 'Daily Login';
      case CoinEarningSource.watchedAd:
        return 'Watched Ad';
      case CoinEarningSource.levelUp:
        return 'Level Up';
      case CoinEarningSource.perfectGame:
        return 'Perfect Game';
      case CoinEarningSource.longSurvival:
        return 'Long Survival';
      case CoinEarningSource.multiplayer:
        return 'Multiplayer';
      case CoinEarningSource.battlePassReward:
        return 'Battle Pass Reward';
      case CoinEarningSource.purchase:
        return 'Purchased';
    }
  }

  String get icon {
    switch (this) {
      case CoinEarningSource.gameCompleted:
        return '🎮';
      case CoinEarningSource.foodEaten:
        return '🍎';
      case CoinEarningSource.scoreMilestone:
        return '🎯';
      case CoinEarningSource.dailyChallenge:
        return '📅';
      case CoinEarningSource.achievementUnlocked:
        return '🏆';
      case CoinEarningSource.tournamentReward:
        return '👑';
      case CoinEarningSource.dailyLogin:
        return '📱';
      case CoinEarningSource.watchedAd:
        return '📺';
      case CoinEarningSource.levelUp:
        return '⬆️';
      case CoinEarningSource.perfectGame:
        return '💯';
      case CoinEarningSource.longSurvival:
        return '⏰';
      case CoinEarningSource.multiplayer:
        return '👥';
      case CoinEarningSource.battlePassReward:
        return '⚔️';
      case CoinEarningSource.purchase:
        return '💰';
    }
  }

  int getBaseAmount() {
    switch (this) {
      case CoinEarningSource.gameCompleted:
        return 1;
      case CoinEarningSource.foodEaten:
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
        return 'Power-ups';
      case CoinSpendingCategory.cosmetics:
        return 'Cosmetics';
      case CoinSpendingCategory.boosts:
        return 'Boosts';
      case CoinSpendingCategory.tournamentEntries:
        return 'Tournament Entries';
      case CoinSpendingCategory.battlePassTiers:
        return 'Battle Pass Tiers';
      case CoinSpendingCategory.extraLives:
        return 'Extra Lives';
      case CoinSpendingCategory.themes:
        return 'Themes';
    }
  }

  String get icon {
    switch (this) {
      case CoinSpendingCategory.powerUps:
        return '⚡';
      case CoinSpendingCategory.cosmetics:
        return '✨';
      case CoinSpendingCategory.boosts:
        return '🚀';
      case CoinSpendingCategory.tournamentEntries:
        return '🎫';
      case CoinSpendingCategory.battlePassTiers:
        return '📈';
      case CoinSpendingCategory.extraLives:
        return '❤️';
      case CoinSpendingCategory.themes:
        return '🎨';
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

  String get icon {
    if (isEarned) {
      return earningSource?.icon ?? '🪙';
    } else {
      return spendingCategory?.icon ?? '🛍️';
    }
  }

  Color get amountColor => isEarned ? Colors.green : Colors.red;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'is_earned': isEarned,
      'earning_source': earningSource?.name,
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
          ? CoinEarningSource.values.firstWhere(
              (s) => s.name == json['earning_source'],
              orElse: () => CoinEarningSource.gameCompleted,
            )
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
        bonusItem: 'Speed Boost Power-up',
        isCollected: false,
      ),
      const DailyLoginBonus(day: 4, coins: 5, isCollected: false),
      const DailyLoginBonus(
        day: 5,
        coins: 6,
        bonusItem: '2x XP Boost',
        isCollected: false,
      ),
      const DailyLoginBonus(day: 6, coins: 7, isCollected: false),
      const DailyLoginBonus(
        day: 7,
        coins: 10,
        bonusItem: 'Premium Theme (1 day)',
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
      bonusCoins > 0 ? '$coins + $bonusCoins bonus' : '$coins coins';

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

  static const List<CoinPurchaseOption> availableOptions = [
    CoinPurchaseOption(
      id: 'coin_pack_small',
      name: 'Starter Pack',
      coins: 100,
      price: 0.99,
      description: 'Perfect for trying out premium items',
    ),
    CoinPurchaseOption(
      id: 'coin_pack_medium',
      name: 'Value Pack',
      coins: 500,
      bonusCoins: 50,
      price: 4.99,
      description: 'Great value with bonus coins',
      isPopular: true,
    ),
    CoinPurchaseOption(
      id: 'coin_pack_large',
      name: 'Premium Pack',
      coins: 1200,
      bonusCoins: 200,
      price: 9.99,
      description: 'Best value for serious players',
      isBestValue: true,
    ),
    CoinPurchaseOption(
      id: 'coin_pack_mega',
      name: 'Ultimate Pack',
      coins: 2500,
      bonusCoins: 500,
      price: 19.99,
      description: 'Maximum coins with huge bonus',
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
