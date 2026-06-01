import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../cosmo_palette.dart';
import '../cosmo_strike_game.dart';
import 'player_ship.dart';

enum PowerUpKind {
  rapidFire,
  spread,
  laser,
  shield,
  extraLife,
  bomb,
  scoreMultiplier;

  /// Weighted random drop — combat upgrades common, life/bomb rare.
  static PowerUpKind random(math.Random rng) {
    const weighted = [
      rapidFire, rapidFire, rapidFire,
      spread, spread, spread,
      laser, laser,
      shield, shield,
      scoreMultiplier, scoreMultiplier,
      bomb,
      extraLife,
    ];
    return weighted[rng.nextInt(weighted.length)];
  }

  String get glyph {
    switch (this) {
      case PowerUpKind.rapidFire:
        return 'R';
      case PowerUpKind.spread:
        return 'S';
      case PowerUpKind.laser:
        return 'L';
      case PowerUpKind.shield:
        return 'O';
      case PowerUpKind.extraLife:
        return '+';
      case PowerUpKind.bomb:
        return 'B';
      case PowerUpKind.scoreMultiplier:
        return 'x2';
    }
  }

  Color get color {
    switch (this) {
      case PowerUpKind.rapidFire:
      case PowerUpKind.laser:
        return CosmoPalette.hull;
      case PowerUpKind.spread:
        return CosmoPalette.energy;
      case PowerUpKind.shield:
        return CosmoPalette.highlight;
      case PowerUpKind.extraLife:
        return CosmoPalette.boon;
      case PowerUpKind.bomb:
        return CosmoPalette.hostile;
      case PowerUpKind.scoreMultiplier:
        return CosmoPalette.hullLight;
    }
  }
}

class PowerUp extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  PowerUp({required this.kind, required Vector2 spawn})
      : super(position: spawn, size: Vector2(26, 26), anchor: Anchor.center);

  final PowerUpKind kind;
  double _age = 0;
  late final TextPaint _text = TextPaint(
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.bold,
      color: CosmoPalette.bgDeep,
    ),
  );

  @override
  Future<void> onLoad() async {
    add(CircleHitbox(collisionType: CollisionType.passive));
  }

  @override
  void update(double dt) {
    _age += dt;
    position.x -= 90 * dt;
    position.y += math.sin(_age * 3) * 18 * dt;
    if (position.x < -30) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final c = size.x / 2;
    canvas.drawCircle(Offset(c, c), c, Paint()..color = kind.color);
    canvas.drawCircle(
      Offset(c, c),
      c,
      Paint()
        ..color = CosmoPalette.bgDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    _text.render(
      canvas,
      kind.glyph,
      Vector2(c, c),
      anchor: Anchor.center,
    );
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerShip) {
      game.applyPowerUp(kind);
      removeFromParent();
    }
  }
}
