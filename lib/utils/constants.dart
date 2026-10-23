import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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

  IconData get icon {
    switch (this) {
      case DPadPosition.bottomLeft:
        return Symbols.west_rounded;
      case DPadPosition.bottomCenter:
        return Symbols.south_rounded;
      case DPadPosition.bottomRight:
        return Symbols.east_rounded;
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
    this.icon = '',
  });

  // Static getters for common board sizes
  static const BoardSize small = BoardSize(
    15,
    15,
    'Compact',
    'Legacy grid preset',
  );
  static const BoardSize classic = BoardSize(
    20,
    20,
    'Standard',
    'Legacy grid preset',
  );
  static const BoardSize large = BoardSize(
    25,
    25,
    'Wide',
    'Legacy grid preset',
  );
  static const BoardSize huge = BoardSize(
    30,
    30,
    'Vast',
    'Legacy grid preset',
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
    BoardSize(15, 15, 'Compact', 'Legacy grid preset'),
    BoardSize(20, 20, 'Standard', 'Legacy grid preset'),
    BoardSize(25, 25, 'Wide', 'Legacy grid preset'),
    BoardSize(30, 30, 'Vast', 'Legacy grid preset'),
    // All board sizes are FREE — anyone can pick any size. (The `isPremium`
    // flag is kept on the model for compatibility but is false everywhere.)
    BoardSize(
      35,
      35,
      'Expanse',
      'Legacy grid preset',
    ),
    BoardSize(
      40,
      40,
      'Frontier',
      'Legacy grid preset',
    ),
    BoardSize(
      50,
      50,
      'Deep Field',
      'Legacy grid preset',
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
  // SECTOR PALETTES (gameplay colour themes — GameTheme)
  // Every sector sits on a deep-space base and is differentiated by a PRIMARY
  // (hull / shots), a SECONDARY (hostile accents / right-hand wash) and a
  // tertiary accent. These only tint GAMEPLAY via CosmoPalette — menus are
  // always Prism Noir.
  // ===========================================================================

  // Prism Noir (default) — the stock Prism cyan / pink.
  static const Color prismNoirBackground = Color(0xFF08080B);
  static const Color prismNoirPrimary = Color(0xFF7CF5FF); // prism cyan
  static const Color prismNoirSecondary = Color(0xFFFF8AD8); // prism pink
  static const Color prismNoirAccent = Color(0xFFA78BFA); // prism violet

  // Neon Grid (free)
  static const Color neonGridBackground = Color(0xFF04040C);
  static const Color neonGridPrimary = Color(0xFF00FFC6); // aqua-mint
  static const Color neonGridSecondary = Color(0xFFFF2BD6); // hot magenta
  static const Color neonGridAccent = Color(0xFF9DFF00); // electric lime

  // Monochrome (free) — graphite and white, zero hue.
  static const Color monochromeBackground = Color(0xFF0A0A0D);
  static const Color monochromePrimary = Color(0xFFF4F3F7); // ink white
  static const Color monochromeSecondary = Color(0xFF9A9AA6); // steel
  static const Color monochromeAccent = Color(0xFFCFCFD8); // silver

  // High Contrast (free, accessibility / colour-blind friendly). Built on a
  // blue↔orange axis — the one pair that stays distinguishable across
  // deuteranopia, protanopia, and tritanopia — over a near-black base.
  // Surfaced via Settings → Accessibility, not the Armory.
  static const Color highContrastBackground = Color(0xFF05070D);
  static const Color highContrastPrimary = Color(0xFF4DA3FF); // vivid blue
  static const Color highContrastSecondary = Color(0xFFFF9E1B); // vivid orange
  static const Color highContrastAccent = Color(0xFFFFFFFF); // pure white

  // Aurora Reach (premium) — green / violet aurora sky.
  static const Color auroraBackground = Color(0xFF050C12);
  static const Color auroraPrimary = Color(0xFF5CFFB0); // aurora green
  static const Color auroraSecondary = Color(0xFFB57BFF); // aurora violet
  static const Color auroraAccent = Color(0xFF7CF5D0); // pale jade

  // Solar Forge (premium) — orange / gold, sun-scorched.
  static const Color solarBackground = Color(0xFF120A06);
  static const Color solarPrimary = Color(0xFFFF8A3D); // forge orange
  static const Color solarSecondary = Color(0xFFFFD166); // solar gold
  static const Color solarAccent = Color(0xFFFFB347); // amber

  // Abyssal Rift (premium) — deep blue / black, bioluminescent.
  static const Color abyssBackground = Color(0xFF02060F);
  static const Color abyssPrimary = Color(0xFF2EF2D0); // bio teal
  static const Color abyssSecondary = Color(0xFF4D7CFF); // trench blue
  static const Color abyssAccent = Color(0xFF1E3A8A); // abyss navy

  // Ion Storm (premium) — electric cyan / indigo.
  static const Color ionBackground = Color(0xFF060718);
  static const Color ionPrimary = Color(0xFF3DE8FF); // arc cyan
  static const Color ionSecondary = Color(0xFF6366F1); // storm indigo
  static const Color ionAccent = Color(0xFF818CF8); // static violet

  // Crimson Expanse (premium) — red nebula.
  static const Color crimsonBackground = Color(0xFF12050A);
  static const Color crimsonPrimary = Color(0xFFFF4D5E); // nebula red
  static const Color crimsonSecondary = Color(0xFFFF9A8B); // coral dust
  static const Color crimsonAccent = Color(0xFFB3123A); // deep crimson

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
  static const String reduceMotionKey = 'reduce_motion';
}

/// Sectors — the gameplay colour palettes (UI name "Sectors"). Only tint
/// gameplay via CosmoPalette; menus are always Prism Noir.
///
/// ⚠️ Declaration ORDER is persisted: Drift `theme_index`, the prefs
/// `selected_theme` int and the synced settings row all store [index].
/// The order is chosen so pre-3.2 indices 0 and 2–8 land on their mapped
/// sector unchanged (classic→prismNoir, neon→neonGrid, retro→monochrome,
/// space→crimson, ocean→abyss, cyberpunk→ion, forest→aurora,
/// desert→solar). Old 9/10 are decoded by [fromIndex]; old 1 (modern) is
/// remapped by the one-time `migrateLegacyCatalog`. Only APPEND new sectors.
enum GameTheme {
  prismNoir,
  highContrast,
  neonGrid,
  monochrome,
  crimson,
  abyss,
  ion,
  aurora,
  solar;

  /// Persisted / synced ID (prefs, owned-item rows, backend
  /// `selected_theme_id` / `owned_themes`). Premium sectors use their store
  /// product suffix. Shadows `Enum.name` on purpose — every existing
  /// persistence call site writes `theme.name`. UI shows [displayName].
  String get name => id;

  String get id {
    switch (this) {
      case GameTheme.prismNoir:
        return 'prism_noir';
      case GameTheme.highContrast:
        return 'high_contrast';
      case GameTheme.neonGrid:
        return 'neon_grid';
      case GameTheme.monochrome:
        return 'monochrome';
      case GameTheme.crimson:
        return 'sector_crimson';
      case GameTheme.abyss:
        return 'sector_abyss';
      case GameTheme.ion:
        return 'sector_ion';
      case GameTheme.aurora:
        return 'sector_aurora';
      case GameTheme.solar:
        return 'sector_solar';
    }
  }

  /// Store product suffix for purchasable sectors; null for free ones.
  String? get productId => isPremium ? id : null;

  /// Parse a persisted / synced ID — current IDs, enum identifiers and every
  /// pre-3.2 form (`space`, `Space`, `space_theme`, old display names).
  static GameTheme? fromId(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var key = raw.trim();
    const prefix = 'com.pranta.cosmostrike.';
    if (key.startsWith(prefix)) key = key.substring(prefix.length);
    for (final t in GameTheme.values) {
      if (t.id == key || t.enumName == key) return t;
    }
    key = key.toLowerCase();
    if (key.endsWith('_theme')) {
      key = key.substring(0, key.length - '_theme'.length);
    }
    for (final t in GameTheme.values) {
      if (t.id == key || t.enumName.toLowerCase() == key) return t;
    }
    return _legacy[key];
  }

  /// Like [fromId] with a Prism Noir fallback.
  static GameTheme parse(String? raw) => fromId(raw) ?? GameTheme.prismNoir;

  /// Identifier of the enum member (`Enum.name` is shadowed by [name]).
  String get enumName => EnumName(this).name;

  /// Pre-3.2 theme names / old display labels (REBRAND_SPEC §2.8).
  static const Map<String, GameTheme> _legacy = {
    'classic': GameTheme.prismNoir,
    'amber phosphor': GameTheme.prismNoir,
    'command cyan': GameTheme.prismNoir,
    'modern': GameTheme.prismNoir,
    'azure': GameTheme.prismNoir,
    'retro': GameTheme.monochrome,
    'synthwave': GameTheme.monochrome,
    'accessible': GameTheme.highContrast,
    'high contrast': GameTheme.highContrast,
    'neon': GameTheme.neonGrid,
    'voltage': GameTheme.neonGrid,
    'forest': GameTheme.aurora,
    'bio lab': GameTheme.aurora,
    'desert': GameTheme.solar,
    'solar flare': GameTheme.solar,
    'ocean': GameTheme.abyss,
    'abyssal': GameTheme.abyss,
    'cyberpunk': GameTheme.ion,
    'override': GameTheme.ion,
    'crystal': GameTheme.ion,
    'prism core': GameTheme.ion,
    'space': GameTheme.crimson,
    'nebula': GameTheme.crimson,
  };

  /// Decode a persisted [index]. 0–8 are current; 9/10 can only be pre-3.2
  /// (crystal / accessible) and are folded here. Anything else → default.
  static GameTheme fromIndex(int index) {
    if (index >= 0 && index < GameTheme.values.length) {
      return GameTheme.values[index];
    }
    if (index == 9) return GameTheme.ion; // legacy crystal
    if (index == 10) return GameTheme.highContrast; // legacy accessible
    return GameTheme.prismNoir;
  }

  /// Decode an index KNOWN to be pre-3.2 (old 11-theme order). Used once by
  /// the legacy catalog migration.
  static GameTheme fromLegacyIndex(int index) {
    const legacyOrder = [
      GameTheme.prismNoir, // classic
      GameTheme.prismNoir, // modern
      GameTheme.neonGrid, // neon
      GameTheme.monochrome, // retro
      GameTheme.crimson, // space
      GameTheme.abyss, // ocean
      GameTheme.ion, // cyberpunk
      GameTheme.aurora, // forest
      GameTheme.solar, // desert
      GameTheme.ion, // crystal
      GameTheme.highContrast, // accessible
    ];
    if (index < 0 || index >= legacyOrder.length) return GameTheme.prismNoir;
    return legacyOrder[index];
  }

  Color get backgroundColor {
    switch (this) {
      case GameTheme.prismNoir:
        return GameConstants.prismNoirBackground;
      case GameTheme.highContrast:
        return GameConstants.highContrastBackground;
      case GameTheme.neonGrid:
        return GameConstants.neonGridBackground;
      case GameTheme.monochrome:
        return GameConstants.monochromeBackground;
      case GameTheme.crimson:
        return GameConstants.crimsonBackground;
      case GameTheme.abyss:
        return GameConstants.abyssBackground;
      case GameTheme.ion:
        return GameConstants.ionBackground;
      case GameTheme.aurora:
        return GameConstants.auroraBackground;
      case GameTheme.solar:
        return GameConstants.solarBackground;
    }
  }

  /// Hull / player-shot colour.
  Color get shipColor {
    switch (this) {
      case GameTheme.prismNoir:
        return GameConstants.prismNoirPrimary;
      case GameTheme.highContrast:
        return GameConstants.highContrastPrimary;
      case GameTheme.neonGrid:
        return GameConstants.neonGridPrimary;
      case GameTheme.monochrome:
        return GameConstants.monochromePrimary;
      case GameTheme.crimson:
        return GameConstants.crimsonPrimary;
      case GameTheme.abyss:
        return GameConstants.abyssPrimary;
      case GameTheme.ion:
        return GameConstants.ionPrimary;
      case GameTheme.aurora:
        return GameConstants.auroraPrimary;
      case GameTheme.solar:
        return GameConstants.solarPrimary;
    }
  }

  /// Secondary sector colour (stripe tail, right-hand wash, hostile pops).
  Color get secondaryColor {
    switch (this) {
      case GameTheme.prismNoir:
        return GameConstants.prismNoirSecondary;
      case GameTheme.highContrast:
        return GameConstants.highContrastSecondary;
      case GameTheme.neonGrid:
        return GameConstants.neonGridSecondary;
      case GameTheme.monochrome:
        return GameConstants.monochromeSecondary;
      case GameTheme.crimson:
        return GameConstants.crimsonSecondary;
      case GameTheme.abyss:
        return GameConstants.abyssSecondary;
      case GameTheme.ion:
        return GameConstants.ionSecondary;
      case GameTheme.aurora:
        return GameConstants.auroraSecondary;
      case GameTheme.solar:
        return GameConstants.solarSecondary;
    }
  }

  Color get accentColor {
    switch (this) {
      case GameTheme.prismNoir:
        return GameConstants.prismNoirAccent;
      case GameTheme.highContrast:
        return GameConstants.highContrastAccent;
      case GameTheme.neonGrid:
        return GameConstants.neonGridAccent;
      case GameTheme.monochrome:
        return GameConstants.monochromeAccent;
      case GameTheme.crimson:
        return GameConstants.crimsonAccent;
      case GameTheme.abyss:
        return GameConstants.abyssAccent;
      case GameTheme.ion:
        return GameConstants.ionAccent;
      case GameTheme.aurora:
        return GameConstants.auroraAccent;
      case GameTheme.solar:
        return GameConstants.solarAccent;
    }
  }

  Color get primaryColor => shipColor;

  /// Every sector sits on a deep-space base, so body text is a single icy
  /// white across all sectors (see also [textPrimary]/[textMuted]).
  Color get textColor => const Color(0xFFEAF3FF);

  /// Surface panel color: a subtly sector-tinted dark glass derived from the
  /// background + a hint of the primary. Used by legacy `cardColor` call
  /// sites; new UI should prefer [surface] / [surfaceGlass].
  Color get cardColor =>
      Color.alphaBlend(shipColor.withValues(alpha: 0.06), backgroundColor);

  // ---------------------------------------------------------------------------
  // Semantic tokens, implemented in terms of the palette getters so only the
  // palette constants ever change.
  // ---------------------------------------------------------------------------

  /// Primary neon accent — hulls, key strokes, CTAs.
  Color get neonPrimary => shipColor;

  /// Secondary neon accent — highlights, energy nodes, contrast pops.
  Color get neonSecondary => secondaryColor;

  /// Glow color for shadows/halos (matches the primary neon).
  Color get glow => shipColor;

  /// Hairline stroke for panels / holographic borders.
  Color get stroke => shipColor.withValues(alpha: 0.35);

  /// Opaque elevated surface (slightly sector-tinted dark).
  Color get surface =>
      Color.alphaBlend(shipColor.withValues(alpha: 0.05), backgroundColor);

  /// Translucent fill for panels rendered over the starfield.
  Color get surfaceGlass => backgroundColor.withValues(alpha: 0.55);

  /// Primary body/label text — icy white.
  Color get textPrimary => const Color(0xFFEAF3FF);

  /// Muted/secondary text.
  Color get textMuted => const Color(0xB3EAF3FF);

  /// Thin holographic grid line color.
  Color get gridLine => shipColor.withValues(alpha: 0.10);

  /// Player-facing sector name. [name]/[id] is kept stable for
  /// persistence/backend sync; UI shows this.
  String get displayName {
    switch (this) {
      case GameTheme.prismNoir:
        return 'Prism Noir';
      case GameTheme.highContrast:
        return 'High Contrast';
      case GameTheme.neonGrid:
        return 'Neon Grid';
      case GameTheme.monochrome:
        return 'Monochrome';
      case GameTheme.crimson:
        return 'Crimson Expanse';
      case GameTheme.abyss:
        return 'Abyssal Rift';
      case GameTheme.ion:
        return 'Ion Storm';
      case GameTheme.aurora:
        return 'Aurora Reach';
      case GameTheme.solar:
        return 'Solar Forge';
    }
  }

  /// One-line Armory blurb.
  String get description {
    switch (this) {
      case GameTheme.prismNoir:
        return 'Stock prism on black. The default.';
      case GameTheme.highContrast:
        return 'Blue and orange. Colour-blind friendly.';
      case GameTheme.neonGrid:
        return 'Aqua and magenta on a dark grid.';
      case GameTheme.monochrome:
        return 'Graphite and white. Zero hue.';
      case GameTheme.crimson:
        return 'Red nebula, coral dust.';
      case GameTheme.abyss:
        return 'Deep-blue void, bioluminescent glow.';
      case GameTheme.ion:
        return 'Arc cyan through a storm of indigo.';
      case GameTheme.aurora:
        return 'Green and violet aurora skies.';
      case GameTheme.solar:
        return 'Sun-scorched orange and gold.';
    }
  }

  /// Purchasable sectors (also included with Strike Command). Matches the
  /// backend ProductCatalog sector entries. Used by `AppBackground` to render
  /// sector-specific decoration layers.
  bool get isPremium {
    switch (this) {
      case GameTheme.aurora:
      case GameTheme.solar:
      case GameTheme.abyss:
      case GameTheme.ion:
      case GameTheme.crimson:
        return true;
      case GameTheme.prismNoir:
      case GameTheme.highContrast:
      case GameTheme.neonGrid:
      case GameTheme.monochrome:
        return false;
    }
  }
}

enum GameMode {
  // ORDER IS PERSISTED: GameSettings.gameModeIndex stores the index. Never
  // reorder or insert in the middle — append new modes at the end.
  sortie,
  cruise,
  afterburn,
  swarm,
  holdout,
  blitz,
  overload,
  knifeEdge;

  /// The enum identifier (`afterburn`), which the backend's GameMode enum
  /// parses case-insensitively. [name] is overridden with display labels
  /// ("Knife Edge") that the API rejects — never send it.
  String get wireName => toString().split('.').last;

  /// Normalised (lower-case, no separators) identifiers accepted by
  /// [tryFromWire]: the current enum names plus every legacy spelling that
  /// may still sit in Drift rows, SharedPreferences, replays, deep links or
  /// older backend payloads (pre-3.2 GameMode names, their display labels,
  /// and the retired tournament-mode names).
  static const Map<String, GameMode> _wireAliases = {
    // current
    'sortie': GameMode.sortie,
    'cruise': GameMode.cruise,
    'afterburn': GameMode.afterburn,
    'swarm': GameMode.swarm,
    'holdout': GameMode.holdout,
    'blitz': GameMode.blitz,
    'overload': GameMode.overload,
    'knifeedge': GameMode.knifeEdge,
    // legacy GameMode identifiers (≤ 3.1)
    'classic': GameMode.sortie,
    'zen': GameMode.cruise,
    'zenmode': GameMode.cruise,
    'speedchallenge': GameMode.afterburn,
    'onslaught': GameMode.swarm,
    'survival': GameMode.holdout,
    'timeattack': GameMode.blitz,
    'powerupmadness': GameMode.overload,
    'perfectgame': GameMode.knifeEdge,
    // legacy tournament-mode identifiers
    'speedrun': GameMode.afterburn,
    'nowalls': GameMode.cruise,
    'bossrush': GameMode.sortie,
  };

  /// Parses a persisted / wire mode string. Accepts the new identifiers and
  /// every legacy alias, in any case and with `_`, `-` or spaces
  /// (`knife_edge`, `PerfectGame`, `Speed Challenge`). Returns null when the
  /// string is not a known mode.
  static GameMode? tryFromWire(String? raw) {
    if (raw == null) return null;
    final key = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');
    if (key.isEmpty) return null;
    return _wireAliases[key];
  }

  /// [tryFromWire] with a fallback (default [GameMode.sortie]).
  static GameMode fromWire(String? raw, {GameMode fallback = GameMode.sortie}) =>
      tryFromWire(raw) ?? fallback;

  /// Rewrites any known mode string (new or legacy) to the current wire
  /// identifier; unknown strings are returned unchanged.
  static String normalizeWire(String raw) => tryFromWire(raw)?.wireName ?? raw;

  String get name {
    switch (this) {
      case GameMode.sortie:
        return 'Sortie';
      case GameMode.cruise:
        return 'Cruise';
      case GameMode.afterburn:
        return 'Afterburn';
      case GameMode.swarm:
        return 'Swarm';
      case GameMode.holdout:
        return 'Holdout';
      case GameMode.blitz:
        return 'Blitz';
      case GameMode.overload:
        return 'Overload';
      case GameMode.knifeEdge:
        return 'Knife Edge';
    }
  }

  String get description {
    switch (this) {
      case GameMode.sortie:
        return 'The standard run: waves, formations, a boss.';
      case GameMode.cruise:
        return 'Lighter fire, no score pressure. Learn the patterns.';
      case GameMode.afterburn:
        return 'Scroll speed climbs every wave.';
      case GameMode.swarm:
        return 'Endless dense formations. Hold the line.';
      case GameMode.holdout:
        return 'Three hulls, no repairs. How long can you last?';
      case GameMode.blitz:
        return 'Three minutes. Score everything.';
      case GameMode.overload:
        return 'Gear drops everywhere. Chaos encouraged.';
      case GameMode.knifeEdge:
        return 'One hit ends the run.';
    }
  }

  /// Material Symbol for the mode (no emoji in the UI).
  IconData get icon {
    switch (this) {
      case GameMode.sortie:
        return Symbols.rocket_launch_rounded;
      case GameMode.cruise:
        return Symbols.explore_rounded;
      case GameMode.afterburn:
        return Symbols.local_fire_department_rounded;
      case GameMode.swarm:
        return Symbols.hive_rounded;
      case GameMode.holdout:
        return Symbols.shield_rounded;
      case GameMode.blitz:
        return Symbols.timer_rounded;
      case GameMode.overload:
        return Symbols.bolt_rounded;
      case GameMode.knifeEdge:
        return Symbols.target_rounded;
    }
  }

  // Game modes are uniformly free — premium subscription does not gate any
  // specific mode. Selection lives in Settings.

  Duration? get timeLimit {
    switch (this) {
      case GameMode.blitz:
        return const Duration(minutes: 3);
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------
  // SHOOTER rules — consumed by CosmoStrikeGame (the real Flame game).
  // ---------------------------------------------------------------------

  /// Ships per run. Holdout and Knife Edge are single-ship modes.
  int get runLives {
    switch (this) {
      case GameMode.holdout:
      case GameMode.knifeEdge:
        return 1;
      default:
        return 3;
    }
  }

  /// Whether enemies and bosses shoot back. Cruise is collision-threat only.
  bool get enemiesFire => this != GameMode.cruise;

  /// Global pacing multiplier applied to enemy speed.
  double get difficultyMultiplier {
    switch (this) {
      case GameMode.cruise:
        return 0.75;
      case GameMode.afterburn:
        return 1.5;
      case GameMode.blitz:
        return 1.25;
      default:
        return 1.0;
    }
  }

  /// Extra enemies added to every wave (Swarm's dense formations).
  int get extraEnemiesPerWave => this == GameMode.swarm ? 4 : 0;

  /// Chance a destroyed enemy drops a power-up.
  double get powerUpDropChance => this == GameMode.overload ? 0.35 : 0.12;

  /// Knife Edge: any hit that lands ends the run outright.
  bool get oneHitRun => this == GameMode.knifeEdge;
}
