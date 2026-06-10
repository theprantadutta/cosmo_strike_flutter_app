import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../../cosmo_strike_game.dart';
import '../../game_assets.dart';
import '../../game_audio.dart';
import '../boss.dart';
import '../fx.dart';

/// A shootable pod orbiting its boss: War Machine shield generators and
/// Mothership escorts. While the boss phase says `invulnerableWhilePods`,
/// the core takes zero damage until every pod is down.
class BossPod extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  BossPod({
    required this.boss,
    required this.orbitIndex,
    required this.orbitCount,
    required int hp,
    this.isShieldGenerator = false,
  })  : _hp = hp,
        _maxHp = hp,
        super(size: Vector2.all(34), anchor: Anchor.center, priority: 9);

  final Boss boss;
  final int orbitIndex;
  final int orbitCount;

  /// Shield-generator art (War Machine) vs escort art (Mothership).
  final bool isShieldGenerator;
  int _hp;
  final int _maxHp;
  double _age = 0;
  double _flash = 0;

  late final Sprite _sprite = Sprite(Flame.images.fromCache(
      isShieldGenerator ? GameAssets.bossPodShield : GameAssets.bossPodEscort));

  static final Paint _flashPaint = Paint()
    ..colorFilter =
        const ColorFilter.mode(Color(0xB8FFFFFF), BlendMode.srcATop);

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
    // Low-hp pods pulse hotter; hits flash white.
    final hpFrac = (_hp / _maxHp).clamp(0.0, 1.0);
    final pulse = 0.5 + 0.5 * math.sin(_age * 6);
    final c = Offset(size.x / 2, size.y / 2);
    canvas.drawCircle(
      c,
      size.x * 0.55,
      Paint()
        ..color = const Color(0xFFFF2D78)
            .withValues(alpha: (0.10 + 0.16 * (1 - hpFrac)) * pulse),
    );
    _sprite.render(
      canvas,
      size: size,
      overridePaint: _flash > 0 ? _flashPaint : null,
    );
  }
}
