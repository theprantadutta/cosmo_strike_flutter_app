import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../../models/premium_cosmetics.dart';
import '../cosmo_strike_game.dart';
import '../game_assets.dart';

class _ExhaustParticle {
  double x = 0, y = 0, vx = 0, vy = 0, age = 0, life = 0, size = 0;
  Color color = const Color(0x00000000);
  bool get alive => age < life;
}

/// Cosmetic engine exhaust behind the player ship, styled by the equipped
/// [ExhaustType]:
///
/// * ion — thin cyan streaks plus a flickering ion line off the nozzle
/// * plasma — a fat, slow violet/pink plume
/// * ember — orange sparks shed with a downward drift
/// * comet — a long, tight tail fading white → cyan
/// * pulse — shock rings fired at intervals that expand as they drift
/// * quantum — ghost after-images of the hull
/// * nova — prism-cycling particles
///
/// Preallocated ring of [_maxParticles] — zero per-frame allocation beyond
/// immutable Colors, no child components mounting/unmounting (the
/// always-mounted pooling philosophy of pools.dart). Emits only while the
/// run is live; `pauseEngine()` freezes everything for free since it's
/// pure game-time.
///
/// Render cost: worst case 56 particles × 2 draws (no MaskFilter) or 5
/// hull echoes — trivial at 60fps.
class ShipExhaust extends Component with HasGameReference<CosmoStrikeGame> {
  ShipExhaust(this.type) : super(priority: 9); // just under the ship (10)

  final ExhaustType type;

  static const int _maxParticles = 56;
  static const int _echoCount = 5;

  final List<_ExhaustParticle> _particles =
      List.generate(_maxParticles, (_) => _ExhaustParticle());
  final Paint _paint = Paint();
  final Paint _ring = Paint()..style = PaintingStyle.stroke;
  final Paint _streak = Paint()..strokeCap = StrokeCap.round;
  final math.Random _rng = math.Random();
  double _emitAccum = 0;
  int _next = 0;
  int _colorCursor = 0;
  double _time = 0;

  /// Ion line flicker length (0..1), re-rolled each frame.
  double _flicker = 1;

  // ---- quantum echo: hull snapshots drifting behind the ship ----
  late final Sprite _hull =
      Sprite(Flame.images.fromCache(GameAssets.playerShip));
  final List<Vector2> _echoPos =
      List.generate(_echoCount, (_) => Vector2.zero());
  final List<double> _echoAge = List.filled(_echoCount, double.infinity);
  late final List<Paint> _echoPaints = [
    for (var i = 0; i < _echoCount; i++)
      Paint()
        ..colorFilter = ColorFilter.mode(
          type.colors[i % type.colors.length].withValues(alpha: 0.85),
          BlendMode.srcATop,
        ),
  ];
  static const double _echoLife = 0.45;
  final Vector2 _echoSize = Vector2(51, 34);
  int _echoNext = 0;

  double get _emitInterval => switch (type) {
        ExhaustType.ion => 0.022,
        ExhaustType.plasma => 0.030,
        ExhaustType.ember => 0.045,
        ExhaustType.comet => 0.016,
        ExhaustType.pulse => 0.22, // one ring per interval
        ExhaustType.quantum => 0.075, // one echo per interval
        ExhaustType.nova => 0.024,
        ExhaustType.stock => 1,
      };

  @override
  void update(double dt) {
    _time += dt;
    // Age + advect everything alive (keeps in-flight particles moving
    // through level intros / clears instead of freezing mid-air).
    for (final p in _particles) {
      if (!p.alive) continue;
      p.age += dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (type == ExhaustType.ember) p.vy += 70 * dt; // sparks fall away
    }
    for (var i = 0; i < _echoCount; i++) {
      if (_echoAge[i] >= _echoLife) continue;
      _echoAge[i] += dt;
      _echoPos[i].x -= 150 * dt;
    }
    _flicker = 0.55 + _rng.nextDouble() * 0.45;
    // Emit only during live play so menus/overlays never pile up a
    // stale stream at the spawn point.
    if (game.phase != GamePhase.playing) return;
    _emitAccum += dt;
    final interval = _emitInterval;
    while (_emitAccum >= interval) {
      _emitAccum -= interval;
      if (type == ExhaustType.quantum) {
        _spawnEcho();
      } else {
        _spawn();
      }
    }
  }

  void _spawnEcho() {
    final ship = game.player;
    _echoPos[_echoNext].setValues(
      ship.position.x - ship.size.x / 2,
      ship.position.y - ship.size.y / 2,
    );
    _echoAge[_echoNext] = 0;
    _echoNext = (_echoNext + 1) % _echoCount;
  }

