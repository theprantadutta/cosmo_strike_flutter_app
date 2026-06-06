import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../cosmo_palette.dart';
import '../cosmo_strike_game.dart';

class _Star {
  _Star(this.position, this.speed, this.radius, this.opacity);
  Vector2 position;
  final double speed;
  final double radius;
  final double opacity;
}

/// Programmatic scrolling parallax starfield. Three depth layers of dots drift
/// left at different speeds — zero external art. Stands in for a real
/// ParallaxComponent (see ASSETS_NEEDED.md for the nebula/layer art).
class Starfield extends PositionComponent with HasGameReference<CosmoStrikeGame> {
  Starfield() : super(priority: -100);

  final List<_Star> _stars = [];
  final math.Random _rng = math.Random(42);

  /// Biome accent for the bright (near) stars; far stars stay icy.
  Color _tint = CosmoPalette.hullLight;

  /// Recolor the field for the active biome (called on level change).
  void setTint(Color tint) => _tint = tint;

  @override
  Future<void> onLoad() async {
    size = game.size;
    final count = (size.x * size.y / 5500).clamp(60, 220).toInt();
    for (int i = 0; i < count; i++) {
      final layer = _rng.nextInt(3); // 0 far, 2 near
      final speed = 18.0 + layer * 34.0 + _rng.nextDouble() * 12;
      final radius = 0.6 + layer * 0.7;
      final opacity = 0.25 + layer * 0.22;
      _stars.add(_Star(
        Vector2(_rng.nextDouble() * size.x, _rng.nextDouble() * size.y),
        speed,
        radius,
        opacity,
      ));
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  void update(double dt) {
    for (final s in _stars) {
      s.position.x -= s.speed * dt;
      if (s.position.x < -2) {
        s.position.x = size.x + 2;
        s.position.y = _rng.nextDouble() * size.y;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint();
    for (final s in _stars) {
      paint.color = (s.radius > 1.4 ? CosmoPalette.highlight : _tint)
          .withValues(alpha: s.opacity);
      canvas.drawCircle(Offset(s.position.x, s.position.y), s.radius, paint);
    }
  }
}
