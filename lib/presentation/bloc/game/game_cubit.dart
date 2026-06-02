import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart' show ReplaysCompanion;
import 'package:cosmo_strike_flutter_app/models/achievement.dart';
import 'package:cosmo_strike_flutter_app/models/food.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/models/game_state.dart' as model;
import 'package:cosmo_strike_flutter_app/models/position.dart';
import 'package:cosmo_strike_flutter_app/models/power_up.dart';
import 'package:cosmo_strike_flutter_app/models/ship.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/models/game_replay.dart' show GameRecorder, GameReplay;
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/power_up/power_up_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/enhanced_audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/haptic_service.dart';
import 'package:cosmo_strike_flutter_app/services/achievement_service.dart';
import 'package:cosmo_strike_flutter_app/services/review_service.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/daily_challenge_service.dart';
import 'package:cosmo_strike_flutter_app/services/weekly_quest_service.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/models/weekly_quest.dart';
import 'package:cosmo_strike_flutter_app/models/battle_pass.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/battle_pass_cubit.dart';
import 'package:cosmo_strike_flutter_app/utils/direction.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

import 'game_state.dart';
import 'game_settings_cubit.dart';

export 'game_state.dart';
export 'game_settings_state.dart';
export 'game_settings_cubit.dart';

/// Cubit for managing the game loop and gameplay state
class GameCubit extends Cubit<GameCubitState> {
  final AudioService _audioService;
  final EnhancedAudioService _enhancedAudioService;
  final HapticService _hapticService;
  final AchievementService _achievementService;
  final StatisticsService _statisticsService;
  final StorageService _storageService;
  final GameSettingsCubit _settingsCubit;
  final CoinsCubit _coinsCubit;
  final BattlePassCubit _battlePassCubit;
  final AnalyticsFacade _analytics;
  final DailyChallengeService _dailyChallengeService = DailyChallengeService();

  Timer? _gameTimer;
  Timer? _animationTimer;
  Timer? _powerUpTimer;
  Timer? _timeAttackTimer;
  Duration? _timeAttackRemaining;

  final GameRecorder _gameRecorder = GameRecorder();

  // Note: Smooth movement animation is now handled locally in GameBoard widget

  // Achievement tracking
  DateTime? _gameStartTime;
  final Set<String> _foodTypesEatenThisGame = {};
  // Per-game collision tracking. The booleans answer "did this game have
  // any wall/self hits at all" (used by achievements + cause-of-death
  // reporting). The int counters accumulate each crash so Survival mode's
  // multi-respawn games record the true number of collisions instead of 1.
  bool _hitWallThisGame = false;
  bool _hitSelfThisGame = false;
  int _wallHitsThisGame = 0;
  int _selfHitsThisGame = 0;
  int _powerUpsCollectedThisGame = 0;
  int _consecutiveGamesWithoutWallHits = 0;

  // PerfectGame mode: every cell the ship's head has ever occupied during
  // the current run. A second visit ends the run. Reset on game start and
  // Survival respawn; left intact when paused.
  final Set<Position> _visitedCells = {};

  // Brief tick-rate slowdown after a level-up so the moment lands. Cleared
  // automatically when the window passes (checked in _scheduleNextGameTick).
  DateTime? _levelUpSlowdownUntil;

  // Timer that clears state.lastRejectedInputAt after the gesture indicators
  // have flashed red. Cancelled on each new rejection so back-to-back
  // rejections keep the flash visible.
  Timer? _rejectedInputClearTimer;

  // Same pattern for accepted inputs — drives the edge bloom + ship-head
  // intent shimmer. Cancelled on each new acceptance so back-to-back swipes
  // each get a fresh pulse.
  Timer? _acceptedInputClearTimer;

  // Wall-clock timestamp of the moment pauseGame() last fired. resumeGame
  // reads it to shift every wall-clock-driven game timer (active power-ups,
  // on-board power-up expiry, TimeAttack countdown) forward by the pause
  // duration — otherwise a 10s power-up sitting under a 20s pause is gone
  // when the player resumes.
  DateTime? _pauseStartedAt;

  // Tracks the next integer-second boundary at which each active power-up
  // should fire its countdown haptic. Keyed by power-up identity (Set of
  // PowerUpType active in the current game). Reset between games.
  final Map<PowerUpType, int> _powerUpCountdownLastSecond = {};

  // Battle pass milestone tracking (reset per game)
  final Set<String> _bpMilestonesThisGame = {};

  // Statistics tracking
  final Map<String, int> _currentGameFoodTypes = {};
  int _currentGameFoodPoints = 0;
  final Map<String, int> _currentGamePowerUpTypes = {};
  int _currentGamePowerUpTime = 0;

  // Pro perks (read from PremiumCubit at game start). Drives the boosted
  // special-food rate in Food.generateRandom and the boosted in-game
  // power-up spawn chance in _trySpawnPowerUp. Sticky for the duration of
  // a single game so a mid-session Pro lapse doesn't visibly degrade what
  // the player was just experiencing.
  bool _isPro = false;

  // Coins credited during this game session — snapshotted from balance.earned
  // diffs around each earnCoins call so it stays accurate after the daily
  // cap or Pro multiplier adjusts the actual grant. Reset on game start;
  // surfaced via GameCubitState.coinsEarnedThisGame for the game-over screen.
  int _currentGameCoinsEarned = 0;

  GameCubit({
    required AudioService audioService,
    required EnhancedAudioService enhancedAudioService,
    required HapticService hapticService,
    required AchievementService achievementService,
    required StatisticsService statisticsService,
    required StorageService storageService,
    required GameSettingsCubit settingsCubit,
    required CoinsCubit coinsCubit,
    required BattlePassCubit battlePassCubit,
    required AnalyticsFacade analytics,
  }) : _audioService = audioService,
       _enhancedAudioService = enhancedAudioService,
       _hapticService = hapticService,
       _achievementService = achievementService,
       _statisticsService = statisticsService,
       _storageService = storageService,
       _settingsCubit = settingsCubit,
       _coinsCubit = coinsCubit,
       _battlePassCubit = battlePassCubit,
       _analytics = analytics,
       super(GameCubitState.initial());

  /// Initialize the game cubit
  Future<void> initialize() async {
    await _audioService.initialize();
    await _enhancedAudioService.initialize();
    await _achievementService.initialize();
    await _statisticsService.initialize();

    _statisticsService.startNewSession();

    final gameState = model.GameState.initial().copyWith(
      highScore: _settingsCubit.state.highScore,
      boardWidth: _settingsCubit.state.boardSize.width,
      boardHeight: _settingsCubit.state.boardSize.height,
      gameMode: _settingsCubit.state.gameMode,
    );

    emit(state.copyWith(status: GamePlayStatus.ready, gameState: gameState));
  }

  /// Start a new game
  /// Coin cost of an offline / no-ad revive. Also the rewarded-ad alternative.
  static const int reviveCoinCost = 1500;

  /// One revive per run — flips true on [revive], reset on [startGame].
  bool _revivedThisGame = false;

  /// Time-Attack rewarded "+30s" extension: how many seconds each ad grants,
  /// and how many extensions a single run may earn (kept low so it can't beat
  /// a fresh game). Reset per run on [startGame].
  static const int timeBonusSeconds = 30;
  static const int maxTimeBonusesPerRun = 2;
  int _timeBonusesUsed = 0;

  void startGame() {
    debugPrint('🎮 [GameCubit] startGame() called');

    final settings = _settingsCubit.state;
    // Tournament mode: honor the tournament's declared rules instead of the
    // user's settings mode. Previously the cubit ignored tournamentMode at
    // tick time, so PowerUpMadness tournaments played identically to Classic.
    final effectiveGameMode =
        state.tournamentMode?.toGameMode() ?? settings.gameMode;
    debugPrint(
      '🎮 [GameCubit] Settings: boardSize=${settings.boardSize.width}x${settings.boardSize.height}, gameMode=${effectiveGameMode.name}, highScore=${settings.highScore}',
    );

    final initialLives = effectiveGameMode.initialLives;
    final startTime = DateTime.now();
    final gameState = model.GameState.initial().copyWith(
      highScore: settings.highScore,
      boardWidth: settings.boardSize.width,
      boardHeight: settings.boardSize.height,
      gameMode: effectiveGameMode,
      status: model.GameStatus.playing,
      currentCombo: 0,
      maxCombo: 0,
      comboMultiplier: 1.0,
      initialLives: initialLives,
      livesRemaining: initialLives,
      gameStartTime: startTime,
    );

    // Reset tracking
    _gameStartTime = DateTime.now();
    _foodTypesEatenThisGame.clear();
    _hitWallThisGame = false;
    _hitSelfThisGame = false;
    _wallHitsThisGame = 0;
    _selfHitsThisGame = 0;
    _powerUpsCollectedThisGame = 0;
    _currentGameFoodTypes.clear();
    _currentGameFoodPoints = 0;
    _currentGamePowerUpTypes.clear();
    _currentGamePowerUpTime = 0;
    _updateCount = 0;
    _bpMilestonesThisGame.clear();
    _currentGameCoinsEarned = 0;
    _revivedThisGame = false;
    _timeBonusesUsed = 0;
    // Snapshot Pro status once at game start — sticky for the session.
    _isPro = getIt.isRegistered<PremiumCubit>()
        ? getIt<PremiumCubit>().state.hasPremium
        : false;
    _achievementService.resetLastGameUnlocks();
    _visitedCells
      ..clear()
      ..addAll(gameState.ship.body);
    _powerUpCountdownLastSecond.clear();

    // Daily first game XP
    _awardDailyFirstGameXP();

    // Generate initial food. MultiFood mode spawns 3 simultaneously.
    final food = Food.generateRandom(
      gameState.boardWidth,
      gameState.boardHeight,
      gameState.ship,
      isPremium: _isPro,
    );
    final List<Food> extraFoods = [];
    if (gameState.gameMode.hasMultipleFood) {
      for (var i = 0; i < 2; i++) {
        extraFoods.add(
          _generateNonOverlappingFood(
            gameState.boardWidth,
            gameState.boardHeight,
            gameState.ship,
            existing: [food, ...extraFoods],
          ),
        );
      }
    }

    _gameRecorder.startRecording();

    final newState = state.copyWith(
      status: GamePlayStatus.playing,
      gameState: gameState.copyWith(food: food, foods: extraFoods),
      moveProgress: 0.0,
      clearPreviousGameState: true,
    );

    debugPrint(
      '🎮 [GameCubit] Emitting new state: status=${newState.status}, gameState.ship.length=${newState.gameState?.ship.length}',
    );
    emit(newState);
    debugPrint(
      '🎮 [GameCubit] State emitted. Current state.status=${state.status}',
    );

    // Brief "Ready" beat before the first tick fires so the player gets a
    // moment to focus on the ship's starting position. Reuses the
    // level-up slowdown plumbing — set the deadline 500ms out and
    // _scheduleNextGameTick will stretch the very first tick by 1.5x.
    // Auto-clears once the window passes.
    _levelUpSlowdownUntil =
        DateTime.now().add(const Duration(milliseconds: 500));

    _startGameLoop();
    _startSmoothAnimation();
    _startPowerUpTimer();
    _startTimeAttackTimer(settings.gameMode);

    // Pre-game power-up activation: if the user armed a power-up via the
    // home-screen loadout, fire it 5 seconds into the game so they have
    // time to settle into the run before the effect kicks in. Consuming
    // from inventory + clearing the armed slot is handled by the cubit.
    _activateArmedPowerUpIfAny();

    // Tournament-mode start sounds louder + adds a medium haptic so the
    // moment registers as different from a casual run. Casual play keeps
    // the original 0.8 game_start volume with no haptic.
    //
    // Single service only — a previous build also called the legacy
    // _audioService.playSound('game_start') here, which double-played
    // the cue on cold start (one service warm, one loading lazily =
    // two audible plays ~half a second apart).
    if (state.isTournamentMode) {
      _enhancedAudioService.playSfx('game_start', volume: 1.0);
      unawaited(_hapticService.mediumImpact());
    } else {
      _enhancedAudioService.playSfx('game_start', volume: 0.8);
    }

    _analytics.trackGameStarted(
      boardWidth: gameState.boardWidth,
      boardHeight: gameState.boardHeight,
      gameMode: state.isTournamentMode ? 'tournament' : gameState.gameMode.name,
    );

    debugPrint('🎮 [GameCubit] startGame() completed');
  }

