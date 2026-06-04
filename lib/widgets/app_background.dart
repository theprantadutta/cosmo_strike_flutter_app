import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/ui/widgets/starfield_background.dart';

/// Legacy background wrappers, now thin shims over the command-HUD
/// [StarfieldBackground].
///
/// The old per-theme decoration painters (amber grids, ocean waves, desert
/// dunes, etc.) are retired. These shims keep the ~25 screens that still import
/// `AppBackground` / `AnimatedAppBackground` rendering the new starfield with
/// zero call-site changes; each screen is migrated to [StarfieldBackground] /
/// `CommandScaffold` directly during the screen sweep, after which this file
/// is deleted.
class AppBackground extends StatelessWidget {
  final Widget child;
  final GameTheme theme;
  final bool showPattern;

  const AppBackground({
    super.key,
    required this.child,
    required this.theme,
    this.showPattern = true,
  });

  @override
  Widget build(BuildContext context) => StarfieldBackground(
        theme: theme,
        // Animate by default so the deep-space scene drifts on every screen
        // (the parallax starfield + comet give the "flying through space" feel;
        // the celestial bodies stay put).
        animated: true,
        showGrid: showPattern,
        child: child,
      );
}

/// Animated variant — same starfield with the parallax/twinkle running.
class AnimatedAppBackground extends StatelessWidget {
  final Widget child;
  final GameTheme theme;
  final bool showPattern;

  const AnimatedAppBackground({
    super.key,
    required this.child,
    required this.theme,
    this.showPattern = true,
  });

  @override
  Widget build(BuildContext context) => StarfieldBackground(
        theme: theme,
        animated: true,
        showGrid: showPattern,
        child: child,
      );
}
