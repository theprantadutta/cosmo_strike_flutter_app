import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';
import '../game_assets.dart';
import 'boss.dart';
import 'bosses/boss_pod.dart';
import 'enemy.dart';
import 'fx.dart';
import 'player_ship.dart';
import 'terrain.dart';

/// A pooled bullet fired by the player. Travels right; damages enemies,
/// bosses, and destructible obstacles. Never removed from the tree —
/// [activate]/[deactivate] recycle it through [GamePools].
class PlayerBullet extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  PlayerBullet()
      : super(size: Vector2(22, 8), anchor: Anchor.center, priority: 5) {
    position.setValues(-9999, -9999);
  }

  bool active = false;
  double speed = 520;
  int damage = 1;

  /// Laser-tier shots use the heavy bolt sprite.
  bool heavy = false;

  /// Vertical drift for the spread fan.
  double driftY = 0;

  late final RectangleHitbox _hitbox =
      RectangleHitbox(collisionType: CollisionType.inactive);

  static Sprite? _normalSprite;
  static Sprite? _heavySprite;

  Sprite get _sprite => heavy
      ? (_heavySprite ??=
          Sprite(Flame.images.fromCache(GameAssets.bulletPlayerHeavy)))
      : (_normalSprite ??=
          Sprite(Flame.images.fromCache(GameAssets.bulletPlayer)));

  @override
  Future<void> onLoad() async {
    add(_hitbox);
  }

  void activate({
    required Vector2 spawn,
    double speed = 520,
    int damage = 1,
    bool heavy = false,
    double driftY = 0,
  }) {
    this.speed = speed;
    this.damage = damage;
    this.heavy = heavy;
    this.driftY = driftY;
    size.setValues(heavy ? 25 : 22, heavy ? 10 : 8);
    position.setFrom(spawn);
    active = true;
    _hitbox.collisionType = CollisionType.active;
  }

  void deactivate() {
    if (!active) return;
    active = false;
    _hitbox.collisionType = CollisionType.inactive;
    position.setValues(-9999, -9999);
  }

  @override
  void update(double dt) {
    if (!active) return;
    position.x += speed * dt;
    if (driftY != 0) position.y += driftY * dt;
    if (position.x > game.size.x + 20) deactivate();
  }

  @override
  void render(Canvas canvas) {
    if (!active) return;
    _sprite.render(canvas, size: size);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (!active) return;
    if (other is EnemyShip) {
      game.pools.hitSpark(position);
      other.takeDamage(damage);
      deactivate();
    } else if (other is EnemyBullet) {
      // Intercept: shoot incoming fire out of the sky. Trades your shot
      // for safety (+10 pts); the heavy laser pierces straight through.
      // Boss energy bolts can't be shot down — but mortar shells can.
      if (other.active && other.canBeShotDown) {
        game.pools.hitSpark(other.position);
        game.addScore(10);
        other.deactivate();
        if (!heavy) deactivate();
      }
    } else if (other is Boss) {
      game.pools.hitSpark(position);
      other.takeDamage(damage);
      deactivate();
    } else if (other is BossPod) {
      game.pools.hitSpark(position);
      other.takeDamage(damage);
      deactivate();
    } else if (other is TerrainObstacle && other.destructible) {
      game.pools.hitSpark(position);
      other.takeDamage(damage);
      deactivate();
    }
  }
}

/// The special weapon: a missile with a small area-of-effect blast.
/// Big damage on direct hit + splash to everything nearby. Rare enough
/// to stay unpooled.
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
    if (directTarget is BossPod) directTarget.takeDamage(directDamage);
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
    for (final p in game.children.whereType<BossPod>().toList()) {
      if (!identical(p, directTarget) &&
          p.position.distanceTo(position) <= splashRadius) {
        p.takeDamage(splashDamage);
      }
    }
    for (final b in game.children.whereType<Boss>().toList()) {
      if (!identical(b, directTarget) &&
          b.position.distanceTo(position) <= splashRadius + 40) {
        b.takeDamage(splashDamage);
      }
    }
    // The blast also sweeps incoming fire (ALL of it, boss bolts
    // included) — missiles double as a panic button.
    game.pools.clearEnemyBulletsWithin(position, splashRadius);
    removeFromParent();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is EnemyShip ||
        other is Boss ||
        other is BossPod ||
        (other is TerrainObstacle && other.destructible)) {
      _detonate(other);
    }
  }
}

