import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../design/tokens.dart';
import 'glass_panel.dart';
import 'starfield_background.dart';

/// The command-HUD app shell. Every screen wraps its body in a
/// [CommandScaffold] to get: the unified starfield backdrop, landscape-safe
/// insets, and an optional glass top command bar (back / title / actions).
///
/// Pass the active [GameTheme] skin so accent colors match the player's choice.
class CommandScaffold extends StatelessWidget {
  const CommandScaffold({
    super.key,
    required this.body,
    this.theme,
    this.title,
    this.leading,
    this.actions,
    this.showTopBar = true,
    this.animatedBackground = true,
    this.showGrid = true,
    this.bodyPadding = const EdgeInsets.fromLTRB(
      GameTokens.space16,
      GameTokens.space8,
      GameTokens.space16,
      GameTokens.space16,
    ),
    this.bottomBar,
  });

  final Widget body;
  final GameTheme? theme;
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showTopBar;
  final bool animatedBackground;
  final bool showGrid;
  final EdgeInsetsGeometry bodyPadding;

  /// Optional bar pinned below the body (e.g. a banner ad).
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final t = theme ?? GameTheme.classic;
    final hasBar = showTopBar &&
        (title != null ||
            leading != null ||
            (actions != null && actions!.isNotEmpty) ||
            Navigator.of(context).canPop());

    return Scaffold(
      backgroundColor: t.backgroundColor,
      bottomNavigationBar: bottomBar,
      body: StarfieldBackground(
        theme: t,
        animated: animatedBackground,
        showGrid: showGrid,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (hasBar) _CommandBar(theme: t, title: title, leading: leading, actions: actions),
              Expanded(
                child: Padding(padding: bodyPadding, child: body),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandBar extends StatelessWidget {
  const _CommandBar({
    required this.theme,
    this.title,
    this.leading,
    this.actions,
  });

  final GameTheme theme;
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GameTokens.space12,
        GameTokens.space8,
        GameTokens.space12,
        0,
      ),
      child: GlassPanel(
        theme: theme,
        radius: GameTokens.radiusMd,
        padding: const EdgeInsets.symmetric(
          horizontal: GameTokens.space12,
          vertical: GameTokens.space8,
        ),
        child: Row(
          children: [
            leading ??
                (canPop
                    ? _BarIcon(
                        theme: theme,
                        icon: Icons.chevron_left,
                        onTap: () => Navigator.of(context).maybePop(),
                      )
                    : const SizedBox(width: GameTokens.space4)),
            const SizedBox(width: GameTokens.space12),
            Expanded(
              child: Text(
                (title ?? '').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
            if (actions != null) ...[
              for (final a in actions!) ...[
                a,
                const SizedBox(width: GameTokens.space8),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.theme, required this.icon, this.onTap});
  final GameTheme theme;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: theme.neonPrimary.withValues(alpha: 0.08),
          borderRadius: GameTokens.brSm,
          border: Border.all(color: theme.stroke, width: 1),
        ),
        child: Icon(icon, color: theme.neonPrimary, size: 22),
      ),
    );
  }
}
