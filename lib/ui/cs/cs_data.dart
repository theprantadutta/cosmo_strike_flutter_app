import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/cosmo_theme.dart';
import 'cs_buttons.dart';
import 'cs_motion.dart';
import 'cs_odometer.dart';
import 'cs_prism.dart';

/// One value + mono caption, as used in stat grids.
///
/// When [value] is a number (`"1,250"`, `"+30"`, `"12s"`) and a later build
/// changes it, [CsStatGrid] rolls it with [CsOdometer] (see [CsRollingText]);
/// the first build is always static. Set [roll] false to opt one stat out.
class CsStat {
  const CsStat(this.value, this.label, {this.color = CsColors.ink, this.roll = true});
  final String value;
  final String label;
  final Color color;
  final bool roll;
}

/// Grid of stats separated by hairlines (top border + a hairline under each
/// row), e.g. the 3×2 pause grid and the 4×2 game-over grid.
class CsStatGrid extends StatelessWidget {
  const CsStatGrid({
    super.key,
    required this.stats,
    this.columns = 3,
    this.valueSize = 24,
    this.labelSize = 10,
    this.cellPadding = 12,
    this.animateValues = true,
  });

  final List<CsStat> stats;
  final int columns;
  final double valueSize;
  final double labelSize;
  final double cellPadding;

  /// Roll numeric values that change after the first build (per-stat opt
  /// out: [CsStat.roll]). Static on first build, instant with reduce motion.
  final bool animateValues;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += columns) {
      final slice = stats.sublist(i, math.min(i + columns, stats.length));
      rows.add(DecoratedBox(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CsColors.hairline))),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: cs(cellPadding)),
          child: Row(children: [
            for (var j = 0; j < columns; j++)
              Expanded(
                child: j < slice.length
                    ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                        // Stretch gives the FittedBox the cell width, so long
                        // values (1,000,000+, "STABLE") scale down instead of
                        // running into the next cell.
                        Padding(
                          padding: EdgeInsets.only(right: cs(10)),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: CsRollingText(
                              // Keyed by label so a different stat landing in
                              // this cell never rolls from its neighbour.
                              key: ValueKey<String>(slice[j].label),
                              slice[j].value,
                              enabled: animateValues && slice[j].roll,
                              style: t.number(valueSize, em: -0.01, height: 1.05, color: slice[j].color),
                            ),
                          ),
                        ),
                        SizedBox(height: cs(4)),
                        Text(slice[j].label.toUpperCase(),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: t.mono(labelSize, color: CsColors.ink45)),
                      ])
                    : const SizedBox.shrink(),
              ),
          ]),
        ),
      ));
    }
    return DecoratedBox(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: CsColors.hairline))),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

enum CsTileState {
  /// Completed / claimed: 1px subtle border, transparent.
  done,

  /// The focal item: prism ring + raised fill.
  current,

  /// Selected (non-focal) item: raised fill + strong border.
  selected,

  /// Available but not yet reached: faint fill, no border.
  future,

  /// Locked: 3% fill, content at 25%.
  locked,

  /// Premium track item: gold dashed border on a 5% gold fill.
  pro,
}

/// Bordered tile used for grids only (levels, pass tiers, store items, plans).
class CsTile extends StatelessWidget {
  const CsTile({
    super.key,
    required this.child,
    this.state = CsTileState.done,
    this.onTap,
    this.padding,
    this.radius = CsRadius.tile,
    this.height,
    this.width,
    this.rotateRing = false,
    this.haptic = CsHaptic.none,
  });

  final Widget child;
  final CsTileState state;

  /// Makes the tile a [CsPressable] (press dip + spring release).
  final VoidCallback? onTap;

  /// Tap feedback when [onTap] is set (none by default; screens often fire
  /// their own in onTap).
  final CsHaptic haptic;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double? height;
  final double? width;
  final bool rotateRing;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final pad = padding ?? EdgeInsets.all(cs(10));
    final br = BorderRadius.circular(radius);
    Widget inner = Padding(padding: pad, child: child);

    final Widget tile = switch (state) {
      CsTileState.current => CsPrismRing(radius: radius, rotate: rotateRing, child: inner),
      CsTileState.done => DecoratedBox(
          decoration: BoxDecoration(borderRadius: br, border: Border.all(color: CsColors.lineSubtle)),
          child: inner),
      CsTileState.selected => DecoratedBox(
          decoration: BoxDecoration(
              color: CsColors.raised, borderRadius: br, border: Border.all(color: CsColors.lineStrong)),
          child: inner),
      CsTileState.future => DecoratedBox(
          decoration: BoxDecoration(color: CsColors.fill04, borderRadius: br), child: inner),
      CsTileState.locked => DecoratedBox(
          decoration: BoxDecoration(color: CsColors.fill03, borderRadius: br), child: inner),
      CsTileState.pro => CustomPaint(
          painter: _DashedRRectPainter(radius: radius, color: CsColors.gold.withValues(alpha: .3)),
          child: DecoratedBox(
              decoration: BoxDecoration(color: CsColors.gold.withValues(alpha: .05), borderRadius: br),
              child: inner),
        ),
    };

