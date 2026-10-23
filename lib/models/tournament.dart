import 'dart:convert';

import 'package:cosmo_strike_flutter_app/utils/constants.dart' show GameMode;

enum TournamentType {
  daily,
  weekly,
  special;

  String get displayName {
    switch (this) {
      case TournamentType.daily:
        return 'Daily Cup';
      case TournamentType.weekly:
        return 'Weekly Cup';
      case TournamentType.special:
        return 'Championship';
    }
  }


  Duration get duration {
    switch (this) {
      case TournamentType.daily:
        return const Duration(days: 1);
      case TournamentType.weekly:
        return const Duration(days: 7);
      case TournamentType.special:
        return const Duration(days: 3);
    }
  }
}

enum TournamentStatus {
  upcoming,
  active,
  ended;

  String get displayName {
    switch (this) {
      case TournamentStatus.upcoming:
        return 'Upcoming';
      case TournamentStatus.active:
        return 'Active';
      case TournamentStatus.ended:
        return 'Ended';
    }
  }

  bool get canJoin => this == TournamentStatus.active;
  bool get canSubmitScore => this == TournamentStatus.active;
}

class TournamentReward {
  final String id;
  final String name;
  final String description;
  final String? iconUrl;
  final int coins;
  final List<String> badges;
  final String type; // 'achievement', 'badge', 'coins', 'title'

  const TournamentReward({
    required this.id,
    required this.name,
    required this.description,
    this.iconUrl,
    this.coins = 0,
    this.badges = const [],
    required this.type,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'iconUrl': iconUrl,
      'coins': coins,
      'badges': badges,
      'type': type,
    };
  }

  factory TournamentReward.fromJson(Map<String, dynamic> json) {
    return TournamentReward(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      iconUrl: json['iconUrl'],
      coins: json['coins'] ?? 0,
      badges: List<String>.from(json['badges'] ?? []),
      type: json['type'] ?? 'achievement',
    );
  }
}

class TournamentParticipant {
  final String userId;
  final String displayName;
  final String? photoUrl;
  final int highScore;
  final int attempts;
  final DateTime lastScoreDate;
  final DateTime joinedDate;
  final Map<String, dynamic> gameStats;

  const TournamentParticipant({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.highScore,
    required this.attempts,
    required this.lastScoreDate,
    required this.joinedDate,
    this.gameStats = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'highScore': highScore,
      'attempts': attempts,
      'lastScoreDate': lastScoreDate.toIso8601String(),
      'joinedDate': joinedDate.toIso8601String(),
      'gameStats': gameStats,
    };
  }

  factory TournamentParticipant.fromJson(Map<String, dynamic> json) {
    return TournamentParticipant(
      userId: json['userId'] ?? '',
      displayName: json['displayName'] ?? 'Unknown',
      photoUrl: json['photoUrl'],
      highScore: json['highScore'] ?? 0,
      attempts: json['attempts'] ?? 0,
      lastScoreDate: DateTime.parse(
        json['lastScoreDate'] ?? DateTime.now().toIso8601String(),
      ),
      joinedDate: DateTime.parse(
        json['joinedDate'] ?? DateTime.now().toIso8601String(),
      ),
      gameStats: Map<String, dynamic>.from(json['gameStats'] ?? {}),
    );
  }
}

class Tournament {
  final String id;
  final String name;
  final String description;
  final TournamentType type;
  final TournamentStatus status;
  final GameMode gameMode;
  final DateTime startDate;
  final DateTime endDate;
  final int maxParticipants;
  final int currentParticipants;
  final Map<int, TournamentReward> rewards; // rank -> reward
  final Map<String, dynamic> gameSettings;
  final Map<String, dynamic> rules;
  final String? imageUrl;
  final bool requiresEntry;
  final int entryCost;
  final List<TournamentParticipant> leaderboard;
  final DateTime? userLastAttempt;
  final int? userBestScore;
  final int? userAttempts;
  // Server-authoritative "did this user join the tournament" flag.
  // Backend (TournamentDto.IsJoined) sets this when the JoinTournament
  // command succeeded. Distinct from userBestScore/userAttempts which
  // only become non-null AFTER the user has played at least once.
  final bool isJoinedServer;

