import 'package:flutter/widgets.dart';

/// Command-HUD design tokens — spacing, radii, motion, blur.
///
/// Colors are NOT here: they live on the per-skin `GameTheme` getters in
/// `lib/utils/constants.dart` (`neonPrimary`, `surfaceGlass`, `stroke`, …).
/// This keeps the sci-fi look consistent across every screen.
class GameTokens {
  GameTokens._();

  // 8pt spacing scale
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;
  static const double space48 = 48;

  // Corner radii
  static const double radiusSm = 6;
  static const double radiusMd = 12;
  static const double radiusLg = 20;
  static const double radiusPanel = 16;
  static const double radiusPill = 999;

  // Motion
  static const Duration motionFast = Duration(milliseconds: 120);
  static const Duration motionBase = Duration(milliseconds: 220);
  static const Duration motionSlow = Duration(milliseconds: 420);

  // Frosted-glass blur sigma for BackdropFilter panels
  static const double panelBlurSigma = 14.0;

  // BorderRadius helpers
  static BorderRadius get brSm => BorderRadius.circular(radiusSm);
  static BorderRadius get brMd => BorderRadius.circular(radiusMd);
  static BorderRadius get brLg => BorderRadius.circular(radiusLg);
  static BorderRadius get brPanel => BorderRadius.circular(radiusPanel);
  static BorderRadius get brPill => BorderRadius.circular(radiusPill);
}
