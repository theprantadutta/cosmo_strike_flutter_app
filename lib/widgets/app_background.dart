import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// Reusable background widget that provides consistent app-wide background styling.
///
/// Free themes (classic / modern / neon / retro) get a deliberately minimal
/// look — radial gradient + faint grid + two soft circles. Premium themes
/// (space / ocean / cyberpunk / forest / desert / crystal) each get a
/// distinctive signature decoration layer painted by [_PremiumDecorPainter]
/// so paying users see a meaningful visual upgrade across every screen that
/// uses [AppBackground].
class AppBackground extends StatelessWidget {
  final Widget child;
  final GameTheme theme;
  final bool showPattern;

  const AppBackground({
    super.key,
    required this.child,
    required this.theme,
    this.showPattern = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.5,
          colors: [
            theme.accentColor.withValues(alpha: 0.15),
            theme.backgroundColor,
            theme.backgroundColor.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.1),
          ],
          stops: const [0.0, 0.4, 0.8, 1.0],
        ),
      ),
      child: Stack(
        children: [
          if (showPattern)
            Positioned.fill(
              child: CustomPaint(
                painter: theme.isPremium
                    ? _PremiumDecorPainter(theme: theme, animationValue: null)
                    : _FreeDecorPainter(theme),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Animated version of the background for screens that need dynamic effects
/// (first-time auth, profile, replay viewer). Premium themes layer drifting
/// elements on top of their static signature decoration.
class AnimatedAppBackground extends StatefulWidget {
  final Widget child;
  final GameTheme theme;
  final bool showPattern;

  const AnimatedAppBackground({
    super.key,
    required this.child,
    required this.theme,
    this.showPattern = true,
  });

  @override
  State<AnimatedAppBackground> createState() => _AnimatedAppBackgroundState();
}

class _AnimatedAppBackgroundState extends State<AnimatedAppBackground>
    with TickerProviderStateMixin {
  late AnimationController _backgroundController;
  late Animation<double> _backgroundAnimation;

  @override
  void initState() {
    super.initState();
    _backgroundController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );
    _backgroundAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _backgroundController, curve: Curves.linear),
    );
    _backgroundController.repeat();
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.5,
          colors: [
            widget.theme.accentColor.withValues(alpha: 0.15),
            widget.theme.backgroundColor,
            widget.theme.backgroundColor.withValues(alpha: 0.9),
            Colors.black.withValues(alpha: 0.1),
          ],
          stops: const [0.0, 0.4, 0.8, 1.0],
        ),
      ),
      child: Stack(
        children: [
          if (widget.showPattern)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _backgroundAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: widget.theme.isPremium
                        ? _PremiumDecorPainter(
                            theme: widget.theme,
                            animationValue: _backgroundAnimation.value,
                          )
                        : _FreeAnimatedDecorPainter(
                            widget.theme,
                            _backgroundAnimation.value,
                          ),
                  );
                },
              ),
            ),
          widget.child,
        ],
      ),
    );
  }
}

// ===========================================================================
// FREE THEME PAINTER — minimal grid + 2 soft circles (the original look).
// Kept deliberately understated so the premium themes feel like an upgrade.
// ===========================================================================

class _FreeDecorPainter extends CustomPainter {
  final GameTheme theme;
  _FreeDecorPainter(this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    _paintFreeBase(canvas, size, theme);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      oldDelegate is! _FreeDecorPainter || oldDelegate.theme != theme;
}

class _FreeAnimatedDecorPainter extends CustomPainter {
  final GameTheme theme;
  final double t;
  _FreeAnimatedDecorPainter(this.theme, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    _paintFreeBase(canvas, size, theme);
    final floatingPaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 8; i++) {
      final progress = (t + i * 0.15) % 1.0;
      final x = (i * 67 + progress * 30) % size.width;
      final y = (i * 89 + math.sin(progress * math.pi * 2) * 40) % size.height;
      final opacity = (math.sin(progress * math.pi * 2) + 1) * 0.5;
      floatingPaint.color = theme.accentColor.withValues(alpha: 0.02 * opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: 6, height: 6),
          const Radius.circular(1),
        ),
        floatingPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

void _paintFreeBase(Canvas canvas, Size size, GameTheme theme) {
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = theme.accentColor.withValues(alpha: 0.05);
  const gridSize = 30.0;
  for (double x = 0; x < size.width; x += gridSize) {
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }
  for (double y = 0; y < size.height; y += gridSize) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
  final shapePaint = Paint()
    ..style = PaintingStyle.fill
    ..color = theme.foodColor.withValues(alpha: 0.02);
  canvas.drawCircle(
    Offset(size.width * 0.15, size.height * 0.25),
    50,
    shapePaint,
  );
  canvas.drawCircle(
    Offset(size.width * 0.85, size.height * 0.75),
    70,
    shapePaint,
  );
}

// ===========================================================================
// PREMIUM THEME PAINTER — dispatches to a theme-specific routine. Each
// premium theme is hand-tuned so the look ties to its name (stars for Space,
// dunes for Desert, etc.). Animation is optional; when null the painter
// renders the static-only elements.
// ===========================================================================

class _PremiumDecorPainter extends CustomPainter {
  final GameTheme theme;
  final double? animationValue;