  const Tournament({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.status,
    required this.gameMode,
    required this.startDate,
    required this.endDate,
    this.maxParticipants = 1000,
    this.currentParticipants = 0,
    this.rewards = const {},
    this.gameSettings = const {},
    this.rules = const {},
    this.imageUrl,
    this.requiresEntry = false,
    this.entryCost = 0,
    this.leaderboard = const [],
    this.userLastAttempt,
    this.userBestScore,
    this.userAttempts,
    this.isJoinedServer = false,
  });

  Duration get timeRemaining {
    final now = DateTime.now();
    if (status == TournamentStatus.upcoming) {
      return startDate.difference(now);
    } else if (status == TournamentStatus.active) {
      return endDate.difference(now);
    }
    return Duration.zero;
  }

  String get timeRemainingFormatted {
    final duration = timeRemaining;
    if (duration.isNegative || duration == Duration.zero) {
      return status == TournamentStatus.upcoming ? 'Starting' : 'Ended';
    }

    if (duration.inDays > 0) {
      return '${duration.inDays}d ${duration.inHours % 24}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
  }

  int get userRank {
    if (userBestScore == null) return 0;

    int rank = 1;
    for (final participant in leaderboard) {
      if (participant.highScore > userBestScore!) {
        rank++;
      }
    }
    return rank;
  }

  // Prefer the explicit server flag (set on JoinTournament success).
  // Fall back to the score-based heuristic for older endpoints that
  // don't return is_joined yet — a user with a non-null best score
  // or any attempts has definitionally joined.
  bool get hasJoined =>
      isJoinedServer ||
      userBestScore != null ||
      (userAttempts != null && userAttempts! > 0);

  TournamentReward? get userReward {
    if (!hasJoined || status != TournamentStatus.ended) return null;
    return rewards[userRank];
  }

  String get formattedDateRange {
    final start = startDate;
    final end = endDate;

    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      // Same day
      return '${start.month}/${start.day}/${start.year}';
    } else if (start.year == end.year && start.month == end.month) {
      // Same month
      return '${start.month}/${start.day}-${end.day}/${start.year}';
    } else {
      // Different months or years
      return '${start.month}/${start.day} - ${end.month}/${end.day}/${end.year}';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.name,
      'status': status.name,
      'gameMode': gameMode.wireName,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'maxParticipants': maxParticipants,
      'currentParticipants': currentParticipants,
      'rewards': rewards.map((k, v) => MapEntry(k.toString(), v.toJson())),
      'gameSettings': gameSettings,
      'rules': rules,
      'imageUrl': imageUrl,
      'requiresEntry': requiresEntry,
      'entryCost': entryCost,
      'leaderboard': leaderboard.map((p) => p.toJson()).toList(),
      'userLastAttempt': userLastAttempt?.toIso8601String(),
      'userBestScore': userBestScore,
      'userAttempts': userAttempts,
      // Persist the server-authoritative flag in cache so a re-hydrated
      // Tournament keeps reporting hasJoined correctly without needing
      // another network round-trip.
      'is_joined': isJoinedServer,
    };
  }

