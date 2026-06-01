import 'package:cosmo_strike_flutter_app/models/position.dart';
import 'package:cosmo_strike_flutter_app/utils/direction.dart';

/// Helper function to parse DateTime from various JSON formats
DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

/// Helper function to convert DateTime to JSON-friendly format
String? _dateTimeToJson(DateTime? dateTime) {
  return dateTime?.toIso8601String();
}

enum MultiplayerGameStatus {
  waiting,
  starting,
  playing,
  paused,
  finished,
  abandoned,
}

enum MultiplayerGameMode { classic, speedRun, survival, powerUpMadness }

enum PlayerStatus { waiting, ready, playing, crashed, disconnected }

class MultiplayerGame {
  final String id;
  final MultiplayerGameMode mode;
  final MultiplayerGameStatus status;
  final List<MultiplayerPlayer> players;
  final Position? foodPosition;
  final Position? bonusFoodPosition;
  final Position? specialFoodPosition;
  final List<PowerUpSpawn> powerUps;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? winnerId;
  final int maxPlayers;
  final bool isPrivate;
  final String? roomCode;
  final Map<String, dynamic> gameSettings;

  const MultiplayerGame({
    required this.id,
    required this.mode,
    required this.status,
    required this.players,
    this.foodPosition,
    this.bonusFoodPosition,
    this.specialFoodPosition,
    this.powerUps = const [],
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.winnerId,
    this.maxPlayers = 2,
    this.isPrivate = false,
    this.roomCode,
    this.gameSettings = const {},
  });

