import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';
import '../game_assets.dart';
import 'boss.dart';
import 'enemy.dart';
import 'fx.dart';
import 'player_ship.dart';
import 'terrain.dart';

/// A bullet fired by the player. Travels right; damages enemies, bosses,
/// and destructible obstacles.
class PlayerBullet extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  PlayerBullet({
    required Vector2 spawn,
    this.speed = 520,
    this.damage = 1,
    this.heavy = false,
  }) : super(
          position: spawn,
          size: heavy ? Vector2(25, 10) : Vector2(22, 8),
          anchor: Anchor.center,
          priority: 5,
        );

  final double speed;
  final int damage;

  /// Laser-tier shots use the heavy bolt sprite.
  final bool heavy;

  late final Sprite _sprite = Sprite(Flame.images
      .fromCache(heavy ? GameAssets.bulletPlayerHeavy : GameAssets.bulletPlayer));

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
    _sprite.render(canvas, size: size);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is EnemyShip) {
      game.add(hitSpark(position));
      other.takeDamage(damage);
      removeFromParent();
    } else if (other is Boss) {
      game.add(hitSpark(position));
      other.takeDamage(damage);
      removeFromParent();
    } else if (other is TerrainObstacle && other.destructible) {
      game.add(hitSpark(position));
      other.takeDamage(damage);
      removeFromParent();
    }
  }
}

/// The special weapon: a missile with a small area-of-effect blast.
/// Big damage on direct hit + splash to everything nearby.
class PlayerMissile extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  PlayerMissile({required Vector2 spawn})
      : super(
          position: spawn,
          size: Vector2(29, 12),
          anchor: Anchor.center,
          priority: 6,
        );

  static const int directDamage = 8;
  static const int splashDamage = 3;
  static const double splashRadius = 80;

  double _speed = 320;

  late final Sprite _sprite =
      Sprite(Flame.images.fromCache(GameAssets.missilePlayer));

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox(collisionType: CollisionType.active));
  }

  @override
  void update(double dt) {
    _speed += 900 * dt; // accelerates after launch
    position.x += _speed * dt;
    if (position.x > game.size.x + 30) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    _sprite.render(canvas, size: size);
  }

  void _detonate(PositionComponent directTarget) {
    game.add(explosionBig(position));
    // Direct hit.
    if (directTarget is EnemyShip) directTarget.takeDamage(directDamage);
    if (directTarget is Boss) directTarget.takeDamage(directDamage);
    if (directTarget is TerrainObstacle && directTarget.destructible) {
      directTarget.takeDamage(directDamage);
    }
    // Splash to everything else nearby.
    for (final e in game.children.whereType<EnemyShip>().toList()) {
      if (!identical(e, directTarget) &&
          e.position.distanceTo(position) <= splashRadius) {
        e.takeDamage(splashDamage);
      }
    }
    for (final b in game.children.whereType<Boss>().toList()) {
      if (!identical(b, directTarget) &&
          b.position.distanceTo(position) <= splashRadius + 40) {
        b.takeDamage(splashDamage);
      }
    }
    removeFromParent();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is EnemyShip ||
        other is Boss ||
        (other is TerrainObstacle && other.destructible)) {
      _detonate(other);
    }
  }
}

/// A bullet fired by an enemy/boss. Travels along [velocity]; damages the
/// player. Slow-mo scales its time; a ghosted player phases through it.
class EnemyBullet extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  EnemyBullet({
    required Vector2 spawn,
    required this.velocity,
    this.damage = 0.34,
    this.fromBoss = false,
  }) : super(
          position: spawn,
          size: fromBoss ? Vector2.all(18) : Vector2.all(14),
          anchor: Anchor.center,
          priority: 5,
        );

  final Vector2 velocity;
  final double damage;
  final bool fromBoss;

  late final Sprite _sprite = Sprite(Flame.images
      .fromCache(fromBoss ? GameAssets.bulletBoss : GameAssets.bulletEnemy));

  @override
  Future<void> onLoad() async {
    add(CircleHitbox(collisionType: CollisionType.active));
  }

  @override
  void update(double dt) {
    // Slow-mo power-up stretches enemy time.
    position += velocity * (dt * game.enemyTimeScale);
    if (position.x < -20 ||
        position.x > game.size.x + 30 ||
        position.y < -20 ||
        position.y > game.size.y + 20) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    _sprite.render(canvas, size: size);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerShip) {
      // Ghost mode: shots pass straight through the phased-out ship.
      if (game.player.ghosted) return;
      game.onPlayerHit(damage);
      removeFromParent();
    }
  }
}
