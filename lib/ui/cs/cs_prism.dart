import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/cosmo_theme.dart';

/// Paints [child] with the prism text gradient (cyan → pink → gold).
/// Use for the ONE word per screen that matters (e.g. "nought", "Pro", "#1").
class CsPrismText extends StatelessWidget {
  const CsPrismText(
    this.text, {
    super.key,
    this.style,
    this.gradient = CsGradients.prismText,
    this.maxLines,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final Gradient gradient;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(Offset.zero & bounds.size),
      child: Text(
        text,
        style: (style ?? context.type.title).copyWith(color: Colors.white),
        maxLines: maxLines,
        textAlign: textAlign,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      ),
    );
  }
}

/// Wraps any widget in the prism gradient (icons, glyphs, custom paint).
class CsPrismMask extends StatelessWidget {
  const CsPrismMask({super.key, required this.child, this.gradient = CsGradients.prismText});
  final Widget child;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (b) => gradient.createShader(Offset.zero & b.size),
        child: child,
      );
}

/// 1px hairline divider (10% white). Horizontal by default.
class CsHairline extends StatelessWidget {
  const CsHairline({super.key, this.vertical = false, this.color = CsColors.hairline});
  final bool vertical;
  final Color color;

  @override
  Widget build(BuildContext context) => vertical
      ? Container(width: 1, color: color)
      : Container(height: 1, color: color);
}

/// Square-ended progress line (2px by default) on a 12% white track.
/// Animates when [value] changes.
class CsProgressLine extends StatelessWidget {
  const CsProgressLine({
    super.key,
    required this.value,
    this.height = 2,
    this.gradient = CsGradients.progress,
    this.trackColor = CsColors.track,
    this.width,
    this.animate = true,
  });

  /// Set false when [value] is already driven per frame (e.g. by an
  /// AnimationController) so the line tracks it exactly.
  final bool animate;

  /// Pass [CsGradients.complete] for a finished (mint) bar, [CsGradients.prism]
  /// for boss HP / hero bars.
  final double value;
  final double height;
  final Gradient gradient;
  final Color trackColor;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: trackColor),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: v),
          duration: animate ? CsMotion.slow : Duration.zero,
          curve: CsMotion.standard,
          builder: (_, t, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: t,
            child: DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
          ),
        ),
      ),
    );
  }
}

/// A rounded box with a 1.5px conic prism border around a [fill].
/// The "current item" marker. Set [rotate] to slowly spin the gradient
/// (6s/turn) — reserve that for the single focal item on screen.
class CsPrismRing extends StatefulWidget {
  const CsPrismRing({
    super.key,
    required this.child,
    this.radius = CsRadius.tile,
    this.width = 1.5,
    this.fill = CsColors.raised,
    this.rotate = false,
    this.padding = EdgeInsets.zero,
    this.circle = false,
    this.colors,
  });

  final Widget child;
  final double radius;
  final double width;
  final Color fill;
  final bool rotate;
  final EdgeInsetsGeometry padding;
  final bool circle;

  /// Override the ring colors (e.g. silver/bronze rank rings). Null = prism.
  final List<Color>? colors;

  @override
  State<CsPrismRing> createState() => _CsPrismRingState();
}

class _CsPrismRingState extends State<CsPrismRing> with SingleTickerProviderStateMixin {
  AnimationController? _spin;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(CsPrismRing old) {
    super.didUpdateWidget(old);
    if (old.rotate != widget.rotate) _sync();
  }

  void _sync() {
    if (widget.rotate) {
      _spin ??= AnimationController(vsync: this, duration: CsMotion.ringTurn)..repeat();
    } else {
      _spin?.dispose();
      _spin = null;
    }
  }

  @override
  void dispose() {
    _spin?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = _RingPainter(
      radius: widget.radius,
      width: widget.width,
      fill: widget.fill,
      circle: widget.circle,
      colors: widget.colors,
      spin: _spin,
    );
    return RepaintBoundary(
      child: CustomPaint(
        painter: painter,
        child: Padding(
          padding: EdgeInsets.all(widget.width).add(widget.padding),
          child: widget.child,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.radius,
    required this.width,
    required this.fill,
    required this.circle,
    required this.colors,
    required this.spin,
  }) : super(repaint: spin);

  final double radius;
  final double width;
  final Color fill;
  final bool circle;
  final List<Color>? colors;
  final Animation<double>? spin;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = circle ? size.shortestSide / 2 : math.min(radius, size.shortestSide / 2);
    final outer = RRect.fromRectAndRadius(rect, Radius.circular(r));
    final inner = outer.deflate(width);

    if (fill.a > 0) canvas.drawRRect(inner, Paint()..color = fill);

    final rot = (spin?.value ?? 0) * 2 * math.pi;
    final shader = colors == null
        ? CsGradients.sweep(rotation: rot).createShader(rect)
        : (colors!.length == 1
            ? null
            : SweepGradient(colors: colors!, transform: GradientRotation(rot)).createShader(rect));
    final ring = Paint()..isAntiAlias = true;
    if (shader != null) {
      ring.shader = shader;
    } else {
      ring.color = colors!.first;
    }
    canvas.drawDRRect(outer, inner, ring);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.radius != radius ||
      old.width != width ||
      old.fill != fill ||
      old.circle != circle ||
      old.colors != colors;
}

/// Circular progress ring (prism sweep) with content in the middle — the
/// daily "3/3 TODAY" ring and the HUD missile cooldown.
class CsRingProgress extends StatelessWidget {
  const CsRingProgress({
    super.key,
    required this.value,
    required this.size,
    this.stroke = 3,
    this.child,
    this.trackColor = CsColors.track,
    this.fill = Colors.transparent,
  });

  final double value;
  final double size;
  final double stroke;
  final Widget? child;
  final Color trackColor;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: CsMotion.slow,
        curve: CsMotion.standard,
        builder: (_, v, c) => CustomPaint(
          painter: _ArcPainter(v, stroke, trackColor, fill),
          child: Center(child: c),
        ),
        child: child,
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter(this.value, this.stroke, this.track, this.fill);
  final double value;
  final double stroke;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke / 2;
    if (fill.a > 0) canvas.drawCircle(c, r, Paint()..color = fill);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(c, r, base);
    if (value <= 0) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = value >= 1 ? StrokeCap.butt : StrokeCap.round
      ..shader = const SweepGradient(
        colors: [CsColors.cyan, CsColors.violet, CsColors.pink, CsColors.gold, CsColors.mint, CsColors.cyan],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, arc);
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.value != value || old.stroke != stroke || old.track != track || old.fill != fill;
}
