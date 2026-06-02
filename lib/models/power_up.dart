import 'dart:math';
import 'package:cosmo_strike_flutter_app/models/position.dart';
import 'package:cosmo_strike_flutter_app/models/ship.dart';
import 'package:flutter/material.dart';

enum PowerUpType {
  speedBoost,
  invincibility,
  scoreMultiplier,
  slowMotion;

  String get name {
    switch (this) {
      case PowerUpType.speedBoost:
        return 'Speed Boost';
      case PowerUpType.invincibility:
        return 'Invincibility';
      case PowerUpType.scoreMultiplier:
        return 'Score Multiplier';
      case PowerUpType.slowMotion:
        return 'Slow Motion';
    }
  }

  String get description {
    switch (this) {
      case PowerUpType.speedBoost:
        return 'Increases ship speed for 7 seconds';
      case PowerUpType.invincibility:
        return 'Pass through walls and yourself for 6 seconds';
      case PowerUpType.scoreMultiplier:
        return 'Double points for 10 seconds';
      case PowerUpType.slowMotion:
        return 'Slows down game for precise control (8 seconds)';
    }
  }

  String get icon {
    switch (this) {
      case PowerUpType.speedBoost:
        return '⚡';
      case PowerUpType.invincibility:
        return '🛡️';
      case PowerUpType.scoreMultiplier:
        return '💰';
      case PowerUpType.slowMotion:
        return '🐌';
    }
  }

  Color get color {
    switch (this) {
      case PowerUpType.speedBoost:
        return Colors.yellow;
      case PowerUpType.invincibility:
        return Colors.blue;
      case PowerUpType.scoreMultiplier:
        return Colors.green;
      case PowerUpType.slowMotion:
        return Colors.purple;
    }
  }

  Duration get duration {
    switch (this) {
      case PowerUpType.speedBoost:
        return const Duration(seconds: 7);
      case PowerUpType.invincibility:
        return const Duration(seconds: 6);
      case PowerUpType.scoreMultiplier:
        return const Duration(seconds: 10);
      case PowerUpType.slowMotion:
        return const Duration(seconds: 8);
    }
  }

  int get rarity {
    switch (this) {
      case PowerUpType.speedBoost:
        return 3; // Common
      case PowerUpType.invincibility:
        return 1; // Rare
      case PowerUpType.scoreMultiplier:
        return 2; // Uncommon
      case PowerUpType.slowMotion:
        return 2; // Uncommon
    }
  }
}

class PowerUp {
  final Position position;
  final PowerUpType type;
  final DateTime createdAt;
  /// Pause-time snapshot — see [ActivePowerUp.pausedAt]. When set, every
  /// time-related getter treats this as the effective "now" so the
  /// on-board power-up's 20s expiration countdown freezes while the game
  /// is paused.
  final DateTime? pausedAt;

  PowerUp({
    required this.position,
    required this.type,
    DateTime? createdAt,
    this.pausedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  DateTime get _effectiveNow => pausedAt ?? DateTime.now();

  static Position generateRandomPosition(
    int boardWidth,
    int boardHeight,
    Ship ship, {
    Position? foodPosition,
    Iterable<Position> foodPositions = const [],
  }) {
    final random = Random();
    final blocked = <Position>{
      ?foodPosition,
      ...foodPositions,
    };
    Position newPosition;

    // Bounded retries — on a fully-occupied board, fall through and accept
    // whatever was generated so the caller doesn't deadlock.
    for (var attempt = 0; attempt < 64; attempt++) {
      newPosition = Position(
        random.nextInt(boardWidth),
        random.nextInt(boardHeight),
      );
      if (!ship.occupiesPosition(newPosition) &&
          !blocked.contains(newPosition)) {
        return newPosition;
      }
    }
    return Position(random.nextInt(boardWidth), random.nextInt(boardHeight));
  }

  static PowerUp? generateRandom(
    int boardWidth,
    int boardHeight,
    Ship ship, {
    Position? foodPosition,
    Iterable<Position> foodPositions = const [],
  }) {
    final random = Random();

    final position = generateRandomPosition(
      boardWidth,
      boardHeight,
      ship,
      foodPosition: foodPosition,
      foodPositions: foodPositions,
    );

    // Select power-up type based on rarity
    final totalRarity = PowerUpType.values.fold(
      0,
      (sum, type) => sum + type.rarity,
    );
    final randomValue = random.nextInt(totalRarity);

    int currentValue = 0;
    for (final type in PowerUpType.values) {
      currentValue += type.rarity;
      if (randomValue < currentValue) {
        return PowerUp(position: position, type: type);
      }
    }

    return PowerUp(position: position, type: PowerUpType.speedBoost);
  }

  bool get isExpired {
    // Power-ups expire after 20 seconds if not collected
    return _effectiveNow.difference(createdAt).inSeconds > 20;
  }

  // Time remaining before expiration
  int get secondsRemaining {
    final elapsed = _effectiveNow.difference(createdAt).inSeconds;
    return (20 - elapsed).clamp(0, 20);
  }

  // Returns true if power-up is about to expire (last 5 seconds)
  bool get isExpiringSoon {
    return secondsRemaining <= 5 && secondsRemaining > 0;
  }

  // Warning intensity from 0.0 (5 seconds left) to 1.0 (0 seconds left)
  double get warningIntensity {
    if (!isExpiringSoon) return 0.0;
    return 1.0 - (secondsRemaining / 5.0);
  }

  double get pulsePhase {
    // Create a pulsing animation effect
    final secondsSinceCreated =
        _effectiveNow.difference(createdAt).inMilliseconds / 1000.0;
    return (sin(secondsSinceCreated * 3.0) + 1.0) / 2.0; // 0.0 to 1.0
  }
}

class ActivePowerUp {
  final PowerUpType type;
  final DateTime activatedAt;
  final Duration duration;
  /// When non-null, getters treat this as the effective "now" so the
  /// displayed remaining time freezes while the game is paused. The cubit
  /// populates it in pauseGame and clears it (after shifting activatedAt
  /// forward by the pause duration) in resumeGame. Without this, animation
  /// controllers in the HUD would tick the displayed seconds down even
  /// while gameplay is frozen, since remainingTime is a computed getter
  /// against wall-clock time.
  final DateTime? pausedAt;

  ActivePowerUp({
    required this.type,
    DateTime? activatedAt,
    Duration? duration,
    this.pausedAt,
  }) : activatedAt = activatedAt ?? DateTime.now(),
       duration = duration ?? type.duration;

  DateTime get _effectiveNow => pausedAt ?? DateTime.now();

  bool get isExpired {
    return _effectiveNow.difference(activatedAt) >= duration;
  }

  Duration get remainingTime {
    final elapsed = _effectiveNow.difference(activatedAt);
    final remaining = duration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  double get progress {
    final elapsed = _effectiveNow.difference(activatedAt).inMilliseconds;
    final total = duration.inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}
