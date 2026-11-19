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
  const ScrollEdgeFade({super.key, required this.child});

  /// The scrollable (e.g. a SingleChildScrollView).
  final Widget child;

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
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
        child: ShaderMask(
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
        ),
      ),
    );
  }
}

/// "m:ss" for run / level clocks.
String formatRunTime(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