    final sized = SizedBox(width: width, height: height, child: tile);
    return onTap == null ? sized : CsPressable(onTap: onTap, haptic: haptic, child: sized);
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.radius, required this.color});
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius));
    final path = Path()..addRRect(rr);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) => old.color != color || old.radius != radius;
}

enum CsRingKind { prism, silver, bronze, none }

/// Circular avatar with initials (or image) inside a 1.5px ring.
class CsAvatarRing extends StatelessWidget {
  const CsAvatarRing({
    super.key,
    required this.name,
    this.size = 34,
    this.ring = CsRingKind.prism,
    this.image,
    this.rotate = false,
  });

  final String name;
  final double size;
  final CsRingKind ring;
  final ImageProvider? image;
  final bool rotate;

  static String initialsOf(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'[\s_\-.]+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return clean.substring(0, math.min(2, clean.length)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final d = cs(size);
    final content = ClipOval(
      child: image != null
          ? Image(image: image!, fit: BoxFit.cover, width: d, height: d)
          : Center(
              child: Text(
                initialsOf(name),
                style: cs.type.display(size * 0.32, weight: FontWeight.w700, em: 0.02, height: 1),
              ),
            ),
    );
    final colors = switch (ring) {
      CsRingKind.prism => null,
      CsRingKind.silver => const [CsColors.rank2],
      CsRingKind.bronze => const [CsColors.rank3],
      CsRingKind.none => const [Color(0x26FFFFFF)],
    };
    return SizedBox.square(
      dimension: d,
      child: CsPrismRing(circle: true, fill: CsColors.raised, colors: colors, rotate: rotate, child: content),
    );
  }
}

enum CsChipKind { outline, solid, gold, prism, mint, pink }

/// Small mono chip: difficulty (EASY), YOU, SAVE 17%, NEW…
class CsChip extends StatelessWidget {
  const CsChip(this.label, {super.key, this.kind = CsChipKind.outline, this.icon, this.size = 9});
  final String label;
  final CsChipKind kind;
  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final (Color? bg, Color fg, Color? border) = switch (kind) {
      CsChipKind.outline => (null, CsColors.ink70, const Color(0x33FFFFFF)),
      CsChipKind.solid => (CsColors.ink, CsColors.onLight, null),
      CsChipKind.gold => (CsColors.gold, CsColors.onLight, null),
      CsChipKind.mint => (CsColors.mint.withValues(alpha: .12), CsColors.mint, null),
      CsChipKind.pink => (CsColors.pink.withValues(alpha: .12), CsColors.pink, null),
      CsChipKind.prism => (null, CsColors.ink, null),
    };
    final text = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: cs(size + 3), color: fg), SizedBox(width: cs(4))],
      Text(label.toUpperCase(), maxLines: 1, style: cs.type.mono(size, color: fg, em: 0.14, height: 1.1)),
    ]);
    final pad = EdgeInsets.symmetric(horizontal: cs(7), vertical: cs(3.5));
    if (kind == CsChipKind.prism) {
      return CsPrismRing(radius: CsRadius.pill, fill: CsColors.bg, width: 1, padding: pad, child: text);
    }
    return Container(
      padding: pad,
      decoration: ShapeDecoration(
        color: bg,
        shape: StadiumBorder(side: border == null ? BorderSide.none : BorderSide(color: border)),
      ),
      child: text,
    );
  }
}

