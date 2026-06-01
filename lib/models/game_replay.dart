import 'dart:convert';

class GameFrame {
  final int frameNumber;
  final int timestamp;
  final List<List<int>> snakePositions;
  final List<int>? foodPosition;
  final List<int>? powerUpPosition;
  final String? powerUpType;
  final int score;
  final int level;
  final String direction;
  final List<String> activePowerUps;
  final Map<String, dynamic>?
  gameEvent; // collision, food consumed, power-up collected, etc.

  const GameFrame({
    required this.frameNumber,
    required this.timestamp,
    required this.snakePositions,
    this.foodPosition,
    this.powerUpPosition,
    this.powerUpType,
    required this.score,
    required this.level,
    required this.direction,
    this.activePowerUps = const [],
    this.gameEvent,
  });

  Map<String, dynamic> toJson() {
    return {
      'frameNumber': frameNumber,
      'timestamp': timestamp,
      'snakePositions': snakePositions,
      'foodPosition': foodPosition,
      'powerUpPosition': powerUpPosition,
      'powerUpType': powerUpType,
      'score': score,
      'level': level,
      'direction': direction,
      'activePowerUps': activePowerUps,
      'gameEvent': gameEvent,
    };
  }

  factory GameFrame.fromJson(Map<String, dynamic> json) {
    return GameFrame(
      frameNumber: json['frameNumber'] ?? 0,
      timestamp: json['timestamp'] ?? 0,
      snakePositions:
          (json['snakePositions'] as List?)
              ?.map((pos) => (pos as List).cast<int>())
              .toList() ??
          [],
      foodPosition: (json['foodPosition'] as List?)?.cast<int>(),
      powerUpPosition: (json['powerUpPosition'] as List?)?.cast<int>(),
      powerUpType: json['powerUpType'],
      score: json['score'] ?? 0,
      level: json['level'] ?? 1,
      direction: json['direction'] ?? 'right',
      activePowerUps: (json['activePowerUps'] as List?)?.cast<String>() ?? [],
      gameEvent: json['gameEvent'],
    );
  }
}

class GameReplay {
  final String id;
  final DateTime createdAt;
  final String playerName;
  final int finalScore;
  final int gameTimeSeconds;
  final int totalFrames;
  final String gameMode;
  final Map<String, dynamic> gameSettings;
  final List<GameFrame> frames;
  final String? crashReason; // 'wall', 'self', null if game completed normally
  final Map<String, dynamic> gameStats;

  const GameReplay({
    required this.id,
    required this.createdAt,
    required this.playerName,
    required this.finalScore,
    required this.gameTimeSeconds,
    required this.totalFrames,
    required this.gameMode,
    required this.gameSettings,
    required this.frames,
    this.crashReason,
    required this.gameStats,
  });

  String get formattedDuration {
    final minutes = gameTimeSeconds ~/ 60;
    final seconds = gameTimeSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  String get gameOutcome {
    if (crashReason != null) {
      switch (crashReason) {
        case 'wall':
          return 'Hit Wall';
        case 'self':
          return 'Hit Self';
        default:
          return 'Game Over';
      }
    }
    return 'Completed';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'playerName': playerName,
      'finalScore': finalScore,
      'gameTimeSeconds': gameTimeSeconds,
      'totalFrames': totalFrames,
      'gameMode': gameMode,
      'gameSettings': gameSettings,
      'frames': frames.map((frame) => frame.toJson()).toList(),
      'crashReason': crashReason,
      'gameStats': gameStats,
    };
  }