  /// Consume the user's armed pre-game power-up (if any) and schedule its
  /// in-game activation 5 seconds in. The PowerUpCubit handles the
  /// server round-trip + inventory decrement; we just inject the
  /// ActivePowerUp into the game state once the delay elapses.
  void _activateArmedPowerUpIfAny() {
    final powerUpCubit = getIt<PowerUpCubit>();
    final armedKey = powerUpCubit.state.armed;
    if (armedKey == null) return;
    final type = PowerUpCubit.typeFromInventoryKey(armedKey);
    if (type == null) {
      AppLogger.warning('Armed power-up key has no PowerUpType mapping: $armedKey');
      return;
    }
    // Consume eagerly so the user can't double-spend by exiting and
    // restarting before the timer fires. consume() also clears the armed
    // slot — re-arming for the next game is intentional.
    unawaited(powerUpCubit.consume(armedKey));
    Future.delayed(const Duration(seconds: 5), () {
      // If the game ended (game over / quit) before the activation
      // window, silently drop. Inventory was already consumed — that's
      // a deliberate "you paid for it" cost.
      if (state.status != GamePlayStatus.playing) return;
      final gameState = state.gameState;
      if (gameState == null) return;
      final updated = gameState.copyWith(
        activePowerUps: [
          ...gameState.activePowerUps,
          ActivePowerUp(type: type),
        ],
      );
      emit(state.copyWith(gameState: updated));
      // Single service only — see startGame() for the cold-start
      // double-play story this avoids.
      _enhancedAudioService.playSfx('power_up_collect', volume: 0.8);
    });
  }

  /// Set tournament mode
  void setTournamentMode(String tournamentId, TournamentGameMode gameMode) {
    emit(state.copyWith(tournamentId: tournamentId, tournamentMode: gameMode));
  }

  /// Exit tournament mode
  void exitTournamentMode() {
    emit(state.copyWith(clearTournament: true));
  }

  /// Pause the game
  void pauseGame() {
    if (state.status != GamePlayStatus.playing) return;

    _gameTimer?.cancel();
    _animationTimer?.cancel();
    _powerUpTimer?.cancel();

    // TimeAttack: snapshot how much time is left so resume can re-arm.
    if (_timeAttackTimer != null && _timeAttackScheduledAt != null) {
      final elapsed = DateTime.now().difference(_timeAttackScheduledAt!);
      final remaining = (_timeAttackRemaining ?? Duration.zero) - elapsed;
      _timeAttackRemaining =
          remaining.isNegative ? Duration.zero : remaining;
      _timeAttackTimer?.cancel();
      _timeAttackTimer = null;
    }

    final pauseStamp = DateTime.now();
    _pauseStartedAt = pauseStamp;

    final current = state.gameState;
    if (current != null) {
      // Stamp pausedAt on every wall-clock-driven object so their getters
      // freeze the displayed time. Without this, the HUD's 60fps animation
      // controllers tick the displayed seconds down even while the game
      // tick timer is cancelled.
      final pausedActive = current.activePowerUps
          .map((p) => ActivePowerUp(
                type: p.type,
                activatedAt: p.activatedAt,
                duration: p.duration,
                pausedAt: pauseStamp,
              ))
          .toList();
      final pausedOnBoard = current.powerUp != null
          ? PowerUp(
              position: current.powerUp!.position,
              type: current.powerUp!.type,
              createdAt: current.powerUp!.createdAt,
              pausedAt: pauseStamp,
            )
          : null;

      emit(
        state.copyWith(
          status: GamePlayStatus.paused,
          gameState: current.copyWith(
            status: model.GameStatus.paused,
            activePowerUps: pausedActive,
            powerUp: pausedOnBoard,
            pausedAt: pauseStamp,
          ),
        ),
      );
    } else {
      emit(
        state.copyWith(
          status: GamePlayStatus.paused,
          gameState: state.gameState?.copyWith(status: model.GameStatus.paused),
        ),
      );
    }

    _analytics.trackGamePaused();
  }

  /// Resume the game
  void resumeGame() {
    if (state.status != GamePlayStatus.paused) return;

    // Shift every wall-clock timer forward by the time we spent paused so
    // power-ups + TimeAttack pick up where they left off instead of losing
    // their remaining seconds to real-world time.
    final pauseDuration = _pauseStartedAt != null
        ? DateTime.now().difference(_pauseStartedAt!)
        : Duration.zero;
    _pauseStartedAt = null;

    final current = state.gameState;
    if (current != null && pauseDuration > Duration.zero) {
      // Shift every wall-clock anchor forward by the pause window AND
      // clear pausedAt so the getters unfreeze. The two halves keep the
      // displayed remaining time stable across the pause boundary: the
      // shift cancels out the elapsed real-world time, the pausedAt clear
      // makes the math use DateTime.now() again.
      final shiftedActive = current.activePowerUps
          .map((p) => ActivePowerUp(
                type: p.type,
                activatedAt: p.activatedAt.add(pauseDuration),
                duration: p.duration,
              ))
          .toList();
      final shiftedPowerUp = current.powerUp != null
          ? PowerUp(
              position: current.powerUp!.position,
              type: current.powerUp!.type,
              createdAt: current.powerUp!.createdAt.add(pauseDuration),
            )
          : null;
      // Same shift for bonus/special food. Food.isExpired compares
      // DateTime.now() to createdAt with no pause concept of its own, so
      // without this a 10–15s pause was enough to expire any bonus/special
      // sitting on the board — the next _updateGame tick after resume would
      // see isExpired==true and reroll its position. Normal food never
      // expires; the shift is harmless either way.
      Food shiftFood(Food f) => Food(
            position: f.position,
            type: f.type,
            createdAt: f.createdAt.add(pauseDuration),
          );
      final shiftedFood =
          current.food != null ? shiftFood(current.food!) : null;
      final shiftedFoods = current.foods.map(shiftFood).toList();
      final shiftedGameStart = current.gameStartTime?.add(pauseDuration);
      emit(
        state.copyWith(
          status: GamePlayStatus.playing,
          gameState: current.copyWith(
            status: model.GameStatus.playing,
            activePowerUps: shiftedActive,
            powerUp: shiftedPowerUp,
            food: shiftedFood,
            foods: shiftedFoods,
            gameStartTime: shiftedGameStart,
            clearPausedAt: true,
          ),
        ),
      );
    } else {
      emit(
        state.copyWith(
          status: GamePlayStatus.playing,
          gameState: current?.copyWith(
            status: model.GameStatus.playing,
            clearPausedAt: true,
          ),
        ),
      );
    }

    // Resume cue: reuse the button_click SFX at low volume + light haptic so
    // the player feels the world come back to life rather than silently
    // sliding from frozen to running.
    _enhancedAudioService.playSfx('button_click', volume: 0.4);
    unawaited(_hapticService.lightImpact());

    _startGameLoop();
    _startSmoothAnimation();
    _startPowerUpTimer();
    _scheduleTimeAttackTimer();

    _analytics.trackGameResumed();
  }

  /// Toggle pause
  void togglePause() {
    if (state.isPlaying) {
      pauseGame();
    } else if (state.isPaused) {
      resumeGame();
    }
  }

