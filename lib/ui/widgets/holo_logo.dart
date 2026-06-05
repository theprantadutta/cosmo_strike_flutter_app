import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// Neon emblem for the brand: concentric holo rings around the official
/// brand mark — the Material `rocket_launch` glyph in neon cyan (same mark
/// as the launcher icon, splash, loading screen, and About dialog).
class HoloLogo extends StatefulWidget {
  const HoloLogo({super.key, this.size = 96, this.theme});

  final double size;
  final GameTheme? theme;

  @override
  State<HoloLogo> createState() => _HoloLogoState();
}

class _HoloLogoState extends State<HoloLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme ?? GameTheme.classic;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _HoloLogoPainter(theme: t, t: _c.value),
          // The official brand mark sits inside the animated holo rings.
          child: Center(
            child: Icon(
              Icons.rocket_launch,
              size: widget.size * 0.42,
              color: t.neonPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _HoloLogoPainter extends CustomPainter {
  _HoloLogoPainter({required this.theme, required this.t});
  final GameTheme theme;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2;
    final primary = theme.neonPrimary;
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);

    // Outer rotating ring (dashed arcs).
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = primary.withValues(alpha: 0.6 + 0.3 * pulse);
    final ringRect = Rect.fromCircle(center: center, radius: r * 0.86);
    for (int i = 0; i < 4; i++) {
      final start = t * 2 * math.pi + i * math.pi / 2;
      canvas.drawArc(ringRect, start, math.pi / 3, false, ringPaint);
    }

    // Inner glow disc.
    final disc = Paint()
      ..shader = RadialGradient(
        colors: [
          primary.withValues(alpha: 0.28),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: r * 0.7));
    canvas.drawCircle(center, r * 0.7, disc);

    // The rocket brand mark itself is rendered as a real Icon widget on top
    // of this painter (see HoloLogo.build) so it stays pixel-identical to the
    // glyph used everywhere else in the app.
  }

  @override
  bool shouldRepaint(_HoloLogoPainter old) =>
      old.t != t || old.theme != theme;
}