  factory Tournament.fromJson(Map<String, dynamic> json) {
    // Pull a value tolerantly: try snake_case (ASP.NET wire format)
    // first, then camelCase (legacy / non-API), then null.
    T? pick<T>(String ship, String camel) {
      return (json[ship] as T?) ?? (json[camel] as T?);
    }

    // Enum lookup that matches both wire formats. Backend sends
    // SnakeCaseLower ("speed_run", "completed"); Flutter names are
    // camelCase ("speedRun") or sometimes different ("ended" vs
    // "completed"). Match by snake-case-equivalent of the enum name.
    String shipFromCamel(String camel) {
      final buf = StringBuffer();
      for (var i = 0; i < camel.length; i++) {
        final c = camel[i];
        if (c == c.toUpperCase() && c != c.toLowerCase()) {
          if (i > 0) buf.write('_');
          buf.write(c.toLowerCase());
        } else {
          buf.write(c);
        }
      }
      return buf.toString();
    }

    return Tournament(
      id: pick<String>('id', 'id') ?? '',
      name: pick<String>('name', 'name') ?? '',
      description: pick<String>('description', 'description') ?? '',
      type: TournamentType.values.firstWhere(
        (t) => t.name == json['type'] || shipFromCamel(t.name) == json['type'],
        orElse: () => TournamentType.daily,
      ),
      status: () {
        // Special-case backend's "completed" → Flutter's "ended".
        final raw = json['status'] as String?;
        if (raw == 'completed' || raw == 'ended') return TournamentStatus.ended;
        if (raw == 'active') return TournamentStatus.active;
        return TournamentStatus.upcoming;
      }(),
      gameMode: GameMode.fromWire(
        (json['game_mode'] ?? json['gameMode'])?.toString(),
      ),
      startDate: DateTime.parse(
        pick<String>('start_date', 'startDate') ??
            DateTime.now().toIso8601String(),
      ),
      endDate: DateTime.parse(
        pick<String>('end_date', 'endDate') ??
            DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      ),
      maxParticipants:
          pick<int>('max_participants', 'maxParticipants') ?? 1000,
      currentParticipants:
          pick<int>('current_participants', 'currentParticipants') ?? 0,
      rewards: (pick<Map>('prize_distribution', 'rewards'))?.map(
            (k, v) {
              final rankKey = int.tryParse(k.toString().split('-').first) ?? 0;
              if (v is Map<String, dynamic>) {
                return MapEntry(rankKey, TournamentReward.fromJson(v));
              }
              // Backend's PrizeDistribution stores a flat
              // {"1": 40000, "6-10": 2000} dict where values are coin
              // amounts. Synthesize a TournamentReward so the Flutter
              // detail screen can render it directly.
              return MapEntry(
                rankKey,
                TournamentReward(
                  id: 'r$k',
                  name: 'Rank $k',
                  description: 'Credit reward for rank $k',
                  type: 'coins',
                  coins: v is int ? v : (v is num ? v.toInt() : 0),
                ),
              );
            },
          ) ??
          {},
      gameSettings: Map<String, dynamic>.from(
          pick<Map>('game_settings', 'gameSettings') ?? {}),
      rules: Map<String, dynamic>.from(pick<Map>('rules', 'rules') ?? {}),
      imageUrl: pick<String>('image_url', 'imageUrl'),
      // Server now derives requires_entry from EntryFee>0; trust it.
      requiresEntry: pick<bool>('requires_entry', 'requiresEntry') ?? false,
      // Backend uses entry_fee; Flutter callers historically passed
      // entry_cost. Accept either.
      entryCost: pick<int>('entry_fee', 'entryCost') ??
          pick<int>('entry_cost', 'entryCost') ??
          0,
      leaderboard: (json['leaderboard'] as List?)
              ?.map((p) => TournamentParticipant.fromJson(p))
              .toList() ??
          [],
      userLastAttempt: pick<String>('user_last_attempt', 'userLastAttempt') !=
              null
          ? DateTime.parse(
              pick<String>('user_last_attempt', 'userLastAttempt')!)
          : null,
      userBestScore: pick<int>('user_best_score', 'userBestScore'),
      userAttempts: pick<int>('user_attempts', 'userAttempts'),
      isJoinedServer: pick<bool>('is_joined', 'isJoined') ?? false,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory Tournament.fromJsonString(String jsonString) {
    return Tournament.fromJson(jsonDecode(jsonString));
  }

  Tournament copyWith({
    String? id,
    String? name,
    String? description,
    TournamentType? type,
    TournamentStatus? status,
    GameMode? gameMode,
    DateTime? startDate,
    DateTime? endDate,
    int? maxParticipants,
    int? currentParticipants,
    Map<int, TournamentReward>? rewards,
    Map<String, dynamic>? gameSettings,
    Map<String, dynamic>? rules,
    String? imageUrl,
    bool? requiresEntry,
    int? entryCost,
    List<TournamentParticipant>? leaderboard,
    DateTime? userLastAttempt,
    int? userBestScore,
    int? userAttempts,
    bool? isJoinedServer,
  }) {
    return Tournament(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      status: status ?? this.status,
      gameMode: gameMode ?? this.gameMode,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      currentParticipants: currentParticipants ?? this.currentParticipants,
      rewards: rewards ?? this.rewards,
      gameSettings: gameSettings ?? this.gameSettings,
      rules: rules ?? this.rules,
      imageUrl: imageUrl ?? this.imageUrl,
      requiresEntry: requiresEntry ?? this.requiresEntry,
      entryCost: entryCost ?? this.entryCost,
      leaderboard: leaderboard ?? this.leaderboard,
      userLastAttempt: userLastAttempt ?? this.userLastAttempt,
      userBestScore: userBestScore ?? this.userBestScore,
      userAttempts: userAttempts ?? this.userAttempts,
      isJoinedServer: isJoinedServer ?? this.isJoinedServer,
    );
  }
}