/// A pooled bullet fired by an enemy/boss. Travels along [velocity];
/// damages the player. Slow-mo scales its time; a ghosted player phases
/// through it.
class EnemyBullet extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  EnemyBullet()
      : super(size: Vector2.all(14), anchor: Anchor.center, priority: 5) {
    position.setValues(-9999, -9999);
  }

  bool active = false;
  final Vector2 velocity = Vector2.zero();
  double damage = 0.34;
  bool fromBoss = false;

  /// Mortar lobs: vertical acceleration giving an arcing trajectory.
  double gravity = 0;
  bool _grazed = false;

  /// Player fire can intercept regular shots and physical mortar shells;
  /// boss energy bolts (walls, radials, beams) cannot be shot down.
  bool get canBeShotDown => !fromBoss || gravity != 0;

  // Graze ring: closer than the outer radius but not dead-center (a
  // straight hit is a hit, not a graze). Center-to-center, squared.
  static const double _grazeOuter2 = 48 * 48;
  static const double _grazeInner2 = 24 * 24;

  late final CircleHitbox _hitbox =
      CircleHitbox(collisionType: CollisionType.inactive);

  static Sprite? _enemySprite;
  static Sprite? _bossSprite;
  static Sprite? _mortarSprite;

  bool get _isMortar => gravity != 0;

  Sprite get _sprite => _isMortar
      ? (_mortarSprite ??=
          Sprite(Flame.images.fromCache(GameAssets.mortarShell)))
      : fromBoss
          ? (_bossSprite ??=
              Sprite(Flame.images.fromCache(GameAssets.bulletBoss)))
          : (_enemySprite ??=
              Sprite(Flame.images.fromCache(GameAssets.bulletEnemy)));

  @override
  Future<void> onLoad() async {
    add(_hitbox);
  }

  void activate({
    required Vector2 spawn,
    required Vector2 velocity,
    double damage = 0.34,
    bool fromBoss = false,
    double gravity = 0,
  }) {
    this.velocity.setFrom(velocity);
    this.damage = damage;
    this.fromBoss = fromBoss;
    this.gravity = gravity;
    _grazed = false;
    final side = gravity != 0 ? 22.0 : (fromBoss ? 18.0 : 14.0);
    size.setValues(side, side);
    position.setFrom(spawn);
    active = true;
    _hitbox.collisionType = CollisionType.active;
  }

  void deactivate() {
    if (!active) return;
    active = false;
    _hitbox.collisionType = CollisionType.inactive;
    position.setValues(-9999, -9999);
  }

  @override
  void update(double dt) {
    if (!active) return;
    // Slow-mo power-up stretches enemy time.
    final scaledDt = dt * game.enemyTimeScale;
    if (gravity != 0) velocity.y += gravity * scaledDt;
    position += velocity * scaledDt;
    // Graze: once per bullet, while the player can actually be hit (no
    // free meter during ghost/invuln windows).
    if (!_grazed) {
      final p = game.player;
      if (!p.ghosted && !p.isInvulnerable) {
        final d2 = position.distanceToSquared(p.position);
        if (d2 < _grazeOuter2 && d2 > _grazeInner2) {
          _grazed = true;
          game.onGraze(position.clone());
        }
      }
    }
    if (position.x < -20 ||
        position.x > game.size.x + 30 ||
        position.y < -20 ||
        position.y > game.size.y + 20) {
      deactivate();
    }
  }

  @override
  void render(Canvas canvas) {
    if (!active) return;
    if (_isMortar) {
      // The shell art points up-right (-45°); spin it along the arc.
      canvas.save();
      canvas.translate(size.x / 2, size.y / 2);
      canvas.rotate(math.atan2(velocity.y, velocity.x) + math.pi / 4);
      canvas.translate(-size.x / 2, -size.y / 2);
      _sprite.render(canvas, size: size);
      canvas.restore();
      return;
    }
    _sprite.render(canvas, size: size);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (!active) return;
    if (other is PlayerShip) {
      // Ghost mode: shots pass straight through the phased-out ship.
      if (game.player.ghosted) return;
      game.onPlayerHit(damage);
      deactivate();
    }
  }
}
