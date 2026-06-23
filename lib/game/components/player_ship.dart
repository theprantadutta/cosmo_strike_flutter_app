import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/painting.dart';

import '../../models/premium_cosmetics.dart' show ShipSkinType;
import '../cosmo_strike_game.dart';
import '../game_assets.dart';
import '../game_audio.dart';
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

  /// Post-revive protection: a timed shield that keeps the ship fully
  /// invulnerable AND renders the shield bubble for its whole duration, so the
  /// player can clearly see they can't die for the next few seconds. Distinct
  /// from the one-hit [shielded] power-up; surfaced as a HUD effect chip.
  double protectTimer = 0;

  /// Red hull flash on landed hits — the ship itself must scream "hit".
  double _damageFlash = 0;
  static final Paint _damagePaint = Paint()
    ..colorFilter =
        const ColorFilter.mode(Color(0xCCFF4D6E), BlendMode.srcATop);

  void flashDamage() => _damageFlash = 0.35;

  // ---- cosmetic skin (tint + glow) ----
  // srcATop at partial alpha tints the hull in the skin's palette while
  // keeping ~45% of the sprite's own shading (full alpha would flatten
  // it to a silhouette; modulate would multiply dark palettes to mud).
  // Classic = null paints = bitwise-identical stock render.
  static const double _skinTintAlpha = 0.55;
  static const double _skinGlowAlpha = 0.30;
  ShipSkinType _skin = ShipSkinType.classic;
  Paint? _skinPaint;
  Paint? _skinGlowPaint;
  double _skinTime = 0;

  // ---- one-shot charges (armed loadout) ----
  /// First lethal-or-not hit is negated by warping back to spawn.
  int teleportCharges = 0;

  /// When health would hit zero, restore to 0.5 instead of losing a life.
  int scoreShieldCharges = 0;

  bool get isInvulnerable => _invuln > 0;
  bool get ghosted => ghostTimer > 0;
  bool get magnetActive => magnetTimer > 0;
  bool get speedBoosted => speedTimer > 0;
  bool get protected => protectTimer > 0;

  double get weaponTimeLeft => _weaponTimer;
  double get speedTimeLeft => speedTimer;
  double get ghostTimeLeft => ghostTimer;
  double get magnetTimeLeft => magnetTimer;
  double get protectTimeLeft => protectTimer;

  double get _moveSpeed => speedBoosted ? 700 : 520;

  /// Where shots leave the hull.
  Vector2 get nose => position + Vector2(size.x / 2, 0);

  // ---- input ----
  Vector2? _target; // pan-steer destination
  Vector2 moveDir = Vector2.zero(); // d-pad analog direction

  /// Smoothed velocity (≈110 ms response): the ship eases into and out of
  /// motion instead of snapping to max speed, so flight reads smooth.
  final Vector2 _vel = Vector2.zero();

  double get _leftBound => game.size.x * 0.04 + size.x / 2;
  // The classic Space Impact stance: hold the LEFT lane and shoot across
  // the field. The band is deliberately tight (~4%–20% of the width) so
  // the game is about vertical dodging, not roaming the screen. Kept
  // proportional to the shorter dimension so an ultra-wide (21:9+)
  // landscape screen doesn't hand the player half the field. The
  // BoundaryGlow component lights this wall up when the ship presses
  // against it.
  double get _rightBound => math.min(game.size.x * 0.20, game.size.y * 0.9);

  /// Public for the boundary glow renderer.
  double get rightBound => _rightBound;
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

    // Equipped cosmetic skin → tint + glow paints (classic stays null).
    _skin = ShipSkinType.values
            .where((s) => s.id == game.selectedSkinId)
            .firstOrNull ??
        ShipSkinType.classic;
    if (_skin != ShipSkinType.classic && _skin.colors.isNotEmpty) {
      final c = _skin.colors.first;
      _skinPaint = Paint()
        ..colorFilter = ColorFilter.mode(
            c.withValues(alpha: _skinTintAlpha), BlendMode.srcATop);
      _skinGlowPaint = Paint()
        ..color = c.withValues(alpha: _skinGlowAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    }
  }

  void respawn({bool withWarpFx = false}) {
    position = Vector2(game.size.x * 0.16, game.size.y / 2);
    _target = position.clone();
    moveDir = Vector2.zero();
    _vel.setZero();
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
    _vel.setZero();
  }

  void grantInvuln(double seconds) {
    if (_invuln < seconds) _invuln = seconds;
  }

  /// Timed protective shield (used on revive): the ship can't be hit for
  /// [seconds] and the shield bubble renders the whole time so the grace
  /// window reads clearly. The bubble and invulnerability expire together.
  void grantProtection(double seconds) {
    if (protectTimer < seconds) protectTimer = seconds;
    grantInvuln(seconds);
  }

  /// Terrain rising under/over the ship displaces it without damage
  /// (the fairness rule for animated corridors).
  void pushOutY(double y) {
    position.y = y.clamp(_topBound, _bottomBound);
    _vel.y = 0;
  }

  void steerTo(Vector2 target) {
    _target = target.clone();
    moveDir = Vector2.zero();
  }

  /// Relative-drag input: shift the steer destination by [delta]
  /// (already sensitivity-scaled). The destination clamps to the
  /// movement bounds so dragging past a wall doesn't bank up overshoot.
  void nudgeTarget(Vector2 delta) {
    final base = _target ?? position.clone();
    base.add(delta);
    base.x = base.x.clamp(_leftBound, _rightBound).toDouble();
    base.y = base.y.clamp(_topBound, _bottomBound).toDouble();
    _target = base;
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
    if (protectTimer > 0) protectTimer -= dt;
    if (_damageFlash > 0) _damageFlash -= dt;
    if (speedTimer > 0) speedTimer -= dt;
    if (ghostTimer > 0) ghostTimer -= dt;
    if (magnetTimer > 0) magnetTimer -= dt;
    if (_weaponTimer > 0) {
      _weaponTimer -= dt;
      if (_weaponTimer <= 0) weapon = WeaponMode.single;
    }
    _exhaust.update(dt);

    // Multi-color skins cycle their palette (rainbow sweeps, golden
    // shimmers): lerp between consecutive colors, one second per color.
    // Re-targets the existing Paint objects — no per-frame allocation
    // beyond the immutable ColorFilter.
    final skinColors = _skin.colors;
    if (_skinPaint != null && skinColors.length > 1) {
      _skinTime += dt;
      final t = _skinTime % skinColors.length;
      final i = t.floor();
      final c = Color.lerp(
          skinColors[i], skinColors[(i + 1) % skinColors.length], t - i)!;
      _skinPaint!.colorFilter = ColorFilter.mode(
          c.withValues(alpha: _skinTintAlpha), BlendMode.srcATop);
      _skinGlowPaint!.color = c.withValues(alpha: _skinGlowAlpha);
    }

    // ---- movement: smoothed velocity toward the desired vector ----
    // (d-pad direction OR pan-steer target with proportional braking)
    final desired = _desiredVelocity();
    final blend = math.min(1.0, dt * 9);
    _vel.x += (desired.x - _vel.x) * blend;
    _vel.y += (desired.y - _vel.y) * blend;
    position.x += _vel.x * dt;
    position.y += _vel.y * dt;
    final cx = position.x.clamp(_leftBound, _rightBound).toDouble();
    final cy = position.y.clamp(_topBound, _bottomBound).toDouble();
    if (cx != position.x) {
      position.x = cx;
      _vel.x = 0;
    }
    if (cy != position.y) {
      position.y = cy;
      _vel.y = 0;
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

  /// The velocity the ship is trying to reach this frame.
  Vector2 _desiredVelocity() {
    if (!moveDir.isZero()) return moveDir * _moveSpeed;
    final target = _target;
    if (target == null) return Vector2.zero();
    final dest = Vector2(
      target.x.clamp(_leftBound, _rightBound).toDouble(),
      target.y.clamp(_topBound, _bottomBound).toDouble(),
    );
    final delta = dest - position;
    final dist = delta.length;
    if (dist < 2) return Vector2.zero();
    // Proportional braking near the destination — smooth arrival, no
    // overshoot jitter.
    final speed = math.min(_moveSpeed, dist * 10);
    return delta..scale(speed / dist);
  }

  void fire() {
    if (_fireCooldown > 0) return;
    final cooldownScale = speedBoosted ? 0.85 : 1.0;
    final spawnNose = nose;
    switch (weapon) {
      case WeaponMode.single:
        game.pools.playerBullet(spawn: spawnNose);
        _fireCooldown = 0.28 * cooldownScale;
        break;
      case WeaponMode.rapid:
        game.pools.playerBullet(spawn: spawnNose, speed: 620);
        _fireCooldown = 0.12 * cooldownScale;
        break;
      case WeaponMode.spread:
        for (final dy in const [-90.0, 0.0, 90.0]) {
          game.pools.playerBullet(spawn: spawnNose, driftY: dy);
        }
        _fireCooldown = 0.26 * cooldownScale;
        break;
      case WeaponMode.laser:
        game.pools.playerBullet(
          spawn: spawnNose,
          speed: 820,
          damage: 3,
          heavy: true,
        );
        _fireCooldown = 0.2 * cooldownScale;
        break;
    }
    game.pools.muzzleFlash(spawnNose + Vector2(6, 0));
    GameAudio.shoot();
  }

  @override
  void render(Canvas canvas) {
    // Invulnerability blink: skip every other flicker window.
    final blinkOff = _invuln > 0 && (_invuln * 8 % 1) > 0.5;

    // Paint priority: ghost phase > fresh-damage red flash > invuln
    // blink > cosmetic skin tint. Gameplay feedback always reads over
    // the cosmetic.
    final paint = ghosted
        ? (Paint()..color = const Color(0x80FFFFFF))
        : _damageFlash > 0
            ? _damagePaint
            : (blinkOff
                ? (Paint()..color = const Color(0x55FFFFFF))
                : _skinPaint);

    // Skin glow halo behind everything — suppressed during blink-off
    // frames so the invulnerability flicker still reads.
    if (_skinGlowPaint != null && !blinkOff) {
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        size.x * 0.62,
        _skinGlowPaint!,
      );
    }

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

    // Shield bubble: the one-hit [shielded] power-up OR the timed post-revive
    // protection window — both read as the same protective dome.
    if (shielded || protectTimer > 0) {
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

/// A faint neon wall that fades in only while the ship presses against
/// its right movement bound — the engagement zone reads as "my zone"
/// instead of the controls feeling stuck, with no permanent line on the
/// clean playfield.
class BoundaryGlow extends PositionComponent
    with HasGameReference<CosmoStrikeGame> {
  BoundaryGlow() : super(priority: 3);

  double _intensity = 0;
  double _age = 0;

  @override
  void update(double dt) {
    _age += dt;
    final p = game.player;
    final pressing = p.position.x >= p.rightBound - 6;
    final target = pressing ? 1.0 : 0.0;
    _intensity +=
        (target - _intensity) * math.min(1, dt * (pressing ? 12 : 4));
  }

  @override
  void render(Canvas canvas) {
    if (_intensity < 0.04) return;
    final p = game.player;
    final x = p.rightBound + p.size.x / 2 + 6;
    final top = game.playfieldTop + 6;
    final bottom = game.playfieldBottom - 6;
    final shimmer = 0.8 + 0.2 * math.sin(_age * 9);
    // Soft halo + crisp core line.
    canvas.drawLine(
      Offset(x, top),
      Offset(x, bottom),
      Paint()
        ..color = const Color(0xFF22D3EE)
            .withValues(alpha: 0.10 * _intensity * shimmer)
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(x, top),
      Offset(x, bottom),
      Paint()
        ..color = const Color(0xFF9BEAF8)
            .withValues(alpha: 0.5 * _intensity * shimmer)
        ..strokeWidth = 2,
    );
  }
}