  /// Change ship direction
  void changeDirection(Direction newDirection) {
    if (state.status != GamePlayStatus.playing) return;
    if (state.gameState == null) return;

    final accepted = state.gameState!.ship.changeDirection(newDirection);
    if (accepted) {
      HapticFeedback.selectionClick();
      // Emit timestamp + direction so the edge bloom and ship-head intent
      // shimmer can fire. Clears after 300ms.
      final stamp = DateTime.now();
      emit(state.copyWith(
        lastAcceptedInputAt: stamp,
        lastAcceptedDirection: newDirection,
      ));
      _acceptedInputClearTimer?.cancel();
      _acceptedInputClearTimer = Timer(const Duration(milliseconds: 300), () {
        if (state.lastAcceptedInputAt == stamp) {
          emit(state.copyWith(clearAcceptedInput: true));
        }
      });
    } else {
      // Denied: surface a double-buzz haptic + timestamp the rejection so
      // the gesture indicators can flash red. Without this, reverse-into-
      // self attempts look like the game ignored the input entirely.
      HapticFeedback.selectionClick();
      Future.delayed(const Duration(milliseconds: 80), () {
        HapticFeedback.selectionClick();
      });
      final stamp = DateTime.now();
      emit(state.copyWith(lastRejectedInputAt: stamp));
      _rejectedInputClearTimer?.cancel();
      _rejectedInputClearTimer = Timer(const Duration(milliseconds: 250), () {
        if (state.lastRejectedInputAt == stamp) {
          emit(state.copyWith(clearRejectedInput: true));
        }
      });
    }
  }

  void _startGameLoop() {
    _gameTimer?.cancel();
    _scheduleNextGameTick();
  }

  /// Schedules the next game tick using the current game speed.
  /// This pattern allows speed changes to take effect immediately
  /// without causing a pause when the timer is restarted.
  void _scheduleNextGameTick() {
    var speed = state.gameState?.gameSpeed ?? 150;
    // Level-up beat: stretch the next ~300ms by 1.5x so the level
    // transition is felt, not just seen. Window is cleared automatically
    // when DateTime.now() passes the deadline.
    final slowdown = _levelUpSlowdownUntil;
    if (slowdown != null) {
      if (DateTime.now().isBefore(slowdown)) {
        speed = (speed * 1.5).round();
      } else {
        _levelUpSlowdownUntil = null;
      }
    }
    final level = state.gameState?.level ?? 1;
    if (_updateCount <= 5 || _updateCount % 100 == 0) {
      debugPrint(
        '🎮 [GameCubit] Scheduling next tick: speed=${speed}ms, level=$level',
      );
    }

    _gameTimer = Timer(Duration(milliseconds: speed), () {
      try {
        _updateGame();
      } catch (e, stackTrace) {
        debugPrint('🎮 [GameCubit] ERROR in game update loop: $e');
        AppLogger.error('Error in game update loop', e, stackTrace);
      }

      // Schedule next tick only if game is still active (playing or paused)
      // Speed is read fresh each time, so level-up speed changes apply immediately
      final currentStatus = state.status;
      if (currentStatus == GamePlayStatus.playing) {
        _scheduleNextGameTick();
      } else if (currentStatus == GamePlayStatus.paused) {
        // Game is paused - don't schedule. resumeGame() will restart the loop.
      }
      // For crashed/gameOver/ready - don't schedule, game has ended
    });
  }

  void _startSmoothAnimation() {
    // DISABLED: Animation is now handled locally in GameBoard widget
    // using AnimatedBuilder + local Ticker. This avoids Bloc state updates
    // entirely for animation, giving better performance.
    // The widget calculates moveProgress based on time since last game state change.
  }