/// Icon + label toggle pill (SFX / MUSIC / HAPTICS). Off = 40% ink, 10% border.
class CsToggleChip extends StatelessWidget {
  const CsToggleChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.offLabel,
    this.offIcon,
  });

  final IconData icon;
  final IconData? offIcon;
  final String label;
  final String? offLabel;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final reduce = CsReduceMotion.of(context);
    final duration = reduce ? CsMotion.instant : CsMotion.base;
    final curve = reduce ? Curves.linear : CsMotion.standard;
    return CsPressable(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      semanticLabel: '$label ${value ? 'on' : 'off'}',
      haptic: CsHaptic.selection,
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.symmetric(horizontal: cs(16)),
        decoration: ShapeDecoration(
          shape: StadiumBorder(side: BorderSide(color: value ? const Color(0x33FFFFFF) : CsColors.hairline)),
        ),
        // Ink crossfades with the border instead of snapping.
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: value ? CsColors.ink : CsColors.ink45),
          duration: duration,
          curve: curve,
          builder: (context, c, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(value ? icon : (offIcon ?? icon), size: cs(18), color: c),
              SizedBox(width: cs(8)),
              Text(
                (value ? label : (offLabel ?? '$label off')).toUpperCase(),
                style: cs.type.mono(11, color: c ?? CsColors.ink45, em: 0.1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prism Noir on/off switch: a drop-in for the theme `Switch` (same 60×48
/// footprint and look: white track + black knob when on, hairline outline +
/// small grey knob when off).
///
/// Motion (MOTION_SPEC "Toggles"): the knob slides and grows on `springSoft`
/// over 220 ms while the track fill and outline crossfade. One tiny
/// CustomPaint, repainted only while the tween runs. Reduce motion: a 120 ms
/// linear crossfade, no overshoot. A direct tap plays [haptic].
class CsSwitch extends StatelessWidget {
  const CsSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.haptic = CsHaptic.selection,
    this.semanticLabel,
    this.reduceMotion,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final CsHaptic haptic;
  final String? semanticLabel;

  /// Overrides [CsReduceMotion.of] (tests).
  final bool? reduceMotion;

  static const _knobDuration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final reduce = CsReduceMotion.of(context, override: reduceMotion);
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      onTap: enabled ? _toggle : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: enabled ? _toggle : null,
        child: SizedBox(
          width: 60,
          height: 48,
          child: Center(
            child: RepaintBoundary(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value ? 1 : 0),
                duration: reduce ? CsMotion.instant : _knobDuration,
                curve: reduce ? Curves.linear : CsMotion.springSoft,
                builder: (context, t, _) => CustomPaint(
                  size: const Size(52, 32),
                  painter: _SwitchPainter(t, enabled: enabled),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggle() {
    haptic.play();
    onChanged?.call(!value);
  }
}

class _SwitchPainter extends CustomPainter {
  _SwitchPainter(this.t, {required this.enabled});

  /// 0 off → 1 on; overshoots slightly on the spring (position only).
  final double t;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final c = t.clamp(0.0, 1.0);
    final alpha = enabled ? 1.0 : 0.4;
    final track = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height / 2));
    final fill = Color.lerp(Colors.transparent, CsColors.ink, c)!;
    if (fill.a > 0) canvas.drawRRect(track, Paint()..color = fill.withValues(alpha: fill.a * alpha));
    final outline = Color.lerp(CsColors.lineStrong, CsColors.ink, c)!;
    canvas.drawRRect(
      track.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline.withValues(alpha: outline.a * alpha),
    );
    // Knob: 16 px grey off, 24 px black on; its centre rides the spring.
    final r = (16 + 8 * c) / 2;
    final cx = size.height / 2 + (size.width - size.height) * t;
    final knob = Color.lerp(CsColors.ink45, CsColors.onLight, c)!;
    canvas.drawCircle(Offset(cx, size.height / 2), r, Paint()..color = knob.withValues(alpha: knob.a * alpha));
  }

  @override
  bool shouldRepaint(_SwitchPainter old) => old.t != t || old.enabled != enabled;
}

/// Pill segmented control (GLOBAL / WEEKLY / FRIENDS). Selected = white pill.
///
/// Motion (MOTION_SPEC "Tabs / segments"): the white pill TRAVELS to the new
/// segment over `CsMotion.screen` on `travel`, morphing its width when the
/// segments differ; label colours crossfade over `CsMotion.base`. The pill
/// is painted from the segments' real layout by one CustomPainter driven by
/// one controller, inside a RepaintBoundary, so a change never rebuilds or
/// repaints the screen around it. Reduce motion: the pill jumps and labels
/// crossfade in 120 ms.
class CsSegmented<T> extends StatefulWidget {
  const CsSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.expand = false,
    this.reduceMotion,
  });

  final Map<T, String> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool expand;

  /// Overrides [CsReduceMotion.of] (tests).
  final bool? reduceMotion;

  @override
  State<CsSegmented<T>> createState() => _CsSegmentedState<T>();
}

class _CsSegmentedState<T> extends State<CsSegmented<T>> with SingleTickerProviderStateMixin {
  final _stackKey = GlobalKey();
  final List<GlobalKey> _segmentKeys = [];
  late final AnimationController _c = AnimationController(vsync: this, duration: CsMotion.screen, value: 1);
  late final CurvedAnimation _t = CurvedAnimation(parent: _c, curve: CsMotion.travel);

  /// Pill travel as fractional segment indexes (-1 = nothing selected).
  late double _from = _indexOf(widget.selected).toDouble();
  late double _to = _from;

  int _indexOf(T value) {
    var i = 0;
    for (final k in widget.segments.keys) {
      if (k == value) return i;
      i++;
    }
    return -1;
  }

  double get _position => _from + (_to - _from) * _t.value;

  @override
  void didUpdateWidget(CsSegmented<T> old) {
    super.didUpdateWidget(old);
    final target = _indexOf(widget.selected).toDouble();
    if (target == _to) return;
    final reduce = CsReduceMotion.of(context, override: widget.reduceMotion, listen: false);
    if (target < 0 || _to < 0 || reduce) {
      _from = _to = target;
      _c.value = 1;
    } else {
      // Retarget from wherever the pill is now, so a quick second tap
      // glides on instead of snapping back.
      _from = _position;
      _to = target;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  /// The pill rect in the stack's coordinates at fractional index [p],
  /// read from the laid-out segments (valid during paint).
  Rect? _pillRect() {
    final p = _position;
    final n = _segmentKeys.length;
    if (p < 0 || n == 0) return null;
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || !stack.hasSize) return null;
    Rect? rectOf(int i) {
      final box = _segmentKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) return null;
      return MatrixUtils.transformRect(box.getTransformTo(stack), Offset.zero & box.size);
    }

    final lo = p.floor().clamp(0, n - 1);
    final hi = p.ceil().clamp(0, n - 1);
    final a = rectOf(lo);
    final b = rectOf(hi);
    if (a == null || b == null) return a ?? b;
    return Rect.lerp(a, b, p - lo);
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final reduce = CsReduceMotion.of(context, override: widget.reduceMotion);
    final n = widget.segments.length;
    while (_segmentKeys.length < n) {
      _segmentKeys.add(GlobalKey());
    }
    if (_segmentKeys.length > n) _segmentKeys.removeRange(n, _segmentKeys.length);

    final base = t.display(12, weight: FontWeight.w700, em: 0.1, height: 1);
    var i = 0;
    final items = widget.segments.entries.map((e) {
      final on = e.key == widget.selected;
      final chip = KeyedSubtree(
        key: _segmentKeys[i++],
        child: CsPressable(
          onTap: () => widget.onChanged(e.key),
          semanticLabel: e.value,
          haptic: on ? CsHaptic.none : CsHaptic.selection,
          child: Container(
            constraints: BoxConstraints(minHeight: cs(34).clamp(36.0, 48.0)),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: cs(16)),
            child: AnimatedDefaultTextStyle(
              duration: reduce ? CsMotion.instant : CsMotion.base,
              curve: reduce ? Curves.linear : CsMotion.standard,
              style: base.copyWith(color: on ? CsColors.onLight : CsColors.ink60),
              child: Text(e.value.toUpperCase(), maxLines: 1),
            ),
          ),
        ),
      );
      return widget.expand ? Expanded(child: chip) : chip;
    }).toList();

    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.all(cs(4)),
        decoration: const ShapeDecoration(
          shape: StadiumBorder(side: BorderSide(color: Color(0x24FFFFFF))),
        ),
        child: Stack(
          key: _stackKey,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _SegmentPillPainter(_pillRect, repaint: _c)),
              ),
            ),
            Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                for (var j = 0; j < items.length; j++) ...[if (j > 0) SizedBox(width: cs(4)), items[j]],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the selected white stadium where [rect] says it is right now.
class _SegmentPillPainter extends CustomPainter {
  _SegmentPillPainter(this.rect, {required Listenable repaint}) : super(repaint: repaint);
  final Rect? Function() rect;

  @override
  void paint(Canvas canvas, Size size) {
    final r = rect();
    if (r == null || r.isEmpty) return;
    canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide / 2)), Paint()..color = CsColors.ink);
  }

  // Segment layout can change without the controller ticking (labels,
  // expand, device size), and painting one rounded rect is trivial.
  @override
  bool shouldRepaint(_SegmentPillPainter old) => true;
}

