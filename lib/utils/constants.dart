import 'package:flutter/material.dart';

/// D-Pad position presets for user preference
enum DPadPosition {
  bottomLeft,
  bottomCenter,
  bottomRight;

  String get displayName {
    switch (this) {
      case DPadPosition.bottomLeft:
        return 'Left';
      case DPadPosition.bottomCenter:
        return 'Center';
      case DPadPosition.bottomRight:
        return 'Right';
    }
  }

  String get icon {
    switch (this) {
      case DPadPosition.bottomLeft:
        return '⬅️';
      case DPadPosition.bottomCenter:
        return '⬇️';
      case DPadPosition.bottomRight:
        return '➡️';
    }
  }
}

class BoardSize {
  final int width;
  final int height;
  final String name;
  final String description;
  final bool isPremium;
  final String icon;

  const BoardSize(
    this.width,
    this.height,
    this.name,
    this.description, {
    this.isPremium = false,
    this.icon = '📐',
  });

  // Static getters for common board sizes
  static const BoardSize small = BoardSize(
    15,
    15,
    'Small',
    'Quick games, tight spaces',
    icon: '🎯',
  );
  static const BoardSize classic = BoardSize(
    20,
    20,
    'Classic',
    'The original Snake experience',
    icon: '🐍',
  );
  static const BoardSize large = BoardSize(
    25,
    25,
    'Large',
    'More room to grow',
    icon: '📏',
  );
  static const BoardSize huge = BoardSize(
    30,
    30,
    'Huge',
    'Maximum challenge and space',
    icon: '🏟️',
  );

  // All board sizes list
  static const List<BoardSize> all = [small, classic, large, huge];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardSize &&
          runtimeType == other.runtimeType &&
          width == other.width &&
          height == other.height;

  @override
  int get hashCode => width.hashCode ^ height.hashCode;

  @override
  String toString() => '$name (${width}x$height)';

  String get id => '${width}x$height';
}

class GameConstants {
  // Board dimensions
  static const int defaultBoardWidth = 20;
  static const int defaultBoardHeight = 20;

  // Available board sizes
  static const List<BoardSize> availableBoardSizes = [
    BoardSize(15, 15, 'Small', 'Quick games, tight spaces', icon: '🎯'),
    BoardSize(20, 20, 'Classic', 'The original Snake experience', icon: '🐍'),
    BoardSize(25, 25, 'Large', 'More room to grow', icon: '📏'),
    BoardSize(30, 30, 'Huge', 'Maximum challenge and space', icon: '🏟️'),
    // All board sizes are FREE — anyone can pick any size. (The `isPremium`
    // flag is kept on the model for compatibility but is false everywhere.)
    BoardSize(
      35,
      35,
      'Epic',
      'A big board for advanced players',
      icon: '⭐',
    ),
    BoardSize(
      40,
      40,
      'Massive',
      'Enormous board for epic games',
      icon: '🏆',
    ),
    BoardSize(
      50,
      50,
      'Ultimate',
      'The largest possible board',
      icon: '👑',
    ),
  ];

  // Every board size is free now; these partitions are kept for any callers
  // but `premiumBoardSizes` is always empty.
  static List<BoardSize> get freeBoardSizes =>
      availableBoardSizes.where((size) => !size.isPremium).toList();
  static List<BoardSize> get premiumBoardSizes =>
      availableBoardSizes.where((size) => size.isPremium).toList();

  // Game timing
  static const int initialGameSpeed = 300; // milliseconds
  static const int minGameSpeed = 100;
  static const int maxGameSpeed = 500;

  // === UI Layout Constants ===
  static const double containerMargin = 8.0;
  static const double smallScreenThreshold = 700.0;
  static const double defaultHorizontalPadding = 12.0;
  static const double smallScreenPadding = 8.0;
  static const double largeScreenPadding = 16.0;
  static const double gameBoardBorderWidth = 3.0;
  static const double gestureIndicatorSize = 70.0;

  // === Swipe Detection Constants ===
  static const double swipeMinDelta = 2.0;
  static const double swipeMinVelocity = 300.0;
  static const int swipeSpamPreventionMs = 50;
  static const int swipeSameDirectionThresholdMs = 150;

  // === Animation Constants ===
  static const double gridBackgroundSize = 30.0;
  static const int colorCycleIntervalMs = 500;
  static const int sparkleAnimationSpeedMs = 200;

