import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart'
    show
        ChallengeDifficulty,
        kLegacyDirectiveCopy,
        formatDirectiveCount,
        directiveModeName;
import 'package:cosmo_strike_flutter_app/utils/constants.dart' show GameMode;

enum WeeklyQuestType {
  score,
  enemiesKilled,
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
      case WeeklyQuestType.enemiesKilled:
        return 'EnemiesKilled';
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
      case 'enemieskilled':
      case 'enemies_killed':
      // Legacy wire/storage name from the snake era.
      case 'foodeaten':
        return WeeklyQuestType.enemiesKilled;
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
      requiredGameMode: _normalizeMode(
          (json['required_game_mode'] ?? json['requiredGameMode']) as String?),
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

/// Rewrites a legacy mode id (`classic`, `perfectGame`…) to the 3.2 wire id.
String? _normalizeMode(String? raw) =>
    raw == null ? null : GameMode.normalizeWire(raw);

extension WeeklyQuestCopy on WeeklyQuest {
  bool get _legacyCopy =>
      kLegacyDirectiveCopy.hasMatch(title) ||
      kLegacyDirectiveCopy.hasMatch(description);

  /// Title safe to show: server text unless it still uses legacy wording
  /// (replaced by copy generated from type + target).
  String get displayTitle => _legacyCopy ? _generatedTitle : title;

  /// Description safe to show (see [displayTitle]).
  String get displayDescription =>
      _legacyCopy ? _generatedDescription : description;

  String get _generatedTitle {
    final n = formatDirectiveCount(targetValue);
    switch (type) {
      case WeeklyQuestType.score:
        return 'Score $n';
      case WeeklyQuestType.enemiesKilled:
        return 'Destroy $n hostiles';
      case WeeklyQuestType.gamesPlayed:
        return 'Fly $n runs';
      case WeeklyQuestType.survival:
        return 'Hold for $n s';
      case WeeklyQuestType.gameMode:
        final mode = directiveModeName(requiredGameMode);
        return mode == null ? 'Fly $n runs' : 'Fly $n $mode runs';
      case WeeklyQuestType.tournamentParticipation:
        return targetValue == 1 ? 'Enter a Sector Cup' : 'Enter $n Sector Cups';
      case WeeklyQuestType.dailyChallengesCompleted:
        return 'Complete $n Daily Directives';
      case WeeklyQuestType.battlePassTiersReached:
        return 'Reach Frontline tier $n';
    }
  }

  String get _generatedDescription {
    final n = formatDirectiveCount(targetValue);
    switch (type) {
      case WeeklyQuestType.score:
        return 'Score $n points in a single run this week.';
      case WeeklyQuestType.enemiesKilled:
        return 'Destroy $n hostiles this week.';
      case WeeklyQuestType.gamesPlayed:
        return 'Launch and finish $n runs this week.';
      case WeeklyQuestType.survival:
        return 'Stay in the fight for $n seconds in a single run.';
      case WeeklyQuestType.gameMode:
        final mode = directiveModeName(requiredGameMode);
        return mode == null
            ? 'Complete $n runs in any mode this week.'
            : 'Complete $n runs in $mode this week.';
      case WeeklyQuestType.tournamentParticipation:
        return 'Fly a scored run in $n Sector Cups this week.';
      case WeeklyQuestType.dailyChallengesCompleted:
        return 'Clear $n Daily Directives this week.';
      case WeeklyQuestType.battlePassTiersReached:
        return 'Climb to Frontline tier $n this season.';
    }
  }
}