/// A hairline-separated list row: leading · title/subtitle · trailing.
class CsListRow extends StatelessWidget {
  const CsListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.titleTrailing,
    this.padding,
    this.divider = true,
    this.dividerTop = false,
    this.below,
    this.haptic = CsHaptic.none,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  /// Makes the row a [CsPressable] (a gentle 0.99 dip + spring release).
  final VoidCallback? onTap;

  /// Tap feedback when [onTap] is set (none by default).
  final CsHaptic haptic;

  /// Inline widget right after the title (e.g. a CsChip).
  final Widget? titleTrailing;
  final EdgeInsetsGeometry? padding;
  final bool divider;
  final bool dividerTop;

  /// Extra content under the subtitle (e.g. a progress line).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: padding ?? EdgeInsets.symmetric(vertical: cs(12), horizontal: cs(2)),
      decoration: BoxDecoration(
        border: Border(
          bottom: divider ? const BorderSide(color: CsColors.hairline) : BorderSide.none,
          top: dividerTop ? const BorderSide(color: CsColors.hairline) : BorderSide.none,
        ),
      ),
      child: Row(children: [
        if (leading != null) ...[leading!, SizedBox(width: cs(14))],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
              ),
              if (titleTrailing != null) ...[SizedBox(width: cs(8)), titleTrailing!],
            ]),
            if (subtitle != null) ...[
              SizedBox(height: cs(3)),
              Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.body),
            ],
            if (below != null) ...[SizedBox(height: cs(8)), below!],
          ]),
        ),
        if (trailing != null) ...[SizedBox(width: cs(14)), trailing!],
      ]),
    );
    return onTap == null ? row : CsPressable(onTap: onTap, scale: 0.99, haptic: haptic, child: row);
  }
}