  // === Safe Zone Warning Constants ===
  static const int wallWarningThreshold = 2; // cells from wall to start warning
  static const double wallWarningMaxIntensity = 0.8;

  // === Power-Up Constants ===
  static const int powerUpExpirationWarningSeconds = 5;
  static const int powerUpSpawnIntervalSeconds = 25;
  static const int powerUpExpirationSeconds = 20;

  // === Crash Feedback Special Modes ===
  static const int crashFeedbackUntilTap = -1; // marker for "until I tap" mode
  static const int crashFeedbackSkip = 0; // marker for "skip entirely" mode

  // Crash feedback duration options (includes special modes)
  // crashFeedbackSkip (0s) = skip entirely, crashFeedbackUntilTap (-1s) = wait for tap
  static const List<Duration> availableCrashFeedbackDurations = [
    Duration(seconds: 0), // Skip entirely
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: -1), // Until I tap (negative duration as marker)
  ];
  static const Duration defaultCrashFeedbackDuration = Duration(seconds: 3);

  /// Gets a user-friendly label for crash feedback duration
  static String getCrashFeedbackLabel(Duration duration) {
    if (duration.inSeconds == crashFeedbackSkip) return 'Skip';
    if (duration.inSeconds == crashFeedbackUntilTap) return 'Until Tap';
    return '${duration.inSeconds}s';
  }

  // Scoring
  static const int baseScore = 10;
  static const int bonusScore = 25;
  static const int specialScore = 50;

  // Colors - Amber Phosphor (Cosmo Strike default; retro dot-matrix amber
  // display seeded from the logo palette). Kept under the `classic` enum slot
  // so it ships as the default theme while the swappable theme system stays
  // intact. Amber hull / electric-blue energy / warm-dark backgrounds.
  static const Color classicBackground = Color(0xFF0a0501); // deepest warm dark
  static const Color classicSnake = Color(0xFFffc14d);      // primary amber hull
  static const Color classicFood = Color(0xFF5cc8ff);       // electric-blue energy
  static const Color classicBorder = Color(0xFFff9e2c);     // darker amber accent

  // Colors - Modern Theme (Improved Contrast)
  static const Color modernBackground = Color(0xFF1a1a2e);
  static const Color modernSnake = Color(0xFF4fc3f7); // Bright cyan-blue
  static const Color modernFood = Color(0xFFe94560); // Kept - good contrast
  static const Color modernAccent = Color(
    0xFF64b5f6,
  ); // Light blue for better visibility

  // Colors - Neon Theme (Enhanced)
  static const Color neonBackground = Color(0xFF0a0a0a);
  static const Color neonSnake = Color(0xFF00ffff); // Electric cyan
  static const Color neonFood = Color(0xFFff1493); // Deep pink
  static const Color neonGlow = Color(0xFF00ff00); // Pure lime green

  // Colors - Retro Theme (80s arcade — bright neon-orange on near-black,
  // intentionally distinct from Desert's earthy palette).
  static const Color retroBackground = Color(0xFF1A0808); // Almost-black with red undertone
  static const Color retroSnake = Color(0xFFFF6A00); // Bright neon orange
  static const Color retroFood = Color(0xFFFFFF00); // Pure arcade yellow
  static const Color retroAccent = Color(0xFFFF1F4F); // Hot pink — arcade marquee glow

  // Colors - Space Theme
  static const Color spaceBackground = Color(0xFF0B0C2A); // Deep space blue
  static const Color spaceSnake = Color(0xFF9932CC); // Dark orchid
  static const Color spaceFood = Color(0xFF00CED1); // Dark turquoise
  static const Color spaceAccent = Color(0xFF4169E1); // Royal blue

  // Colors - Ocean Theme
  static const Color oceanBackground = Color(0xFF001B3D); // Deep ocean blue
  static const Color oceanSnake = Color(0xFF20B2AA); // Light sea green
  static const Color oceanFood = Color(0xFFFF7F50); // Coral
  static const Color oceanAccent = Color(0xFF4682B4); // Steel blue

  // Colors - Cyberpunk Theme
  static const Color cyberpunkBackground = Color(0xFF0D0221); // Deep midnight purple
  static const Color cyberpunkSnake = Color(0xFFFF003C); // Neon red/magenta
  static const Color cyberpunkFood = Color(0xFFFCEE0A); // Electric yellow
  static const Color cyberpunkAccent = Color(0xFFB537F2); // Vivid purple

  // Colors - Forest Theme (rich emerald jungle — vivid green snake on
  // deep forest, distinct from Classic's pale Game Boy yellow-green).
  static const Color forestBackground = Color(0xFF0D2818); // Dark forest floor
  static const Color forestSnake = Color(0xFF2ECC71); // Vivid emerald
  static const Color forestFood = Color(0xFFDC143C); // Crimson berry
  static const Color forestAccent = Color(0xFFF1C40F); // Sunlit-canopy gold

  // Colors - Desert Theme (Southwestern — terracotta canyon with cactus
  // teal food, intentionally separated from Retro's arcade orange).
  static const Color desertBackground = Color(0xFF3D1F0E); // Warm terracotta canyon
  static const Color desertSnake = Color(0xFFCD853F); // Peru — sand-rattlesnake brown
  static const Color desertFood = Color(0xFF5FCBC9); // Cactus turquoise (prickly pear bloom)
  static const Color desertAccent = Color(0xFFE8B894); // Sun-bleached sandy peach

  // Colors - Crystal Theme (icy prismatic — pale crystalline snake on
  // deep amethyst with a rose-quartz food, distinct from Space's cosmic
  // purple-on-navy palette).
  static const Color crystalBackground = Color(0xFF1A0033); // Deep amethyst
  static const Color crystalSnake = Color(0xFFB0E0E6); // Powder-blue ice crystal
  static const Color crystalFood = Color(0xFFFFB6C1); // Rose quartz pink
  static const Color crystalAccent = Color(0xFFE6E6FA); // Lavender shimmer

  // Animation durations
  static const Duration shortAnimation = Duration(milliseconds: 150);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);

  // UI dimensions
  static const double cellSize = 20.0;
  static const double borderWidth = 2.0;
  static const double borderRadius = 4.0;

  // Crash feedback timing
  static const Duration crashFeedbackDuration = Duration(seconds: 5);

  // Storage keys
  static const String highScoreKey = 'high_score';
  static const String selectedThemeKey = 'selected_theme';
  static const String soundEnabledKey = 'sound_enabled';
  static const String musicEnabledKey = 'music_enabled';
  static const String achievementsKey = 'achievements';
  static const String boardSizeKey = 'board_size';
  static const String crashFeedbackDurationKey = 'crash_feedback_duration';
  // statisticsKey ('game_statistics') retired — stats are Drift-first via
  // `gameDao.getStatisticsAsJson()` / `updateStatisticsFromJson()`. No
  // SharedPreferences blob is read or written for stats anymore.
  static const String trailSystemEnabledKey = 'trail_system_enabled';
}

