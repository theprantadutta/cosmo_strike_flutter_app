import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../cosmo_palette.dart';
import '../cosmo_strike_game.dart';
import 'bullets.dart';
import 'enemy.dart';
import 'power_up.dart';

enum WeaponMode { single, rapid, spread, laser }

/// The player's ship. Confined to the left portion of the screen, moves toward
/// the drag target, and auto-fires forward. Rendered as a geometric amber hull
/// (placeholder — see ASSETS_NEEDED.md for the real sprite/animation).
class PlayerShip extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  PlayerShip()
      : super(size: Vector2(46, 30), anchor: Anchor.center, priority: 10);

  double health = 1.0;
  bool shielded = false;
  WeaponMode weapon = WeaponMode.single;
  double _weaponTimer = 0;
  double _fireCooldown = 0;
  double _invuln = 0;

  Vector2? _target;

  double get _leftBound => game.size.x * 0.04 + size.x / 2;
  double get _rightBound => game.size.x * 0.42;

  @override
  Future<void> onLoad() async {
    add(RectangleHitbox(
      collisionType: CollisionType.active,
      size: Vector2(size.x * 0.7, size.y * 0.7),
      position: size * 0.15,
    ));
    respawn();
  }

  void respawn() {
    position = Vector2(game.size.x * 0.16, game.size.y / 2);
    _target = position.clone();
    _invuln = 1.5;
  }

  void steerTo(Vector2 target) => _target = target.clone();

  void applyPowerUp(PowerUpKind kind) {
    switch (kind) {
      case PowerUpKind.rapidFire:
        weapon = WeaponMode.rapid;
        _weaponTimer = 8;
        break;
      case PowerUpKind.spread:
        weapon = WeaponMode.spread;
        _weaponTimer = 8;
        break;
      case PowerUpKind.laser:
        weapon = WeaponMode.laser;
        _weaponTimer = 8;
        break;
      case PowerUpKind.shield:
        shielded = true;
        break;
      case PowerUpKind.extraLife:
      case PowerUpKind.bomb:
      case PowerUpKind.scoreMultiplier:
        // Handled by the game (lives / screen-clear / score multiplier).
        break;
    }
  }

  void popShield() {
    shielded = false;
    _invuln = 0.8;
  }

  @override
  void update(double dt) {
    if (_invuln > 0) _invuln -= dt;
    if (_weaponTimer > 0) {
      _weaponTimer -= dt;
      if (_weaponTimer <= 0) weapon = WeaponMode.single;
    }

    final target = _target;
    if (target != null) {
      final clampedX = target.x.clamp(_leftBound, _rightBound).toDouble();
      final clampedY =
          target.y.clamp(size.y / 2 + 8, game.size.y - size.y / 2 - 8).toDouble();
      final dest = Vector2(clampedX, clampedY);
      final delta = dest - position;
      final maxStep = 520 * dt;
      if (delta.length <= maxStep) {
        position = dest;
      } else {
        position += delta.normalized() * maxStep;
      }
    }

    _fireCooldown -= dt;
    if (game.autoFire && _fireCooldown <= 0) {
      fire();
    }
  }

  void fire() {
    if (_fireCooldown > 0) return;
    final nose = position + Vector2(size.x / 2, 0);
    switch (weapon) {
      case WeaponMode.single:
        game.add(PlayerBullet(spawn: nose.clone()));
        _fireCooldown = 0.28;
        break;
      case WeaponMode.rapid:
        game.add(PlayerBullet(spawn: nose.clone(), speed: 620));
        _fireCooldown = 0.12;
        break;
      case WeaponMode.spread:
        for (final dy in const [-90.0, 0.0, 90.0]) {
          final b = PlayerBullet(spawn: nose.clone())
            ..position.y = nose.y;
          game.add(b);
          b.add(_SpreadDrift(dy));
        }
        _fireCooldown = 0.26;
        break;
      case WeaponMode.laser:
        game.add(PlayerBullet(
          spawn: nose.clone(),
          speed: 820,
          damage: 3,
          tint: CosmoPalette.highlight,
        ));
        _fireCooldown = 0.2;
        break;
    }
  }

  @override
  void render(Canvas canvas) {
    final hull = Paint()..color = CosmoPalette.hull;
    final accent = Paint()..color = CosmoPalette.energy;
    // Arrow-shaped hull pointing right.
    final path = Path()
      ..moveTo(size.x, size.y / 2)
      ..lineTo(size.x * 0.2, 0)
      ..lineTo(size.x * 0.36, size.y / 2)
      ..lineTo(size.x * 0.2, size.y)
      ..close();
    canvas.drawPath(path, hull);
    // Cockpit / engine glow.
    canvas.drawCircle(
        Offset(size.x * 0.42, size.y / 2), 4, accent);
    canvas.drawRect(
      Rect.fromLTWH(0, size.y * 0.38, size.x * 0.2, size.y * 0.24),
      Paint()..color = CosmoPalette.hullDark,
    );
    if (shielded) {
      canvas.drawCircle(
        Offset(size.x / 2, size.y / 2),
        size.x * 0.7,
        Paint()
          ..color = CosmoPalette.energy.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    if (_invuln > 0) {
      // Blink overlay while invulnerable.
      canvas.drawPath(
          path,
          Paint()
            ..color = CosmoPalette.highlight
                .withValues(alpha: (_invuln * 6 % 1) > 0.5 ? 0.4 : 0.0));
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is EnemyShip) {
      if (_invuln <= 0) game.onPlayerHit(0.5);
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
