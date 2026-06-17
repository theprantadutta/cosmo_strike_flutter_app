import 'package:cosmo_strike_flutter_app/utils/logger.dart';

enum ChallengeType {
  score,
  foodEaten,
  gameMode,
  survival,
  gamesPlayed;

  /// Canonical wire value — the backend serializes its `ChallengeType` enum as
  /// snake_case (JsonStringEnumConverter(SnakeCaseLower)), so we mirror that
  /// exactly. `foodEaten` maps to the backend's `enemies_killed`.
  String get apiValue {
    switch (this) {
      case ChallengeType.score:
        return 'score';
      case ChallengeType.foodEaten:
        return 'enemies_killed';
      case ChallengeType.gameMode:
        return 'game_mode';
      case ChallengeType.survival:
        return 'survival';
      case ChallengeType.gamesPlayed:
        return 'games_played';
    }
  }

  /// Parse a backend (snake_case) or legacy (PascalCase / camelCase) type
  /// string. Normalizes by lowercasing and stripping separators so
  /// `enemies_killed`, `EnemiesKilled` and the legacy `FoodEaten` all resolve
  /// to [ChallengeType.foodEaten]. Returns null for an unrecognized value so
  /// the caller can log + skip instead of silently miscounting it as a score
  /// challenge.
  static ChallengeType? tryParse(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'[_\s-]'), '');
    switch (normalized) {
      case 'score':
        return ChallengeType.score;
      case 'enemieskilled':
      case 'foodeaten':
        return ChallengeType.foodEaten;
      case 'gamemode':
        return ChallengeType.gameMode;
      case 'survival':
        return ChallengeType.survival;
      case 'gamesplayed':
        return ChallengeType.gamesPlayed;
      default:
        return null;
    }
  }

  static ChallengeType fromString(String value) {
    final parsed = tryParse(value);
    if (parsed == null) {
      AppLogger.warning(
        'ChallengeType.fromString: unrecognized type "$value" — '
        'defaulting to score',
      );
      return ChallengeType.score;
    }
    return parsed;
  }
}

enum ChallengeDifficulty {
  easy,
  medium,
  hard;

  static ChallengeDifficulty fromString(String value) {
    switch (value.toLowerCase()) {
      case 'easy':
        return ChallengeDifficulty.easy;
      case 'medium':
        return ChallengeDifficulty.medium;
      case 'hard':
        return ChallengeDifficulty.hard;
      default:
        return ChallengeDifficulty.easy;
    }
  }

  String get displayName {
    switch (this) {
      case ChallengeDifficulty.easy:
        return 'Easy';
      case ChallengeDifficulty.medium:
        return 'Medium';
      case ChallengeDifficulty.hard:
        return 'Hard';
    }
  }
}

class DailyChallenge {
  final String id;
  final String title;
  final String description;
  final ChallengeType type;
  final ChallengeDifficulty difficulty;
  final int targetValue;
  final int currentProgress;
  final bool isCompleted;
  final int coinReward;
  final int xpReward;
  final String? requiredGameMode;
  final bool claimedReward;

  DailyChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.difficulty,
    required this.targetValue,
    this.currentProgress = 0,
    this.isCompleted = false,
    required this.coinReward,
    required this.xpReward,
    this.requiredGameMode,
    this.claimedReward = false,
  });

  double get progressPercentage {
    if (targetValue <= 0) return 0;
    return (currentProgress / targetValue).clamp(0.0, 1.0);
  }

  bool get canClaim => isCompleted && !claimedReward;

  factory DailyChallenge.fromJson(Map<String, dynamic> json) {
    // Strict on type: an unrecognized type would otherwise be silently
    // tracked as a score challenge (wrong completion metric). Throw so the
    // caller's parse loop skips this entry instead.
    final rawType = json['type'] as String;
    final parsedType = ChallengeType.tryParse(rawType);
    if (parsedType == null) {
      throw FormatException('Unknown challenge type: "$rawType"');
    }
    return DailyChallenge(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      type: parsedType,
      difficulty: ChallengeDifficulty.fromString(json['difficulty'] as String),
      targetValue: (json['target_value'] ?? json['targetValue']) as int,
      currentProgress:
          (json['current_progress'] ?? json['currentProgress'] ?? 0) as int,
      isCompleted:
          (json['is_completed'] ?? json['isCompleted'] ?? false) as bool,
      coinReward: (json['coin_reward'] ?? json['coinReward']) as int,
      xpReward: (json['xp_reward'] ?? json['xpReward']) as int,
      requiredGameMode:
          (json['required_game_mode'] ?? json['requiredGameMode']) as String?,
      claimedReward:
          (json['claimed_reward'] ?? json['claimedReward'] ?? false) as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type.apiValue,
      'difficulty': difficulty.name,
      'targetValue': targetValue,
      'currentProgress': currentProgress,
      'isCompleted': isCompleted,
      'coinReward': coinReward,
      'xpReward': xpReward,
      'requiredGameMode': requiredGameMode,
      'claimedReward': claimedReward,
    };
  }

  DailyChallenge copyWith({
    String? id,
    String? title,
    String? description,
    ChallengeType? type,
    ChallengeDifficulty? difficulty,
    int? targetValue,
    int? currentProgress,
    bool? isCompleted,
    int? coinReward,
    int? xpReward,
    String? requiredGameMode,
    bool? claimedReward,
  }) {
    return DailyChallenge(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      type: type ?? this.type,
      difficulty: difficulty ?? this.difficulty,
      targetValue: targetValue ?? this.targetValue,
      currentProgress: currentProgress ?? this.currentProgress,
      isCompleted: isCompleted ?? this.isCompleted,
      coinReward: coinReward ?? this.coinReward,
      xpReward: xpReward ?? this.xpReward,
      requiredGameMode: requiredGameMode ?? this.requiredGameMode,
      claimedReward: claimedReward ?? this.claimedReward,
    );
  }
}

class DailyChallengesResponse {
  final List<DailyChallenge> challenges;
  final int completedCount;
  final int totalCount;
  final bool allCompleted;
  final int bonusCoins;

  DailyChallengesResponse({
    required this.challenges,
    required this.completedCount,
    required this.totalCount,
    required this.allCompleted,
    required this.bonusCoins,
  });

  factory DailyChallengesResponse.fromJson(Map<String, dynamic> json) {
    return DailyChallengesResponse(
      challenges: (json['challenges'] as List<dynamic>)
          .map((c) => DailyChallenge.fromJson(c as Map<String, dynamic>))
          .toList(),
      completedCount:
          (json['completed_count'] ?? json['completedCount'] ?? 0) as int,
      totalCount: (json['total_count'] ?? json['totalCount'] ?? 0) as int,
      allCompleted:
          (json['all_completed'] ?? json['allCompleted'] ?? false) as bool,
      bonusCoins: (json['bonus_coins'] ?? json['bonusCoins'] ?? 0) as int,
    );
  }

  bool get hasUnclaimedRewards =>
      challenges.any((c) => c.isCompleted && !c.claimedReward);
}
