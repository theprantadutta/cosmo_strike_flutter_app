import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../design/tokens.dart';
import 'glass_panel.dart';

/// Tappable glass tile for lists, store rows, and grid items. A selected card
/// brightens its stroke and lights its glow.
class HoloCard extends StatelessWidget {
  const HoloCard({
    super.key,
    required this.child,
    this.onTap,
    this.theme,
    this.selected = false,
    this.padding = const EdgeInsets.all(GameTokens.space16),
    this.radius = GameTokens.radiusMd,
  });

  final Widget child;
  final VoidCallback? onTap;
  final GameTheme? theme;
  final bool selected;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? GameTheme.classic;
    return GlassPanel(
      theme: t,
      onTap: onTap,
      padding: padding,
      radius: radius,
      glow: selected,
      borderColor: selected ? t.neonPrimary : t.stroke,
      fillColor: selected
          ? t.neonPrimary.withValues(alpha: 0.10)
          : t.surfaceGlass,
      child: child,
    );
  }
}
