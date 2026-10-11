import 'package:flutter/material.dart';

import '../../theme/cosmo_theme.dart';
import 'cs_buttons.dart';

/// A soft radial color wash behind content (10-18% alpha). Positions are
/// fractional (0..1) of the screen; [rx]/[ry] are radii as fractions too.
class CsWash {
  const CsWash(this.color, this.cx, this.cy, {this.rx = .3, this.ry = .5, this.alpha = .14});
  final Color color;
  final double cx, cy, rx, ry, alpha;

  static const pinkRight = CsWash(CsColors.pink, .82, .5, alpha: .16);
  static const cyanLeft = CsWash(CsColors.cyan, .12, .5, alpha: .12);
  static const violetTopRight = CsWash(CsColors.violet, .85, 0, rx: .4, ry: .6, alpha: .18);
  static const violetCenter = CsWash(CsColors.violet, .5, .45, rx: .4, ry: .6, alpha: .22);
  static const pinkTopLeft = CsWash(CsColors.pink, .2, .3, rx: .4, ry: .7, alpha: .14);
  static const goldTopRight = CsWash(CsColors.gold, .92, .05, rx: .3, ry: .45, alpha: .10);
  static const cyanBottomLeft = CsWash(CsColors.cyan, .3, .8, alpha: .10);
  static const pinkBottomRight = CsWash(CsColors.pink, .75, .8, alpha: .10);
}

/// Near-black canvas + optional washes + a sparse static starfield.
/// Painted once (no animation) — cheap on every device.
class CsBackground extends StatelessWidget {
  const CsBackground({
    super.key,
    this.child,
    this.washes = const [],
    this.stars = false,
    this.color = CsColors.bg,
  });

  final Widget? child;
  final List<CsWash> washes;
  final bool stars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BgPainter(color, washes, stars),
        child: child ?? const SizedBox.expand(),
      ),
    );
  }
}

class _BgPainter extends CustomPainter {
  _BgPainter(this.color, this.washes, this.stars);
  final Color color;
  final List<CsWash> washes;
  final bool stars;

  // Fixed star positions (fractional) — the same sparse sky on every screen.
  static const _stars = [
    Offset(.12, .30), Offset(.26, .76), Offset(.41, .20), Offset(.55, .62),
    Offset(.72, .62), Offset(.84, .18), Offset(.63, .88), Offset(.07, .66),
    Offset(.93, .45), Offset(.35, .52), Offset(.78, .34), Offset(.48, .08),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = color);
    for (final w in washes) {
      final c = Offset(w.cx * size.width, w.cy * size.height);
      final rx = w.rx * size.width, ry = w.ry * size.height;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(1, ry / rx);
      final r = Rect.fromCircle(center: Offset.zero, radius: rx);
      canvas.drawCircle(
        Offset.zero,
        rx,
        Paint()
          ..shader = RadialGradient(
            colors: [w.color.withValues(alpha: w.alpha), w.color.withValues(alpha: 0)],
            stops: const [0, .7],
          ).createShader(r),
      );
      canvas.restore();
    }
    if (stars) {
      final p = Paint()..color = const Color(0x73FFFFFF);
      for (final s in _stars) {
        canvas.drawCircle(Offset(s.dx * size.width, s.dy * size.height), 0.8, p);
      }
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) =>
      old.color != color || old.stars != stars || old.washes != washes;
}

/// Standard screen top bar: back arrow + MONO TITLE on the left, meta on the
/// right. Matches the mocks (CAMPAIGN · ★ 04 / 36 · CLEARED 02 / 12).
class CsTopBar extends StatelessWidget {
  const CsTopBar({
    super.key,
    this.title,
    this.trailing = const [],
    this.onBack,
    this.showBack = true,
    this.leading,
  });

  final String? title;
  final List<Widget> trailing;
  final VoidCallback? onBack;
  final bool showBack;

  /// Replaces the back arrow entirely (e.g. a logo on root screens).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (showBack) ...[
            CsBackButton(onPressed: onBack),
            SizedBox(width: cs(4)),
          ],
          if (title != null)
            Flexible(
              child: Text(
                title!.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.mono(11, color: CsColors.ink, weight: FontWeight.w600),
              ),
            ),
          const Spacer(),
          for (var i = 0; i < trailing.length; i++) ...[
            if (i > 0) SizedBox(width: cs(18)),
            trailing[i],
          ],
        ],
      ),
    );
  }
}

