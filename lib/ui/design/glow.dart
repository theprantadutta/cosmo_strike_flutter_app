import 'package:flutter/widgets.dart';

/// Neon glow box-shadows for the command-HUD look. Layer a tight bright shadow
/// over a wide soft one so edges read as emissive without washing out.
List<BoxShadow> neonGlow(
  Color color, {
  double intensity = 1.0,
  double spread = 0,
}) {
  return [
    BoxShadow(
      color: color.withValues(alpha: 0.45 * intensity),
      blurRadius: 18 * intensity,
      spreadRadius: spread,
    ),
    BoxShadow(
      color: color.withValues(alpha: 0.18 * intensity),
      blurRadius: 40 * intensity,
      spreadRadius: spread,
    ),
  ];
}

/// A single soft halo — for text/icon glow or subtle resting state.
List<BoxShadow> softGlow(Color color, {double intensity = 1.0}) {
  return [
    BoxShadow(
      color: color.withValues(alpha: 0.30 * intensity),
      blurRadius: 16 * intensity,
    ),
  ];
}
