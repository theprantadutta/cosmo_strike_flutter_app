import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../cosmo_palette.dart';
import '../cosmo_strike_game.dart';
import 'boss.dart';
import 'enemy.dart';
import 'player_ship.dart';

/// A bullet fired by the player. Travels right; damages enemies and bosses.
class PlayerBullet extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  PlayerBullet({
    required Vector2 spawn,
    this.speed = 520,
    this.damage = 1,
    this.tint = CosmoPalette.energy,
  }) : super(position: spawn, size: Vector2(16, 4), anchor: Anchor.center);

  final double speed;
  final int damage;
  final Color tint;

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox(collisionType: CollisionType.active));
  }

  @override
  void update(double dt) {
    position.x += speed * dt;
    if (position.x > game.size.x + 20) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = tint;
    canvas.drawRRect(
      RRect.fromRectAndRadius(size.toRect(), const Radius.circular(2)),
      paint,
    );
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is EnemyShip) {
      other.takeDamage(damage);
      removeFromParent();
    } else if (other is Boss) {
      other.takeDamage(damage);
      removeFromParent();
    }
  }
}

/// A bullet fired by an enemy/boss. Travels left; damages the player.
class EnemyBullet extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  EnemyBullet({
    required Vector2 spawn,
    required this.velocity,
    this.damage = 0.34,
  }) : super(position: spawn, size: Vector2(8, 8), anchor: Anchor.center);

  final Vector2 velocity;
  final double damage;

  @override
  Future<void> onLoad() async {
    add(CircleHitbox(collisionType: CollisionType.active));
  }

  @override
  void update(double dt) {
    position += velocity * dt;
    if (position.x < -20 ||
        position.y < -20 ||
        position.y > game.size.y + 20) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final c = size.x / 2;
    canvas.drawCircle(Offset(c, c), c, Paint()..color = CosmoPalette.hostile);
    canvas.drawCircle(
        Offset(c, c), c * 0.5, Paint()..color = CosmoPalette.highlight);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerShip) {
      game.onPlayerHit(damage);
      removeFromParent();
    }
  }
}
