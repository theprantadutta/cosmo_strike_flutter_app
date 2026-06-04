import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/audio_service.dart';
import '../../utils/constants.dart';
import '../design/glow.dart';
import '../design/tokens.dart';

enum NeonButtonVariant {
  /// Filled neon gradient — primary CTA.
  solid,

  /// Transparent fill, neon stroke — secondary action.
  outline,

  /// Subtle glass, low emphasis.
  ghost,
}

/// Primary command-HUD button. Replaces `GradientButton`, preserving its
/// press-scale animation + haptic + click sound, restyled to neon/glass.
class NeonButton extends StatefulWidget {
  const NeonButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.leading,
    this.theme,
    this.variant = NeonButtonVariant.solid,
    this.width,
    this.height = 52,
    this.expand = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;

  /// Optional leading widget (e.g. a brand FaIcon). Takes precedence over [icon].
  final Widget? leading;
  final GameTheme? theme;
  final NeonButtonVariant variant;
  final double? width;
  final double height;

  /// If true, stretches to the available width (use inside a Row/Column).
  final bool expand;

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 130),
    vsync: this,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.theme ?? GameTheme.classic;
    final enabled = widget.onPressed != null;
    final primary = t.neonPrimary;
    final secondary = t.neonSecondary;
    final solid = widget.variant == NeonButtonVariant.solid;
    final outline = widget.variant == NeonButtonVariant.outline;

    final fg = solid ? const Color(0xFF03040A) : primary;

    return GestureDetector(
      onTapDown: enabled ? (_) => _c.forward() : null,
      onTapUp: enabled ? (_) => _c.reverse() : null,
      onTapCancel: enabled ? () => _c.reverse() : null,
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              AudioService().playSound('button_click');
              widget.onPressed!();
            }
          : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final g = _c.value;
          return Transform.scale(
            scale: 1.0 - g * 0.06,
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: Container(
                width: widget.expand ? double.infinity : widget.width,
                height: widget.height,
                padding: const EdgeInsets.symmetric(
                    horizontal: GameTokens.space20),
                decoration: BoxDecoration(
                  gradient: solid
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [primary, secondary],
                        )
                      : null,
                  color: outline
                      ? primary.withValues(alpha: 0.06)
                      : (solid ? null : t.surfaceGlass),
                  borderRadius: GameTokens.brMd,
                  border: Border.all(
                    color: solid
                        ? Colors.white.withValues(alpha: 0.18)
                        : primary.withValues(alpha: 0.85),
                    width: 1.4,
                  ),
                  boxShadow: solid
                      ? neonGlow(primary, intensity: 0.6 + g * 0.4)
                      : softGlow(primary, intensity: 0.3 + g * 0.3),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize:
                        widget.expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.leading != null) ...[
                        widget.leading!,
                        const SizedBox(width: GameTokens.space8),
                      ] else if (widget.icon != null) ...[
                        Icon(widget.icon, color: fg, size: 20),
                        const SizedBox(width: GameTokens.space8),
                      ],
                      Flexible(
                        child: Text(
                          widget.label.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
