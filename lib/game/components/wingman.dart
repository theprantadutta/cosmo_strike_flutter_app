import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';
import '../game_assets.dart';

/// Wingman Drone upgrade: a small escort that trails the ship above
/// (index 0) or below (index 1) and auto-fires forward. Cosmetic body only —
/// it can't be hit and never collides.
class Wingman extends PositionComponent with HasGameReference<CosmoStrikeGame> {
  Wingman({required this.index})
      : super(size: Vector2(28, 19), anchor: Anchor.center, priority: 9);

  final int index;
  double _cooldown = 0.2;

  late final Sprite _sprite =
      Sprite(Flame.images.fromCache(GameAssets.playerShip));
  static final Paint _paint = Paint()..color = const Color(0xCCFFFFFF);

  Vector2 get _slot =>
      game.player.position + Vector2(-16, index == 0 ? -42 : 42);

  @override
  Future<void> onLoad() async {
    position = _slot;
  }

  @override
  void update(double dt) {
    // Ease toward the slot so the escort trails the ship's movement.
    position += (_slot - position) * (dt * 9).clamp(0, 1);
    if (game.phase != GamePhase.playing) return;
    _cooldown -= dt;
    if (_cooldown <= 0) {
      _cooldown = 0.34 * game.upgrades.fireCooldownScale;
      game.pools.playerBullet(
        spawn: position + Vector2(size.x / 2, 0),
        damage: 1 + game.upgrades.bonusDamage,
        pierce: game.upgrades.pierce,
      );
    }
  }

  @override
  void render(Canvas canvas) {
    _sprite.render(canvas, size: size, overridePaint: _paint);
  }
}
