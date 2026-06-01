import 'package:flutter/painting.dart';

/// Amber-phosphor palette for the Cosmo Strike gameplay layer, seeded from the
/// logo tokens. Kept separate from the app `GameTheme` system so the Flame
/// engine stays self-contained on the gameplay screen.
class CosmoPalette {
  CosmoPalette._();

  // Hull / primary amber
  static const Color hull = Color(0xFFffc14d);
  static const Color hullDark = Color(0xFFff9e2c);
  static const Color hullLight = Color(0xFFffb74d);

  // Energy / accent (electric blue)
  static const Color energy = Color(0xFF5cc8ff);

  // Highlight (icy white)
  static const Color highlight = Color(0xFFeaf6ff);

  // Backgrounds (warm dark, deepest -> lightest)
  static const Color bgDeep = Color(0xFF0a0501);
  static const Color bgMid = Color(0xFF180b03);
  static const Color bgHigh = Color(0xFF2c1707);

  // Muted / grid lines
  static const Color grid = Color(0xFF8a5a22);

  // Hazard / enemy red (kept warm to sit in the amber world)
  static const Color hostile = Color(0xFFff5a3c);
  static const Color hostileDeep = Color(0xFFc23a22);

  // Power-up green
  static const Color boon = Color(0xFF7CFC9A);
}
