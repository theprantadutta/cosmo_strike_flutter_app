import 'package:flutter/material.dart';

import '../../game/cosmo_palette.dart';
import '../../ui/design.dart';
import '../../utils/constants.dart';

/// Shared borderless building blocks for the pause / game-over overlays.
/// Per the clean Command-HUD direction these float straight on the dimmed
/// battlefield — definition comes from neon icon discs, slim bars, glow
/// and spacing, never outlines or panels.

/// One run-telemetry stat: neon icon disc + big value + tiny label.
class RunStatTile extends StatelessWidget {
  const RunStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.accent,
    this.width = 158,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? accent;

  /// Tile width — the game-over grid packs a tighter 3-column layout.
  final double width;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? CosmoPalette.hull;
    return SizedBox(
      width: width,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              boxShadow: softGlow(color, intensity: 0.45),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CosmoPalette.highlight,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CosmoPalette.hull.withValues(alpha: 0.7),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase section heading for the overlay panels.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.accent});

  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: (accent ?? CosmoPalette.hull).withValues(alpha: 0.85),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
      ),
    );
  }
}

/// Slim 6px progress bar matching the HUD energy bar language.
class SlimBar extends StatelessWidget {
  const SlimBar({
    super.key,
    required this.value,
    this.color = CosmoPalette.energy,
    this.height = 6,
  });

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: height,
        backgroundColor: CosmoPalette.bgHigh,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

/// Overlay action button — NeonButton at a fixed 44px so the button row
/// stays comfortable on short landscape phones.
class OverlayActionButton extends StatelessWidget {
  const OverlayActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.variant = NeonButtonVariant.solid,
    this.expand = true,
  });

  final String label;
  final VoidCallback onTap;
  final NeonButtonVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return NeonButton(
      label: label,
      onPressed: onTap,
      theme: GameTheme.classic,
      variant: variant,
      height: 44,
      expand: expand,
    );
  }
}
