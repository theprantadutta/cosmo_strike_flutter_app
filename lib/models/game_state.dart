import 'package:cosmo_strike_flutter_app/models/food.dart';
import 'package:cosmo_strike_flutter_app/models/ship.dart';
import 'package:cosmo_strike_flutter_app/models/position.dart';
import 'package:cosmo_strike_flutter_app/models/power_up.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

enum GameStatus {
  playing,
  paused,
  crashed, // New state for showing crash feedback
  gameOver,
  menu,
}

enum CrashReason {
  wallCollision,
  selfCollision;

  String get message {
    switch (this) {
      case CrashReason.wallCollision:
        return 'You crashed into the wall!';
      case CrashReason.selfCollision:
        return 'You crashed into yourself!';
    }
  }

  String get icon {
    switch (this) {
      case CrashReason.wallCollision:
        return '🧱';
      case CrashReason.selfCollision:
        return '🚀';
    }
  }
}

class GameState {
  final Ship ship;
  final Food? food;
  final List<Food> foods;
  final PowerUp? powerUp;
  final List<ActivePowerUp> activePowerUps;
  final int score;
  final int highScore;
  final GameStatus status;
  final CrashReason? crashReason;
  final Position? crashPosition;
  final Position?
  collisionBodyPart; // For self-collision, shows which body part was hit
  final bool showCrashModal; // Whether to show the crash feedback modal
  final int level;
  final int boardWidth;
  final int boardHeight;
  final DateTime? lastMoveTime;
  final GameMode gameMode;

  // Combo system
  final int currentCombo; // Current streak count
  final int maxCombo; // Best streak this game
  final double comboMultiplier; // Score multiplier based on combo

  // Survival mode lives. Defaults to 1 so non-survival modes behave as before.
  final int livesRemaining;
  final int initialLives;

  // TimeAttack mode: when the current game started. Null in modes without a
  // time limit so the HUD knows to skip the countdown chip.
  final DateTime? gameStartTime;

  /// Pause-time snapshot for TimeAttack — see ActivePowerUp.pausedAt for
  /// the full pattern. When non-null, timeAttackSecondsRemaining treats
  /// this as 'now' so the countdown chip freezes during pause.
  final DateTime? pausedAt;

  // PerfectGame mode: every cell the ship's head has occupied this run.
  // Empty in modes that don't enforce no-revisit so the painter can early-out
  // without iterating an unused set. The cubit owns the master copy and
  // emits a Set.of(...) snapshot each tick in enforcesNoRevisit modes.
  final Set<Position> visitedCells;

  GameState({
    required this.ship,
    this.food,
    this.foods = const [],
    this.powerUp,
    this.activePowerUps = const [],
    this.score = 0,
    this.highScore = 0,
    this.status = GameStatus.menu,
    this.crashReason,
    this.crashPosition,
    this.collisionBodyPart,
    this.showCrashModal = false,
    this.level = 1,
    this.boardWidth = 20,
    this.boardHeight = 20,
    this.lastMoveTime,
    this.gameMode = GameMode.classic,
    this.currentCombo = 0,
    this.maxCombo = 0,
    this.comboMultiplier = 1.0,
    this.livesRemaining = 1,
    this.initialLives = 1,
    this.gameStartTime,
    this.pausedAt,
    this.visitedCells = const {},
  });

  factory GameState.initial() {
    return GameState(
      ship: Ship.initial(),
      status: GameStatus.menu,
      crashReason: null,
      crashPosition: null,
      collisionBodyPart: null,
      showCrashModal: false,
      powerUp: null,
      activePowerUps: const [],
      currentCombo: 0,
      maxCombo: 0,
      comboMultiplier: 1.0,
    );
  }

  /// Calculates the combo multiplier based on the current combo count
  /// - 1-4 foods: 1x multiplier
  /// - 5-9 foods: 1.5x multiplier
  /// - 10-19 foods: 2x multiplier
  /// - 20+ foods: 3x multiplier
  static double calculateComboMultiplier(int combo) {
    if (combo >= 20) return 3.0;
    if (combo >= 10) return 2.0;
    if (combo >= 5) return 1.5;
    return 1.0;
  }

  /// Game speed in milliseconds per tick. Recomputed on each access so that
  /// power-up expiry (which doesn't always trigger a new state emit) is
  /// reflected immediately. Called on the game-tick scheduling path, not the
  /// 60fps render path, so the cost is negligible.
  int get gameSpeed {
    // Speed increases with level (lower milliseconds = faster).
    // Start at 300ms, decrease by game mode-specific amount per level.
    final baseSpeed = 300;
    final speedDecrease = (level - 1) * gameMode.speedIncreaseRate;
    int speed = (baseSpeed - speedDecrease).clamp(50, 300);

    final hasSpeedBoost = activePowerUps.any(
      (p) => p.type == PowerUpType.speedBoost && !p.isExpired,
    );
    final hasSlowMotion = activePowerUps.any(
      (p) => p.type == PowerUpType.slowMotion && !p.isExpired,
    );

    if (hasSpeedBoost) {
      speed = (speed * 0.5).round();
    }
    if (hasSlowMotion) {
      speed = (speed * 1.5).round();
    }

    return speed.clamp(50, 600);
  }

  /// Get cumulative score needed to reach a specific level
  /// Uses triangular progression: 100, 300, 600, 1000, 1500, 2100...
  /// Each level requires 100 more points than the previous level
  static int getTargetScoreForLevel(int lvl) {
    if (lvl <= 1) return 0;
    // Triangular formula: 50 * (lvl - 1) * lvl
    // Level 2: 100, Level 3: 300, Level 4: 600, Level 5: 1000...
    return 50 * (lvl - 1) * lvl;
  }

