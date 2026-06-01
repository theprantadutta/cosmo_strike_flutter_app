import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Game typography system using custom fonts
/// - Orbitron: Futuristic display font for headlines and scores
/// - Rajdhani: Clean readable font for body text and UI elements
abstract class GameTypography {
  // Font family names
  static const String headlineFont = 'Orbitron';
  static const String bodyFont = 'Rajdhani';

  // === Display Styles (Large headlines) ===

  /// Extra large display text - 48px Orbitron Bold
  /// Use for: Main titles, splash screens
  static TextStyle displayLarge({Color? color}) => GoogleFonts.orbitron(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: color,
      );

  /// Large display text - 40px Orbitron SemiBold
  /// Use for: Screen titles, important headers
  static TextStyle displayMedium({Color? color}) => GoogleFonts.orbitron(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: color,
      );

  /// Small display text - 34px Orbitron SemiBold
  /// Use for: Section headers
  static TextStyle displaySmall({Color? color}) => GoogleFonts.orbitron(
        fontSize: 34,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
        color: color,
      );

  // === Headline Styles ===

  /// Large headline - 32px Orbitron SemiBold
  /// Use for: Page titles, major section headers
  static TextStyle headlineLarge({Color? color}) => GoogleFonts.orbitron(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: color,
      );

  /// Medium headline - 28px Orbitron Medium
  /// Use for: Card titles, dialog headers
  static TextStyle headlineMedium({Color? color}) => GoogleFonts.orbitron(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        letterSpacing: 1,
        color: color,
      );

  /// Small headline - 24px Orbitron Medium
  /// Use for: Subsection headers
  static TextStyle headlineSmall({Color? color}) => GoogleFonts.orbitron(
        fontSize: 24,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: color,
      );

  // === Title Styles ===

  /// Large title - 22px Rajdhani SemiBold
  /// Use for: List item titles, prominent labels
  static TextStyle titleLarge({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// Medium title - 18px Rajdhani SemiBold
  /// Use for: Card content titles
  static TextStyle titleMedium({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// Small title - 16px Rajdhani SemiBold
  /// Use for: Small card titles, list headers
  static TextStyle titleSmall({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color,
      );

  // === Body Styles ===

  /// Large body text - 16px Rajdhani Regular
  /// Use for: Primary content, descriptions
  static TextStyle bodyLarge({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  /// Medium body text - 14px Rajdhani Regular
  /// Use for: Secondary content, details
  static TextStyle bodyMedium({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color,
      );

  /// Small body text - 12px Rajdhani Regular
  /// Use for: Captions, helper text
  static TextStyle bodySmall({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: color,
      );

  // === Label Styles ===

  /// Large label - 14px Rajdhani SemiBold
  /// Use for: Button text, prominent labels
  static TextStyle labelLarge({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: color,
      );

  /// Medium label - 12px Rajdhani Medium
  /// Use for: Chip text, tags
  static TextStyle labelMedium({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: color,
      );

  /// Small label - 10px Rajdhani Medium
  /// Use for: Badges, small indicators
  static TextStyle labelSmall({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: color,
      );

  // === Special Game Styles ===

  /// Score display - 36px Orbitron Black
  /// Use for: In-game score, high scores
  static TextStyle scoreDisplay({Color? color}) => GoogleFonts.orbitron(
        fontSize: 36,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
        color: color,
      );

  /// Large score display - 48px Orbitron Black
  /// Use for: Game over score, leaderboard top scores
  static TextStyle scoreLarge({Color? color}) => GoogleFonts.orbitron(
        fontSize: 48,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
        color: color,
      );

  /// Small score display - 24px Orbitron Bold
  /// Use for: Mini scores, stats
  static TextStyle scoreSmall({Color? color}) => GoogleFonts.orbitron(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: color,
      );

  /// Button text - 16px Rajdhani Bold
  /// Use for: Primary buttons, CTAs
  static TextStyle buttonLarge({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: color,
      );

  /// Small button text - 14px Rajdhani SemiBold
  /// Use for: Secondary buttons, small actions
  static TextStyle buttonMedium({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: color,
      );

  /// Tiny button text - 12px Rajdhani SemiBold
  /// Use for: Compact buttons, icon buttons with labels
  static TextStyle buttonSmall({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: color,
      );

  /// Game title style - 28px Orbitron ExtraBold
  /// Use for: "SNAKE CLASSIC" title, brand text
  static TextStyle gameTitle({Color? color}) => GoogleFonts.orbitron(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: 3,
        color: color,
      );

  /// Level indicator - 20px Orbitron Bold
  /// Use for: Level numbers, tier indicators
  static TextStyle levelIndicator({Color? color}) => GoogleFonts.orbitron(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// Stats value - 18px Rajdhani Bold
  /// Use for: Statistics numbers, counts
  static TextStyle statsValue({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// Stats label - 12px Rajdhani Medium
  /// Use for: Statistics labels
  static TextStyle statsLabel({Color? color}) => GoogleFonts.rajdhani(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 1,
        color: color,
      );

  // === Helper to create TextTheme ===

  /// Creates a complete TextTheme using game typography
  static TextTheme createTextTheme({Color? color}) => TextTheme(
        displayLarge: displayLarge(color: color),
        displayMedium: displayMedium(color: color),
        displaySmall: displaySmall(color: color),
        headlineLarge: headlineLarge(color: color),
        headlineMedium: headlineMedium(color: color),
        headlineSmall: headlineSmall(color: color),
        titleLarge: titleLarge(color: color),
        titleMedium: titleMedium(color: color),
        titleSmall: titleSmall(color: color),
        bodyLarge: bodyLarge(color: color),
        bodyMedium: bodyMedium(color: color),
        bodySmall: bodySmall(color: color),
        labelLarge: labelLarge(color: color),
        labelMedium: labelMedium(color: color),
        labelSmall: labelSmall(color: color),
      );
}
