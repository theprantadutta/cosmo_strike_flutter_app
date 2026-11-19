import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

/// Home's bottom navigation: equal-width [HomeNavItem] cells over a
/// hairline. A flat canvas fill keeps the labels off the eclipse art
/// behind (its orbit line used to run through them).
///
/// The cells fade up in a short stagger when the bar first mounts. Home
/// stays mounted under pushed routes, so coming back never replays it.
class HomeNavBar extends StatelessWidget {
  const HomeNavBar({super.key, required this.items});
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CsColors.bg.withValues(alpha: 0.82),
        border: const Border(top: BorderSide(color: CsColors.hairline)),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: context.cs(4)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, item) in items.indexed)
              Expanded(child: CsFadeUp(index: i, distance: 8, child: item)),
          ],
        ),
      ),
    );
  }
}

/// One Home nav destination: icon (with an optional mono badge / gold
/// dot) over a label, filling its cell with a ≥48dp touch target.
class HomeNavItem extends StatelessWidget {
  const HomeNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.badgeColor = CsColors.mint,
    this.dot = false,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;
  final Color badgeColor;
  final bool dot;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final fg = color ?? CsColors.ink70;
    final iconSize = cs(20);
    return CsPressable(
      onTap: onTap,
      semanticLabel: semanticLabel ?? label,
      // Fixed height (FittedBox needs a bounded box, or it grows to keep
      // the content's aspect ratio across the full cell width).
      child: SizedBox(
        height: math.max(48.0, cs(54)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: cs(4), vertical: cs(5)),
          // The pressable carries the full semantic label (badge included).
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(icon, size: iconSize, color: fg),
                          if (dot)
                            Positioned(
                              right: -cs(2),
                              top: -cs(1),
                              // Pops in when a reward becomes ready.
                              child: CsPop(
                                trigger: dot,
                                playOnMount: true,
                                peak: 1.4,
                                child: Container(
                                  width: cs(6),
                                  height: cs(6),
                                  decoration: const BoxDecoration(color: CsColors.gold, shape: BoxShape.circle),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (badge != null) ...[
                        SizedBox(width: cs(5)),
                        // Pops when the progress / tier changes.
                        CsPop(
                          trigger: badge,
                          peak: 1.18,
                          child: Text(badge!, maxLines: 1, style: t.mono(10, color: badgeColor, em: 0.04)),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: cs(4)),
                  Text(label.toUpperCase(), maxLines: 1, style: t.nav.copyWith(color: fg)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