  /// Target score to reach the NEXT level
  int get targetScore => getTargetScoreForLevel(level + 1);

  /// Score at the START of current level
  int get levelStartScore => getTargetScoreForLevel(level);

  /// Points needed to complete current level (increases each level)
  /// Level 1: 100, Level 2: 200, Level 3: 300, Level 4: 400...
  int get pointsForCurrentLevel => targetScore - levelStartScore;

  /// Progress within current level (0.0 to 1.0)
  double get levelProgress {
    if (pointsForCurrentLevel <= 0) return 0.0;
    final pointsInLevel = score - levelStartScore;
    return (pointsInLevel / pointsForCurrentLevel).clamp(0.0, 1.0);
  }

  /// Points earned within current level
  int get pointsInCurrentLevel =>
      (score - levelStartScore).clamp(0, pointsForCurrentLevel);

  bool get shouldLevelUp => score >= targetScore;

  // Additional power-up effect getters (hasInvincibility is defined later
  // in file). The premium "mega" variants and snake-era exclusive checks
  // were removed with the legacy PremiumActivePowerUp model — premium
  // power-ups now ride the armed-loadout path (ArmedLoadout.apply), not
  // this legacy GameState power-up list.
  bool get hasSpeedBoost => activePowerUps.any(
    (p) => p.type == PowerUpType.speedBoost && !p.isExpired,
  );

  bool get hasSlowMotion => activePowerUps.any(
    (p) => p.type == PowerUpType.slowMotion && !p.isExpired,
  );

  bool get hasScoreMultiplier => activePowerUps.any(
    (p) => p.type == PowerUpType.scoreMultiplier && !p.isExpired,
  );

  /// Always false since the legacy premium power-up spawns were removed —
  /// ghost mode is now an armed-loadout effect inside the Flame game
  /// (PlayerShip.ghostTimer), invisible to this legacy GameState.
  bool get hasGhostMode => false;

  GameState copyWith({
    Ship? ship,
    Food? food,
    List<Food>? foods,
    PowerUp? powerUp,
    bool clearPowerUp = false,
    List<ActivePowerUp>? activePowerUps,
    int? score,
    int? highScore,
    GameStatus? status,
    CrashReason? crashReason,
    Position? crashPosition,
    Position? collisionBodyPart,
    bool? showCrashModal,
    int? level,
    int? boardWidth,
    int? boardHeight,
    DateTime? lastMoveTime,
    GameMode? gameMode,
    int? currentCombo,
    int? maxCombo,
    double? comboMultiplier,
    int? livesRemaining,
    int? initialLives,
    DateTime? gameStartTime,
    DateTime? pausedAt,
    Set<Position>? visitedCells,
    bool clearPausedAt = false,
  }) {
    return GameState(
      ship: ship ?? this.ship,
      food: food ?? this.food,
      foods: foods ?? this.foods,
      powerUp: clearPowerUp ? null : (powerUp ?? this.powerUp),
      activePowerUps: activePowerUps ?? this.activePowerUps,
      score: score ?? this.score,
      highScore: highScore ?? this.highScore,
      status: status ?? this.status,
      crashReason: crashReason ?? this.crashReason,
      crashPosition: crashPosition ?? this.crashPosition,
      collisionBodyPart: collisionBodyPart ?? this.collisionBodyPart,
      showCrashModal: showCrashModal ?? this.showCrashModal,
      level: level ?? this.level,
      boardWidth: boardWidth ?? this.boardWidth,
      boardHeight: boardHeight ?? this.boardHeight,
      lastMoveTime: lastMoveTime ?? this.lastMoveTime,
      gameMode: gameMode ?? this.gameMode,
      currentCombo: currentCombo ?? this.currentCombo,
      maxCombo: maxCombo ?? this.maxCombo,
      comboMultiplier: comboMultiplier ?? this.comboMultiplier,
      livesRemaining: livesRemaining ?? this.livesRemaining,
      initialLives: initialLives ?? this.initialLives,
      gameStartTime: gameStartTime ?? this.gameStartTime,
      pausedAt: clearPausedAt ? null : (pausedAt ?? this.pausedAt),
      visitedCells: visitedCells ?? this.visitedCells,
    );
  }

  /// Seconds remaining in TimeAttack mode (0 if not a timed mode). Uses
  /// pausedAt as the effective "now" so the chip freezes mid-pause.
  int get timeAttackSecondsRemaining {
    final limit = gameMode.timeLimit;
    if (limit == null || gameStartTime == null) return 0;
    final effectiveNow = pausedAt ?? DateTime.now();
    final elapsed = effectiveNow.difference(gameStartTime!);
    final remaining = limit - elapsed;
    return remaining.isNegative ? 0 : remaining.inSeconds;
  }

  GameState clearFood() {
    return copyWith(food: null);
  }

  GameState clearPowerUp() {
    return copyWith(clearPowerUp: true);
  }

  GameState addActivePowerUp(ActivePowerUp activePowerUp) {
    return copyWith(activePowerUps: [...activePowerUps, activePowerUp]);
  }

  GameState removeExpiredPowerUps() {
    final unexpiredPowerUps = activePowerUps
        .where((p) => !p.isExpired)
        .toList();
    return copyWith(activePowerUps: unexpiredPowerUps);
  }

  bool get hasInvincibility {
    return activePowerUps.any(
      (p) => p.type == PowerUpType.invincibility && !p.isExpired,
    );
  }

  int get scoreMultiplier {
    final hasMultiplier = activePowerUps.any(
      (p) => p.type == PowerUpType.scoreMultiplier && !p.isExpired,
    );
    return hasMultiplier ? 2 : 1;
  }
}