  _PremiumDecorPainter({required this.theme, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    switch (theme) {
      case GameTheme.space:
        _paintSpace(canvas, size);
        break;
      case GameTheme.ocean:
        _paintOcean(canvas, size);
        break;
      case GameTheme.cyberpunk:
        _paintCyberpunk(canvas, size);
        break;
      case GameTheme.forest:
        _paintForest(canvas, size);
        break;
      case GameTheme.desert:
        _paintDesert(canvas, size);
        break;
      case GameTheme.crystal:
        _paintCrystal(canvas, size);
        break;
      // Free themes won't reach here (gated by theme.isPremium upstream)
      // but Dart needs the switch to be exhaustive.
      case GameTheme.classic:
      case GameTheme.modern:
      case GameTheme.neon:
      case GameTheme.retro:
        _paintFreeBase(canvas, size, theme);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! _PremiumDecorPainter) return true;
    return oldDelegate.theme != theme ||
        oldDelegate.animationValue != animationValue;
  }

  // -------------------------------------------------------------------------
  // SPACE — twinkling starfield + a soft nebula glow + a planet silhouette.
  // -------------------------------------------------------------------------

  void _paintSpace(Canvas canvas, Size size) {
    final t = animationValue ?? 0.0;

    // Nebula glow — large radial gradient in the upper-left.
    final nebulaCenter = Offset(size.width * 0.25, size.height * 0.3);
    final nebulaRect = Rect.fromCircle(center: nebulaCenter, radius: size.width * 0.55);
    final nebulaPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          theme.accentColor.withValues(alpha: 0.18),
          theme.foodColor.withValues(alpha: 0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(nebulaRect);
    canvas.drawRect(nebulaRect, nebulaPaint);

    // Planet silhouette bottom-right.
    final planetCenter = Offset(size.width * 0.88, size.height * 0.78);
    final planetPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.3, -0.3),
        colors: [
          theme.snakeColor.withValues(alpha: 0.45),
          theme.snakeColor.withValues(alpha: 0.18),
          theme.backgroundColor.withValues(alpha: 0.6),
        ],
      ).createShader(Rect.fromCircle(center: planetCenter, radius: 60));
    canvas.drawCircle(planetCenter, 60, planetPaint);
    // Planet ring
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = theme.accentColor.withValues(alpha: 0.35);
    canvas.drawOval(
      Rect.fromCenter(center: planetCenter, width: 160, height: 32),
      ringPaint,
    );

    // Starfield — deterministic random so the same stars appear every paint.
    final rng = math.Random(42);
    final starPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 80; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 0.6 + rng.nextDouble() * 1.8;
      // Twinkle: each star has its own phase, modulated by global t.
      final phase = rng.nextDouble();
      final twinkle = 0.45 +
          0.45 * (0.5 + 0.5 * math.sin((t + phase) * math.pi * 2));
      starPaint.color = Colors.white.withValues(alpha: 0.25 + 0.5 * twinkle);
      canvas.drawCircle(Offset(x, y), r, starPaint);
      // Cross-shaped glint on the largest stars.
      if (r > 2.0) {
        final glintPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.15 * twinkle)
          ..strokeWidth = 0.6;
        canvas.drawLine(Offset(x - 4, y), Offset(x + 4, y), glintPaint);
        canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), glintPaint);
      }
    }
  }

  // -------------------------------------------------------------------------
  // OCEAN — wave bands + drifting bubbles + caustic-light streaks.
  // -------------------------------------------------------------------------

  void _paintOcean(Canvas canvas, Size size) {
    final t = animationValue ?? 0.0;

    // Three sine-wave bands stacked at different y positions.
    final wavePaint = Paint()..style = PaintingStyle.fill;
    for (int band = 0; band < 3; band++) {
      final baseY = size.height * (0.18 + band * 0.32);
      final amp = 12.0 + band * 4;
      final freq = 0.014 + band * 0.004;
      final phase = t * math.pi * 2 + band * 0.7;
      final path = Path()..moveTo(0, baseY);
      for (double x = 0; x <= size.width; x += 6) {
        path.lineTo(x, baseY + math.sin(x * freq + phase) * amp);
      }
      path.lineTo(size.width, baseY + 60);
      path.lineTo(0, baseY + 60);
      path.close();
      wavePaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          theme.accentColor.withValues(alpha: 0.18 - band * 0.04),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, baseY, size.width, 60));
      canvas.drawPath(path, wavePaint);
    }

    // Drifting bubbles — rise slowly, reset at top.
    final rng = math.Random(11);
    final bubbleStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final bubbleFill = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 28; i++) {
      final col = rng.nextDouble() * size.width;
      final r = 2.0 + rng.nextDouble() * 5.0;
      final phase = rng.nextDouble();
      final yProgress = ((phase + t * 0.4) % 1.0);
      final y = size.height - yProgress * (size.height + 40);
      final drift = math.sin(yProgress * math.pi * 3) * 12;
      final x = (col + drift).clamp(0.0, size.width);
      bubbleStroke.color = theme.foodColor.withValues(alpha: 0.18);
      bubbleFill.color = theme.foodColor.withValues(alpha: 0.04);
      canvas.drawCircle(Offset(x, y), r, bubbleFill);
      canvas.drawCircle(Offset(x, y), r, bubbleStroke);
    }
  }

  // -------------------------------------------------------------------------
  // CYBERPUNK — perspective grid + neon intersection nodes + scan line.
  // -------------------------------------------------------------------------

  void _paintCyberpunk(Canvas canvas, Size size) {
    final t = animationValue ?? 0.0;

    // Perspective grid emanating from a vanishing point near center-upper.
    final vanish = Offset(size.width * 0.5, size.height * 0.42);
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = theme.accentColor.withValues(alpha: 0.22);
    // Radial lines from vanishing point to edges (bottom half).
    for (int i = -8; i <= 8; i++) {
      final dx = i / 8.0 * size.width;
      canvas.drawLine(
        vanish,
        Offset(vanish.dx + dx, size.height + 50),
        gridPaint,
      );
    }
    // Horizon lines, getting closer together near the vanishing point.
    for (int i = 1; i <= 10; i++) {
      final pow = i * i / 100.0; // quadratic spacing for perspective feel
      final y = vanish.dy + pow * (size.height - vanish.dy);
      gridPaint.color = theme.accentColor.withValues(alpha: 0.06 + i * 0.012);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Neon dots scattered above the horizon.
    final rng = math.Random(7);
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final glowPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (int i = 0; i < 36; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * vanish.dy * 0.95;
      final r = 0.8 + rng.nextDouble() * 1.6;
      final color = i.isEven ? theme.foodColor : theme.snakeColor;
      glowPaint.color = color.withValues(alpha: 0.4);
      canvas.drawCircle(Offset(x, y), r + 1.5, glowPaint);
      dotPaint.color = color.withValues(alpha: 0.95);
      canvas.drawCircle(Offset(x, y), r, dotPaint);
    }

    // Animated horizontal scan line sweeping the screen.
    if (animationValue != null) {
      final scanY = (t * 1.3) % 1.0 * size.height;
      final scanPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            theme.accentColor.withValues(alpha: 0.18),
            theme.foodColor.withValues(alpha: 0.22),
            theme.accentColor.withValues(alpha: 0.18),
            Colors.transparent,
          ],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        ).createShader(Rect.fromLTWH(0, scanY - 1, size.width, 2));
      canvas.drawRect(Rect.fromLTWH(0, scanY - 1, size.width, 2), scanPaint);
    }
  }

  // -------------------------------------------------------------------------
  // FOREST — vertical god-ray light shafts + canopy silhouettes + drifting
  // leaves.
  // -------------------------------------------------------------------------

  void _paintForest(Canvas canvas, Size size) {
    final t = animationValue ?? 0.0;

    // Diagonal god rays — soft light beams coming down from the upper-left.
    final raySpacing = size.width / 5;
    for (int i = 0; i < 6; i++) {
      final originX = -size.width * 0.2 + i * raySpacing;
      final rayPath = Path()
        ..moveTo(originX, 0)
        ..lineTo(originX + 80, 0)
        ..lineTo(originX + 280, size.height)
        ..lineTo(originX + 200, size.height)
        ..close();
      final rayPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.accentColor.withValues(alpha: 0.12),
            theme.accentColor.withValues(alpha: 0.02),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromLTWH(originX, 0, 280, size.height));
      canvas.drawPath(rayPath, rayPaint);
    }

    // Canopy silhouettes at top — bumpy tree-line.
    final canopyPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    final canopy = Path()..moveTo(0, 0);
    for (double x = 0; x <= size.width; x += 18) {
      final y = 24 + math.sin(x * 0.13) * 12 + math.cos(x * 0.07) * 10;
      canopy.lineTo(x, y);
    }
    canopy
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(canopy, canopyPaint);

    // Falling leaves — small rotated rounded rects.
    final rng = math.Random(23);
    final leafPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 18; i++) {
      final col = rng.nextDouble() * size.width;
      final phase = rng.nextDouble();
      final yProgress = ((phase + t * 0.25) % 1.0);
      final y = yProgress * (size.height + 40) - 20;
      final sway = math.sin((yProgress + phase) * math.pi * 4) * 30;
      final x = (col + sway).clamp(-10.0, size.width + 10.0);
      final rotation = (yProgress + phase) * math.pi * 2;
      final color = i.isEven ? theme.foodColor : theme.snakeColor;
      leafPaint.color = color.withValues(alpha: 0.32);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 4),
          const Radius.circular(2),
        ),
        leafPaint,
      );
      canvas.restore();
    }
  }

  // -------------------------------------------------------------------------
  // DESERT — layered dunes + sun disc + drifting dust motes.
  // -------------------------------------------------------------------------

  void _paintDesert(Canvas canvas, Size size) {
    final t = animationValue ?? 0.0;

    // Sun disc top-right with concentric rings.
    final sunCenter = Offset(size.width * 0.82, size.height * 0.18);
    final sunPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          theme.accentColor.withValues(alpha: 0.85),
          theme.accentColor.withValues(alpha: 0.35),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: 70));
    canvas.drawCircle(sunCenter, 70, sunPaint);
    // Concentric rings.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      ringPaint.color = theme.accentColor.withValues(alpha: 0.18 - i * 0.04);
      canvas.drawCircle(sunCenter, 70.0 + i * 18.0, ringPaint);
    }

    // Three layered dune silhouettes at the bottom.
    final duneColors = [
      theme.snakeColor.withValues(alpha: 0.32),
      Colors.black.withValues(alpha: 0.28),
      Colors.black.withValues(alpha: 0.4),
    ];
    for (int layer = 0; layer < 3; layer++) {
      final baseY = size.height * (0.62 + layer * 0.1);
      final amp = 20.0 + layer * 8;
      final freq = 0.008 + layer * 0.003;
      final phase = layer * 1.7;
      final path = Path()..moveTo(0, baseY);
      for (double x = 0; x <= size.width; x += 12) {
        path.lineTo(x, baseY + math.sin(x * freq + phase) * amp);
      }
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = duneColors[layer],
      );
    }

    // Drifting dust motes.
    final rng = math.Random(91);
    final dustPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 24; i++) {
      final phase = rng.nextDouble();
      final xProgress = ((phase + t * 0.35) % 1.0);
      final x = xProgress * (size.width + 30) - 15;
      final y = rng.nextDouble() * size.height * 0.6;
      final r = 0.8 + rng.nextDouble() * 1.4;
      dustPaint.color = theme.accentColor.withValues(alpha: 0.22);
      canvas.drawCircle(Offset(x, y), r, dustPaint);
    }
  }

  // -------------------------------------------------------------------------
  // CRYSTAL — floating polygon shards with prismatic gradient fills +
  // sparkle highlights.
  // -------------------------------------------------------------------------

  void _paintCrystal(Canvas canvas, Size size) {
    final t = animationValue ?? 0.0;

    // 8 shards, deterministic placement.
    final rng = math.Random(57);
    for (int i = 0; i < 8; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final scale = 24.0 + rng.nextDouble() * 36.0;
      final rotation = (rng.nextDouble() * math.pi * 2) + t * 0.4 * (i.isEven ? 1 : -1);
      // Diamond-ish polygon (6 vertices).
      final pts = <Offset>[];
      for (int k = 0; k < 6; k++) {
        final angle = (k / 6.0) * math.pi * 2 + rotation;
        final r = scale * (0.7 + (k.isEven ? 0.35 : 0.0));
        pts.add(Offset(cx + math.cos(angle) * r, cy + math.sin(angle) * r));
      }
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();

      // Prismatic gradient: snakeColor → foodColor → accentColor.
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.snakeColor.withValues(alpha: 0.42),
            theme.foodColor.withValues(alpha: 0.28),
            theme.accentColor.withValues(alpha: 0.32),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: scale));
      canvas.drawPath(path, fillPaint);

      // Outline.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = theme.accentColor.withValues(alpha: 0.65),
      );
    }

    // Sparkle highlights — tiny 4-pointed stars scattered across the screen.
    final sparkRng = math.Random(99);
    for (int i = 0; i < 40; i++) {
      final x = sparkRng.nextDouble() * size.width;
      final y = sparkRng.nextDouble() * size.height;
      final phase = sparkRng.nextDouble();
      final twinkle = 0.5 + 0.5 * math.sin((t + phase) * math.pi * 2);
      final alpha = 0.4 + twinkle * 0.5;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = 0.8;
      canvas.drawLine(Offset(x - 3, y), Offset(x + 3, y), paint);
      canvas.drawLine(Offset(x, y - 3), Offset(x, y + 3), paint);
      canvas.drawCircle(
        Offset(x, y),
        0.6,
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }
  }
}
