import 'package:flutter/painting.dart';

/// Command-HUD palette for the Cosmo Strike gameplay layer: a neon cyan player
/// hull, sky-blue energy, hot-magenta hostiles, and a deep-indigo space base —
/// the same sleek sci-fi language as the app shell. Kept separate from the app
/// `GameTheme` system so the Flame engine stays self-contained on the gameplay
/// screen. Every Flame component reads these constants, so changing the values
/// reskins player_ship / enemy / bullets / power_up / boss / explosion /
/// starfield in one place.
class CosmoPalette {
  CosmoPalette._();

  // Hull / primary (neon cyan)
  static const Color hull = Color(0xFF22D3EE);
  static const Color hullDark = Color(0xFF0891B2);
  static const Color hullLight = Color(0xFF67E8F9);

  // Energy / accent (sky-blue — player thrust & shots, cyan family so it reads
  // as "ours" vs the magenta hostiles)
  static const Color energy = Color(0xFF38BDF8);

  // Highlight (icy white)
  static const Color highlight = Color(0xFFEAF6FF);

  // Backgrounds (deep space indigo, deepest -> lightest)
  static const Color bgDeep = Color(0xFF05060F);
  static const Color bgMid = Color(0xFF0A0C1C);
  static const Color bgHigh = Color(0xFF121634);

  // Muted / holographic grid lines (indigo-cyan)
  static const Color grid = Color(0xFF24407A);

  // Hazard / enemy (hot magenta-red — unmistakably hostile vs the cyan player)
  static const Color hostile = Color(0xFFFF2D78);
  static const Color hostileDeep = Color(0xFFB3164C);

  // Power-up green (positive pickup)
  static const Color boon = Color(0xFF7CFC9A);
}
