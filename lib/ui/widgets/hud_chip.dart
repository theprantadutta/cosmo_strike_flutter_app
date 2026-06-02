import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../design/glow.dart';
import '../design/tokens.dart';

/// Compact status pill for telemetry readouts (score, coins, mode, count).
/// Neon icon + value on a translucent capsule with a faint glow.
class HudChip extends StatelessWidget {
  const HudChip({
    super.key,
    required this.label,
    this.icon,
    this.theme,
    this.accent,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final GameTheme? theme;
  final Color? accent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? GameTheme.classic;
    final c = accent ?? t.neonPrimary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? GameTokens.space8 : GameTokens.space12,
        vertical: dense ? GameTokens.space4 : GameTokens.space8,
      ),
      decoration: BoxDecoration(
        color: t.surfaceGlass,
        borderRadius: GameTokens.brPill,
        border: Border.all(color: c.withValues(alpha: 0.5), width: 1),
        boxShadow: softGlow(c, intensity: 0.25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: c, size: dense ? 14 : 18),
            const SizedBox(width: GameTokens.space4),
          ],
          Text(
            label,
            style: TextStyle(
              color: t.textPrimary,
              fontSize: dense ? 12 : 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