  void _spawn() {
    final p = _particles[_next];
    _next = (_next + 1) % _maxParticles; // recycle oldest slot
    final ship = game.player;
    p.x = ship.position.x - ship.size.x * 0.55;
    p.y = ship.position.y;
    p.age = 0;
    final colors = type.colors;
    p.color = colors.isEmpty
        ? const Color(0xFFFFFFFF)
        : colors[_colorCursor % colors.length];
    _colorCursor++;
    final r = _rng.nextDouble();
    switch (type) {
      case ExhaustType.ion:
        p.y += (r - 0.5) * 3;
        p.vx = -280 - _rng.nextDouble() * 60;
        p.vy = (_rng.nextDouble() - 0.5) * 8;
        p.life = 0.18 + _rng.nextDouble() * 0.10;
        p.size = 1.1;
      case ExhaustType.plasma:
        p.y += (r - 0.5) * 10;
        p.vx = -90 - _rng.nextDouble() * 40;
        p.vy = (_rng.nextDouble() - 0.5) * 30;
        p.life = 0.45 + _rng.nextDouble() * 0.25;
        p.size = 4.0 + _rng.nextDouble() * 3.0;
      case ExhaustType.ember:
        p.y += (r - 0.5) * 6;
        p.vx = -120 - _rng.nextDouble() * 90;
        p.vy = (_rng.nextDouble() - 0.5) * 90;
        p.life = 0.35 + _rng.nextDouble() * 0.35;
        p.size = 1.2 + _rng.nextDouble() * 1.4;
      case ExhaustType.comet:
        p.y += (r - 0.5) * 2;
        p.vx = -170;
        p.vy = 0;
        p.life = 0.9;
        p.size = 3.2;
      case ExhaustType.pulse:
        p.vx = -110;
        p.vy = 0;
        p.life = 0.6;
        p.size = 3; // start radius; grows with age
      case ExhaustType.nova:
        p.y += (r - 0.5) * 8;
        p.vx = -150 - _rng.nextDouble() * 50;
        p.vy = math.sin(_time * 9) * 22;
        p.life = 0.5 + _rng.nextDouble() * 0.25;
        p.size = 2.0 + _rng.nextDouble() * 1.6;
      case ExhaustType.quantum:
      case ExhaustType.stock:
        p.life = 0;
    }
  }

  @override
  void render(Canvas canvas) {
    switch (type) {
      case ExhaustType.quantum:
        _renderEchoes(canvas);
        return;
      case ExhaustType.ion:
        _renderIonLine(canvas);
      default:
        break;
    }
    final colors = type.colors;
    for (final p in _particles) {
      if (!p.alive) continue;
      if (p.x < -24) continue; // scrolled offscreen — skip draw
      final f = p.age / p.life; // 0 → 1 over the particle's life
      final fade = 1.0 - f;
      final o = Offset(p.x, p.y);
      switch (type) {
        case ExhaustType.ion:
          _streak
            ..strokeWidth = p.size
            ..color = p.color.withValues(alpha: 0.9 * fade);
          canvas.drawLine(o, Offset(p.x + 9, p.y), _streak);
        case ExhaustType.comet:
          // White at the nozzle cooling to cyan down the tail.
          final c = Color.lerp(colors.first, colors.last, f)!;
          _paint.color = c.withValues(alpha: 0.16 * fade);
          canvas.drawCircle(o, p.size * 2.0, _paint);
          _paint.color = c.withValues(alpha: 0.9 * fade);
          canvas.drawCircle(o, p.size * (0.35 + 0.65 * fade), _paint);
        case ExhaustType.pulse:
          _ring
            ..strokeWidth = 1.6 * fade + 0.4
            ..color = p.color.withValues(alpha: 0.85 * fade);
          canvas.drawCircle(o, p.size + 14 * f, _ring);
        case ExhaustType.ember:
          _paint.color = p.color.withValues(alpha: 0.22 * fade);
          canvas.drawCircle(o, p.size * 2.4, _paint);
          _paint.color = p.color.withValues(alpha: fade);
          canvas.drawCircle(o, p.size, _paint);
        case ExhaustType.nova:
          // Hue walks the prism over the particle's life.
          final c = colors[(_colorIndex(p) + (f * colors.length).floor()) %
              colors.length];
          _paint.color = c.withValues(alpha: 0.2 * fade);
          canvas.drawCircle(o, p.size * 2.2, _paint);
          _paint.color = c.withValues(alpha: 0.9 * fade);
          canvas.drawCircle(o, p.size * fade, _paint);
        default: // plasma — fat soft plume
          _paint.color = p.color.withValues(alpha: 0.14 * fade);
          canvas.drawCircle(o, p.size * 2.0, _paint);
          _paint.color = p.color.withValues(alpha: 0.55 * fade);
          canvas.drawCircle(o, p.size * (0.6 + 0.4 * fade), _paint);
      }
    }
  }

  int _colorIndex(_ExhaustParticle p) =>
      math.max(0, type.colors.indexOf(p.color));

  /// Thin ion line straight off the nozzle; its length flickers.
  void _renderIonLine(Canvas canvas) {
    if (game.phase != GamePhase.playing) return;
    final ship = game.player;
    final x = ship.position.x - ship.size.x * 0.55;
    final y = ship.position.y;
    final len = 34 * _flicker;
    _streak
      ..strokeWidth = 3
      ..color = type.colors.first.withValues(alpha: 0.18 * _flicker);
    canvas.drawLine(Offset(x, y), Offset(x - len, y), _streak);
    _streak
      ..strokeWidth = 1
      ..color = type.colors.last.withValues(alpha: 0.9 * _flicker);
    canvas.drawLine(Offset(x, y), Offset(x - len, y), _streak);
  }

  void _renderEchoes(Canvas canvas) {
    for (var i = 0; i < _echoCount; i++) {
      final age = _echoAge[i];
      if (age >= _echoLife) continue;
      final fade = 1.0 - age / _echoLife;
      final paint = _echoPaints[i]
        ..color = Color.fromRGBO(255, 255, 255, 0.4 * fade);
      _hull.render(canvas,
          position: _echoPos[i], size: _echoSize, overridePaint: paint);
    }
  }
}
