import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';

const Color _warnColor = Color(0xFFFF2D78);

double _pulse(double age, {double hz = 7}) =>
    0.35 + 0.45 * (0.5 + 0.5 * math.sin(age * hz));

/// Pulsing chevrons at a screen edge: "something is about to enter from
/// here" (rear ambushes, scripted callouts). One-shot, self-removing.
class EdgeWarningMarker extends PositionComponent
    with HasGameReference<CosmoStrikeGame> {
  EdgeWarningMarker({
    required this.fromLeft,
    required double y,
    this.life = 1.2,
  })  : _y = y,
        super(priority: 55);

  final bool fromLeft;
  final double life;
  final double _y;
  double _age = 0;

  @override
  void update(double dt) {
    _age += dt;
    if (_age >= life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final x = fromLeft ? 16.0 : game.size.x - 16.0;
    final dir = fromLeft ? 1.0 : -1.0;
    final paint = Paint()
      ..color = _warnColor.withValues(alpha: _pulse(_age))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    // Two chevrons pointing into the field.
    for (var k = 0; k < 2; k++) {
      final cx = x + dir * k * 14;
      canvas.drawPath(
        Path()
          ..moveTo(cx, _y - 14)
          ..lineTo(cx + dir * 12, _y)
          ..lineTo(cx, _y + 14),
        paint,
      );
    }
  }
}

/// Full-width horizontal danger band (charge beams, dash sweeps). The
/// attack will rake exactly this row — get out of it.
class RowBandMarker extends PositionComponent
    with HasGameReference<CosmoStrikeGame> {
  RowBandMarker({
    required this.centerY,
    this.bandHeight = 46,
    this.life = 1.2,
  }) : super(priority: 55);

  final double centerY;
  final double bandHeight;
  final double life;
  double _age = 0;

  @override
  void update(double dt) {
    _age += dt;
    if (_age >= life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final a = _pulse(_age);
    final rect = Rect.fromLTWH(
        0, centerY - bandHeight / 2, game.size.x, bandHeight);
    canvas.drawRect(
      rect,
      Paint()..color = _warnColor.withValues(alpha: a * 0.22),
    );
    final edge = Paint()
      ..color = _warnColor.withValues(alpha: a)
      ..strokeWidth = 2;
    canvas.drawLine(rect.topLeft, rect.topRight, edge);
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, edge);
  }
}

/// Dashed aim ray frozen at telegraph start — the exact trajectory the
/// attack will take, shown for the whole windup.
class AimLineMarker extends PositionComponent
    with HasGameReference<CosmoStrikeGame> {
  AimLineMarker({
    required Vector2 origin,
    required Vector2 direction,
    this.life = 1.0,
    this.length = 900,
  })  : _origin = origin.clone(),
        _dir = direction.normalized(),
        super(priority: 55);

  final double life;
  final double length;
  final Vector2 _origin;
  final Vector2 _dir;
  double _age = 0;

  @override
  void update(double dt) {
    _age += dt;
    if (_age >= life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()
      ..color = _warnColor.withValues(alpha: _pulse(_age))
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    const dash = 16.0;
    const gapLen = 10.0;
    var d = 0.0;
    while (d < length) {
      final a = _origin + _dir * d;
      final b = _origin + _dir * math.min(d + dash, length);
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
      d += dash + gapLen;
    }
  }
}

/// Green "be HERE" band — marks the safe gap of an incoming bullet wall.
class SafeGapMarker extends PositionComponent
    with HasGameReference<CosmoStrikeGame> {
  SafeGapMarker({
    required this.centerY,
    this.bandHeight = 110,
    this.life = 1.4,
  }) : super(priority: 55);

  static const Color _safeColor = Color(0xFF7CFC9A);

  final double centerY;
  final double bandHeight;
  final double life;
  double _age = 0;

  @override
  void update(double dt) {
    _age += dt;
    if (_age >= life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final a = _pulse(_age, hz: 5);
    final rect = Rect.fromLTWH(
        0, centerY - bandHeight / 2, game.size.x, bandHeight);
    canvas.drawRect(
      rect,
      Paint()..color = _safeColor.withValues(alpha: a * 0.14),
    );
    final edge = Paint()
      ..color = _safeColor.withValues(alpha: a * 0.8)
      ..strokeWidth = 1.5;
    canvas.drawLine(rect.topLeft, rect.topRight, edge);
    canvas.drawLine(rect.bottomLeft, rect.bottomRight, edge);
  }
}

/// Contracting impact ring (mortar landings, burrow points): the strike
/// lands exactly here when the ring closes.
class LandingRingMarker extends PositionComponent
    with HasGameReference<CosmoStrikeGame> {
  LandingRingMarker({required Vector2 at, this.life = 1.1})
      : super(position: at, anchor: Anchor.center, priority: 55);

  final double life;
  double _age = 0;

  @override
  void update(double dt) {
    _age += dt;
    if (_age >= life) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final p = (_age / life).clamp(0.0, 1.0);
    final radius = 38 - 24 * p;
    final paint = Paint()
      ..color = _warnColor.withValues(alpha: _pulse(_age, hz: 9))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset.zero, radius, paint);
    canvas.drawCircle(
      Offset.zero,
      4,
      Paint()..color = _warnColor.withValues(alpha: 0.8),
    );
  }
}