  factory GameReplay.fromJson(Map<String, dynamic> json) {
    return GameReplay(
      id: json['id'] ?? '',
      createdAt: DateTime.parse(
        json['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      playerName: json['playerName'] ?? 'Unknown',
      finalScore: json['finalScore'] ?? 0,
      gameTimeSeconds: json['gameTimeSeconds'] ?? 0,
      totalFrames: json['totalFrames'] ?? 0,
      gameMode: json['gameMode'] ?? 'classic',
      gameSettings: Map<String, dynamic>.from(json['gameSettings'] ?? {}),
      frames:
          (json['frames'] as List?)
              ?.map((frame) => GameFrame.fromJson(frame))
              .toList() ??
          [],
      crashReason: json['crashReason'],
      gameStats: Map<String, dynamic>.from(json['gameStats'] ?? {}),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory GameReplay.fromJsonString(String jsonString) {
    return GameReplay.fromJson(jsonDecode(jsonString));
  }

  // Get frame at specific time (for seeking)
  GameFrame? getFrameAtTime(int timeSeconds) {
    for (final frame in frames) {
      if (frame.timestamp >= timeSeconds * 1000) {
        return frame;
      }
    }
    return frames.isNotEmpty ? frames.last : null;
  }

  // Get frame by number
  GameFrame? getFrameByNumber(int frameNumber) {
    if (frameNumber >= 0 && frameNumber < frames.length) {
      return frames[frameNumber];
    }
    return null;
  }

  // Get summary statistics for this replay. Guards against empty
  // `frames` — older / malformed rows can deserialize with no frames
  // (the fresh write path can't produce one, but pre-existing storage
  // rows from earlier formats or truncated blobs can), and unguarded
  // `frames.map(...).reduce(...)` throws StateError("No element") which
  // cascades through the entire ReplaysScreen ListView during layout.
  Map<String, dynamic> getSummary() {
    final totalFood = frames
        .where((f) => f.gameEvent?['type'] == 'food_consumed')
        .length;
    final totalPowerUps = frames
        .where((f) => f.gameEvent?['type'] == 'power_up_collected')
        .length;
    final maxSnakeLength = frames.isEmpty
        ? 0
        : frames
            .map((f) => f.snakePositions.length)
            .reduce((a, b) => a > b ? a : b);

    return {
      'duration': formattedDuration,
      'outcome': gameOutcome,
      'foodConsumed': totalFood,
      'powerUpsCollected': totalPowerUps,
      'maxLength': maxSnakeLength,
      'averageScore': frames.isNotEmpty ? finalScore / frames.length * 100 : 0,
    };
  }
}

class GameRecorder {
  final List<GameFrame> _frames = [];
  int _frameCounter = 0;
  DateTime? _gameStartTime;

  bool get isRecording => _gameStartTime != null;
  int get frameCount => _frames.length;

  void startRecording() {
    _frames.clear();
    _frameCounter = 0;
    _gameStartTime = DateTime.now();
  }

  void recordFrame({
    required List<List<int>> snakePositions,
    List<int>? foodPosition,
    List<int>? powerUpPosition,
    String? powerUpType,
    required int score,
    required int level,
    required String direction,
    List<String> activePowerUps = const [],
    Map<String, dynamic>? gameEvent,
  }) {
    if (!isRecording) return;

    final now = DateTime.now();
    final timestamp = _gameStartTime != null
        ? now.difference(_gameStartTime!).inMilliseconds
        : 0;

    final frame = GameFrame(
      frameNumber: _frameCounter++,
      timestamp: timestamp,
      snakePositions: snakePositions.map((pos) => [...pos]).toList(),
      foodPosition: foodPosition != null ? [...foodPosition] : null,
      powerUpPosition: powerUpPosition != null ? [...powerUpPosition] : null,
      powerUpType: powerUpType,
      score: score,
      level: level,
      direction: direction,
      activePowerUps: [...activePowerUps],
      gameEvent: gameEvent != null
          ? Map<String, dynamic>.from(gameEvent)
          : null,
    );

    _frames.add(frame);
  }

  GameReplay? finishRecording({
    required String playerName,
    required int finalScore,
    required String gameMode,
    required Map<String, dynamic> gameSettings,
    String? crashReason,
    required Map<String, dynamic> gameStats,
  }) {
    if (!isRecording || _frames.isEmpty) return null;

    final gameTime = _gameStartTime != null
        ? DateTime.now().difference(_gameStartTime!).inSeconds
        : 0;

    final replay = GameReplay(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: _gameStartTime ?? DateTime.now(),
      playerName: playerName,
      finalScore: finalScore,
      gameTimeSeconds: gameTime,
      totalFrames: _frames.length,
      gameMode: gameMode,
      gameSettings: gameSettings,
      frames: [..._frames],
      crashReason: crashReason,
      gameStats: gameStats,
    );

    stopRecording();
    return replay;
  }

  void stopRecording() {
    _frames.clear();
    _frameCounter = 0;
    _gameStartTime = null;
  }
}
