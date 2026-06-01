import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart' show ChallengeDifficulty;

enum WeeklyQuestType {
  score,
  foodEaten,
  gamesPlayed,
  survival,
  gameMode,
  tournamentParticipation,
  dailyChallengesCompleted,
  battlePassTiersReached;

  /// Casing the backend's MediatR validator accepts (string-parsed enum).
  String get apiValue {
    switch (this) {
      case WeeklyQuestType.score:
        return 'Score';
      case WeeklyQuestType.foodEaten:
        return 'FoodEaten';
      case WeeklyQuestType.gamesPlayed:
        return 'GamesPlayed';
      case WeeklyQuestType.survival:
        return 'Survival';
      case WeeklyQuestType.gameMode:
        return 'GameMode';
      case WeeklyQuestType.tournamentParticipation:
        return 'TournamentParticipation';
      case WeeklyQuestType.dailyChallengesCompleted:
        return 'DailyChallengesCompleted';
      case WeeklyQuestType.battlePassTiersReached:
        return 'BattlePassTiersReached';
    }
  }

  static WeeklyQuestType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'score':
        return WeeklyQuestType.score;
      case 'foodeaten':
        return WeeklyQuestType.foodEaten;
      case 'gamesplayed':
        return WeeklyQuestType.gamesPlayed;
      case 'survival':
        return WeeklyQuestType.survival;
      case 'gamemode':
        return WeeklyQuestType.gameMode;
      case 'tournamentparticipation':
        return WeeklyQuestType.tournamentParticipation;
      case 'dailychallengescompleted':
        return WeeklyQuestType.dailyChallengesCompleted;
      case 'battlepasstiersreached':
        return WeeklyQuestType.battlePassTiersReached;
      default:
        return WeeklyQuestType.score;
    }
  }
}

class WeeklyQuest {
  final String id;
  final DateTime weekStartDate;
  final WeeklyQuestType type;
  final ChallengeDifficulty difficulty;
  final String title;
  final String description;
  final int targetValue;
  final int currentProgress;
  final bool isCompleted;
  final bool claimedReward;
  final int coinReward;
  final int battlePassXpReward;
  final String? requiredGameMode;
  final DateTime? completedAt;

  const WeeklyQuest({
    required this.id,
    required this.weekStartDate,
    required this.type,
    required this.difficulty,
    required this.title,
    required this.description,
    required this.targetValue,
    this.currentProgress = 0,
    this.isCompleted = false,
    this.claimedReward = false,
    required this.coinReward,
    required this.battlePassXpReward,
    this.requiredGameMode,
    this.completedAt,
  });

  double get progressPercentage {
    if (targetValue <= 0) return 0;
    return (currentProgress / targetValue).clamp(0.0, 1.0);
  }

  bool get canClaim => isCompleted && !claimedReward;

  factory WeeklyQuest.fromJson(Map<String, dynamic> json) {
    return WeeklyQuest(
      id: json['id'] as String,
      weekStartDate: DateTime.parse(
          (json['week_start_date'] ?? json['weekStartDate']) as String),
      type: WeeklyQuestType.fromString(json['type'] as String),
      difficulty: ChallengeDifficulty.fromString(json['difficulty'] as String),
      title: json['title'] as String,
      description: json['description'] as String,
      targetValue: (json['target_value'] ?? json['targetValue']) as int,
      currentProgress:
          (json['current_progress'] ?? json['currentProgress'] ?? 0) as int,
      isCompleted:
          (json['is_completed'] ?? json['isCompleted'] ?? false) as bool,
      claimedReward:
          (json['claimed_reward'] ?? json['claimedReward'] ?? false) as bool,
      coinReward: (json['coin_reward'] ?? json['coinReward']) as int,
      battlePassXpReward:
          (json['battle_pass_xp_reward'] ?? json['battlePassXpReward']) as int,
      requiredGameMode:
          (json['required_game_mode'] ?? json['requiredGameMode']) as String?,
      completedAt: (json['completed_at'] ?? json['completedAt']) != null
          ? DateTime.parse(
              (json['completed_at'] ?? json['completedAt']) as String)
          : null,
    );
  }

  WeeklyQuest copyWith({
    int? currentProgress,
    bool? isCompleted,
    bool? claimedReward,
    DateTime? completedAt,
  }) {
    return WeeklyQuest(
      id: id,
      weekStartDate: weekStartDate,
      type: type,
      difficulty: difficulty,
      title: title,
      description: description,
      targetValue: targetValue,
      currentProgress: currentProgress ?? this.currentProgress,
      isCompleted: isCompleted ?? this.isCompleted,
      claimedReward: claimedReward ?? this.claimedReward,
      coinReward: coinReward,
      battlePassXpReward: battlePassXpReward,
      requiredGameMode: requiredGameMode,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
