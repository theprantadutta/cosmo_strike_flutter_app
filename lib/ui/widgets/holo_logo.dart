import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// Neon emblem for the brand: concentric holo rings + a ship chevron, gently
/// pulsing. Replaces the asset-based `AnimatedShipLogo` (no amber sprite).
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
    final secondary = theme.neonSecondary;
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

    // Ship chevron (points right, like the player ship).
    final chevron = Path();
    final s = r * 0.5;
    chevron.moveTo(center.dx + s, center.dy);
    chevron.lineTo(center.dx - s * 0.7, center.dy - s * 0.7);
    chevron.lineTo(center.dx - s * 0.35, center.dy);
    chevron.lineTo(center.dx - s * 0.7, center.dy + s * 0.7);
    chevron.close();
    canvas.drawPath(
      chevron,
      Paint()
        ..color = secondary
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      chevron,
      Paint()
        ..color = theme.textPrimary.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_HoloLogoPainter old) =>
      old.t != t || old.theme != theme;
}
