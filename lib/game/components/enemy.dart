import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../cosmo_palette.dart';
import '../cosmo_strike_game.dart';
import 'bullets.dart';

enum EnemyPattern { straight, sine, dive, tracking }

/// A single enemy fighter. Spawns from the right edge and advances left using
/// one of four movement patterns, firing at intervals. Rendered as a geometric
/// hostile (placeholder — see ASSETS_NEEDED.md for the real sprites).
class EnemyShip extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  EnemyShip({
    required this.pattern,
    required Vector2 spawn,
    required this.hp,
    required this.speed,
    required this.pointValue,
  }) : super(position: spawn, size: Vector2(38, 30), anchor: Anchor.center);

  final EnemyPattern pattern;
  int hp;
  final double speed;
  final int pointValue;

  double _age = 0;
  double _fireTimer = 0;
  late final double _baseY = position.y;
  late final double _fireInterval = 1.4 + game.rng.nextDouble() * 1.6;

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox(collisionType: CollisionType.passive));
    _fireTimer = _fireInterval * (0.4 + game.rng.nextDouble());
  }

  @override
  void update(double dt) {
    _age += dt;
    position.x -= speed * dt;

    switch (pattern) {
      case EnemyPattern.straight:
        break;
      case EnemyPattern.sine:
        position.y = _baseY + math.sin(_age * 3) * 60;
        break;
      case EnemyPattern.dive:
        if (position.x < game.size.x * 0.7) {
          final targetY = game.player.position.y;
          position.y += (targetY - position.y) * math.min(1, dt * 1.2);
        }
        break;
      case EnemyPattern.tracking:
        final targetY = game.player.position.y;
        position.y += (targetY - position.y).clamp(-1, 1) * 40 * dt;
        break;
    }

    if (position.x < -40) removeFromParent();

    _fireTimer -= dt;
    if (_fireTimer <= 0 && position.x < game.size.x) {
      _fireTimer = _fireInterval;
      _fire();
    }
  }

  void _fire() {
    Vector2 velocity;
    if (pattern == EnemyPattern.tracking || pattern == EnemyPattern.dive) {
      final dir = (game.player.position - position)..normalize();
      velocity = dir * 240;
    } else {
      velocity = Vector2(-260, 0);
    }
    game.add(EnemyBullet(spawn: position.clone(), velocity: velocity));
  }

  void takeDamage(int dmg) {
    hp -= dmg;
    if (hp <= 0) {
      game.onEnemyKilled(this);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final body = Paint()..color = CosmoPalette.hostile;
    final dark = Paint()..color = CosmoPalette.hostileDeep;
    // Arrow pointing left.
    final path = Path()
      ..moveTo(0, size.y / 2)
      ..lineTo(size.x * 0.8, 0)
      ..lineTo(size.x * 0.64, size.y / 2)
      ..lineTo(size.x * 0.8, size.y)
      ..close();
    canvas.drawPath(path, body);
    canvas.drawRect(
      Rect.fromLTWH(size.x * 0.8, size.y * 0.36, size.x * 0.2, size.y * 0.28),
      dark,
    );
    canvas.drawCircle(
        Offset(size.x * 0.5, size.y / 2), 3, Paint()..color = CosmoPalette.highlight);
  }
}
