import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../cosmo_palette.dart';
import '../cosmo_strike_game.dart';
import 'bullets.dart';
import 'explosion.dart';
import 'player_ship.dart';

/// End-of-stage boss. Enters from the right, holds station near the right edge
/// while weaving vertically, and cycles through two attack patterns (radial
/// spray + aimed burst). Reports its health to the HUD via the game notifier.
class Boss extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  Boss({required this.maxHp, required Vector2 spawn})
      : super(position: spawn, size: Vector2(96, 90), anchor: Anchor.center);

  final int maxHp;
  late int hp = maxHp;

  bool _entered = false;
  double _age = 0;
  double _attackTimer = 1.5;
  int _attackIndex = 0;
  late final double _stationX = game.size.x * 0.78;
  late final double _baseY = game.size.y / 2;

  @override
  Future<void> onLoad() async {
    add(CircleHitbox(
      collisionType: CollisionType.passive,
      radius: size.x * 0.42,
      position: size * 0.08,
    ));
  }

  @override
  void update(double dt) {
    _age += dt;
    if (!_entered) {
      position.x -= 120 * dt;
      if (position.x <= _stationX) _entered = true;
      return;
    }
    position.y = _baseY + math.sin(_age * 1.2) * (game.size.y * 0.22);

    _attackTimer -= dt;
    if (_attackTimer <= 0) {
      _attackTimer = 1.8;
      _attackIndex++;
      if (_attackIndex.isEven) {
        _radialSpray();
      } else {
        _aimedBurst();
      }
    }
  }

  void _radialSpray() {
    const count = 12;
    for (int i = 0; i < count; i++) {
      final angle = math.pi * 0.5 + (i / (count - 1)) * math.pi; // left-facing half-circle
      final v = Vector2(math.cos(angle), math.sin(angle)) * 200;
      game.add(EnemyBullet(spawn: position.clone(), velocity: v, damage: 0.25));
    }
  }

  void _aimedBurst() {
    for (int i = -1; i <= 1; i++) {
      final dir = (game.player.position - position)..normalize();
      final spread = Vector2(0, i * 60.0);
      game.add(EnemyBullet(
        spawn: position.clone(),
        velocity: dir * 300 + spread,
        damage: 0.3,
      ));
    }
  }

  void takeDamage(int dmg) {
    hp -= dmg;
    game.bossHealthNotifier.value = (hp / maxHp).clamp(0, 1).toDouble();
    if (hp <= 0) {
      game.spawnExplosion(position.clone(), CosmoExplosionKind.boss);
      game.onBossDefeated();
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final body = Paint()..color = CosmoPalette.hostileDeep;
    final plate = Paint()..color = CosmoPalette.hostile;
    final core = Paint()..color = CosmoPalette.energy;
    final cx = size.x / 2;
    final cy = size.y / 2;
    // Hull: hexagon-ish menacing shape facing left.
    final path = Path()
      ..moveTo(0, cy)
      ..lineTo(size.x * 0.45, size.y * 0.05)
      ..lineTo(size.x, size.y * 0.2)
      ..lineTo(size.x, size.y * 0.8)
      ..lineTo(size.x * 0.45, size.y * 0.95)
      ..close();
    canvas.drawPath(path, body);
    canvas.drawRect(
      Rect.fromLTWH(size.x * 0.25, size.y * 0.3, size.x * 0.4, size.y * 0.4),
      plate,
    );
    canvas.drawCircle(Offset(cx * 0.7, cy), 10, core);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerShip) {
      game.onPlayerHit(0.5);
    }
  }
}
