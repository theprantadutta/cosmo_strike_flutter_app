import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../cosmo_strike_game.dart';
import '../../game_audio.dart';
import '../boss.dart';
import '../fx.dart';

/// A shootable pod orbiting its boss: War Machine shield generators and
/// Mothership escorts. While the boss phase says `invulnerableWhilePods`,
/// the core takes zero damage until every pod is down.
///
/// Rendered procedurally (pulsing neon orb) until dedicated pod sprites
/// land with the asset pass.
class BossPod extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  BossPod({
    required this.boss,
    required this.orbitIndex,
    required this.orbitCount,
    required int hp,
  })  : _hp = hp,
        _maxHp = hp,
        super(size: Vector2.all(34), anchor: Anchor.center, priority: 9);

  final Boss boss;
  final int orbitIndex;
  final int orbitCount;
  int _hp;
  final int _maxHp;
  double _age = 0;
  double _flash = 0;

  static const double orbitRadius = 96;
  static const double orbitOmega = 0.9;

  @override
  Future<void> onLoad() async {
    add(CircleHitbox(collisionType: CollisionType.passive));
    _place(0);
  }

  void _place(double dt) {
    _age += dt;
    final a = (orbitIndex / orbitCount) * math.pi * 2 + _age * orbitOmega;
    position.setValues(
      boss.position.x + math.cos(a) * orbitRadius,
      (boss.position.y + math.sin(a) * orbitRadius)
          .clamp(game.playfieldTop + 20, game.playfieldBottom - 20),
    );
  }

  @override
  void update(double dt) {
    dt *= game.enemyTimeScale;
    if (_flash > 0) _flash -= dt;
    if (boss.isRemoving || !boss.isMounted) {
      removeFromParent();
      return;
    }
    _place(dt);
  }

  void takeDamage(int dmg) {
    _hp -= dmg;
    if (_hp <= 0) {
      GameAudio.enemyDown();
      game.addKillScore(150);
      game.pools.scorePopup(position + Vector2(0, -20), 'POD DOWN');
      game.add(explosionSmall(position, scale: 1.2));
      removeFromParent();
    } else {
      _flash = 0.09;
    }
  }

  @override
  void onRemove() {
    boss.onPodGone(this);
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final hpFrac = (_hp / _maxHp).clamp(0.0, 1.0);
    final pulse = 0.6 + 0.4 * math.sin(_age * 6);
    final core = _flash > 0
        ? const Color(0xFFFFFFFF)
        : Color.lerp(const Color(0xFFFF2D78), const Color(0xFFFFB36B),
            1 - hpFrac)!;
    canvas.drawCircle(
      c,
      size.x * 0.46,
      Paint()..color = core.withValues(alpha: 0.22 * pulse),
    );
    canvas.drawCircle(c, size.x * 0.3, Paint()..color = core);
    canvas.drawCircle(
      c,
      size.x * 0.3,
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.5 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
