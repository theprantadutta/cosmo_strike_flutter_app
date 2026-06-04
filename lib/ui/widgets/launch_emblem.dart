import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// The hero "ready to launch" emblem: a slowly-rotating HUD reticle (four
/// bracket arcs) wrapped around a glowing neon play triangle that breathes.
/// This is the focal point of the home screen's launch panel — a command-HUD
/// replacement for the old filled-gradient circle.
class LaunchEmblem extends StatefulWidget {
  const LaunchEmblem({super.key, required this.theme, this.size = 150});

  final GameTheme theme;
  final double size;

  @override
  State<LaunchEmblem> createState() => _LaunchEmblemState();
}

class _LaunchEmblemState extends State<LaunchEmblem>
    with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))
        ..repeat();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_spin, _pulse]),
        builder: (context, _) => CustomPaint(
          painter: _LaunchEmblemPainter(
            theme: widget.theme,
            spin: _spin.value,
            pulse: _pulse.value,
          ),
        ),
      ),
    );
  }
}

class _LaunchEmblemPainter extends CustomPainter {
  _LaunchEmblemPainter({
    required this.theme,
    required this.spin,
    required this.pulse,
  });

  final GameTheme theme;
  final double spin;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final primary = theme.neonPrimary;
    final secondary = theme.neonSecondary;
    final glow = 0.5 + 0.5 * pulse;

    // Outer rotating reticle — four bracket arcs with gaps.
    final reticle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = primary.withValues(alpha: 0.9)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 + 2.5 * glow);
    final outer = Rect.fromCircle(center: c, radius: r * 0.92);
    for (int i = 0; i < 4; i++) {
      final start = spin * 2 * math.pi + i * (math.pi / 2) + math.pi / 14;
      canvas.drawArc(outer, start, math.pi / 2 - math.pi / 7, false, reticle);
    }

    // Counter-rotating tick ring (small dashes).
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = secondary.withValues(alpha: 0.5);
    const ticks = 24;
    for (int i = 0; i < ticks; i++) {
      final a = -spin * 2 * math.pi + i * (2 * math.pi / ticks);
      final p1 = c + Offset(math.cos(a), math.sin(a)) * (r * 0.74);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r * 0.78);
      canvas.drawLine(p1, p2, tickPaint);
    }

    // Soft glow disc behind the triangle.
    canvas.drawCircle(
      c,
      r * 0.62,
      Paint()
        ..shader = RadialGradient(
          colors: [primary.withValues(alpha: 0.30 * glow), Colors.transparent],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.62)),
    );

    // Play triangle (rounded, pointing right), optically centered.
    final ts = r * 0.52;
    final cx = c.dx - ts * 0.06;
    final tri = Path()
      ..moveTo(cx + ts * 0.72, c.dy)
      ..lineTo(cx - ts * 0.5, c.dy - ts * 0.64)
      ..lineTo(cx - ts * 0.5, c.dy + ts * 0.64)
      ..close();

    // Glow pass.
    canvas.drawPath(
      tri,
      Paint()
        ..color = primary.withValues(alpha: 0.9)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 * glow),
    );
    // Fill.
    canvas.drawPath(
      tri,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primary, secondary],
        ).createShader(tri.getBounds()),
    );
    // Bright edge.
    canvas.drawPath(
      tri,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = theme.textPrimary.withValues(alpha: 0.92),
    );
  }

  @override
  bool shouldRepaint(_LaunchEmblemPainter old) =>
      old.spin != spin || old.pulse != pulse || old.theme != theme;
}
