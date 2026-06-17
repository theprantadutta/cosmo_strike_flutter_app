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
    'The original Ship experience',
    icon: '🚀',
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
    BoardSize(20, 20, 'Classic', 'The original Ship experience', icon: '🚀'),
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

  // ===========================================================================
  // COMMAND-HUD SKIN PALETTES
  // Every skin shares a deep indigo / near-black space base and is differentiated
  // by a neon PRIMARY (ship) + neon SECONDARY (food) + tertiary accent. This is
  // the "sleek sci-fi command HUD" language — no amber-phosphor, no warm dot-matrix.
  // Field names are preserved (they back the GameTheme getters + ~1,175 call
  // sites); only the values change.
  // ===========================================================================

  // Command Cyan (default skin, `classic` slot) — cyan hull / magenta energy.
  static const Color classicBackground = Color(0xFF05060F); // deep indigo black
  static const Color classicShip = Color(0xFF22D3EE);       // neon cyan
  static const Color classicFood = Color(0xFFF21DC4);       // neon magenta
  static const Color classicBorder = Color(0xFF38BDF8);     // sky-blue accent

  // Azure skin
  static const Color modernBackground = Color(0xFF070A18);
  static const Color modernShip = Color(0xFF38BDF8); // sky blue
  static const Color modernFood = Color(0xFFFB7185); // rose
  static const Color modernAccent = Color(0xFF60A5FA); // azure

  // Voltage skin
  static const Color neonBackground = Color(0xFF04040C);
  static const Color neonShip = Color(0xFF00FFC6); // aqua-mint
  static const Color neonFood = Color(0xFFFF2BD6); // hot magenta
  static const Color neonGlow = Color(0xFF9DFF00); // electric lime

  // Synthwave skin
  static const Color retroBackground = Color(0xFF0B0518);
  static const Color retroShip = Color(0xFFFF3CAC); // magenta-pink
  static const Color retroFood = Color(0xFF36E2FF); // electric cyan
  static const Color retroAccent = Color(0xFFFFC53D); // amber-gold marquee

  // Nebula skin (premium)
  static const Color spaceBackground = Color(0xFF070A20);
  static const Color spaceShip = Color(0xFF8B5CF6); // violet
  static const Color spaceFood = Color(0xFF22D3EE); // cyan
  static const Color spaceAccent = Color(0xFF6366F1); // indigo

  // Abyssal skin (premium)
  static const Color oceanBackground = Color(0xFF03101E);
  static const Color oceanShip = Color(0xFF2DD4BF); // teal
  static const Color oceanFood = Color(0xFF38BDF8); // sky
  static const Color oceanAccent = Color(0xFF0EA5E9); // cerulean

  // Override skin (premium)
  static const Color cyberpunkBackground = Color(0xFF0A0118);
  static const Color cyberpunkShip = Color(0xFFFF2BD6); // neon magenta
  static const Color cyberpunkFood = Color(0xFFFCEE0A); // electric yellow
  static const Color cyberpunkAccent = Color(0xFF9D4EDD); // vivid purple

  // Bio Lab skin (premium)
  static const Color forestBackground = Color(0xFF04130D);
  static const Color forestShip = Color(0xFF34D399); // emerald neon
  static const Color forestFood = Color(0xFF22D3EE); // cyan
  static const Color forestAccent = Color(0xFFA3E635); // lime

  // Solar Flare skin (premium) — warm neon, still on the deep-space base.
  static const Color desertBackground = Color(0xFF120A08);
  static const Color desertShip = Color(0xFFFF7849); // warm orange-neon
  static const Color desertFood = Color(0xFF2DE2E6); // cyan counterpoint
  static const Color desertAccent = Color(0xFFFFC24B); // solar gold

  // Prism Core skin (premium)
  static const Color crystalBackground = Color(0xFF0A0820);
  static const Color crystalShip = Color(0xFFA5F3FC); // icy cyan
  static const Color crystalFood = Color(0xFFF0ABFC); // orchid
  static const Color crystalAccent = Color(0xFFC4B5FD); // lavender

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

  Color get shipColor {
    switch (this) {
      case GameTheme.classic:
        return GameConstants.classicShip;
      case GameTheme.modern:
        return GameConstants.modernShip;
      case GameTheme.neon:
        return GameConstants.neonShip;
      case GameTheme.retro:
        return GameConstants.retroShip;
      case GameTheme.space:
        return GameConstants.spaceShip;
      case GameTheme.ocean:
        return GameConstants.oceanShip;
      case GameTheme.cyberpunk:
        return GameConstants.cyberpunkShip;
      case GameTheme.forest:
        return GameConstants.forestShip;
      case GameTheme.desert:
        return GameConstants.desertShip;
      case GameTheme.crystal:
        return GameConstants.crystalShip;
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
        return GameConstants.classicShip;
      case GameTheme.modern:
        return GameConstants.modernShip;
      case GameTheme.neon:
        return GameConstants.neonShip;
      case GameTheme.retro:
        return GameConstants.retroShip;
      case GameTheme.space:
        return GameConstants.spaceShip;
      case GameTheme.ocean:
        return GameConstants.oceanShip;
      case GameTheme.cyberpunk:
        return GameConstants.cyberpunkShip;
      case GameTheme.forest:
        return GameConstants.forestShip;
      case GameTheme.desert:
        return GameConstants.desertShip;
      case GameTheme.crystal:
        return GameConstants.crystalShip;
    }
  }

  /// Every command-HUD skin sits on a deep-space base, so body text is a single
  /// icy white across all skins (see also [textPrimary]/[textMuted]).
  Color get textColor => const Color(0xFFEAF3FF);

  /// Surface panel color: a subtly skin-tinted dark glass derived from the
  /// background + a hint of the neon primary. Used by legacy `cardColor` call
  /// sites; new UI should prefer [surface] / [surfaceGlass].
  Color get cardColor =>
      Color.alphaBlend(shipColor.withValues(alpha: 0.06), backgroundColor);

  // ---------------------------------------------------------------------------
  // Command-HUD semantic tokens (new design language). Implemented in terms of
  // the existing skin getters so only the ~30 palette constants ever change.
  // ---------------------------------------------------------------------------

  /// Primary neon accent (cyan/violet/etc. per skin) — hulls, key strokes, CTAs.
  Color get neonPrimary => shipColor;

  /// Secondary neon accent — highlights, energy nodes, contrast pops.
  Color get neonSecondary => foodColor;

  /// Glow color for shadows/halos (matches the primary neon).
  Color get glow => shipColor;

  /// Hairline stroke for glass panels / holographic borders.
  Color get stroke => shipColor.withValues(alpha: 0.35);

  /// Opaque elevated surface (slightly skin-tinted dark).
  Color get surface =>
      Color.alphaBlend(shipColor.withValues(alpha: 0.05), backgroundColor);

  /// Frosted-glass fill (translucent) for panels rendered over the starfield.
  Color get surfaceGlass => backgroundColor.withValues(alpha: 0.55);

  /// Primary body/label text — icy white.
  Color get textPrimary => const Color(0xFFEAF3FF);

  /// Muted/secondary text.
  Color get textMuted => const Color(0xB3EAF3FF);

  /// Thin holographic grid line color.
  Color get gridLine => shipColor.withValues(alpha: 0.10);

  /// Player-facing skin label (cockpit naming). [name] is kept stable for
  /// persistence/backend sync; UI should show [displayName].
  String get displayName {
    switch (this) {
      case GameTheme.classic:
        return 'Command Cyan';
      case GameTheme.modern:
        return 'Azure';
      case GameTheme.neon:
        return 'Voltage';
      case GameTheme.retro:
        return 'Synthwave';
      case GameTheme.space:
        return 'Nebula';
      case GameTheme.ocean:
        return 'Abyssal';
      case GameTheme.cyberpunk:
        return 'Override';
      case GameTheme.forest:
        return 'Bio Lab';
      case GameTheme.desert:
        return 'Solar Flare';
      case GameTheme.crystal:
        return 'Prism Core';
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

  // ---------------------------------------------------------------------
  // SHOOTER rules — consumed by CosmoStrikeGame (the real Flame game).
  // The legacy grid getters below (hasWalls / hasMultipleFood / etc.) are
  // legacy grid mechanics still referenced by the old GameCubit grid engine;
  // do NOT use them for the shooter.
  // ---------------------------------------------------------------------

  /// Ships per run. Survival and Perfect Game are single-ship modes.
  int get runLives {
    switch (this) {
      case GameMode.survival:
      case GameMode.perfectGame:
        return 1;
      default:
        return 3;
    }
  }

  /// Whether enemies and bosses shoot back. Zen is collision-threat only.
  bool get enemiesFire => this != GameMode.zen;

  /// Global pacing multiplier applied to enemy speed.
  double get difficultyMultiplier {
    switch (this) {
      case GameMode.zen:
        return 0.75;
      case GameMode.speedChallenge:
        return 1.5;
      case GameMode.timeAttack:
        return 1.25;
      default:
        return 1.0;
    }
  }

  /// Extra enemies added to every wave (Onslaught's swarms).
  int get extraEnemiesPerWave => this == GameMode.onslaught ? 4 : 0;

  /// Chance a destroyed enemy drops a power-up.
  double get powerUpDropChance =>
      this == GameMode.powerUpMadness ? 0.35 : 0.12;

  /// Perfect Game: any hit that lands ends the run outright.
  bool get oneHitRun => this == GameMode.perfectGame;

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

  // PerfectGame rule: the ship's head must never re-enter any cell its
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
