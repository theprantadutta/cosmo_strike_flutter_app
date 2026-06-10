import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';
import '../game_assets.dart';
import '../game_audio.dart';
import '../levels/level_def.dart';
import 'fx.dart';

enum EnemyPattern { straight, sine, dive, tracking }

/// A single hostile. Type-driven stats (sprite, hp, speed, fire style,
/// contact damage) come from [EnemyTypeStats]; level scalars multiply on
/// top. Spawns off the right edge and advances left using its pattern.
class EnemyShip extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  EnemyShip({
    required this.type,
    EnemyPattern? pattern,
    required Vector2 spawn,
    double hpScale = 1,
    double speedScale = 1,
    double fireRateScale = 1,
    double scoreScale = 1,
  })  : pattern = type == EnemyType.kamikaze
            ? EnemyPattern.dive // kamikazes always commit
            : (pattern ?? type.defaultPattern),
        hp = (type.baseHp * hpScale).ceil(),
        speed = type.baseSpeed * speedScale,
        pointValue = (type.basePoints * scoreScale).round(),
        contactDamage = type.contactDamage,
        _fireRateScale = fireRateScale,
        super(
          position: spawn,
          size: type.logicalSize,
          anchor: Anchor.center,
          priority: 9,
        );

  final EnemyType type;
  final EnemyPattern pattern;
  int hp;
  final double speed;
  final int pointValue;
  final double contactDamage;
  final double _fireRateScale;

  double _age = 0;
  double _fireTimer = 0;
  int _burstShotsLeft = 0;
  double _burstTimer = 0;

  /// White hit-flash countdown (seconds).
  double _flash = 0;
  static final Paint _flashPaint = Paint()
    ..colorFilter =
        const ColorFilter.mode(Color(0xB8FFFFFF), BlendMode.srcATop);
  late final double _baseY = position.y;
  late final double _fireInterval =
      (1.4 + game.rng.nextDouble() * 1.6) / _fireRateScale;

  // Mines animate (4-frame rotation loop); everything else is a sprite.
  Sprite? _sprite;
  SpriteAnimationTicker? _animTicker;

  @override
  Future<void> onLoad() async {
    if (type == EnemyType.mine) {
      _animTicker = loopAnimation(GameAssets.enemyMineSheet, 4, fps: 6)
          .createTicker();
    } else {
      _sprite = Sprite(Flame.images.fromCache(type.asset));
    }
    add(RectangleHitbox(
      collisionType: CollisionType.passive,
      // Inset so the transparent padding in the art never registers.
      size: Vector2(size.x * 0.74, size.y * 0.74),
      position: size * 0.13,
    ));
    _fireTimer = _fireInterval * (0.4 + game.rng.nextDouble());
  }

  @override
  void update(double dt) {
    // Slow-mo power-up stretches enemy time.
    dt *= game.enemyTimeScale;

    _age += dt;
    _animTicker?.update(dt);
    if (_flash > 0) _flash -= dt;
    position.x -= speed * dt;

    if (type.floorLocked) {
      // Ground unit: ride the floor strip.
      position.y = game.floorSurfaceY - size.y / 2;
    } else {
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
    }

    if (position.x < -60) removeFromParent();

    // Zen mode: enemies never shoot — collision is the only threat.
    if (!game.mode.enemiesFire || type.fireStyle == EnemyFireStyle.none) {
      return;
    }

    // Burst-in-progress (gunship): rattle off the queued shots.
    if (_burstShotsLeft > 0) {
      _burstTimer -= dt;
      if (_burstTimer <= 0) {
        _burstShotsLeft--;
        _burstTimer = 0.14;
        _fireOne();
      }
      return;
    }

    _fireTimer -= dt;
    if (_fireTimer <= 0 && position.x < game.size.x) {
      _fireTimer = _fireInterval;
      if (type.fireStyle == EnemyFireStyle.burst3) {
        _burstShotsLeft = 3;
        _burstTimer = 0;
      } else {
        _fireOne();
      }
    }
  }

  void _fireOne() {
    Vector2 velocity;
    final aimed = type.fireStyle == EnemyFireStyle.aimed ||
        type.fireStyle == EnemyFireStyle.burst3 ||
        pattern == EnemyPattern.tracking ||
        pattern == EnemyPattern.dive;
    if (aimed) {
      final dir = (game.player.position - position)..normalize();
      velocity = dir * 240;
    } else {
      velocity = Vector2(-260, 0);
    }
    game.pools.enemyBullet(spawn: position.clone(), velocity: velocity);
  }

  void takeDamage(int dmg) {
    hp -= dmg;
    if (hp <= 0) {
      GameAudio.enemyDown();
      game.onEnemyKilled(this);
      removeFromParent();
    } else {
      _flash = 0.09;
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = _flash > 0 ? _flashPaint : null;
    final ticker = _animTicker;
    if (ticker != null) {
      ticker.getSprite().render(canvas, size: size, overridePaint: paint);
    } else {
      _sprite?.render(canvas, size: size, overridePaint: paint);
    }
  }
}