enum GameTheme {
  classic,
  modern,
  neon,
  retro,
  space,
  ocean,
  cyberpunk,
  forest,
  desert,
  crystal;

  String get name {
    switch (this) {
      case GameTheme.classic:
        return 'Amber Phosphor';
      case GameTheme.modern:
        return 'Modern';
      case GameTheme.neon:
        return 'Neon';
      case GameTheme.retro:
        return 'Retro';
      case GameTheme.space:
        return 'Space';
      case GameTheme.ocean:
        return 'Ocean';
      case GameTheme.cyberpunk:
        return 'Cyberpunk';
      case GameTheme.forest:
        return 'Forest';
      case GameTheme.desert:
        return 'Desert';
      case GameTheme.crystal:
        return 'Crystal';
    }
  }

  Color get backgroundColor {
    switch (this) {
      case GameTheme.classic:
        return GameConstants.classicBackground;
      case GameTheme.modern:
        return GameConstants.modernBackground;
      case GameTheme.neon:
        return GameConstants.neonBackground;
      case GameTheme.retro:
        return GameConstants.retroBackground;
      case GameTheme.space:
        return GameConstants.spaceBackground;
      case GameTheme.ocean:
        return GameConstants.oceanBackground;
      case GameTheme.cyberpunk:
        return GameConstants.cyberpunkBackground;
      case GameTheme.forest:
        return GameConstants.forestBackground;
      case GameTheme.desert:
        return GameConstants.desertBackground;
      case GameTheme.crystal:
        return GameConstants.crystalBackground;
    }
  }