  void _startPowerUpTimer() {
    _powerUpTimer?.cancel();
    final mode = state.gameState?.gameMode;
    final intervalSeconds = mode?.powerUpSpawnIntervalSecondsOverride ??
        GameConstants.powerUpSpawnIntervalSeconds;
    _powerUpTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _trySpawnPowerUp(),
    );
  }

  /// TimeAttack mode: schedule a one-shot timer that ends the game when
  /// the mode's timeLimit elapses. _timeAttackRemaining tracks the
  /// outstanding duration so pause/resume can re-arm with the leftover.
  void _startTimeAttackTimer(GameMode mode) {
    _timeAttackTimer?.cancel();
    final limit = mode.timeLimit;
    if (limit == null) {
      _timeAttackRemaining = null;
      return;
    }
    _timeAttackRemaining = limit;
    _scheduleTimeAttackTimer();
  }

  void _scheduleTimeAttackTimer() {
    final remaining = _timeAttackRemaining;
    if (remaining == null || remaining <= Duration.zero) return;
    final scheduledAt = DateTime.now();
    _timeAttackTimer?.cancel();
    _timeAttackTimer = Timer(remaining, () async {
      if (state.status == GamePlayStatus.playing) {
        _timeAttackRemaining = Duration.zero;
        // Offer a rewarded "+30s" extension before ending the run, if eligible
        // and an ad is (or can become) ready. Otherwise just end the game.
        if (_canOfferTimeBonus()) {
          final hasAds = getIt.isRegistered<AdService>();
          final adReady = hasAds && getIt<AdService>().isRewardedReady;
          if (hasAds) getIt<AdService>().preloadRewarded();
          if (adReady) {
            _offerTimeBonus();
            return;
          }
        }
        await _gameOver();
      }
    });
    // Remember the scheduling moment so resumeGame can compute leftover.
    _timeAttackScheduledAt = scheduledAt;
  }

  DateTime? _timeAttackScheduledAt;

  // Note: _updateAnimation removed - animation is now handled locally in GameBoard widget

  // Track update count for debugging (disabled in production)
  int _updateCount = 0;
  DateTime? _lastTickTime;

  void _updateGame() {
    _updateCount++;
    final now = DateTime.now();
    if (_lastTickTime != null) {
      final timeSinceLastTick = now.difference(_lastTickTime!).inMilliseconds;
      final expectedSpeed = state.gameState?.gameSpeed ?? 150;
      // Warn if tick took much longer than expected (more than 50% over)
      if (timeSinceLastTick > expectedSpeed * 1.5) {
        debugPrint(
          '🎮 [GameCubit] WARNING: ${timeSinceLastTick}ms since last tick (expected ~${expectedSpeed}ms)',
        );
      }
    }
    _lastTickTime = now;

    if (state.status != GamePlayStatus.playing) {
      if (_updateCount <= 5) {
        debugPrint(
          '🎮 [GameCubit] _updateGame #$_updateCount skipped: status=${state.status}',
        );
      }
      return;
    }
    if (state.gameState == null) {
      debugPrint(
        '🎮 [GameCubit] _updateGame #$_updateCount skipped: gameState is null',
      );
      return;
    }

    if (_updateCount <= 5 || _updateCount % 50 == 0) {
      debugPrint(
        '🎮 [GameCubit] _updateGame #$_updateCount running, ship at ${state.gameState!.ship.head}',
      );
    }

    final previousState = state.gameState!;
    final ship = previousState.ship.copy();
    final isMultiFood = previousState.gameMode.hasMultipleFood;

    // Check for expired food
    var currentFood = previousState.food;
    if (currentFood?.isExpired == true) {
      currentFood = Food.generateRandom(
        previousState.boardWidth,
        previousState.boardHeight,
        ship,
        isPremium: _isPro,
      );
    }

    // MultiFood: refresh any expired extras so the board always has the
    // target count of simultaneously-visible foods.
    var extraFoods = List<Food>.from(previousState.foods);
    if (isMultiFood) {
      for (var i = 0; i < extraFoods.length; i++) {
        if (extraFoods[i].isExpired) {
          extraFoods[i] = _generateNonOverlappingFood(
            previousState.boardWidth,
            previousState.boardHeight,
            ship,
            existing: [
              ?currentFood,
              ...extraFoods.where((f) => f != extraFoods[i]),
            ],
          );
        }
      }
    }

    // Check for expired power-up
    var currentPowerUp = previousState.powerUp;
    var shouldClearPowerUp = false;
    if (currentPowerUp?.isExpired == true) {
      currentPowerUp = null;
      shouldClearPowerUp = true;
    }

    // Check collisions before moving
    final nextHeadPosition = ship.head.move(ship.currentDirection);
    final willEatPrimaryFood =
        currentFood != null &&
        nextHeadPosition == currentFood.position;
    // MultiFood: also check the extras list. Track which index was eaten
    // so we can regenerate just that slot.
    int eatenExtraIndex = -1;
    if (!willEatPrimaryFood && isMultiFood) {
      for (var i = 0; i < extraFoods.length; i++) {
        if (extraFoods[i].position == nextHeadPosition) {
          eatenExtraIndex = i;
          break;
        }
      }
    }
    final willEatFood = willEatPrimaryFood || eatenExtraIndex >= 0;

    // Check power-up collision: both current position AND next position
    // This ensures we don't miss collection if ship spawned on or passed through
    final willCollectPowerUp =
        currentPowerUp != null &&
        (nextHeadPosition == currentPowerUp.position ||
         ship.head == currentPowerUp.position);

    // Debug logging for power-up collision detection (throttled to avoid perf impact)
    if (currentPowerUp != null && (_updateCount <= 5 || _updateCount % 100 == 0)) {
      debugPrint('🎯 Power-up at: ${currentPowerUp.position} (type: ${currentPowerUp.type.name})');
      debugPrint('🚀 Ship head: ${ship.head}, next: $nextHeadPosition');
      debugPrint('✅ Will collect power-up: $willCollectPowerUp');
    }

    // Immunity (invincibility power-up OR the post-revive grace OR ghost mode)
    // also bypasses the outer walls — the collision check below skips wall
    // death while it's active. But bypassing the wall is only safe if the ship
    // actually STAYS on the board: with wrapAround off, an immune ship driven
    // into a wall walks out of bounds invisibly and then dies the instant
    // immunity ends. So while immune we wrap it to the opposite edge (same as
    // no-wall modes) — it re-enters the board and keeps moving instead of
    // sailing off into a doomed off-screen state.
    final hasImmunity =
        previousState.hasInvincibility || previousState.hasGhostMode;

    // Move ship
    ship.move(
      ateFood: willEatFood,
      boardWidth: previousState.boardWidth,
      boardHeight: previousState.boardHeight,
      wrapAround: !previousState.gameMode.hasWalls || hasImmunity,
    );

    // Check collisions
    final wallCollision =
        !hasImmunity &&
        previousState.gameMode.hasWalls &&
        ship.checkWallCollision(
          previousState.boardWidth,
          previousState.boardHeight,
        );
    final selfCollision = !hasImmunity && ship.checkSelfCollision();

    if (wallCollision || selfCollision) {
      final crashReason = wallCollision
          ? model.CrashReason.wallCollision
          : model.CrashReason.selfCollision;

      // Get collision body part for self-collision feedback
      Position? collisionBodyPart;
      if (selfCollision) {
        collisionBodyPart = ship.getSelfCollisionBodyPart();
      }

      _handleCrash(
        crashReason,
        ship.head,
        collisionBodyPart: collisionBodyPart,
        fatalShip: ship,
      );
      return;
    }

    // PerfectGame: head re-entering a previously-visited cell is fatal,
    // regardless of food/immunity. Skip if this tick the head landed on a
    // cell that is currently part of the ship's body — that case is already
    // caught by the self-collision branch above, so any revisit reaching this
    // point is a true trail-cross.
    if (previousState.gameMode.enforcesNoRevisit &&
        !hasImmunity &&
        _visitedCells.contains(ship.head)) {
      _handleCrash(
        model.CrashReason.selfCollision,
        ship.head,
        fatalShip: ship,
      );
      return;
    }
    _visitedCells.add(ship.head);

    // Handle food consumption
    var newScore = previousState.score;
    var newLevel = previousState.level;
    var newCombo = previousState.currentCombo;
    var newMaxCombo = previousState.maxCombo;
    var newComboMultiplier = previousState.comboMultiplier;

    if (willEatFood) {
      // Identify which food was actually consumed (primary vs an extra).
      final eatenFood = willEatPrimaryFood ? currentFood : extraFoods[eatenExtraIndex];

      _foodTypesEatenThisGame.add(eatenFood.type.name);
      _currentGameFoodTypes[eatenFood.type.name] =
          (_currentGameFoodTypes[eatenFood.type.name] ?? 0) + 1;

      newCombo++;
      newMaxCombo = max(newMaxCombo, newCombo);
      newComboMultiplier = model.GameState.calculateComboMultiplier(newCombo);

      // Combo tier crossing — 1.0→1.5 at 5, 1.5→2.0 at 10, 2.0→3.0 at 20.
      // Each crossing earns a medium haptic; the 3.0 tier earns an extra
      // heavy on top so 20-bite streaks land with weight. SFX reuses the
      // existing score_milestone key at low volume so it doesn't drown the
      // food-eat sound (a dedicated combo_milestone asset is a follow-up).
      if (newComboMultiplier > previousState.comboMultiplier) {
        unawaited(_hapticService.mediumImpact());
        if (newComboMultiplier >= 3.0) {
          unawaited(_hapticService.heavyImpact());
        }
        _enhancedAudioService.playSfx('score_milestone', volume: 0.45);
      }

      final basePoints = eatenFood.type.points;
      final comboBonus = (basePoints * newComboMultiplier).round();
      final multipliedPoints = comboBonus * previousState.scoreMultiplier;
      newScore += multipliedPoints;
      _currentGameFoodPoints += multipliedPoints;

      // Battle pass score milestones - deferred to avoid event loop contention
      // during the game tick (addXP can trigger HTTP calls on first invocation)
      Future.microtask(() => _checkScoreMilestones(newScore));

      // Level up (unlimited levels with progressive difficulty).
      // Loop so that a high-combo or multiplied bite can cross multiple
      // level thresholds in a single tick.
      final previousLevel = newLevel;
      while (newScore >= model.GameState.getTargetScoreForLevel(newLevel + 1)) {
        newLevel++;
      }
      if (newLevel > previousLevel) {
        debugPrint(
          '🎮 [GameCubit] LEVEL UP! $previousLevel -> $newLevel (next target: ${model.GameState.getTargetScoreForLevel(newLevel + 1)})',
        );
        _audioService.playSound('level_up');
        unawaited(_hapticService.levelUp());
        // 300ms tick slowdown so the level transition reads as an event
        // rather than a silent counter increment.
        _levelUpSlowdownUntil =
            DateTime.now().add(const Duration(milliseconds: 300));
        _analytics.trackLevelUp(newLevel);

        // Award coins for every level gained this tick.
        for (var lvl = previousLevel + 1; lvl <= newLevel; lvl++) {
          final levelForCoins = lvl;
          Future.microtask(() => _earnAndTrack(
            CoinEarningSource.levelUp,
            metadata: {'level': levelForCoins},
          ));
        }
      } else {
        _audioService.playSound('eat');
        // Standardize through the service so intensity stays consistent with
        // the power-up collect / bonus / special variants. The direct
        // HapticFeedback.lightImpact() call was an inconsistency with the
        // rest of the audio/haptic plumbing.
        unawaited(_hapticService.foodEaten());
      }

      // Regenerate only the eaten food slot. In single-food mode this just
      // replaces currentFood; in multi-food mode it preserves the other
      // visible foods so the board stays populated.
      if (willEatPrimaryFood) {
        currentFood = _generateNonOverlappingFood(
          previousState.boardWidth,
          previousState.boardHeight,
          ship,
          existing: extraFoods,
        );
      } else {
        extraFoods[eatenExtraIndex] = _generateNonOverlappingFood(
          previousState.boardWidth,
          previousState.boardHeight,
          ship,
          existing: [
            ?currentFood,
            ...extraFoods.where((f) => f != extraFoods[eatenExtraIndex]),
          ],
        );
      }
    }

    // Handle power-up collection
    // Performance: inline filter instead of removeExpiredPowerUps() which
    // creates a throwaway GameState copy with 20+ fields just to get a list
    var activePowerUps = previousState.activePowerUps
        .where((p) => !p.isExpired)
        .toList();

    // Power-up countdown haptic: fire once when each active power-up's
    // remaining time first dips below 3s, 2s, and 1s. Visual flash already
    // pulses in the last 3 seconds (game_hud.dart:758) — this adds a felt
    // cue so a player whose eyes are on the ship still gets the warning.
    for (final p in activePowerUps) {
      final remainingMs = p.remainingTime.inMilliseconds;
      if (remainingMs <= 0 || remainingMs > 3000) continue;
      // Bucket = ceil(remainingMs / 1000) → 3, 2, 1.
      final bucket = (remainingMs + 999) ~/ 1000;
      final lastBucket = _powerUpCountdownLastSecond[p.type];
      if (lastBucket == null || lastBucket > bucket) {
        _powerUpCountdownLastSecond[p.type] = bucket;
        unawaited(_hapticService.scoreMilestone());
      }
    }
    // Drop entries for power-ups that have expired since the last tick so a
    // fresh future collection of the same type re-arms the countdown.
    if (_powerUpCountdownLastSecond.isNotEmpty) {
      final activeTypes = activePowerUps.map((p) => p.type).toSet();
      _powerUpCountdownLastSecond
          .removeWhere((type, _) => !activeTypes.contains(type));
    }

    if (willCollectPowerUp) {
      debugPrint('🎁 Collecting power-up: ${currentPowerUp.type.name}');
      _hapticService.powerUpCollected();
      _powerUpsCollectedThisGame++;
      _analytics.trackPowerUpUsed(currentPowerUp.type.name);

      // Buffer battle pass XP for power-up collection (flushed at game end)
      _battlePassCubit.bufferXP(
        BattlePassXpSource.getXpForAction('power_up_collected'),
        source: 'power_up_collected',
      );

      // Track power-up type for statistics
      _currentGamePowerUpTypes[currentPowerUp.type.name] =
          (_currentGamePowerUpTypes[currentPowerUp.type.name] ?? 0) + 1;

      // Pre-credit the full duration to the power-up-time counter. At
      // game-end (_trackGameEndLocal) we subtract any leftover time on
      // power-ups that are still active. Net effect: every expired
      // power-up contributes its full duration; active-at-end power-ups
      // contribute the time actually spent under the effect. Previously
      // the counter was computed only from active-at-end power-ups,
      // erasing every expired one entirely.
      _currentGamePowerUpTime += currentPowerUp.type.duration.inSeconds;

      activePowerUps = [
        ...activePowerUps,
        ActivePowerUp(type: currentPowerUp.type),
      ];
      currentPowerUp = null;
      shouldClearPowerUp = true;
      _audioService.playSound('power_up');
    }

    // PerfectGame: snapshot the visited-cells set into state so the painter
    // can render the dim trail overlay. Out of mode, emit empty so the
    // painter early-outs (zero cost for 95% of play).
    final visitedSnapshot = previousState.gameMode.enforcesNoRevisit
        ? Set<Position>.of(_visitedCells)
        : const <Position>{};

    final newGameState = previousState.copyWith(
      ship: ship,
      food: currentFood,
      foods: extraFoods,
      powerUp: currentPowerUp,
      clearPowerUp: shouldClearPowerUp,
      score: newScore,
      level: newLevel,
      currentCombo: newCombo,
      maxCombo: newMaxCombo,
      comboMultiplier: newComboMultiplier,
      activePowerUps: activePowerUps,
      lastMoveTime: now, // Reuse timestamp from start of tick instead of calling DateTime.now() again
      visitedCells: visitedSnapshot,
    );

    final newCubitState = state.copyWith(
      gameState: newGameState,
      previousGameState: previousState,
      moveProgress: 0.0,
    );

    if (_updateCount <= 5) {
      debugPrint(
        '🎮 [GameCubit] _updateGame #$_updateCount emitting: ship moved to ${ship.head}',
      );
    }

    emit(newCubitState);

    // Note: No need to restart game loop on level-up anymore.
    // The new timer pattern (_scheduleNextGameTick) reads speed fresh each tick,
    // so speed changes from level-ups apply immediately without a pause.

    _recordFrame(
      ship,
      currentFood,
      currentPowerUp,
      newGameState,
      willEatFood,
      willCollectPowerUp,
    );
  }

  void _recordFrame(
    Ship ship,
    Food? food,
    PowerUp? powerUp,
    model.GameState gameState,
    bool ateFood,
    bool collectedPowerUp,
  ) {
    Map<String, dynamic>? event;
    if (ateFood) {
      event = {'type': 'food_consumed', 'foodType': food?.type.name};
    } else if (collectedPowerUp) {
      event = {'type': 'power_up_collected', 'powerUpType': powerUp?.type.name};
    }

    final shipPositions = <List<int>>[];
    for (final pos in ship.body) {
      shipPositions.add(<int>[pos.x, pos.y]);
    }

    _gameRecorder.recordFrame(
      shipPositions: shipPositions,
      foodPosition: food != null
          ? <int>[food.position.x, food.position.y]
          : null,
      powerUpPosition: powerUp != null
          ? <int>[powerUp.position.x, powerUp.position.y]
          : null,
      powerUpType: powerUp?.type.name,
      score: gameState.score,
      level: gameState.level,
      direction: ship.currentDirection.name,
      activePowerUps: gameState.activePowerUps.map((p) => p.type.name).toList(),
      gameEvent: event,
    );
  }

  /// Generate a Food whose position doesn't overlap the ship, any of the
  /// already-placed foods, or the active power-up. Used by MultiFood mode so
  /// the simultaneous foods don't stack onto the same cell or land on a
  /// power-up that the player would then "eat" instead of collect.
  Food _generateNonOverlappingFood(
    int boardWidth,
    int boardHeight,
    Ship ship, {
    Iterable<Food> existing = const [],
  }) {
    final taken = <Position>{
      ...existing.map((f) => f.position),
      ?state.gameState?.powerUp?.position,
    };
    // Bounded retry: at most 32 attempts. If everything collides (effectively
    // never on a normal-size board) fall back to the unguarded generator so
    // we never deadlock the game tick.
    for (var attempt = 0; attempt < 32; attempt++) {
      final candidate = Food.generateRandom(
        boardWidth,
        boardHeight,
        ship,
        isPremium: _isPro,
      );
      if (!taken.contains(candidate.position)) {
        return candidate;
      }
    }
    return Food.generateRandom(
      boardWidth,
      boardHeight,
      ship,
      isPremium: _isPro,
    );
  }

  void _trySpawnPowerUp() {
    if (state.status != GamePlayStatus.playing) return;
    if (state.gameState?.powerUp != null) return;

    final random = Random();
    final baseChance =
        state.gameState?.gameMode.powerUpSpawnChanceOverride ?? 0.5;
    // Pro perk: 30% more in-game power-up spawns. Capped at 0.95 so a mode
    // that already overrides to ~0.9 doesn't become a 100% guarantee.
    final spawnChance = _isPro
        ? min(0.95, baseChance * 1.3)
        : baseChance;
    if (random.nextDouble() < spawnChance) {
      final current = state.gameState!;
      // Avoid every visible food (primary + multi-food extras) so the new
      // power-up doesn't share a cell with an eatable target.
      final powerUp = PowerUp.generateRandom(
        current.boardWidth,
        current.boardHeight,
        current.ship,
        foodPosition: current.food?.position,
        foodPositions: current.foods.map((f) => f.position),
      );

      if (powerUp != null) {
        emit(
          state.copyWith(
            gameState: state.gameState?.copyWith(powerUp: powerUp),
          ),
        );
      }
    }
  }

  /// Survival-mode respawn: rebuild ship at spawn, regenerate food, keep
  /// the current score and level, and decrement livesRemaining by one.
  /// Plays a softer "crash" cue rather than the full game-over flow.
  void _respawnAfterCrash(model.GameState current) {
    _audioService.playSound('game_over');
    _enhancedAudioService.playSfx('game_over', volume: 0.6);
    HapticFeedback.heavyImpact();

    final newShip = Ship.initial();
    // PerfectGame respawns get a fresh visited-cell map; the rule applies
    // per-life rather than across the whole run.
    _visitedCells
      ..clear()
      ..addAll(newShip.body);
    final newFood = Food.generateRandom(
      current.boardWidth,
      current.boardHeight,
      newShip,
      isPremium: _isPro,
    );
    // Re-seed extras list if the active mode wants multiple simultaneous foods.
    final extras = <Food>[];
    if (current.gameMode.hasMultipleFood) {
      for (var i = 0; i < 2; i++) {
        extras.add(
          _generateNonOverlappingFood(
            current.boardWidth,
            current.boardHeight,
            newShip,
            existing: [newFood, ...extras],
          ),
        );
      }
    }

    emit(
      state.copyWith(
        gameState: current.copyWith(
          ship: newShip,
          food: newFood,
          foods: extras,
          activePowerUps: const [],
          clearPowerUp: true,
          // Survival respawn: preserve combo across lives instead of zeroing
          // it. Resetting punished the player twice — once with the lost life,
          // once by dropping their multiplier — which felt unfair.
          currentCombo: current.currentCombo,
          comboMultiplier: current.comboMultiplier,
          livesRemaining: current.livesRemaining - 1,
          status: model.GameStatus.playing,
          crashReason: null,
          crashPosition: null,
          collisionBodyPart: null,
          showCrashModal: false,
        ),
        previousGameState: current,
        moveProgress: 0.0,
      ),
    );
  }

  void _handleCrash(
    model.CrashReason reason,
    Position? crashPosition, {
    Position? collisionBodyPart,
    Ship? fatalShip,
  }) {
    debugPrint(
      '🎮 [GameCubit] _handleCrash called: reason=$reason, crashPosition=$crashPosition',
    );

    // Track what type of crash for achievements + per-game counts. In
    // Survival mode this method fires once per life lost; the int counters
    // accumulate while the booleans stay true after the first hit.
    if (reason == model.CrashReason.wallCollision) {
      _hitWallThisGame = true;
      _wallHitsThisGame++;
      _hapticService.wallHit();
    } else if (reason == model.CrashReason.selfCollision) {
      _hitSelfThisGame = true;
      _selfHitsThisGame++;
      _hapticService.selfCollision();
    }

    // Survival mode: consume a life and respawn instead of ending the game.
    final currentGameState = state.gameState;
    if (currentGameState != null &&
        currentGameState.gameMode.initialLives > 1 &&
        currentGameState.livesRemaining > 1) {
      _respawnAfterCrash(currentGameState);
      return;
    }

    // Crash render: we commit the FATAL ship ([fatalShip], head on the cell
    // it died on — into the wall / onto its body) as the crash-frame ship, and
    // pin previousGameState to the pre-move state (head on the last valid cell).
    // The board interpolates the head from previousGameState → gameState, so it
    // gets a clean one-cell delta to lunge across; the board plays that as a
    // short one-shot "lunge into the wall" on crash (see GameBoard's crash
    // lunge controller). Without committing the fatal ship the head would stay
    // a cell back from where it died.
    final preMoveState = currentGameState;

    // Cancel all timers
    _gameTimer?.cancel();
    _animationTimer?.cancel();
    _powerUpTimer?.cancel();
    _timeAttackTimer?.cancel();
    _timeAttackTimer = null;
    _timeAttackRemaining = null;

    // Play crash sound and haptic feedback immediately
    _audioService.playSound('game_over');
    _enhancedAudioService.playSfx('game_over', volume: 1.0);
    HapticFeedback.heavyImpact();

    // Offer a revive (rewarded ad or coins) before ending the game. Once per
    // run, single-life modes only, and whenever a revive path is *possible*:
    // ads are enabled (so a rewarded ad can be shown — even if it's still
    // loading), or the player can afford the coin cost. We intentionally gate
    // on "ads enabled" rather than "ad already loaded" so the popup still
    // appears while the ad finishes loading; the ReviveOverlay greys the
    // watch-ad button until it's ready (live re-check) and re-enables it the
    // moment it loads during the countdown — same UX as the greyed-out coin
    // button. revive() / declineRevive() resolve it. We DON'T schedule
    // game-over here — the overlay owns that timeout.
    if (_canOfferRevive()) {
      final hasAds = getIt.isRegistered<AdService>();
      final adsPossible = hasAds && getIt<AdService>().adsEnabled;
      // Kick a (re)load so the ad can become ready during the offer countdown
      // — the overlay re-checks readiness live and enables the button then.
      if (adsPossible) getIt<AdService>().preloadRewarded();
      final canAfford = _coinsCubit.state.balance.total >= reviveCoinCost;
      if (adsPossible || canAfford) {
        emit(
          state.copyWith(
            status: GamePlayStatus.crashed,
            gameState: state.gameState?.copyWith(
              ship: fatalShip,
              status: model.GameStatus.crashed,
              crashReason: reason,
              crashPosition: crashPosition,
              collisionBodyPart: collisionBodyPart,
              showCrashModal: false,
            ),
            previousGameState: preMoveState,
            offeringRevive: true,
          ),
        );
        return;
      }
    }

    // Get crash feedback duration from settings
    final crashFeedbackDuration = _settingsCubit.state.crashFeedbackDuration;
    final durationSeconds = crashFeedbackDuration.inSeconds;

    // Skip mode: go directly to game over with minimal feedback
    if (durationSeconds == GameConstants.crashFeedbackSkip) {
      final crashedGameState = state.gameState?.copyWith(
        ship: fatalShip,
        status: model.GameStatus.crashed,
        crashReason: reason,
        crashPosition: crashPosition,
        collisionBodyPart: collisionBodyPart,
        showCrashModal: false,
      );

      emit(
        state.copyWith(
          status: GamePlayStatus.crashed,
          gameState: crashedGameState,
          previousGameState: preMoveState,
        ),
      );

      // Immediately transition to game over after short delay
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (state.status == GamePlayStatus.crashed) {
          await _gameOver();
        }
      });
      return;
    }

    // First show crash feedback with reason and position details (visual only)
    final crashedGameState = state.gameState?.copyWith(
      ship: fatalShip,
      status: model.GameStatus.crashed,
      crashReason: reason,
      crashPosition: crashPosition,
      collisionBodyPart: collisionBodyPart,
      showCrashModal: false, // Start with visual feedback only
    );

    emit(
      state.copyWith(
        status: GamePlayStatus.crashed,
        gameState: crashedGameState,
        previousGameState: preMoveState,
      ),
    );

    // Show visual crash feedback for 2 seconds, then show modal
    Future.delayed(const Duration(seconds: 2), () {
      if (state.status == GamePlayStatus.crashed) {
        // Now show the crash feedback modal
        emit(
          state.copyWith(
            gameState: state.gameState?.copyWith(showCrashModal: true),
          ),
        );

        // Until Tap mode: don't auto-advance, wait for user to skip
        if (durationSeconds == GameConstants.crashFeedbackUntilTap) {
          // User must tap to continue - handled by skipCrashFeedback()
          return;
        }

        // Normal mode: use configured duration
        final modalDuration = Duration(seconds: durationSeconds.clamp(1, 10));
        Future.delayed(modalDuration, () async {
          if (state.status == GamePlayStatus.crashed) {
            await _gameOver();
          }
        });
      }
    });
  }

  /// Revive eligibility: once per run, and not in Time Attack (a fresh game
  /// loop there would hand back a full timer, which would be exploitable).
  bool _canOfferRevive() {
    if (_revivedThisGame) return false;
    final gs = state.gameState;
    if (gs == null) return false;
    if (gs.gameMode == GameMode.timeAttack) return false;
    return true;
  }

  /// Continue the current run after a crash — this is a true "revive", not a
  /// restart. The ship the player crashed with is KEPT as-is (same length,
  /// same score/level/combo/food/power-ups). The crash FRAME's ship is the
  /// fatal ship (head lunged into the wall / onto its body, possibly out of
  /// bounds) used only for the death animation — so we revive from the
  /// pre-crash ship we pinned into `previousGameState`, which is the last
  /// valid in-bounds ship.
  ///
  /// The only thing we change is the heading — it's still pointed at the wall
  /// / its own body that killed it, so without turning it the next tick would
  /// re-crash instantly. We pick a safe direction to continue in and grant a
  /// short invincibility grace period so the player can reorient.
  ///
  /// Driven by the ReviveOverlay after a rewarded ad or coin spend; the caller
  /// owns the ad/coin side, this just resumes play.
  void revive() {
    final current = state.gameState;
    if (current == null || _revivedThisGame) return;
    _revivedThisGame = true;

    // Restore the last valid (in-bounds) ship from the pinned pre-crash state,
    // not the fatal crash-frame ship; only steer it somewhere safe to continue.
    final preCrash = state.previousGameState ?? current;
    final ship = preCrash.ship.copy();
    final safeDir = _safeReviveDirection(ship, current);
    final revivedShip = safeDir != null
        ? Ship.fromPositions(ship.body, safeDir)
        : ship;

    // 3-second invincibility grace so the immediate surroundings (and the
    // wall/body it just hit) can't re-kill before the player reacts.
    final grace = ActivePowerUp(
      type: PowerUpType.invincibility,
      duration: const Duration(seconds: 3),
    );

    emit(
      state.copyWith(
        status: GamePlayStatus.playing,
        offeringRevive: false,
        gameState: current.copyWith(
          ship: revivedShip,
          activePowerUps: [...current.activePowerUps, grace],
          status: model.GameStatus.playing,
          crashReason: null,
          crashPosition: null,
          collisionBodyPart: null,
          showCrashModal: false,
        ),
        moveProgress: 0.0,
      ),
    );

    // A brief "ready" beat before the first tick, same as startGame.
    _levelUpSlowdownUntil =
        DateTime.now().add(const Duration(milliseconds: 600));
    _startGameLoop();
    _startSmoothAnimation();
    _startPowerUpTimer();
    HapticFeedback.mediumImpact();
  }

  /// Pick a direction to continue in after a revive that won't immediately
  /// re-crash: prefer a heading whose next cell is in-bounds and not part of
  /// the ship's body, and never a 180° reverse into the neck. Returns null
  /// if the ship is fully boxed in (the invincibility grace then covers it).
  Direction? _safeReviveDirection(Ship ship, model.GameState gs) {
    final head = ship.head;
    final body = ship.body.toSet();
    final reverse = ship.currentDirection.opposite;
    for (final dir in Direction.values) {
      if (dir == reverse) continue; // can't flip straight back into the body
      final next = head.move(dir);
      final inBounds = !gs.gameMode.hasWalls ||
          next.isWithinBounds(gs.boardWidth, gs.boardHeight);
      if (inBounds && !body.contains(next)) return dir;
    }
    return null;
  }

  /// Dismiss the revive offer and fall through to the normal game-over flow.
  Future<void> declineRevive() async {
    if (state.status != GamePlayStatus.crashed) return;
    emit(state.copyWith(offeringRevive: false));
    await _gameOver();
  }

  /// Time-Attack "+30s" eligibility: only in Time Attack, capped per run.
  bool _canOfferTimeBonus() {
    final gs = state.gameState;
    if (gs == null) return false;
    if (gs.gameMode != GameMode.timeAttack) return false;
    return _timeBonusesUsed < maxTimeBonusesPerRun;
  }

  /// The Time-Attack timer hit zero with an extension still available and an ad
  /// ready. Freeze the run (reusing the pause freeze so power-up timers don't
  /// bleed during the offer) and flag the offer; the TimeBonusOverlay drives
  /// [grantTimeBonus] / [declineTimeBonus].
  void _offerTimeBonus() {
    pauseGame(); // sets status=paused, cancels loops, stamps wall-clock anchors
    emit(state.copyWith(offeringTimeBonus: true));
  }

  /// Player watched a rewarded ad: add [timeBonusSeconds] to the Time-Attack
  /// clock and resume the frozen run. The caller owns the ad side; this just
  /// extends the timer and unfreezes (resumeGame reschedules the TA timer with
  /// the bumped remaining and shifts power-ups past the offer window).
  void grantTimeBonus() {
    if (!state.offeringTimeBonus) return;
    _timeBonusesUsed++;
    _timeAttackRemaining = (_timeAttackRemaining ?? Duration.zero) +
        const Duration(seconds: timeBonusSeconds);
    emit(state.copyWith(offeringTimeBonus: false));
    resumeGame();
  }

  /// Dismiss the Time-Attack offer and end the run.
  Future<void> declineTimeBonus() async {
    if (!state.offeringTimeBonus) return;
    emit(state.copyWith(offeringTimeBonus: false));
    await _gameOver();
  }

  /// Local-only game end processing: achievement checks + coin awards + recording.
  /// No API calls — all syncing is deferred to [_postGameSync].
  void _trackGameEndLocal() {
    // Calculate game duration
    final gameDurationSeconds = _gameStartTime != null
        ? DateTime.now().difference(_gameStartTime!).inSeconds
        : 0;

    // Track consecutive games without wall hits
    if (_hitWallThisGame) {
      _consecutiveGamesWithoutWallHits = 0;
    } else {
      _consecutiveGamesWithoutWallHits++;
    }

    final gameState = state.gameState;
    if (gameState == null) return;

    // Filter-aware local evaluation so offline play still reveals
    // achievements at game-end. Mirrors AchievementAutoEvaluator's
    // SQL guards exactly: per-game Score / Survival rows only fire when
    // gameModeFilter and difficultyFilter (if set) match the finished
    // game. GamesInMode / GamesInDifficulty rows stay server-only because
    // the client doesn't track per-mode game counts. Special achievements
    // (combo / ship length / no-wall etc.) are always client-only.
    //
    // The post-sync diff in _updateAchievementsFromBackend still catches
    // any server-only unlocks (cumulative tallies, GamesInMode totals)
    // so the reveal sequence stays complete online.
    final modeName = gameState.gameMode.name;
    const difficultyName = 'normal'; // mirrors the value sent in queueSync
    final projectedTotalGames =
        _statisticsService.statistics.totalGamesPlayed + 1;

    final scoreUnlocks = _achievementService.checkScoreAchievements(
      gameState.score,
      gameMode: modeName,
      difficulty: difficultyName,
    );
    final survivalUnlocks = _achievementService.checkSurvivalAchievements(
      gameDurationSeconds,
      gameMode: modeName,
      difficulty: difficultyName,
    );
    final gamesUnlocks =
        _achievementService.checkGamePlayedAchievements(projectedTotalGames);
    final specialUnlocks = _achievementService.checkSpecialAchievements(
      level: gameState.level,
      hitWall: _hitWallThisGame,
      hitSelf: _hitSelfThisGame,
      foodTypesEaten: _foodTypesEatenThisGame,
      noWallGames: _consecutiveGamesWithoutWallHits,
      maxCombo: gameState.maxCombo,
      shipLength: gameState.ship.body.length,
      gameEndTime: DateTime.now(),
    );

    // Buffer battle pass XP for client-evaluated unlocks now. Server-only
    // unlocks (filter-gated games counts, cumulative tallies) earn their
    // BP XP after the post-game sync completes — see the diff handler
    // below the fire-and-forget syncWithBackend call.
    final allLocalUnlocks = [
      ...scoreUnlocks,
      ...survivalUnlocks,
      ...gamesUnlocks,
      ...specialUnlocks,
    ];
    for (final achievement in allLocalUnlocks) {
      final xpKey = 'achievement_unlocked_${achievement.rarity.name}';
      final xp = BattlePassXpSource.getXpForAction(xpKey);
      if (xp > 0) {
        _battlePassCubit.bufferXP(xp, source: xpKey);
      }
    }

    // Calculate power-up time. `_currentGamePowerUpTime` was pre-credited
    // with each collected power-up's full duration at collection time.
    // Subtract any time that wasn't actually spent — the remaining time
    // on power-ups still active when the game ended.
    final unspentPowerUpSeconds = gameState.activePowerUps.fold<int>(
      0,
      (sum, p) => sum + p.remainingTime.inSeconds,
    );
    _currentGamePowerUpTime = (_currentGamePowerUpTime - unspentPowerUpSeconds)
        .clamp(0, 1 << 30);

    // Finish game recording (local only)
    final crashReasonStr = _hitWallThisGame
        ? 'wall'
        : _hitSelfThisGame
        ? 'self'
        : null;
    final replay = _gameRecorder.finishRecording(
      playerName: 'Player',
      finalScore: gameState.score,
      gameMode: gameState.gameMode.name,
      gameSettings: {
        'boardWidth': gameState.boardWidth,
        'boardHeight': gameState.boardHeight,
        'gameSpeed': gameState.gameSpeed,
      },
      crashReason: crashReasonStr,
      gameStats: {
        'level': gameState.level,
        'foodConsumed': _currentGameFoodTypes.values.fold(
          0,
          (sum, count) => sum + count,
        ),
        'powerUpsCollected': _powerUpsCollectedThisGame,
        'gameDurationSeconds': gameDurationSeconds,
      },
    );

    // Persist the replay locally. GameDao's saveReplay enforces the
    // retention policy (top 10 by score + 10 most recent), so the
    // table can never exceed 20 rows even after a long play session.
    // Fire-and-forget — a failed write must not block the game-over
    // UI; talker logs catch any errors.
    if (replay != null) {
      unawaited(_persistReplay(replay, gameState));
    }
  }

  Future<void> _persistReplay(
    GameReplay replay,
    model.GameState gameState,
  ) async {
    try {
      await _storageService.gameDao.saveReplay(
        ReplaysCompanion(
          id: Value(replay.id),
          name: Value(replay.playerName),
          score: Value(replay.finalScore),
          shipLength: Value(gameState.ship.length),
          gameDurationSeconds: Value(replay.gameTimeSeconds),
          gameMode: Value(replay.gameMode),
          boardSize: Value('${gameState.boardWidth}x${gameState.boardHeight}'),
          replayData: Value(jsonEncode(replay.toJson())),
          recordedAt: Value(replay.createdAt),
        ),
      );
    } catch (e) {
      AppLogger.error('Failed to persist replay', e);
    }
  }

  /// Get game recording data (simplified)
  Map<String, dynamic>? getRecordingData() {
    try {
      return {
        'score': state.gameState?.score ?? 0,
        'level': state.gameState?.level ?? 1,
        'maxCombo': state.gameState?.maxCombo ?? 0,
        'foodEaten': _currentGameFoodTypes.values.fold(0, (a, b) => a + b),
        'powerUpsCollected': _powerUpsCollectedThisGame,
      };
    } catch (e) {
      return null;
    }
  }

  /// Reset the game to initial state while preserving high score
  void resetGame() {
    _gameTimer?.cancel();
    _animationTimer?.cancel();
    _powerUpTimer?.cancel();
    _timeAttackTimer?.cancel();
    _timeAttackTimer = null;
    _timeAttackRemaining = null;
    _gameRecorder.stopRecording();

    final highScore =
        state.gameState?.highScore ?? _settingsCubit.state.highScore;
    final gameState = model.GameState.initial().copyWith(
      highScore: highScore,
      boardWidth: _settingsCubit.state.boardSize.width,
      boardHeight: _settingsCubit.state.boardSize.height,
      gameMode: _settingsCubit.state.gameMode,
      foods: const [],
    );

    emit(
      state.copyWith(
        status: GamePlayStatus.ready,
        gameState: gameState,
        clearPreviousGameState: true,
        moveProgress: 0.0,
      ),
    );
  }

  /// Return to menu state
  void backToMenu() {
    _gameTimer?.cancel();
    _animationTimer?.cancel();
    _powerUpTimer?.cancel();
    _timeAttackTimer?.cancel();
    _timeAttackTimer = null;
    _timeAttackRemaining = null;
    _gameRecorder.stopRecording();

    emit(
      state.copyWith(
        status: GamePlayStatus.ready,
        clearPreviousGameState: true,
        moveProgress: 0.0,
      ),
    );
  }

  /// Skip crash feedback and go directly to game over
  void skipCrashFeedback() {
    if (state.status == GamePlayStatus.crashed) {
      _finalizeGameOver();
    }
  }

  /// Finalize game over after crash feedback - transitions from crashed to gameOver
  Future<void> _gameOver() async {
    debugPrint('🎮 [GameCubit] _gameOver called');

    _hapticService.gameOver();

    final gameState = state.gameState;
    if (gameState == null) return;

    // Determine high score FIRST (sync operation)
    int highScore = gameState.highScore;
    bool isNewHighScore = gameState.score > highScore;
    if (isNewHighScore) {
      highScore = gameState.score;
    }

    // Local-only achievement checks (no API calls) so game over screen has data
    _trackGameEndLocal();

    // If this game unlocked anything rare or better, treat it as a positive
    // moment worth asking for an app-store review. The service runs all
    // eligibility gates (cap, install grace period, lifetime games) and
    // self-throttles, so it's safe to fire on every qualifying unlock.
    final unlockedSomethingMeaningful =
        _achievementService.lastGameUnlocks.any(
      (a) => a.rarity.index >= AchievementRarity.rare.index,
    );
    if (unlockedSomethingMeaningful) {
      unawaited(
        getIt<ReviewService>()
            .maybeRequestReview(ReviewTrigger.achievementUnlocked),
      );
    }

    // Track game over analytics
    final gameDuration = _gameStartTime != null
        ? DateTime.now().difference(_gameStartTime!).inSeconds
        : 0;
    final totalFoodEaten = _currentGameFoodTypes.values.fold(0, (a, b) => a + b);
    final cause = _hitWallThisGame
        ? 'wall'
        : _hitSelfThisGame
            ? 'self'
            : 'unknown';
    _analytics.trackGameOver(
      score: gameState.score,
      level: gameState.level,
      durationSeconds: gameDuration,
      cause: cause,
      foodEaten: totalFoodEaten,
      powerUpsCollected: _powerUpsCollectedThisGame,
      maxCombo: gameState.maxCombo,
      isNewHighScore: isNewHighScore,
    );

    // EMIT STATE immediately — UI transitions to game over screen INSTANTLY
    emit(
      state.copyWith(
        status: GamePlayStatus.gameOver,
        gameState: gameState.copyWith(
          status: model.GameStatus.gameOver,
          highScore: highScore,
        ),
      ),
    );

    // All remaining work is fire-and-forget — user already sees game over screen
    unawaited(_postGameSync(
      gameState: gameState,
      isNewHighScore: isNewHighScore,
      highScore: highScore,
    ));

    // Stop recording
    _gameRecorder.stopRecording();
  }

  /// Runs all post-game API syncs in the background (non-blocking).
  Future<void> _postGameSync({
    required model.GameState gameState,
    required bool isNewHighScore,
    required int highScore,
  }) async {
    try {
      if (isNewHighScore) {
        await _storageService.saveHighScore(highScore);
        _settingsCubit.updateHighScore(highScore);
        _audioService.playSound('high_score');
        _enhancedAudioService.playSfx('high_score', volume: 1.0);

        // Strongest positive signal we have — ask the platform to consider
        // a review prompt. Service self-throttles to once per 60 days and
        // gates on lifetime games + install age.
        unawaited(
          getIt<ReviewService>()
              .maybeRequestReview(ReviewTrigger.newHighScore),
        );
      }

      final gameDurationSeconds = _gameStartTime != null
          ? DateTime.now().difference(_gameStartTime!).inSeconds
          : 0;
      final foodEaten = _currentGameFoodTypes.values.fold(
        0,
        (sum, count) => sum + count,
      );

      // Offline-first build: score submission to the backend was
      // removed along with the global leaderboard and tournament
      // endpoints. The score is still persisted locally below via
      // StatisticsService / GameDao (the `STEP A — Local stats update`
      // block), and the high score lives in GameSettingsCubit's
      // Drift-backed state. Nothing to queue here.

      // Award coins for game completion (local)
      await _awardGameCompletionCoins(
        score: gameState.score,
        level: gameState.level,
        foodEaten: foodEaten,
        gameDurationSeconds: gameDurationSeconds,
      );

      // Buffer remaining battle pass XP and flush once
      _bufferBattlePassXP(
        score: gameState.score,
        foodEaten: foodEaten,
        survivalSeconds: gameDurationSeconds,
      );

      // STEP A — Local stats update + cache refresh first. These are all
      // fast local writes (Drift + in-memory snapshot copy). Doing this
      // before the network-bearing Future.wait below guarantees that when
      // the user navigates to the Profile or Statistics screen right after
      // game-over, the AppDataCache snapshot already reflects the new high
      // score. Previously the refresh fired after the Future.wait, which
      // could take 200ms–1.5s online (and used to take ~15s offline before
      // the BattlePass connectivity gate landed), producing a visible
      // stale-then-fresh flash on those screens.
      await _statisticsService.recordGameResult(
        score: gameState.score,
        gameTime: gameDurationSeconds,
        level: gameState.level,
        foodConsumed: foodEaten,
        foodTypes: _currentGameFoodTypes,
        foodPoints: _currentGameFoodPoints,
        powerUpsCollected: _powerUpsCollectedThisGame,
        powerUpTypes: _currentGamePowerUpTypes,
        powerUpTime: _currentGamePowerUpTime,
        wallHits: _wallHitsThisGame,
        selfHits: _selfHitsThisGame,
        // Perfect game = no wall/self hits + lasted >= 30 seconds. The
        // original spec; TimeAttack timeouts naturally satisfy this since
        // surviving the full 3 minutes without crashing IS impressive.
        isPerfectGame:
            !_hitWallThisGame && !_hitSelfThisGame && gameDurationSeconds >= 30,
        unlockedAchievements: [],
      );

      // Now that lifetime stats include this game, check the catalog's
      // lifetime-driven achievements (power-ups, food variety, perfect
      // games, streaks, weekend days).
      final stats = _statisticsService.statistics;
      _achievementService.checkLifetimeAchievements(
        totalPowerUps: stats.totalPowerUpsCollected,
        powerUpTypeCount: stats.powerUpTypeCount,
        foodTypeCount: stats.foodTypeCount,
        perfectGames: stats.perfectGames,
        currentWinStreak: stats.currentWinStreak,
        dailyPlayTime: stats.dailyPlayTime,
      );

      // Daily reminder scheduling moved server-side — the Hangfire job
      // `send-daily-reminder` (backend) reads streak / challenge / high-
      // score state from the DB at each 30-min tick and pushes via FCM.
      // No per-game refresh needed here.

      await getIt<AppDataCache>().refreshStatistics();

      // STEP B — Network-bearing syncs. _postGameSync is already wrapped in
      // unawaited(...) by the caller, so even if these block on slow API
      // calls the user-visible game-over flow doesn't wait on them.
      await Future.wait([
        _achievementService.syncUnlockedAchievements(),
        _dailyChallengeService.updateProgressBatch([
          if (gameState.score > 0)
            (type: ChallengeType.score, value: gameState.score, gameMode: null),
          if (foodEaten > 0)
            (type: ChallengeType.foodEaten, value: foodEaten, gameMode: null),
          if (gameDurationSeconds > 0)
            (type: ChallengeType.survival, value: gameDurationSeconds, gameMode: null),
          (type: ChallengeType.gamesPlayed, value: 1, gameMode: null),
          (
            type: ChallengeType.gameMode,
            value: 1,
            gameMode: gameState.gameMode.name,
          ),
        ]),
        // Mirror the daily-challenge progress events to the weekly-quest
        // tracker — the backend filters by Type so events without a matching
        // active quest are no-ops.
        WeeklyQuestService().reportProgressBatch([
          if (gameState.score > 0)
            (
              type: WeeklyQuestType.score,
              incrementBy: gameState.score,
              gameMode: null,
            ),
          if (foodEaten > 0)
            (
              type: WeeklyQuestType.foodEaten,
              incrementBy: foodEaten,
              gameMode: null,
            ),
          if (gameDurationSeconds > 0)
            (
              type: WeeklyQuestType.survival,
              incrementBy: gameDurationSeconds,
              gameMode: null,
            ),
          (
            type: WeeklyQuestType.gamesPlayed,
            incrementBy: 1,
            gameMode: null,
          ),
          if (state.isTournamentMode)
            (
              type: WeeklyQuestType.tournamentParticipation,
              incrementBy: 1,
              gameMode: null,
            ),
        ]),
        _battlePassCubit.flushXP(),
      ]);

      // Refetch achievements so any server-derived unlocks (score / games /
      // survival auto-evaluated during the queued score submit) replace the
      // local-only state. The sync also auto-claims pending rewards, which
      // increments User.Coins / User.Experience server-side — so chase it
      // with a coin balance refresh to pull the new total client-side.
      // Fire-and-forget — next refresh cycle catches anything missed if
      // the score POST is still queued. After the achievement sync lands,
      // buffer BP XP for any newly server-confirmed unlocks (score / games
      // / survival). The achievement service notifies listeners, so the
      // game-over screen's ListenableBuilder picks up the new entries on
      // top of the specialUnlocks it already revealed.
      final preSyncIds =
          _achievementService.lastGameUnlocks.map((a) => a.id).toSet();
      unawaited(() async {
        await _achievementService.syncWithBackend();
        await _coinsCubit.syncWithBackend();
        for (final achievement in _achievementService.lastGameUnlocks) {
          if (preSyncIds.contains(achievement.id)) continue;
          final xpKey =
              'achievement_unlocked_${achievement.rarity.name}';
          final xp = BattlePassXpSource.getXpForAction(xpKey);
          if (xp > 0) {
            _battlePassCubit.bufferXP(xp, source: xpKey);
          }
        }
      }());
    } catch (e) {
      debugPrint('🎮 [GameCubit] Post-game sync error: $e');
    }
  }

  /// Award coins for completing a game based on performance
  Future<void> _awardGameCompletionCoins({
    required int score,
    required int level,
    required int foodEaten,
    required int gameDurationSeconds,
  }) async {
    try {
      // Base coins + bonus based on score (1 base + 1 per 200 points, max 10)
      final coinsEarned = (1 + (score ~/ 200)).clamp(1, 10);

      await _earnAndTrack(
        CoinEarningSource.gameCompleted,
        customAmount: coinsEarned,
        metadata: {'score': score, 'level': level, 'foodEaten': foodEaten},
      );

      // Bonus for perfect game (no wall/self hits, played >= 30 seconds).
      // Threshold matches GameStatistics.updateWithGameResult so the
      // perfect-game counter and the coin-bonus award are consistent.
      final isPerfectGame = !_hitWallThisGame &&
          !_hitSelfThisGame &&
          gameDurationSeconds >= 30;

      if (isPerfectGame) {
        await _earnAndTrack(
          CoinEarningSource.perfectGame,
          metadata: {
            'duration': gameDurationSeconds,
            'score': score,
          },
        );
      }

      // Bonus for long survival (> 5 minutes = 300 seconds)
      if (gameDurationSeconds > 300) {
        await _earnAndTrack(
          CoinEarningSource.longSurvival,
          metadata: {
            'duration': gameDurationSeconds,
            'score': score,
          },
        );
      }

      // Surface the running per-game total to the cubit state so the
      // game-over screen can render it. We emit even when 0 (e.g., daily
      // cap maxed out) so the screen always reads a fresh value.
      emit(state.copyWith(coinsEarnedThisGame: _currentGameCoinsEarned));

      AppLogger.info(
        'Awarded game completion coins: $coinsEarned (score: $score, perfect: $isPerfectGame, long: ${gameDurationSeconds > 300}); total this game: $_currentGameCoinsEarned',
      );
    } catch (e) {
      AppLogger.error('Error awarding game completion coins', e);
    }
  }

  /// Wraps [CoinsCubit.earnCoins] so the actual granted amount (post-Pro
  /// multiplier, post-daily-cap) is accumulated into [_currentGameCoinsEarned].
  /// `balance.earned` is a monotonic lifetime counter; the diff before and
  /// after the call is exactly what the cubit credited this time.
  Future<void> _earnAndTrack(
    CoinEarningSource source, {
    int? customAmount,
    Map<String, dynamic>? metadata,
  }) async {
    final before = _coinsCubit.state.balance.earned;
    await _coinsCubit.earnCoins(
      source,
      customAmount: customAmount,
      metadata: metadata,
    );
    final after = _coinsCubit.state.balance.earned;
    final delta = after - before;
    if (delta > 0) _currentGameCoinsEarned += delta;
  }

  /// Buffer battle pass XP locally based on game performance.
  /// Called before [flushXP] sends everything in one API call.
  void _bufferBattlePassXP({
    required int score,
    required int foodEaten,
    required int survivalSeconds,
  }) {
    // Game completed XP
    final gameCompletedXp = BattlePassXpSource.getXpForAction('game_completed');
    if (gameCompletedXp > 0) {
      _battlePassCubit.bufferXP(gameCompletedXp, source: 'game_completed');
    }

    // Survival milestone XP (only if not already awarded this game)
    if (survivalSeconds >= 300 && !_bpMilestonesThisGame.contains('survival_300s')) {
      _bpMilestonesThisGame.add('survival_300s');
      final xp = BattlePassXpSource.getXpForAction('survival_300s');
      if (xp > 0) {
        _battlePassCubit.bufferXP(xp, source: 'survival_300s');
      }
    }
    if (survivalSeconds >= 60 && !_bpMilestonesThisGame.contains('survival_60s')) {
      _bpMilestonesThisGame.add('survival_60s');
      final xp = BattlePassXpSource.getXpForAction('survival_60s');
      if (xp > 0) {
        _battlePassCubit.bufferXP(xp, source: 'survival_60s');
      }
    }

    // Tournament participation XP — once per tournament game. The flush at
    // game end combines this with the per-game sources above into a single
    // backend POST that the AddBattlePassXp validator accepts via its
    // comma-separated source allowlist.
    if (state.isTournamentMode &&
        !_bpMilestonesThisGame.contains('tournament_participation')) {
      _bpMilestonesThisGame.add('tournament_participation');
      final xp = BattlePassXpSource.getXpForAction('tournament_participation');
      if (xp > 0) {
        _battlePassCubit.bufferXP(xp, source: 'tournament_participation');
      }
    }
  }

  /// Check and award battle pass XP for score milestones
  void _checkScoreMilestones(int score) {
    if (score >= 1000 && !_bpMilestonesThisGame.contains('score_1000')) {
      _bpMilestonesThisGame.add('score_1000');
      final xp = BattlePassXpSource.getXpForAction('score_milestone_1000');
      if (xp > 0) _battlePassCubit.bufferXP(xp, source: 'score_milestone_1000');
    }
    if (score >= 500 && !_bpMilestonesThisGame.contains('score_500')) {
      _bpMilestonesThisGame.add('score_500');
      final xp = BattlePassXpSource.getXpForAction('score_milestone_500');
      if (xp > 0) _battlePassCubit.bufferXP(xp, source: 'score_milestone_500');
    }
    if (score >= 100 && !_bpMilestonesThisGame.contains('score_100')) {
      _bpMilestonesThisGame.add('score_100');
      final xp = BattlePassXpSource.getXpForAction('score_milestone_100');
      if (xp > 0) _battlePassCubit.bufferXP(xp, source: 'score_milestone_100');
    }
  }

  /// Award daily first game XP if this is the first game today
  Future<void> _awardDailyFirstGameXP() async {
    try {
      final lastPlayDate = await _storageService.getLastPlayDate();
      final today = DateTime.now();
      final isFirstGameToday = lastPlayDate == null ||
          lastPlayDate.year != today.year ||
          lastPlayDate.month != today.month ||
          lastPlayDate.day != today.day;

      if (isFirstGameToday) {
        final xp = BattlePassXpSource.getXpForAction('daily_game');
        if (xp > 0) {
          _battlePassCubit.bufferXP(xp, source: 'daily_game');
        }
        await _storageService.saveLastPlayDate(today);
      }
    } catch (e) {
      AppLogger.error('Error checking daily first game', e);
    }
  }

  /// Alias for _gameOver - kept for compatibility with skipCrashFeedback
  void _finalizeGameOver() {
    _gameOver();
  }

  @override
  Future<void> close() {
    _gameTimer?.cancel();
    _animationTimer?.cancel();
    _powerUpTimer?.cancel();
    _timeAttackTimer?.cancel();
    _rejectedInputClearTimer?.cancel();
    _acceptedInputClearTimer?.cancel();
    return super.close();
  }
}
