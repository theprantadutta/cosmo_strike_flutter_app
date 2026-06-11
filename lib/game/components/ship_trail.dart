import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../models/premium_cosmetics.dart';
import '../cosmo_strike_game.dart';

class _TrailParticle {
  double x = 0, y = 0, vx = 0, vy = 0, age = 0, life = 0, size = 0;
  Color color = const Color(0x00000000);
  bool get alive => age < life;
}

/// Cosmetic particle stream behind the player ship, colored from the
/// equipped [TrailEffectType]'s palette. Preallocated ring of
/// [_maxParticles] — zero per-frame allocation, no child components
/// mounting/unmounting (the always-mounted pooling philosophy of
/// pools.dart, without touching it). Emits only while the run is live;
/// `pauseEngine()` freezes everything for free since it's pure
/// game-time.
///
/// Render cost: worst case 48 particles × 2 `drawCircle` (soft halo +
/// bright core, no MaskFilter) — trivial at 60fps.
class ShipTrail extends Component with HasGameReference<CosmoStrikeGame> {
  ShipTrail(this.type) : super(priority: 9); // just under the ship (10)

  final TrailEffectType type;

  static const int _maxParticles = 48;
  static const double _emitInterval = 0.030; // ~33 particles/s

  final List<_TrailParticle> _particles =
      List.generate(_maxParticles, (_) => _TrailParticle());
  final Paint _paint = Paint();
  final math.Random _rng = math.Random();
  double _emitAccum = 0;
  int _next = 0;
  int _colorCursor = 0;

  @override
  void update(double dt) {
    // Age + advect everything alive (keeps in-flight particles moving
    // through level intros / clears instead of freezing mid-air).
    for (final p in _particles) {
      if (!p.alive) continue;
      p.age += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
    // Emit only during live play so menus/overlays never pile up a
    // stale stream at the spawn point.
    if (game.phase != GamePhase.playing) return;
    _emitAccum += dt;
    while (_emitAccum >= _emitInterval) {
      _emitAccum -= _emitInterval;
      _spawn();
    }
  }

  void _spawn() {
    final p = _particles[_next];
    _next = (_next + 1) % _maxParticles; // recycle oldest slot
    final ship = game.player;
    p.x = ship.position.x - ship.size.x * 0.55;
    p.y = ship.position.y + (_rng.nextDouble() - 0.5) * 8;
    p.vx = -140 - _rng.nextDouble() * 60; // stream left, behind the ship
    p.vy = (_rng.nextDouble() - 0.5) * 26;
    p.age = 0;
    p.life = 0.45 + _rng.nextDouble() * 0.30;
    p.size = 2.0 + _rng.nextDouble() * 2.0;
    final colors = type.colors;
    p.color = colors.isEmpty
        ? const Color(0xFFFFFFFF)
        : colors[_colorCursor % colors.length];
    _colorCursor++;
  }

  @override
  void render(Canvas canvas) {
    for (final p in _particles) {
      if (!p.alive) continue;
      if (p.x < -24) continue; // scrolled offscreen — skip draw
      final fade = 1.0 - p.age / p.life;
      final o = Offset(p.x, p.y);
      _paint.color = p.color.withValues(alpha: 0.18 * fade); // soft halo
      canvas.drawCircle(o, p.size * 2.2, _paint);
      _paint.color = p.color.withValues(alpha: 0.85 * fade); // bright core
      canvas.drawCircle(o, p.size * fade, _paint);
    }
  }
}