  Color get snakeColor {
    switch (this) {
      case GameTheme.classic:
        return GameConstants.classicSnake;
      case GameTheme.modern:
        return GameConstants.modernSnake;
      case GameTheme.neon:
        return GameConstants.neonSnake;
      case GameTheme.retro:
        return GameConstants.retroSnake;
      case GameTheme.space:
        return GameConstants.spaceSnake;
      case GameTheme.ocean:
        return GameConstants.oceanSnake;
      case GameTheme.cyberpunk:
        return GameConstants.cyberpunkSnake;
      case GameTheme.forest:
        return GameConstants.forestSnake;
      case GameTheme.desert:
        return GameConstants.desertSnake;
      case GameTheme.crystal:
        return GameConstants.crystalSnake;
    }
  }

  Color get foodColor {
    switch (this) {
      case GameTheme.classic:
        return GameConstants.classicFood;
      case GameTheme.modern:
        return GameConstants.modernFood;
      case GameTheme.neon:
        return GameConstants.neonFood;
      case GameTheme.retro:
        return GameConstants.retroFood;
      case GameTheme.space:
        return GameConstants.spaceFood;
      case GameTheme.ocean:
        return GameConstants.oceanFood;
      case GameTheme.cyberpunk:
        return GameConstants.cyberpunkFood;
      case GameTheme.forest:
        return GameConstants.forestFood;
      case GameTheme.desert:
        return GameConstants.desertFood;
      case GameTheme.crystal:
        return GameConstants.crystalFood;
    }
  }

  Color get accentColor {
    switch (this) {
      case GameTheme.classic:
        return GameConstants.classicBorder;
      case GameTheme.modern:
        return GameConstants.modernAccent;
      case GameTheme.neon:
        return GameConstants.neonGlow;
      case GameTheme.retro:
        return GameConstants.retroAccent;
      case GameTheme.space:
        return GameConstants.spaceAccent;
      case GameTheme.ocean:
        return GameConstants.oceanAccent;
      case GameTheme.cyberpunk:
        return GameConstants.cyberpunkAccent;
      case GameTheme.forest:
        return GameConstants.forestAccent;
      case GameTheme.desert:
        return GameConstants.desertAccent;
      case GameTheme.crystal:
        return GameConstants.crystalAccent;
    }
  }

  Color get primaryColor {
    switch (this) {
      case GameTheme.classic:
        return GameConstants.classicSnake;
      case GameTheme.modern:
        return GameConstants.modernSnake;
      case GameTheme.neon:
        return GameConstants.neonSnake;
      case GameTheme.retro:
        return GameConstants.retroSnake;
      case GameTheme.space:
        return GameConstants.spaceSnake;
      case GameTheme.ocean:
        return GameConstants.oceanSnake;
      case GameTheme.cyberpunk:
        return GameConstants.cyberpunkSnake;
      case GameTheme.forest:
        return GameConstants.forestSnake;
      case GameTheme.desert:
        return GameConstants.desertSnake;
      case GameTheme.crystal:
        return GameConstants.crystalSnake;
    }
  }

  Color get textColor {
    switch (this) {
      // Amber Phosphor ships on a warm-dark background, so it reads with the
      // icy-white highlight rather than the light-background black87 group.
      case GameTheme.classic:
        return const Color(0xFFeaf6ff);
      case GameTheme.modern:
      case GameTheme.retro:
        return Colors.black87;
      case GameTheme.neon:
      case GameTheme.space:
      case GameTheme.cyberpunk:
      case GameTheme.crystal:
        return Colors.white;
      case GameTheme.ocean:
      case GameTheme.forest:
        return Colors.white70;
      case GameTheme.desert:
        return Colors.black54;
    }
  }

  Color get cardColor {
    switch (this) {
      // Amber Phosphor: warm-dark surface panel (one step lighter than bg).
      case GameTheme.classic:
        return const Color(0xFF180b03);
      case GameTheme.modern:
        return Colors.grey.shade100;
      case GameTheme.neon:
        return Colors.black12;
      case GameTheme.retro:
        return Colors.brown.shade100;
      case GameTheme.space:
        return Colors.indigo.shade900;
      case GameTheme.ocean:
        return Colors.blue.shade900;
      case GameTheme.cyberpunk:
        return Colors.purple.shade900;
      case GameTheme.forest:
        return Colors.green.shade900;
      case GameTheme.desert:
        return Colors.orange.shade100;
      case GameTheme.crystal:
        return Colors.purple.shade100;
    }
  }