/// Mono uppercase meta text for top bars / captions ("RESETS IN 06:42:10").
class CsMeta extends StatelessWidget {
  const CsMeta(this.text, {super.key, this.color = CsColors.ink55, this.icon, this.iconColor, this.size = 11});
  final String text;
  final Color color;
  final IconData? icon;
  final Color? iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final label = Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: cs.type.mono(size, color: color),
    );
    if (icon == null) return label;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: cs(size + 3), color: iconColor ?? color),
      SizedBox(width: cs(6)),
      Flexible(child: label),
    ]);
  }
}

/// Mono uppercase section label ("DAILY DIRECTIVES", "YOUR RANK").
class CsLabel extends StatelessWidget {
  const CsLabel(this.text, {super.key, this.color = CsColors.ink55, this.size = 11, this.maxLines = 1});
  final String text;
  final Color color;
  final double size;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: context.type.mono(size, color: color, em: 0.16),
      );
}

/// The app shell for every non-gameplay screen.
///
/// Near-black canvas (+ optional washes) → landscape SafeArea (notch/cutout and
/// home indicator aware) → screen padding → optional [CsTopBar] → [body].
/// Tablets automatically get the same composition at a larger scale.
class CsScaffold extends StatelessWidget {
  const CsScaffold({
    super.key,
    required this.body,
    this.title,
    this.trailing = const [],
    this.onBack,
    this.showBack = true,
    this.showTopBar = true,
    this.topBarLeading,
    this.washes = const [],
    this.stars = false,
    this.padding,
    this.bottomBar,
    this.overlay,
    this.backgroundColor = CsColors.bg,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget body;
  final String? title;
  final List<Widget> trailing;
  final VoidCallback? onBack;
  final bool showBack;
  final bool showTopBar;
  final Widget? topBarLeading;
  final List<CsWash> washes;
  final bool stars;

  /// Override the standard screen padding (scaled 32/24/32/22).
  final EdgeInsets? padding;

  /// Pinned under the body, outside the padding (e.g. a banner ad).
  final Widget? bottomBar;

  /// Full-bleed layer painted above the body (confetti, toasts…).
  final Widget? overlay;
  final Color backgroundColor;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final pad = padding ?? cs.screenPadding;
    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: CsBackground(
        color: backgroundColor,
        washes: washes,
        stars: stars,
        child: Stack(
          children: [
            SafeArea(
              bottom: bottomBar == null,
              child: Padding(
                padding: pad,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showTopBar) ...[
                      CsTopBar(
                        title: title,
                        trailing: trailing,
                        onBack: onBack,
                        showBack: showBack,
                        leading: topBarLeading,
                      ),
                      SizedBox(height: cs(14)),
                    ],
                    Expanded(child: body),
                  ],
                ),
              ),
            ),
            ?overlay,
          ],
        ),
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}

/// The standard landscape two-region layout: a summary column on the left
/// (fixed width, scaled), content on the right. On very narrow screens the
/// left column shrinks; it never scrolls — wrap tall content in
/// [CsFitColumn].
class CsSplit extends StatelessWidget {
  const CsSplit({
    super.key,
    required this.left,
    required this.right,
    this.leftWidth,
    this.gap,
    this.leftFlex,
  });

  final Widget left;
  final Widget right;

  /// Design-frame width of the left column (scaled). Defaults to ~290.
  final double? leftWidth;
  final double? gap;

  /// Use proportional widths instead of a fixed left column (e.g. 5 → 5:6).
  final int? leftFlex;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final g = gap ?? cs(44);
    if (leftFlex != null) {
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: leftFlex!, child: left),
        SizedBox(width: g),
        Expanded(flex: 10 - leftFlex!, child: right),
      ]);
    }
    final w = leftWidth == null ? cs.sideColumn : cs(leftWidth!);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: w, child: left),
      SizedBox(width: g),
      Expanded(child: right),
    ]);
  }
}

/// A column that renders at natural size and scales DOWN (never scrolls)
/// when the available height is short — for side panels / summaries.
class CsFitColumn extends StatelessWidget {
  const CsFitColumn({
    super.key,
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.alignment = Alignment.topLeft,
  });

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: c.maxWidth, minWidth: c.maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxisAlignment,
            children: children,
          ),
        ),
      );
    });
  }
}