/// The one Credits glyph (the gold coin). Use it wherever Credits appear —
/// balances, prices, tabs — never a "$"/paid icon, which reads as real money.
/// [size] is in design-frame px (scaled through `context.cs`).
class CsCoinGlyph extends StatelessWidget {
  const CsCoinGlyph({super.key, this.size = 16, this.opacity = 1});
  final double size;
  final double opacity;

  static const asset = 'assets/images/ui/coin.png';

  @override
  Widget build(BuildContext context) {
    final d = context.cs(size);
    final img = Image.asset(asset, width: d, height: d, excludeFromSemantics: true);
    return opacity >= 1 ? img : Opacity(opacity: opacity, child: img);
  }
}

/// Coin glyph + gold mono amount ("◉ 928").
///
/// When the amount changes after the first build (a purchase, a claim) the
/// number rolls to the new balance with [CsOdometer]; the first build is a
/// plain Text, so lists of prices cost nothing extra. Set [roll] false to
/// keep it static.
class CsCoins extends StatelessWidget {
  const CsCoins(
    this.amount, {
    super.key,
    this.size = 11,
    this.prefix = '',
    this.suffix = '',
    this.color = CsColors.gold,
    this.roll = true,
  });
  final Object amount;
  final double size;
  final String prefix;
  final String suffix;
  final Color color;
  final bool roll;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CsCoinGlyph(size: size * 1.45),
        SizedBox(width: cs(6)),
        CsRollingText(
          '$prefix$amount$suffix',
          enabled: roll,
          style: cs.type.mono(size, color: color, em: 0.1),
        ),
      ],
    );
  }
}

/// Row of 3 stars (gold filled / ink25 outline).
class CsStars extends StatelessWidget {
  const CsStars(this.filled, {super.key, this.total = 3, this.size = 12});
  final int filled;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < total; i++)
        Icon(
          i < filled ? Symbols.star_rounded : Symbols.star_rounded,
          size: cs(size),
          fill: i < filled ? 1 : 0,
          color: i < filled ? CsColors.gold : CsColors.gold.withValues(alpha: .7),
        ),
    ]);
  }
}

/// Small icon in a faint circle — for list leading glyphs.
class CsIconDisc extends StatelessWidget {
  const CsIconDisc(this.icon, {super.key, this.size = 36, this.color = CsColors.ink, this.fill = CsColors.raised});
  final IconData icon;
  final double size;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final d = context.cs(size);
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: CsColors.hairline)),
      alignment: Alignment.center,
      child: Icon(icon, size: d * 0.5, color: color),
    );
  }
}

/// Re-export so screens can render prism-highlighted headlines in one line:
/// `CsHeadline(['Strike ', 'Command'], prismIndex: 1)`.
class CsHeadline extends StatelessWidget {
  const CsHeadline(this.parts, {super.key, this.prismIndex, this.style, this.maxLines = 2, this.textAlign});
  final List<String> parts;
  final int? prismIndex;
  final TextStyle? style;
  final int maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final st = style ?? context.type.title;
    return Text.rich(
      TextSpan(children: [
        for (var i = 0; i < parts.length; i++)
          if (i == prismIndex)
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: CsPrismText(parts[i], style: st),
            )
          else
            TextSpan(text: parts[i], style: st),
      ]),
      maxLines: maxLines,
      textAlign: textAlign,
      overflow: TextOverflow.ellipsis,
    );
  }
}
