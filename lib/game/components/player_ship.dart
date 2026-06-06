import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';
import '../game_assets.dart';
import '../game_audio.dart';
import 'bullets.dart';
import 'enemy.dart';
import 'fx.dart';
import 'power_up.dart';

enum WeaponMode { single, rapid, spread, laser }

/// The player's ship. Confined to the left portion of the screen, moves
/// toward the drag target (or by d-pad direction), and auto-fires forward.
/// Rendered with the 3-pose sprite set (level / banking up / banking down)
/// plus a looping exhaust animation, shield bubble, and muzzle flashes.
class PlayerShip extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  PlayerShip()
      : super(size: Vector2(51, 34), anchor: Anchor.center, priority: 10);

  double health = 1.0;
  bool shielded = false;

  // ---- weapon ----
  WeaponMode weapon = WeaponMode.single;
  double _weaponTimer = 0;
  double _fireCooldown = 0;

  // ---- timed effects (power-ups / armed loadout) ----
  double _invuln = 0;
  double speedTimer = 0;
  double ghostTimer = 0;
  double magnetTimer = 0;

  // ---- one-shot charges (armed loadout) ----
  /// First lethal-or-not hit is negated by warping back to spawn.
  int teleportCharges = 0;

  /// When health would hit zero, restore to 0.5 instead of losing a life.
  int scoreShieldCharges = 0;

  bool get isInvulnerable => _invuln > 0;
  bool get ghosted => ghostTimer > 0;
  bool get magnetActive => magnetTimer > 0;
  bool get speedBoosted => speedTimer > 0;

  double get weaponTimeLeft => _weaponTimer;
  double get speedTimeLeft => speedTimer;
  double get ghostTimeLeft => ghostTimer;
  double get magnetTimeLeft => magnetTimer;

  double get _moveSpeed => speedBoosted ? 700 : 520;

  /// Where shots leave the hull.
  Vector2 get nose => position + Vector2(size.x / 2, 0);

  // ---- input ----
  Vector2? _target; // pan-steer destination
  Vector2 moveDir = Vector2.zero(); // d-pad analog direction

  double get _leftBound => game.size.x * 0.04 + size.x / 2;
  // Keep the player's lane proportional to the SHORTER dimension so an
  // ultra-wide (21:9+) landscape screen doesn't hand them half the field.
  double get _rightBound => math.min(game.size.x * 0.42, game.size.y * 0.9);
  // Vertical limits span the full field — terrain is reachable (and
  // dangerous); the crash rule in TerrainStrip handles the consequences.
  double get _topBound => size.y / 2 + 4;
  double get _bottomBound => game.size.y - size.y / 2 - 4;

  // ---- sprites ----
  late final Sprite _spriteLevel =
      Sprite(Flame.images.fromCache(GameAssets.playerShip));
  late final Sprite _spriteUp =
      Sprite(Flame.images.fromCache(GameAssets.playerShipUp));
  late final Sprite _spriteDown =
      Sprite(Flame.images.fromCache(GameAssets.playerShipDown));
  late final Sprite _shieldSprite =
      Sprite(Flame.images.fromCache(GameAssets.shieldBubble));
  late final SpriteAnimationTicker _exhaust =
      loopAnimation(GameAssets.playerExhaustSheet, 3, fps: 14).createTicker();

  /// Smoothed vertical velocity driving the banking pose.
  double _vySmoothed = 0;
  double _lastY = 0;

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox(
      collisionType: CollisionType.active,
      size: Vector2(size.x * 0.7, size.y * 0.7),
      position: size * 0.15,
    ));
    respawn();
    _lastY = position.y;
  }

  void respawn({bool withWarpFx = false}) {
    position = Vector2(game.size.x * 0.16, game.size.y / 2);
    _target = position.clone();
    moveDir = Vector2.zero();
    _invuln = withWarpFx ? 3.0 : 1.5;
    if (withWarpFx) game.add(warpFlash(position));
  }

  /// Bounce away from a terrain surface: displace, kill the steer target
  /// so a held drag doesn't immediately re-enter, and grant anti-grind
  /// invulnerability (handled by the caller via [grantInvuln]).
  void bounce(Vector2 displacement) {
    position += displacement;
    position.y = position.y.clamp(_topBound, _bottomBound);
    _target = position.clone();
    moveDir = Vector2.zero();
  }

  void grantInvuln(double seconds) {
    if (_invuln < seconds) _invuln = seconds;
  }

  void steerTo(Vector2 target) {
    _target = target.clone();
    moveDir = Vector2.zero();
  }

  /// D-pad analog input; latest input wins over pan-steer.
  void setMoveDirection(Vector2 dir) {
    moveDir = dir.clone();
    if (!dir.isZero()) _target = null;
  }

  /// One step up the weapon ladder (weapon orb). Re-pickup at the top
  /// tier just refreshes the timer.
  void tierUpWeapon() {
    weapon = switch (weapon) {
      WeaponMode.single => WeaponMode.rapid,
      WeaponMode.rapid => WeaponMode.spread,
      WeaponMode.spread => WeaponMode.laser,
      WeaponMode.laser => WeaponMode.laser,
    };
    _weaponTimer = 10;
  }

  void applyPowerUp(PowerUpKind kind) {
    switch (kind) {
      case PowerUpKind.weapon:
        tierUpWeapon();
        break;
      case PowerUpKind.shield:
        shielded = true;
        break;
      case PowerUpKind.speed:
        speedTimer = math.max(speedTimer, 10);
        break;
      case PowerUpKind.ghost:
        ghostTimer = math.max(ghostTimer, 5);
        break;
      case PowerUpKind.magnet:
        magnetTimer = math.max(magnetTimer, 8);
        break;
      case PowerUpKind.life:
      case PowerUpKind.bomb:
      case PowerUpKind.x2:
      case PowerUpKind.missiles:
      case PowerUpKind.slowmo:
        // Handled by the game (lives / screen-clear / score / ammo / time).
        break;
    }
  }

  void popShield() {
    shielded = false;
    _invuln = 0.8;
  }

  /// Armed-loadout teleport: negate the incoming hit by warping home.
  /// Returns true when a charge was consumed.
  bool consumeTeleportCharge() {
    if (teleportCharges <= 0) return false;
    teleportCharges--;
    respawn(withWarpFx: true);
    _invuln = 1.5;
    return true;
  }

  /// Armed-loadout score shield: returns true when a charge absorbed the
  /// would-be-lethal hit (caller restores health to 0.5).
  bool consumeScoreShieldCharge() {
    if (scoreShieldCharges <= 0) return false;
    scoreShieldCharges--;
    return true;
  }

  @override
  void update(double dt) {
    if (_invuln > 0) _invuln -= dt;
    if (speedTimer > 0) speedTimer -= dt;
    if (ghostTimer > 0) ghostTimer -= dt;
    if (magnetTimer > 0) magnetTimer -= dt;
    if (_weaponTimer > 0) {
      _weaponTimer -= dt;
      if (_weaponTimer <= 0) weapon = WeaponMode.single;
    }
    _exhaust.update(dt);

    // ---- movement: d-pad direction OR pan-steer target ----
    if (!moveDir.isZero()) {
      position += moveDir * _moveSpeed * dt;
      position.x = position.x.clamp(_leftBound, _rightBound);
      position.y = position.y.clamp(_topBound, _bottomBound);
    } else {
      final target = _target;
      if (target != null) {
        final clampedX = target.x.clamp(_leftBound, _rightBound).toDouble();
        final clampedY = target.y.clamp(_topBound, _bottomBound).toDouble();
        final dest = Vector2(clampedX, clampedY);
        final delta = dest - position;
        final maxStep = _moveSpeed * dt;
        if (delta.length <= maxStep) {
          position = dest;
        } else {
          position += delta.normalized() * maxStep;
        }
      }
    }

    // Banking pose from smoothed vertical velocity.
    if (dt > 0) {
      final vy = (position.y - _lastY) / dt;
      _vySmoothed += (vy - _vySmoothed) * math.min(1, dt * 10);
      _lastY = position.y;
    }

    _fireCooldown -= dt;
    if (game.autoFire &&
        _fireCooldown <= 0 &&
        game.phase == GamePhase.playing) {
      fire();
    }
  }

  void fire() {
    if (_fireCooldown > 0) return;
    final cooldownScale = speedBoosted ? 0.85 : 1.0;
    final spawnNose = nose;
    switch (weapon) {
      case WeaponMode.single:
        game.add(PlayerBullet(spawn: spawnNose.clone()));
        _fireCooldown = 0.28 * cooldownScale;
        break;
      case WeaponMode.rapid:
        game.add(PlayerBullet(spawn: spawnNose.clone(), speed: 620));
        _fireCooldown = 0.12 * cooldownScale;
        break;
      case WeaponMode.spread:
        for (final dy in const [-90.0, 0.0, 90.0]) {
          final b = PlayerBullet(spawn: spawnNose.clone());
          game.add(b);
          b.add(_SpreadDrift(dy));
        }
        _fireCooldown = 0.26 * cooldownScale;
        break;
      case WeaponMode.laser:
        game.add(PlayerBullet(
          spawn: spawnNose.clone(),
          speed: 820,
          damage: 3,
          heavy: true,
        ));
        _fireCooldown = 0.2 * cooldownScale;
        break;
    }
    game.add(muzzleFlash(spawnNose + Vector2(6, 0)));
    GameAudio.shoot();
  }

  @override
  void render(Canvas canvas) {
    // Invulnerability blink: skip every other flicker window.
    final blinkOff = _invuln > 0 && (_invuln * 8 % 1) > 0.5;

    // Ghost mode: phase the whole ship to half alpha.
    final paint = ghosted
        ? (Paint()..color = const Color(0x80FFFFFF))
        : (blinkOff ? (Paint()..color = const Color(0x55FFFFFF)) : null);

    // Exhaust behind the tail.
    final exhaustSprite = _exhaust.getSprite();
    exhaustSprite.render(
      canvas,
      position: Vector2(-14, size.y / 2 - 9),
      size: Vector2.all(18),
      overridePaint: paint,
    );

    // Banking pose by smoothed vertical velocity (screen y grows down).
    final sprite = _vySmoothed < -60
        ? _spriteUp
        : (_vySmoothed > 60 ? _spriteDown : _spriteLevel);
    sprite.render(canvas, size: size, overridePaint: paint);

    if (shielded) {
      _shieldSprite.render(
        canvas,
        position: Vector2(-7, -10),
        size: Vector2(size.x + 14, size.y + 20),
      );
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is EnemyShip) {
      // Ghost mode: pass straight through hostiles.
      if (ghosted) return;
      if (_invuln <= 0) game.onPlayerHit(other.contactDamage);
      other.takeDamage(2);
    }
  }
}

/// Drives a spread bullet diagonally by nudging its vertical position.
class _SpreadDrift extends Component {
  _SpreadDrift(this.vy);
  final double vy;

  @override
  void update(double dt) {
    final parent = this.parent;
    if (parent is PositionComponent) {
      parent.position.y += vy * dt;
    }
  }
}