  /// Whether this theme is a Pro / IAP-gated premium theme. The premium set
  /// matches the ProductCatalog.Themes entries on the backend (six themes
  /// included with the Pro subscription). Used by `AppBackground` to render
  /// distinctive theme-specific decoration layers so paying users see a
  /// meaningful visual upgrade over the free themes.
  bool get isPremium {
    switch (this) {
      case GameTheme.space:
      case GameTheme.ocean:
      case GameTheme.cyberpunk:
      case GameTheme.forest:
      case GameTheme.desert:
      case GameTheme.crystal:
        return true;
      case GameTheme.classic:
      case GameTheme.modern:
      case GameTheme.neon:
      case GameTheme.retro:
        return false;
    }
  }
}

enum GameMode {
  classic,
  zen,
  speedChallenge,
  onslaught,
  survival,
  timeAttack,
  powerUpMadness,
  perfectGame;

  String get name {
    switch (this) {
      case GameMode.classic:
        return 'Classic';
      case GameMode.zen:
        return 'Zen Mode';
      case GameMode.speedChallenge:
        return 'Speed Challenge';
      case GameMode.onslaught:
        return 'Onslaught';
      case GameMode.survival:
        return 'Survival';
      case GameMode.timeAttack:
        return 'Time Attack';
      case GameMode.powerUpMadness:
        return 'Power-Up Madness';
      case GameMode.perfectGame:
        return 'Perfect Game';
    }
  }

  String get description {
    switch (this) {
      case GameMode.classic:
        return 'Blast through enemy waves and clear the stage';
      case GameMode.zen:
        return 'Relaxed flight — no pressure, just fly and shoot';
      case GameMode.speedChallenge:
        return 'Speed increases rapidly for maximum challenge';
      case GameMode.onslaught:
        return 'Endless enemy swarms — survive the onslaught';
      case GameMode.survival:
        return 'Survive as long as possible with limited lives';
      case GameMode.timeAttack:
        return 'Score as much as possible in limited time';
      case GameMode.powerUpMadness:
        return 'Power-ups spawn far more often — embrace the chaos';
      case GameMode.perfectGame:
        return 'Take a single hit and the run ends. Flawless flying only.';
    }
  }

  String get icon {
    switch (this) {
      case GameMode.classic:
        return '🚀';
      case GameMode.zen:
        return '🧘';
      case GameMode.speedChallenge:
        return '⚡';
      case GameMode.onslaught:
        return '💥';
      case GameMode.survival:
        return '❤️';
      case GameMode.timeAttack:
        return '⏰';
      case GameMode.powerUpMadness:
        return '✨';
      case GameMode.perfectGame:
        return '🎯';
    }
  }

  // Game modes are uniformly free — premium subscription does not gate any
  // specific mode. Selection lives in Settings; the store no longer surfaces
  // a "Modes" tab.

  Duration? get timeLimit {
    switch (this) {
      case GameMode.timeAttack:
        return const Duration(minutes: 3);
      default:
        return null;
    }
  }

  int get initialLives {
    switch (this) {
      case GameMode.survival:
        return 3;
      default:
        return 1;
    }
  }

  bool get hasWalls {
    switch (this) {
      case GameMode.zen:
        return false;
      default:
        return true;
    }
  }

  bool get hasMultipleFood {
    switch (this) {
      case GameMode.onslaught:
        return true;
      default:
        return false;
    }
  }

  int get speedIncreaseRate {
    switch (this) {
      case GameMode.speedChallenge:
        return 15; // Faster speed increase
      case GameMode.timeAttack:
        return 20; // Very fast speed increase
      default:
        return 10; // Normal speed increase
    }
  }

  // Per-mode power-up spawn override. Returns null to fall back to
  // GameConstants.powerUpSpawnIntervalSeconds.
  int? get powerUpSpawnIntervalSecondsOverride {
    switch (this) {
      case GameMode.powerUpMadness:
        return 8;
      default:
        return null;
    }
  }

  // Per-mode power-up spawn probability override (0.0–1.0). Null falls back
  // to the default 0.5 chance inside _trySpawnPowerUp.
  double? get powerUpSpawnChanceOverride {
    switch (this) {
      case GameMode.powerUpMadness:
        return 0.9;
      default:
        return null;
    }
  }

  // PerfectGame rule: the snake's head must never re-enter any cell its
  // body has previously occupied. The cubit tracks visited cells in a Set
  // and crashes the run when this returns true and the head re-enters one.
  bool get enforcesNoRevisit {
    switch (this) {
      case GameMode.perfectGame:
        return true;
      default:
        return false;
    }
  }
}