  factory MultiplayerGame.fromJson(Map<String, dynamic> json) {
    return MultiplayerGame(
      id: json['id'] ?? '',
      mode: MultiplayerGameMode.values.firstWhere(
        (mode) => mode.name == json['mode'],
        orElse: () => MultiplayerGameMode.classic,
      ),
      status: MultiplayerGameStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => MultiplayerGameStatus.waiting,
      ),
      players: (json['players'] as List? ?? [])
          .map((player) => MultiplayerPlayer.fromJson(player))
          .toList(),
      foodPosition: json['foodPosition'] != null
          ? Position.fromJson(json['foodPosition'])
          : null,
      bonusFoodPosition: json['bonusFoodPosition'] != null
          ? Position.fromJson(json['bonusFoodPosition'])
          : null,
      specialFoodPosition: json['specialFoodPosition'] != null
          ? Position.fromJson(json['specialFoodPosition'])
          : null,
      powerUps: (json['powerUps'] as List? ?? [])
          .map((powerUp) => PowerUpSpawn.fromJson(powerUp))
          .toList(),
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      startedAt: _parseDateTime(json['startedAt']),
      finishedAt: _parseDateTime(json['finishedAt']),
      winnerId: json['winnerId'],
      maxPlayers: json['maxPlayers'] ?? 2,
      isPrivate: json['isPrivate'] ?? false,
      roomCode: json['roomCode'],
      gameSettings: Map<String, dynamic>.from(json['gameSettings'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mode': mode.name,
      'status': status.name,
      'players': players.map((player) => player.toJson()).toList(),
      'foodPosition': foodPosition?.toJson(),
      'bonusFoodPosition': bonusFoodPosition?.toJson(),
      'specialFoodPosition': specialFoodPosition?.toJson(),
      'powerUps': powerUps.map((powerUp) => powerUp.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'startedAt': _dateTimeToJson(startedAt),
      'finishedAt': _dateTimeToJson(finishedAt),
      'winnerId': winnerId,
      'maxPlayers': maxPlayers,
      'isPrivate': isPrivate,
      'roomCode': roomCode,
      'gameSettings': gameSettings,
    };
  }

  MultiplayerGame copyWith({
    String? id,
    MultiplayerGameMode? mode,
    MultiplayerGameStatus? status,
    List<MultiplayerPlayer>? players,
    Position? foodPosition,
    Position? bonusFoodPosition,
    Position? specialFoodPosition,
    List<PowerUpSpawn>? powerUps,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? winnerId,
    int? maxPlayers,
    bool? isPrivate,
    String? roomCode,
    Map<String, dynamic>? gameSettings,
  }) {
    return MultiplayerGame(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      players: players ?? this.players,
      foodPosition: foodPosition ?? this.foodPosition,
      bonusFoodPosition: bonusFoodPosition ?? this.bonusFoodPosition,
      specialFoodPosition: specialFoodPosition ?? this.specialFoodPosition,
      powerUps: powerUps ?? this.powerUps,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      winnerId: winnerId ?? this.winnerId,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      isPrivate: isPrivate ?? this.isPrivate,
      roomCode: roomCode ?? this.roomCode,
      gameSettings: gameSettings ?? this.gameSettings,
    );
  }

  bool get isFull => players.length >= maxPlayers;
  bool get canStart =>
      players.length >= 2 &&
      players.every((p) => p.status == PlayerStatus.ready);
  bool get isFinished =>
      status == MultiplayerGameStatus.finished ||
      status == MultiplayerGameStatus.abandoned;

  MultiplayerPlayer? getPlayer(String userId) {
    try {
      return players.firstWhere((player) => player.userId == userId);
    } catch (e) {
      return null;
    }
  }

  List<MultiplayerPlayer> get alivePlayers {
    return players
        .where((player) => player.status == PlayerStatus.playing)
        .toList();
  }

  String get modeDisplayName {
    switch (mode) {
      case MultiplayerGameMode.classic:
        return 'Classic Battle';
      case MultiplayerGameMode.speedRun:
        return 'Speed Run';
      case MultiplayerGameMode.survival:
        return 'Survival Mode';
      case MultiplayerGameMode.powerUpMadness:
        return 'Power-up Madness';
    }
  }

  String get modeEmoji {
    switch (mode) {
      case MultiplayerGameMode.classic:
        return '🐍';
      case MultiplayerGameMode.speedRun:
        return '⚡';
      case MultiplayerGameMode.survival:
        return '⏱️';
      case MultiplayerGameMode.powerUpMadness:
        return '🎆';
    }
  }
}

// Extensions for MultiplayerGameMode
extension MultiplayerGameModeExtensions on MultiplayerGameMode {
  String get modeDisplayName {
    switch (this) {
      case MultiplayerGameMode.classic:
        return 'Classic Battle';
      case MultiplayerGameMode.speedRun:
        return 'Speed Run';
      case MultiplayerGameMode.survival:
        return 'Survival Mode';
      case MultiplayerGameMode.powerUpMadness:
        return 'Power-up Madness';
    }
  }

  String get modeEmoji {
    switch (this) {
      case MultiplayerGameMode.classic:
        return '🐍';
      case MultiplayerGameMode.speedRun:
        return '⚡';
      case MultiplayerGameMode.survival:
        return '⏱️';
      case MultiplayerGameMode.powerUpMadness:
        return '🎆';
    }
  }
}

class MultiplayerPlayer {
  final String userId;
  final String displayName;
  /// Stable username (from backend), prefer this for player-facing labels.
  /// Falls back to displayName via [publicLabel] when null/empty.
  final String? username;
  final String? photoUrl;
  final PlayerStatus status;
  final List<Position> snake;
  final Direction currentDirection;
  final int score;
  final int rank;
  final DateTime? lastUpdate;
  final List<String> activePowerUps;

  // Reconnection support
  final String? connectionId;
  final DateTime? disconnectedAt;

  // Elimination tracking
  final int? eliminationRank;
  final DateTime? eliminatedAt;

  const MultiplayerPlayer({
    required this.userId,
    required this.displayName,
    this.username,
    this.photoUrl,
    required this.status,
    this.snake = const [],
    this.currentDirection = Direction.right,
    this.score = 0,
    this.rank = 0,
    this.lastUpdate,
    this.activePowerUps = const [],
    this.connectionId,
    this.disconnectedAt,
    this.eliminationRank,
    this.eliminatedAt,
  });

  /// Best label to show on the multiplayer board, lobby, and elimination
  /// banners. Prefers the backend-assigned username (stable, fits the
  /// 20-char column, matches the leaderboard rendering) and falls back
  /// to the Google display name then 'Player'.
  String get publicLabel {
    if (username != null && username!.isNotEmpty) return username!;
    if (displayName.isNotEmpty && displayName != 'Unknown Player') {
      return displayName;
    }
    return 'Player';
  }

  factory MultiplayerPlayer.fromJson(Map<String, dynamic> json) {
    return MultiplayerPlayer(
      userId: json['userId'] ?? json['user_id'] ?? '',
      displayName:
          json['displayName'] ?? json['display_name'] ?? 'Unknown Player',
      username: json['username'] as String?,
      photoUrl: json['photoUrl'] ?? json['photo_url'],
      status: PlayerStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => PlayerStatus.waiting,
      ),
      snake: (json['snake'] as List? ?? json['snake_positions'] as List? ?? [])
          .map((pos) => Position.fromJson(pos))
          .toList(),
      currentDirection: Direction.values.firstWhere(
        (direction) =>
            direction.name == (json['currentDirection'] ?? json['direction']),
        orElse: () => Direction.right,
      ),
      score: json['score'] ?? 0,
      rank: json['rank'] ?? 0,
      lastUpdate: _parseDateTime(json['lastUpdate'] ?? json['last_update_at']),
      activePowerUps: List<String>.from(
        json['activePowerUps'] ?? json['active_power_ups'] ?? [],
      ),
      connectionId: json['connectionId'] ?? json['connection_id'],
      disconnectedAt: _parseDateTime(
        json['disconnectedAt'] ?? json['disconnected_at'],
      ),
      eliminationRank: json['eliminationRank'] ?? json['elimination_rank'],
      eliminatedAt: _parseDateTime(
        json['eliminatedAt'] ?? json['eliminated_at'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'status': status.name,
      'snake': snake.map((pos) => pos.toJson()).toList(),
      'currentDirection': currentDirection.name,
      'score': score,
      'rank': rank,
      'lastUpdate': _dateTimeToJson(lastUpdate),
      'activePowerUps': activePowerUps,
      'connectionId': connectionId,
      'disconnectedAt': _dateTimeToJson(disconnectedAt),
      'eliminationRank': eliminationRank,
      'eliminatedAt': _dateTimeToJson(eliminatedAt),
    };
  }

  MultiplayerPlayer copyWith({
    String? userId,
    String? displayName,
    String? photoUrl,
    PlayerStatus? status,
    List<Position>? snake,
    Direction? currentDirection,
    int? score,
    int? rank,
    DateTime? lastUpdate,
    List<String>? activePowerUps,
    String? connectionId,
    DateTime? disconnectedAt,
    int? eliminationRank,
    DateTime? eliminatedAt,
  }) {
    return MultiplayerPlayer(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      status: status ?? this.status,
      snake: snake ?? this.snake,
      currentDirection: currentDirection ?? this.currentDirection,
      score: score ?? this.score,
      rank: rank ?? this.rank,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      activePowerUps: activePowerUps ?? this.activePowerUps,
      connectionId: connectionId ?? this.connectionId,
      disconnectedAt: disconnectedAt ?? this.disconnectedAt,
      eliminationRank: eliminationRank ?? this.eliminationRank,
      eliminatedAt: eliminatedAt ?? this.eliminatedAt,
    );
  }

  /// Check if player can reconnect (within 60 second window)
  bool get canReconnect =>
      disconnectedAt != null &&
      DateTime.now().difference(disconnectedAt!).inSeconds < 60;

  Position get head {
    if (snake.isEmpty) return const Position(10, 10);
    return snake.first;
  }

  bool get isAlive => status == PlayerStatus.playing;
}

class PowerUpSpawn {
  final String id;
  final String type;
  final Position position;
  final DateTime createdAt;
  final DateTime expiresAt;

  const PowerUpSpawn({
    required this.id,
    required this.type,
    required this.position,
    required this.createdAt,
    required this.expiresAt,
  });

  factory PowerUpSpawn.fromJson(Map<String, dynamic> json) {
    return PowerUpSpawn(
      id: json['id'] ?? '',
      type: json['type'] ?? '',
      position: Position.fromJson(json['position']),
      createdAt: _parseDateTime(json['createdAt']) ?? DateTime.now(),
      expiresAt:
          _parseDateTime(json['expiresAt']) ??
          DateTime.now().add(const Duration(minutes: 1)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'position': position.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class MultiplayerGameAction {
  final String playerId;
  final String actionType;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  const MultiplayerGameAction({
    required this.playerId,
    required this.actionType,
    required this.data,
    required this.timestamp,
  });

  factory MultiplayerGameAction.fromJson(Map<String, dynamic> json) {
    return MultiplayerGameAction(
      playerId: json['playerId'] ?? '',
      actionType: json['actionType'] ?? '',
      data: Map<String, dynamic>.from(json['data'] ?? {}),
      timestamp: _parseDateTime(json['timestamp']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'playerId': playerId,
      'actionType': actionType,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  // Factory methods for common actions
  factory MultiplayerGameAction.changeDirection(
    String playerId,
    Direction direction,
  ) {
    return MultiplayerGameAction(
      playerId: playerId,
      actionType: 'changeDirection',
      data: {'direction': direction.name},
      timestamp: DateTime.now(),
    );
  }

  factory MultiplayerGameAction.playerReady(String playerId) {
    return MultiplayerGameAction(
      playerId: playerId,
      actionType: 'playerReady',
      data: {},
      timestamp: DateTime.now(),
    );
  }

  factory MultiplayerGameAction.gameUpdate(
    String playerId,
    List<Position> snake,
    int score,
  ) {
    return MultiplayerGameAction(
      playerId: playerId,
      actionType: 'gameUpdate',
      data: {
        'snake': snake.map((pos) => pos.toJson()).toList(),
        'score': score,
      },
      timestamp: DateTime.now(),
    );
  }
}

// Extensions for game mode settings
extension MultiplayerGameModeSettings on MultiplayerGameMode {
  Map<String, dynamic> get defaultSettings {
    switch (this) {
      case MultiplayerGameMode.classic:
        return {
          'boardSize': 20,
          'initialSpeed': 200,
          'speedIncrease': false,
          'powerUpsEnabled': false,
        };
      case MultiplayerGameMode.speedRun:
        return {
          'boardSize': 20,
          'initialSpeed': 150,
          'speedIncrease': true,
          'powerUpsEnabled': false,
        };
      case MultiplayerGameMode.survival:
        return {
          'boardSize': 25,
          'initialSpeed': 180,
          'speedIncrease': false,
          'powerUpsEnabled': false,
          'timeLimit': 300, // 5 minutes
        };
      case MultiplayerGameMode.powerUpMadness:
        return {
          'boardSize': 20,
          'initialSpeed': 200,
          'speedIncrease': false,
          'powerUpsEnabled': true,
          'powerUpFrequency': 'high',
        };
    }
  }
}
