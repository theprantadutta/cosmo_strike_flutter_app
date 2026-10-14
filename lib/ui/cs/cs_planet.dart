import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/cosmo_theme.dart';

/// A small Prism Noir planet: graphite sphere lit from the top-left with a
/// thin prism rim and a soft violet halo — the compact sibling of the home
/// screen's eclipse. [dim] fades it for locked states. Static paint.
class CsPlanet extends StatelessWidget {
  const CsPlanet({super.key, required this.size, this.dim = false});
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dim ? 0.4 : 1,
      child: SizedBox.square(
        dimension: size,
        child: const RepaintBoundary(child: CustomPaint(painter: _PlanetPainter())),
      ),
    );
  }
}

class _PlanetPainter extends CustomPainter {
  const _PlanetPainter();

  static const _light = Offset(-0.62, -0.78);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.36;
    final body = Rect.fromCircle(center: c, radius: r);
    final bounds = Offset.zero & size;
    final lit = c + _light * r;
    final dark = c - _light * r * 0.5;
    Shader litMask() => LinearGradient(
          begin: Alignment(lit.dx / size.width * 2 - 1, lit.dy / size.height * 2 - 1),
          end: Alignment(dark.dx / size.width * 2 - 1, dark.dy / size.height * 2 - 1),
          colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(bounds);

    // Halo.
    canvas.saveLayer(bounds, Paint());
    final haloR = size.shortestSide / 2;
    canvas.drawCircle(
      c,
      haloR,
      Paint()
        ..shader = RadialGradient(
          colors: const [Color(0x00A78BFA), Color(0x66A78BFA), Color(0x00FF8AD8)],
          stops: [r / haloR - 0.02, r / haloR, 1],
        ).createShader(Rect.fromCircle(center: c, radius: haloR)),
    );
    canvas.drawRect(bounds, Paint()..shader = litMask()..blendMode = BlendMode.dstIn);
    canvas.restore();

    // Body.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.55, -0.7),
          radius: 1.05,
          colors: [Color(0xFF26262F), Color(0xFF131319), Color(0xFF09090C)],
          stops: [0, 0.45, 1],
        ).createShader(body),
    );

    // Prism rim, fading toward the dark side.
    canvas.saveLayer(bounds, Paint());
    final sweep = SweepGradient(
      colors: const [CsColors.cyan, CsColors.violet, CsColors.pink, CsColors.gold, CsColors.cyan],
      transform: GradientRotation(math.atan2(_light.dy, _light.dx) - 1.2),
    ).createShader(body);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..shader = sweep
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
    );
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, r * 0.025)
        ..shader = sweep,
    );
    canvas.drawRect(bounds, Paint()..shader = litMask()..blendMode = BlendMode.dstIn);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlanetPainter old) => false;
}
