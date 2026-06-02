import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// The unified command-HUD backdrop: a deep-space radial base, a faint
/// holographic grid, a parallax starfield, and (for premium skins) a soft neon
/// nebula tint. Replaces the old per-theme `AppBackground` decoration painters.
class StarfieldBackground extends StatefulWidget {
  const StarfieldBackground({
    super.key,
    required this.child,
    this.theme,
    this.animated = true,
    this.showGrid = true,
  });

  final Widget child;
  final GameTheme? theme;
  final bool animated;
  final bool showGrid;

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  // Deterministic star layout (stable across rebuilds).
  late final List<_Star> _stars = _generateStars();

  static List<_Star> _generateStars() {
    final rnd = math.Random(7);
    return List.generate(120, (_) {
      return _Star(
        dx: rnd.nextDouble(),
        dy: rnd.nextDouble(),
        radius: 0.4 + rnd.nextDouble() * 1.6,
        phase: rnd.nextDouble(),
        depth: 0.3 + rnd.nextDouble() * 0.7,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.animated) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme ?? GameTheme.classic;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return CustomPaint(
            painter: _StarfieldPainter(
              theme: t,
              t: widget.animated ? _c.value : 0,
              showGrid: widget.showGrid,
              stars: _stars,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _Star {
  const _Star({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.phase,
    required this.depth,
  });
  final double dx;
  final double dy;
  final double radius;
  final double phase;
  final double depth;
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.theme,
    required this.t,
    required this.showGrid,
    required this.stars,
  });

  final GameTheme theme;
  final double t;
  final bool showGrid;
  final List<_Star> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = theme.backgroundColor;

    // Deep-space radial base — slightly lifted toward the top.
    final base = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.55),
        radius: 1.3,
        colors: [
          Color.alphaBlend(theme.neonPrimary.withValues(alpha: 0.06), bg),
          bg,
          const Color(0xFF02030A),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    // Premium skins get a soft nebula bloom (secondary neon).
    if (theme.isPremium) {
      final nebula = Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.7, 0.8),
          radius: 0.9,
          colors: [
            theme.neonSecondary.withValues(alpha: 0.10),
            Colors.transparent,
          ],
        ).createShader(rect);
      canvas.drawRect(rect, nebula);
    }

    // Thin holographic grid.
    if (showGrid) {
      final gridPaint = Paint()
        ..color = theme.gridLine
        ..strokeWidth = 1;
      const step = 56.0;
      final drift = (t * step) % step;
      for (double x = -drift; x <= size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = -drift; y <= size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    // Parallax twinkling stars.
    final starPaint = Paint()..color = theme.textPrimary;
    for (final s in stars) {
      final twinkle =
          0.35 + 0.65 * (0.5 + 0.5 * math.sin((t + s.phase) * 2 * math.pi));
      final drift = (t * 18 * s.depth) % size.height;
      final y = (s.dy * size.height + drift) % size.height;
      final p = Offset(s.dx * size.width, y);
      starPaint.color =
          theme.textPrimary.withValues(alpha: 0.55 * twinkle * s.depth);
      canvas.drawCircle(p, s.radius * s.depth, starPaint);
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) =>
      old.t != t || old.theme != theme || old.showGrid != showGrid;
}
