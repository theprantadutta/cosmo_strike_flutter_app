import 'dart:ui' as ui;

import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:flutter/material.dart';

import '../../services/ads/ad_tuning.dart';
import '../ads/banner_ad_widget.dart';

/// Shared Prism Noir shell for the in-game overlays (pause / level clear /
/// game over): a full-bleed scrim that swallows stray taps (optionally
/// blurred — the pause scrim is the system's one sanctioned blur), soft
/// colour washes, the top banner-ad strip, then landscape SafeArea + the
/// scaled overlay padding around [child].
///
/// The banner reserves its height up front and the content lives in the
/// Expanded below it, so a late ad load never shifts or overlaps the
/// overlay. Remote kill switch via [AdTuning.overlayBannersEnabled].
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
            if (AdTuning.overlayBannersEnabled) const ShipBannerAd(top: true),
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

/// "m:ss" for run / level clocks.
String formatRunTime(int seconds) {
  final m = seconds ~/ 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
