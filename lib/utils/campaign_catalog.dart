/// Campaign metadata shared by persistence (star rules), the level-select
/// screen (names/grouping), and the gameplay layer (par targets shown on
/// the LEVEL CLEAR overlay).
///
/// Deliberately has NO dependency on `lib/game/` — the Flame-side
/// `LevelCatalog` owns gameplay data (waves, bosses, scalars) and reads
/// display names from here so the two can never drift apart.
class CampaignCatalog {
  CampaignCatalog._();

  /// Total number of campaign levels. Adding a level means appending to
  /// [levelNames] (+ a `LevelDef` in the game's LevelCatalog) — every
  /// loop/star/unlock rule keys off this count.
  static const int totalLevels = 12;

  /// Levels per biome (12 levels / 4 biomes).
  static const int levelsPerBiome = 3;

  /// Max obtainable stars across the whole campaign.
  static const int totalStars = totalLevels * 3;

  /// Biome ids in campaign order. Index = (level - 1) ~/ [levelsPerBiome].
  static const List<String> biomeIds = ['asteroid', 'city', 'hive', 'crystal'];

  /// Display names per biome id.
  static const Map<String, String> biomeNames = {
    'asteroid': 'ASTEROID BELT',
    'city': 'NEON RUINS',
    'hive': 'HIVE NEBULA',
    'crystal': 'CRYSTAL EXPANSE',
  };

  /// Display names per level (index 0 = level 1).
  static const List<String> levelNames = [
    // Asteroid Belt (1–3)
    'FIRST CONTACT',
    'ROCKFALL RUN',
    'IRON DREADNOUGHT',
    // Neon Ruins (4–6)
    'CITY OF GHOSTS',
    'SKYLINE SIEGE',
    'WAR MACHINE',
    // Hive Nebula (7–9)
    'INTO THE HIVE',
    'SWARMLORDS',
    'QUEEN\'S LAIR',
    // Crystal Expanse (10–12)
    'SHATTERED LIGHT',
    'LEVIATHAN DEEP',
    'MOTHERSHIP',
  ];

  static String biomeIdFor(int level) =>
      biomeIds[((level - 1) ~/ levelsPerBiome).clamp(0, biomeIds.length - 1)];

  static String biomeNameFor(int level) => biomeNames[biomeIdFor(level)]!;

  static String levelNameFor(int level) =>
      levelNames[(level - 1).clamp(0, levelNames.length - 1)];

  /// Par clear time in seconds for the 2nd star's "fast clear" path.
  /// Levels get longer as waves grow, so par scales linearly.
  static int parTimeSeconds(int level) => 90 + 10 * (level - 1);

  /// Par score for the 2nd star's alternative "high score" path.
  static int parScore(int level) => 1500 * level;

  /// Star rating from MERGED bests (not a single run), so stars
  /// accumulate across runs and can never regress:
  ///   ★1 — cleared at least once.
  ///   ★2 — cleared under par time OR above par score.
  ///   ★3 — cleared without taking a hit.
  static int starsFor({
    required int stageId,
    required bool cleared,
    required bool noHit,
    required int bestTimeSeconds,
    required int bestScore,
  }) {
    if (!cleared) return 0;
    var stars = 1;
    final fastClear =
        bestTimeSeconds > 0 && bestTimeSeconds <= parTimeSeconds(stageId);
    if (fastClear || bestScore >= parScore(stageId)) stars++;
    if (noHit) stars++;
    return stars;
  }
}
