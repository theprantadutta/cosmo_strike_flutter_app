import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:material_ui/material_ui.dart';

/// Shared Prism Noir shell for the in-game overlays (pause / level clear /
/// game over): a full-bleed scrim that swallows stray taps (optionally
/// blurred — the pause scrim is the system's one sanctioned blur), soft
/// colour washes, then landscape SafeArea + the scaled overlay padding
/// around [child]. (No banner strip: full-width banners were removed.)
class GameplayOverlayFrame extends StatelessWidget {
  const GameplayOverlayFrame({
    super.key,
    required this.child,
    this.scrim = CsColors.scrim,
    this.blur = false,
    this.washes = const [],
  });

  final Widget child;

  /// Scrim colour over the frozen battlefield (82% near-black by default).
  final Color scrim;

  /// Blur the battlefield behind the scrim (pause only).
  final bool blur;
  final List<CsWash> washes;

  static final ui.ImageFilter _blur = ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10);

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    Widget backdrop = CsBackground(color: scrim, washes: washes);
    if (blur) {
      backdrop = ClipRect(child: BackdropFilter(filter: _blur, child: backdrop));
    }
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: backdrop,
          ),
        ),
        Column(
          children: [
            Expanded(
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(cs(36), cs(26), cs(36), cs(24)),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The overlays' two-region landscape body: the hero/summary column on the
/// left (wider) and a list column on the right, separated by a scaled gap.
class OverlaySplit extends StatelessWidget {
  const OverlaySplit({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 50, child: left),
        SizedBox(width: cs(cs.isCompact ? 32 : 56)),
        Expanded(flex: 35, child: right),
      ],
    );
  }
}

/// A left-aligned action row that scales down (never overflows) on the
/// narrowest phones.
class OverlayActions extends StatelessWidget {
  const OverlayActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final gap = context.cs(12);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A vertical scroller that fades its bottom edge out while more content
/// sits below the fold (the debrief's directives / commendations column
/// was cut mid-row with no hint it scrolled). The fade drops once the end
/// is reached; nothing is faded when the content fits.
class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({super.key, required this.child, this.fadeColor});

  /// The scrollable (e.g. a SingleChildScrollView).
  final Widget child;

  /// When the backdrop is a known opaque colour (the results overlays sit on
  /// `CsColors.bg`), pass it: the edge is then a gradient painted OVER the
  /// list in that colour instead of a ShaderMask, so rows animating inside
  /// never force a saveLayer per frame. Null keeps the alpha mask (needed
  /// over the blurred pause backdrop).
  final Color? fadeColor;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  bool _moreBelow = false;

  bool _onMetrics(ScrollMetrics m) {
    if (m.axis != Axis.vertical) return false;
    final more = m.extentAfter > 1;
    if (more != _moreBelow) setState(() => _moreBelow = more);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final fade = context.cs(36);
    final color = widget.fadeColor;
    final Widget body;
    if (color != null) {
      body = Stack(
        children: [
          Positioned.fill(child: widget.child),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: fade,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _moreBelow ? 1 : 0,
                duration: CsMotion.base,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [color.withValues(alpha: 0), color],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      body = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) {
          final h = rect.height <= 0 ? 1.0 : rect.height;
          final start = (1 - fade / h).clamp(0.0, 1.0);
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFFFFF),
              const Color(0xFFFFFFFF),
              _moreBelow ? const Color(0x00FFFFFF) : const Color(0xFFFFFFFF),
            ],
            stops: [0, start, 1],
          ).createShader(rect);
        },
        child: widget.child,
      );
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
        child: body,
      ),
    );
  }
}

/// The debrief's 4×2 stat grid, laid out exactly like [CsStatGrid] (top
/// hairline, a hairline under each row) but with each cell passed through
/// [cell] so the overlays can stagger the tiles in on their beat sheet.
class RunStatGrid extends StatelessWidget {
  const RunStatGrid({
    super.key,
    required this.stats,
    this.columns = 4,
    this.valueSize = 20,
    this.labelSize = 9,
    this.cellPadding = 10,
    this.cell,
  });

  final List<CsStat> stats;
  final int columns;
  final double valueSize;
  final double labelSize;
  final double cellPadding;

  /// Wraps tile [index] (row-major); null renders it as is.
  final Widget Function(int index, Widget tile)? cell;

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
                    ? _wrap(
                        i + j,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(right: cs(10)),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  slice[j].value,
                                  maxLines: 1,
                                  style: t.number(valueSize, em: -0.01, height: 1.05, color: slice[j].color),
                                ),
                              ),
                            ),
                            SizedBox(height: cs(4)),
                            Text(
                              slice[j].label.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.mono(labelSize, color: CsColors.ink45),
                            ),
                          ],
                        ),
                      )
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

  Widget _wrap(int index, Widget tile) => cell?.call(index, tile) ?? tile;
}

/// "m:ss" for run / level clocks.
String formatRunTime(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
