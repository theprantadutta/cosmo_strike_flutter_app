import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

/// A pooled floating text popup ("+120", "FORMATION WIPE", "COMBO BREAK").
/// Stays mounted forever; [show] re-arms it, then it rises, pops, and
/// parks itself off-screen. One TextPaint per show keeps the laid-out
/// text cached for the popup's whole lifetime.
class ScorePopup extends PositionComponent {
  ScorePopup() : super(anchor: Anchor.center, priority: 60) {
    position.setValues(-9999, -9999);
  }

  static const Color defaultColor = Color(0xFFF4F3F7); // Prism ink

  bool active = false;
  String _text = '';
  TextPaint? _paint;
  double _life = 0;
  double _duration = 0.7;
  double _baseScale = 1;
  double _riseSpeed = 40;

  void show(
    Vector2 at,
    String text, {
    Color color = defaultColor,
    double scale = 1,
    double duration = 0.7,
    double riseSpeed = 40,
  }) {
    _text = text;
    _baseScale = scale;
    _duration = duration;
    _riseSpeed = riseSpeed;
    _life = duration;
    position.setFrom(at);
    _paint = TextPaint(
      // Prism Noir: mono uppercase label, no glow — a crisp 1px dark
      // drop keeps it legible over bright FX.
      style: TextStyle(
        fontFamily: 'IBMPlexMono',
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        shadows: const [
          Shadow(color: Color(0xE608080B), offset: Offset(0, 1)),
        ],
      ),
    );
    active = true;
  }

  void hide() {
    active = false;
    position.setValues(-9999, -9999);
  }

  @override
  void update(double dt) {
    if (!active) return;
    _life -= dt;
    if (_life <= 0) {
      hide();
      return;
    }
    position.y -= _riseSpeed * dt;
  }

  @override
  void render(Canvas canvas) {
    if (!active) return;
    final paint = _paint;
    if (paint == null) return;
    // Quick pop-in over the first 0.12 s, gentle shrink over the last 0.15 s.
    final age = _duration - _life;
    final popIn = math.min(1.0, age / 0.12);
    final fadeOut = math.min(1.0, _life / 0.15);
    final s = _baseScale * (0.7 + 0.3 * popIn) * (0.65 + 0.35 * fadeOut);
    canvas.save();
    canvas.scale(s, s);
    paint.render(canvas, _text, Vector2.zero(), anchor: Anchor.center);
    canvas.restore();
  }
}
