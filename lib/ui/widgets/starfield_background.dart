import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/preferences_service.dart';
import '../../utils/constants.dart';

/// The unified command-HUD backdrop: a full "middle of deep space" scene —
/// a graded space base, soft neon nebula clouds, a glowing sun, a banded gas
/// giant, a ringed planet, a cratered moon, and a parallax field of twinkling
/// stars with the occasional comet streaking past.
///
/// It is split into two layers for performance: a STATIC scene (base gradient,
/// nebulae, grid, celestial bodies) painted once behind a [RepaintBoundary],
/// and an ANIMATED star/comet layer that repaints each frame on its own
/// boundary so the expensive gradients are never re-rendered.
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
    duration: const Duration(seconds: 48),
  );

  // Deterministic star layout (stable across rebuilds).
  late final List<_Star> _stars = _generateStars();

  static List<_Star> _generateStars() {
    final rnd = math.Random(7);
    return List.generate(180, (_) {
      final depth = 0.25 + rnd.nextDouble() * 0.75;
      final radius = 0.4 + rnd.nextDouble() * 1.8;
      return _Star(
        dx: rnd.nextDouble(),
        dy: rnd.nextDouble(),
        radius: radius,
        phase: rnd.nextDouble(),
        depth: depth,
        bright: radius > 1.7,
        // Whole screen-widths travelled per loop. Integer so the wrap is
        // seamless (no snap), and parallax by depth: near stars stream faster.
        wraps: (2 + depth * 5).round().toDouble(),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    // Honor the reduce-motion accessibility preference: keep the scene static
    // (no drifting parallax / comet) for players sensitive to motion.
    if (widget.animated && !PreferencesService().reduceMotion) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme ?? GameTheme.classic;

    // Animated star/comet layer (its own boundary → static scene stays cached).
    final Widget starLayer = RepaintBoundary(
      child: widget.animated
          ? AnimatedBuilder(
              animation: _c,
              builder: (context, child) => CustomPaint(
                painter: _StarLayerPainter(theme: t, t: _c.value, stars: _stars),
                child: child,
              ),
              child: widget.child,
            )
          : CustomPaint(
              painter: _StarLayerPainter(theme: t, t: 0, stars: _stars),
              child: widget.child,
            ),
    );

    return RepaintBoundary(
      child: CustomPaint(
        painter: _SpaceScenePainter(theme: t, showGrid: widget.showGrid),
        child: starLayer,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Static scene: base gradient, nebulae, grid, celestial bodies.
// ---------------------------------------------------------------------------

class _SpaceScenePainter extends CustomPainter {
  _SpaceScenePainter({required this.theme, required this.showGrid});

  final GameTheme theme;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = theme.backgroundColor;
    final short = size.shortestSide;

    // 1. Deep-space base — a radial lift toward the upper-left fading to black.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.15, -0.5),
          radius: 1.4,
          colors: [
            Color.alphaBlend(theme.neonPrimary.withValues(alpha: 0.05), bg),
            bg,
            const Color(0xFF01020A),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );

    // 2. Soft neon nebula clouds (additive bloom).
    void nebula(Alignment at, double radFrac, Color col, double a) {
      final c = at.alongSize(size);
      final r = short * radFrac;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [col.withValues(alpha: a), Colors.transparent],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    nebula(const Alignment(-0.75, -0.65), 0.95, theme.neonPrimary, 0.10);
    nebula(const Alignment(0.85, 0.7), 1.05, theme.neonSecondary, 0.10);
    nebula(const Alignment(0.25, -0.15), 0.7, const Color(0xFF6A3DF0), 0.07);
    nebula(const Alignment(-0.4, 0.85), 0.6, const Color(0xFF2BD1C4), 0.05);

    // 3. Celestial bodies. The sun also drives every body's lighting.
    // The whole set is composited through a translucent layer so the bodies
    // read as DISTANT scenery — bright enough to sell the scene, dim enough
    // that foreground text stays readable when it passes over them.
    canvas.saveLayer(
      rect,
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    // Nudged a touch toward the lower-left so it clears the brand logo.
    final sun = const Alignment(-0.88, -0.62).alongSize(size);
    _drawSun(canvas, sun, short * 0.045);

    // Banded gas giant, upper-right.
    _drawPlanet(
      canvas,
      const Alignment(0.86, -0.58).alongSize(size),
      short * 0.085,
      sun,
      const Color(0xFF2C5A66),
      banded: true,
      atmosphere: theme.neonPrimary,
    );

    // Cratered moon, lower-left.
    _drawMoon(
      canvas,
      const Alignment(-0.6, 0.62).alongSize(size),
      short * 0.04,
      sun,
    );

    // Big ringed planet anchored off the bottom-right corner.
    _drawRingedPlanet(
      canvas,
      const Alignment(1.08, 1.18).alongSize(size),
      short * 0.2,
      sun,
      const Color(0xFF3A4A6B),
      const Color(0xFFC9B391),
    );

    // Close the translucent celestial-bodies layer.
    canvas.restore();
  }

  // Unit vector from a body toward the sun (its light direction).
  Offset _lightDir(Offset from, Offset sun) {
    final d = sun - from;
    final len = d.distance == 0 ? 1.0 : d.distance;
    return Offset(d.dx / len, d.dy / len);
  }

  void _drawSun(Canvas canvas, Offset c, double r) {
    const core = Color(0xFFFFF1C2);
    const glow = Color(0xFFFFB24D);
    // Wide corona.
    canvas.drawCircle(
      c,
      r * 5.0,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [glow.withValues(alpha: 0.28), Colors.transparent],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r * 5.0)),
    );
    // Inner bloom.
    canvas.drawCircle(
      c,
      r * 2.0,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [glow.withValues(alpha: 0.55), Colors.transparent],
        ).createShader(Rect.fromCircle(center: c, radius: r * 2.0)),
    );
    // Core disc.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, core, glow],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  void _drawPlanet(
    Canvas canvas,
    Offset c,
    double r,
    Offset sun,
    Color base, {
    bool banded = false,
    Color? atmosphere,
  }) {
    final l = _lightDir(c, sun);
    final rect = Rect.fromCircle(center: c, radius: r);

    // Atmosphere halo.
    if (atmosphere != null) {
      canvas.drawCircle(
        c,
        r * 1.18,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              Colors.transparent,
              atmosphere.withValues(alpha: 0.22),
              Colors.transparent,
            ],
            stops: const [0.78, 0.9, 1.0],
          ).createShader(Rect.fromCircle(center: c, radius: r * 1.18)),
      );
    }

    // Shaded sphere — highlight toward the sun, dark terminator opposite.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(l.dx * 0.7, l.dy * 0.7),
          radius: 1.15,
          colors: [
            Color.lerp(base, Colors.white, 0.55)!,
            base,
            Color.lerp(base, Colors.black, 0.78)!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );

    // Gas-giant latitude bands (clipped to the disc).
    if (banded) {
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      for (int i = 0; i < 5; i++) {
        final yy = c.dy - r + r * 2 * ((i + 0.5) / 5);
        final h = r * 0.16;
        canvas.drawRect(
          Rect.fromLTRB(c.dx - r, yy - h / 2, c.dx + r, yy + h / 2),
          Paint()
            ..color = Color.lerp(
                    base, i.isEven ? Colors.white : Colors.black, 0.14)!
                .withValues(alpha: 0.3),
        );
      }
      canvas.restore();
    }
  }

  void _drawRingedPlanet(
    Canvas canvas,
    Offset c,
    double r,
    Offset sun,
    Color base,
    Color ringCol,
  ) {
    const tilt = -0.42;
    final ringRect = Rect.fromCenter(
      center: Offset.zero,
      width: r * 4.6,
      height: r * 1.5,
    );
    Paint ringPaint() => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.55
      ..shader = LinearGradient(
        colors: [
          ringCol.withValues(alpha: 0.0),
          ringCol.withValues(alpha: 0.55),
          ringCol.withValues(alpha: 0.15),
          ringCol.withValues(alpha: 0.5),
          ringCol.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      ).createShader(ringRect);

    // Back half of the ring (behind the planet).
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    canvas.drawArc(ringRect, math.pi, math.pi, false, ringPaint());
    canvas.restore();

    // The planet itself.
    _drawPlanet(canvas, c, r, sun, base);

    // Front half of the ring (over the planet).
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt);
    canvas.drawArc(ringRect, 0, math.pi, false, ringPaint());
    canvas.restore();
  }

  void _drawMoon(Canvas canvas, Offset c, double r, Offset sun) {
    _drawPlanet(canvas, c, r, sun, const Color(0xFF9AA3B2));
    // Craters on the lit hemisphere.
    final rnd = math.Random(99);
    final l = _lightDir(c, sun);
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    for (int i = 0; i < 7; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final rr = rnd.nextDouble() * r * 0.7;
      final cc = c + Offset(math.cos(a), math.sin(a)) * rr;
      final cr = r * (0.08 + rnd.nextDouble() * 0.13);
      canvas.drawCircle(
        cc,
        cr,
        Paint()..color = Colors.black.withValues(alpha: 0.2),
      );
      // Tiny lit rim on each crater toward the sun.
      canvas.drawCircle(
        cc - Offset(l.dx, l.dy) * cr * 0.25,
        cr * 0.85,
        Paint()..color = Colors.white.withValues(alpha: 0.06),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpaceScenePainter old) =>
      old.theme != theme || old.showGrid != showGrid;
}

// ---------------------------------------------------------------------------
// Animated layer: twinkling parallax stars + a periodic comet.
// ---------------------------------------------------------------------------

class _Star {
  const _Star({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.phase,
    required this.depth,
    required this.bright,
    required this.wraps,
  });
  final double dx;
  final double dy;
  final double radius;
  final double phase;
  final double depth;
  final bool bright;
  final double wraps;
}

class _StarLayerPainter extends CustomPainter {
  _StarLayerPainter({
    required this.theme,
    required this.t,
    required this.stars,
  });

  final GameTheme theme;
  final double t;
  final List<_Star> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final base = theme.textPrimary;
    final dot = Paint();
    final spark = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1;

    for (final s in stars) {
      // Twinkle runs faster than the drift (×6, integer so it stays seamless)
      // so stars keep shimmering even with the slow loop.
      final twinkle =
          0.4 + 0.6 * (0.5 + 0.5 * math.sin((t * 6 + s.phase) * 2 * math.pi));
      // Constant leftward parallax drift (ship flying forward); the integer
      // wrap count keeps it seamless across the loop.
      final x = ((s.dx - t * s.wraps) % 1.0 + 1.0) % 1.0 * size.width;
      final p = Offset(x, s.dy * size.height);
      // Capped softer than full white so drifting stars never wash out
      // foreground text as they pass beneath it.
      final a = (0.42 * twinkle * s.depth).clamp(0.0, 1.0);
      dot.color = base.withValues(alpha: a);
      canvas.drawCircle(p, s.radius * s.depth, dot);

      // Bright stars get a soft 4-point sparkle.
      if (s.bright) {
        final len = s.radius * 4.5 * twinkle;
        spark.color = base.withValues(alpha: a * 0.5);
        canvas.drawLine(p - Offset(len, 0), p + Offset(len, 0), spark);
        canvas.drawLine(p - Offset(0, len), p + Offset(0, len), spark);
      }
    }

    _drawComet(canvas, size);
  }

  // One comet sweeps across during the first slice of each loop.
  void _drawComet(Canvas canvas, Size size) {
    const window = 0.22;
    if (t >= window) return;
    final progress = t / window;
    final fade = math.sin(progress * math.pi); // ease in/out

    final start = Offset(size.width * 1.08, size.height * 0.08);
    final end = Offset(size.width * 0.25, size.height * 0.62);
    final head = Offset.lerp(start, end, progress)!;
    final tail = Offset.lerp(start, end, (progress - 0.16).clamp(0.0, 1.0))!;

    final trail = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          theme.neonPrimary.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.85 * fade),
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromPoints(tail, head));
    canvas.drawLine(tail, head, trail);

    // Glowing head.
    canvas.drawCircle(
      head,
      4.5,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: fade),
            theme.neonPrimary.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: head, radius: 4.5)),
    );
    canvas.drawCircle(
      head,
      1.8,
      Paint()..color = Colors.white.withValues(alpha: fade),
    );
  }

  @override
  bool shouldRepaint(_StarLayerPainter old) => old.t != t || old.theme != theme;
}
