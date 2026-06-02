import 'dart:math';
import 'package:cosmo_strike_flutter_app/models/position.dart';
import 'package:cosmo_strike_flutter_app/models/ship.dart';

enum FoodType {
  normal,
  bonus,
  special;

  int get points {
    switch (this) {
      case FoodType.normal:
        return 10;
      case FoodType.bonus:
        return 25;
      case FoodType.special:
        return 50;
    }
  }
}

class Food {
  final Position position;
  final FoodType type;
  final DateTime createdAt;

  Food({
    required this.position,
    this.type = FoodType.normal,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static Position generateRandomPosition(
    int boardWidth,
    int boardHeight,
    Ship ship,
  ) {
    final random = Random();
    // Bounded retry mirrors PowerUp.generateRandom — on a near-full late-game
    // board the random walk could theoretically spin forever; cap attempts
    // then deterministically scan for the first free cell.
    for (var attempt = 0; attempt < 64; attempt++) {
      final candidate = Position(
        random.nextInt(boardWidth),
        random.nextInt(boardHeight),
      );
      if (!ship.occupiesPosition(candidate)) {
        return candidate;
      }
    }
    for (var x = 0; x < boardWidth; x++) {
      for (var y = 0; y < boardHeight; y++) {
        final fallback = Position(x, y);
        if (!ship.occupiesPosition(fallback)) {
          return fallback;
        }
      }
    }
    return Position(0, 0);
  }

  static Food generateRandom(
    int boardWidth,
    int boardHeight,
    Ship ship, {
    bool isPremium = false,
  }) {
    final position = generateRandomPosition(boardWidth, boardHeight, ship);
    final random = Random();

    FoodType type = FoodType.normal;
    final chance = random.nextDouble();

    // Base rate: 8% special (50pt star), 10% bonus (25pt), 82% normal (10pt).
    // Pro subscribers get a 50% boost to the special-food rate (8% -> 12%),
    // surfacing the rare 50pt target more often. Bonus rate is unchanged so
    // the bump is felt specifically on the "wow" tier.
    final specialThreshold = isPremium ? 0.12 : 0.08;
    final bonusThreshold = specialThreshold + 0.10;
    if (chance < specialThreshold) {
      type = FoodType.special;
    } else if (chance < bonusThreshold) {
      type = FoodType.bonus;
    }

    return Food(position: position, type: type);
  }

  bool get isExpired {
    if (type == FoodType.normal) return false;

    final expiration = type == FoodType.special ? 10000 : 15000; // milliseconds
    return DateTime.now().difference(createdAt).inMilliseconds > expiration;
  }
}
