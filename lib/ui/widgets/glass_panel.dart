import 'dart:ui';

import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../design/glow.dart';
import '../design/tokens.dart';

/// Frosted-glass surface — the base building block of the command-HUD UI.
///
/// `ClipRRect → BackdropFilter(blur) → translucent skin-tinted fill + hairline
/// neon stroke + optional glow`. Pass the active [GameTheme] skin for accent
/// coloring; falls back to the default Command Cyan skin.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.theme,
    this.padding = const EdgeInsets.all(GameTokens.space16),
    this.radius = GameTokens.radiusPanel,
    this.blurSigma = GameTokens.panelBlurSigma,
    this.glow = false,
    this.borderColor,
    this.fillColor,
    this.onTap,
    this.width,
    this.height,
  });

  final Widget child;
  final GameTheme? theme;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blurSigma;
  final bool glow;
  final Color? borderColor;
  final Color? fillColor;
  final VoidCallback? onTap;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? GameTheme.classic;
    final border = borderColor ?? t.stroke;

    Widget panel = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: fillColor ?? t.surfaceGlass,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: border, width: 1),
            boxShadow: glow ? neonGlow(t.glow, intensity: 0.5) : null,
          ),
          child: child,
        ),
      ),
    );

    if (onTap != null) {
      panel = GestureDetector(onTap: onTap, child: panel);
    }
    return panel;
  }
}
