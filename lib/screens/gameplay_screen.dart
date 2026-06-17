import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../game/cosmo_palette.dart';
import '../game/cosmo_strike_game.dart';
import '../game/tutorial_director.dart';
import '../models/daily_challenge.dart';
import '../models/level_run_result.dart';
import '../models/ship_coins.dart';
import '../presentation/bloc/coins/coins_cubit.dart';
import '../presentation/bloc/game/game_cubit.dart';
import '../presentation/bloc/power_up/power_up_cubit.dart';
import '../presentation/bloc/premium/battle_pass_cubit.dart';
import '../presentation/bloc/premium/premium_cubit.dart';
import '../presentation/bloc/theme/theme_cubit.dart';
import '../router/routes.dart';
import '../services/achievement_service.dart';
import '../services/ads/ad_service.dart';
import '../services/analytics/analytics_facade.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/daily_challenge_service.dart';
import '../services/tournament_service.dart';
import '../services/haptic_service.dart';
import '../services/walkthrough_service.dart';
import '../ui/design.dart';
import '../utils/campaign_catalog.dart';
import '../utils/constants.dart';
import '../widgets/game_dpad.dart';
import '../widgets/gameplay/game_over_overlay.dart';
import '../widgets/gameplay/pause_overlay.dart';
import '../widgets/reward_toast.dart';

/// Hosts the Flame shoot-'em-up. Flame is scoped to this screen only; the
/// HUD, pause / level-clear / revive / game-over overlays, d-pad, missile
/// button, and drag input live in Flutter on top of the [GameWidget].
///
/// Campaign wiring: each level clear persists incrementally through
/// StageProgressDao (crash-safe); the final result also submits to the
/// backend score endpoint and feeds coins / battle-pass XP.
class GameplayScreen extends StatefulWidget {
  const GameplayScreen({super.key, this.startLevel = 1, this.onRunComplete});

  /// 1-based campaign level the run starts at (from level select).
  final int startLevel;

  /// Invoked once per run with the final result (score submission hook).
  final void Function(GameResult result)? onRunComplete;

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen>
    with WidgetsBindingObserver {
  late final CosmoStrikeGame _game;
  GameResult? _lastResult;

  // Snapshotted control settings (mid-run changes don't retro-apply).
  late final bool _dPadEnabled;
  late final DPadPosition _dPadPosition;

  /// Outcomes of the incremental per-level-clear persists, keyed by
  /// stage id — drives the "LEVEL N+1 UNLOCKED" flourish + end rewards.
  final Map<int, StageClearOutcome> _outcomes = {};

  /// Stage ids already persisted incrementally (skip at game over).
  final Set<int> _persistedClears = {};

  bool _quitPersisted = false;

  /// The tree-provided GameCubit (tournament context lives here). Captured in
  /// initState so we read THIS run's tournament id and can clear it on dispose
  /// — tournament mode is otherwise never reset and would leak into the next
  /// run, mis-attributing a normal game's score to the tournament.
  GameCubit? _gameCubit;

  /// Tournament this run counts toward (null for a normal game). Captured at
  /// run start; the final score is submitted to it in [_submitRun].
  String? _tournamentId;

  /// First-run tutorial: true when this run opened with the guided beats.
  bool _tutorialRun = false;

  /// Drives the PILOT CERTIFIED celebration overlay after the tutorial's
  /// final beat (auto-dismisses).
  bool _showCertified = false;

  /// Drives the gold REVIVED flourish after a paid continue (auto-dismisses).
  bool _showRevived = false;

  /// Coins granted for finishing the tutorial — the celebration overlay
  /// shows the same number it actually pays out.
  static const int _tutorialRewardCoins = 150;

  /// Coins this run actually earned (set by _submitRun) — the game-over
  /// "watch ad → 2× coins" offer pays out exactly this amount again.
  int _runCoinsEarned = 0;

  /// Whether the double-coins reward was already claimed this run.
  bool _coinsDoubled = false;

  /// High score BEFORE this run submitted — _submitRun overwrites the
  /// stored best, so the NEW RECORD badge compares against this.
  int _prevBestScore = 0;

  /// Battle-pass XP this run buffered (set by _submitRun, shown on the
  /// debrief).
  int _runXpEarned = 0;

  /// Per-challenge progress at run start (id → progress) so the debrief
  /// can tag exactly what THIS run advanced.
  late final Map<String, int> _challengeRunStart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Full-screen play: hide the status / notification bar.
    Immersive.enterGame();

    final settings = context.read<GameSettingsCubit>().state;
    _dPadEnabled = settings.dPadEnabled;
    _dPadPosition = settings.dPadPosition;

    // Capture the tournament context for this run (set by the tournament
    // detail screen before launching). Held for the screen's lifetime so the
    // game-over submit attributes the score to the right tournament.
    try {
      _gameCubit = context.read<GameCubit>();
      _tournamentId = _gameCubit?.state.tournamentId;
    } catch (_) {
      _gameCubit = null;
      _tournamentId = null;
    }

    // The debrief shows only THIS run's achievement unlocks and challenge
    // deltas — reset/snapshot both at run start.
    AchievementService().resetLastGameUnlocks();
    _challengeRunStart = {
      for (final c in DailyChallengeService().challenges)
        c.id: c.currentProgress,
    };

    // Armed store loadout: consume the inventory item exactly once and
    // hand the key to the game (applied when the level goes live).
    final powerUps = context.read<PowerUpCubit>();
    final armedKey = powerUps.state.armed;
    String? loadoutKey;
    if (armedKey != null && powerUps.state.countFor(armedKey) > 0) {
      loadoutKey = armedKey;
      unawaited(powerUps.consume(armedKey));
    }

    // Pre-load a rewarded ad so the revive / double-coins offers are
    // ready when needed, and an interstitial for the game-over exit
    // (frequency-capped inside AdService — every 3rd game, 3-min gap,
    // never in the first session, never for Pro).
    AdService().preloadRewarded();
    AdService().preloadInterstitial();

    // First-run tutorial: only on a Level-1 start, only until completed
    // or skipped once (the flag is prefs-backed and resettable from
    // Settings). The service is hydrated in main() so this sync read is
    // always safe.
    final walkthroughs = WalkthroughService();
    _tutorialRun = widget.startLevel == 1 &&
        walkthroughs.isInitialized &&
        !walkthroughs.isComplete(WalkthroughService.gameTutorialId);
    if (_tutorialRun) {
      unawaited(GetIt.I<AnalyticsFacade>().trackGameTutorialStarted());
    }

    // Equipped cosmetics (skin tint + trail stream) — snapshot at run
    // start, same as the control settings.
    final premium = context.read<PremiumCubit>().state;
    final themeState = context.read<ThemeCubit>().state;

    // The selected game mode is a MODIFIER on top of the campaign level
    // (lives, pacing, enemy fire, drops, one-hit, Time Attack clock).
    // Snapshot at run start.
    _game = CosmoStrikeGame(
      onGameOver: _handleGameOver,
      onLevelCleared: _handleLevelCleared,
      mode: settings.gameMode,
      startLevel: widget.startLevel,
      armedLoadoutKey: loadoutKey,
      screenShake: settings.screenShakeEnabled,
      tutorial: _tutorialRun,
      dPadControls: _dPadEnabled,
      onTutorialOutcome: _handleTutorialOutcome,
      selectedSkinId: premium.selectedSkinId,
      selectedTrailId: premium.selectedTrailId,
      trailEffectsEnabled: themeState.trailSystemEnabled,
    );
  }

  /// Tutorial resolved: certified (completed) or skipped. Either way the
  /// flag flips so the beats never replay uninvited; only certification
  /// pays the reward + celebration.
  void _handleTutorialOutcome(bool completed) {
    unawaited(WalkthroughService().markComplete(
      WalkthroughService.gameTutorialId,
    ));
    final analytics = GetIt.I<AnalyticsFacade>();
    if (!completed) {
      unawaited(analytics.trackGameTutorialSkipped());
      return;
    }
    unawaited(analytics.trackGameTutorialCompleted());
    if (!mounted) return;
    unawaited(context.read<CoinsCubit>().earnCoins(
          CoinEarningSource.achievementUnlocked,
          customAmount: _tutorialRewardCoins,
        ));
    setState(() => _showCertified = true);
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _showCertified = false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Android drops immersiveSticky on resume — re-assert it.
      Immersive.enterGame();
    } else {
      _game.pauseGame();
    }
  }

  @override
  void dispose() {
    // Restore the menu chrome (status/nav bars) when leaving the game.
    Immersive.enterMenu();
    // Clear tournament mode so it can't leak into the next (possibly normal)
    // run — nothing else resets it. The next tournament run re-sets it from
    // the detail screen.
    _gameCubit?.exitTournamentMode();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Crash-safe incremental persistence: each level clear merges into
  /// Drift (and enqueues sync) the moment the boss falls.
  void _handleLevelCleared(LevelRunResult result) {
    _persistedClears.add(result.stageId);
    unawaited(() async {
      try {
        final outcomes = await GetIt.I<AppDatabase>()
            .stageProgressDao
            .applyRunResults([result]);
        if (!mounted) return;
        setState(() {
          for (final o in outcomes) {
            _outcomes[o.stageId] = o;
          }
        });
      } catch (_) {
        // Monotonic merge self-heals on the game-over apply / next run.
      }
    }());
  }

  void _handleGameOver(GameResult result) {
    _lastResult = result;
    widget.onRunComplete?.call(result);
    if (!mounted) return;
    // The submit below overwrites the stored high score — capture the
    // previous best first for the NEW RECORD comparison.
    _prevBestScore = context.read<GameSettingsCubit>().state.highScore;
    // Capture cubit references synchronously (no BuildContext across awaits).
    _submitRun(
      result,
      context.read<GameSettingsCubit>(),
      context.read<CoinsCubit>(),
      context.read<BattlePassCubit>(),
    );
  }

  /// Persist campaign progress, submit the run to the backend
  /// (leaderboards + server-side high score / achievements) and feed
  /// local progression (high score, coins, battle-pass XP).
  /// Fire-and-forget; failures are swallowed so the game-over overlay
  /// is never blocked.
  Future<void> _submitRun(
    GameResult r,
    GameSettingsCubit settings,
    CoinsCubit coins,
    BattlePassCubit battlePass,
  ) async {
    // One idempotency key for this run, reused across retries of any submit
    // so a timed-out request that actually landed isn't double-counted.
    final runIdempotencyKey = const Uuid().v4();

    try {
      await settings.updateHighScore(r.score);
    } catch (_) {}

    // Persist the results that didn't already land incrementally (the
    // in-progress level's bestWaveReached; cleared levels were saved on
    // the spot — re-applying them would double-count clearCount).
    var firstClears = 0;
    try {
      final pending = r.levelResults
          .where((lr) => !lr.cleared || !_persistedClears.contains(lr.stageId))
          .toList();
      if (pending.isNotEmpty) {
        final outcomes = await GetIt.I<AppDatabase>()
            .stageProgressDao
            .applyRunResults(pending);
        for (final o in outcomes) {
          _outcomes[o.stageId] = o;
        }
      }
      firstClears = _outcomes.values.where((o) => o.firstClear).length;
    } catch (_) {}

    unawaited(ApiService().submitGameRun(
      score: r.score,
      gameDurationSeconds: r.durationSeconds,
      enemiesKilled: r.enemiesKilled,
      stageReached: r.stageReached,
      waveReached: r.waveReached,
      bossesKilled: r.bossesKilled,
      idempotencyKey: runIdempotencyKey,
      gameData: {
        'campaign': {
          'start_level': r.startLevel,
          'furthest_level': r.stageReached,
          'levels_cleared': [
            for (final lr in r.levelResults.where((lr) => lr.cleared))
              {
                'stage_id': lr.stageId,
                'score': lr.score,
                'time_seconds': lr.timeSeconds,
                'no_hit': lr.noHit,
              },
          ],
          'missiles_fired': r.missilesFired,
          'revives_used': r.revivesUsed,
          if (r.cleared) 'victory': true,
        },
      },
    ));

    // Tournament run: submit the score to the live leaderboard. Reuses the
    // run's idempotency key so a retry de-dupes server-side (BestScore is
    // max-merged, GamesPlayed is guarded by the key).
    final tournamentId = _tournamentId;
    if (tournamentId != null) {
      unawaited(TournamentService().submitScore(
        tournamentId,
        r.score,
        {
          'gameDurationSeconds': r.durationSeconds,
          'foodsEaten': r.enemiesKilled,
        },
        idempotencyKey: runIdempotencyKey,
      ));
    }

    try {
      final coinsEarned = 10 +
          r.enemiesKilled +
          r.bossesKilled * 50 +
          r.levelsCleared * 25 +
          firstClears * 75;
      if (mounted) setState(() => _runCoinsEarned = coinsEarned);
      await coins.earnCoins(
        CoinEarningSource.gameCompleted,
        customAmount: coinsEarned,
      );
      final xp = 20 + r.score ~/ 100 + r.levelsCleared * 15 + firstClears * 40;
      if (mounted) setState(() => _runXpEarned = xp);
      battlePass.bufferXP(xp, source: 'game_completed');
      await battlePass.flushXP();
    } catch (_) {}

    // Feed the run into daily challenges + achievements — the debrief
    // panels watch both and update live as these land. Kills ride the
    // legacy FoodEaten wire type (snake-era challenge vocabulary).
    final modeName = settings.state.gameMode.name;
    unawaited(DailyChallengeService().updateProgressBatch([
      (type: ChallengeType.score, value: r.score, gameMode: null),
      (type: ChallengeType.foodEaten, value: r.enemiesKilled, gameMode: null),
      (type: ChallengeType.survival, value: r.durationSeconds, gameMode: null),
      (type: ChallengeType.gamesPlayed, value: 1, gameMode: null),
      (type: ChallengeType.gameMode, value: 1, gameMode: modeName),
    ]));
    try {
      AchievementService()
        ..checkScoreAchievements(r.score,
            gameMode: modeName, difficulty: 'normal')
        ..checkSurvivalAchievements(r.durationSeconds,
            gameMode: modeName, difficulty: 'normal');
    } catch (_) {}
  }

  /// Abandon the run mid-game (quit or restart from pause): persist the
  /// partial run so campaign progress (bestWaveReached, cleared levels)
  /// survives, submit the aborted score for forensics. No coin/XP rewards.
  void _persistAbandonedRun() {
    if (!_quitPersisted && _game.phase != GamePhase.gameOver) {
      _quitPersisted = true;
      final partial = _game.buildPartialResult();
      final pending = partial.levelResults
          .where((lr) => !lr.cleared || !_persistedClears.contains(lr.stageId))
          .toList();
      if (pending.isNotEmpty) {
        unawaited(GetIt.I<AppDatabase>()
            .stageProgressDao
            .applyRunResults(pending)
            .catchError((_) => const <StageClearOutcome>[]));
      }
      unawaited(ApiService().submitGameRun(
        score: partial.score,
        gameDurationSeconds: partial.durationSeconds,
        enemiesKilled: partial.enemiesKilled,
        stageReached: partial.stageReached,
        waveReached: partial.waveReached,
        bossesKilled: partial.bossesKilled,
        idempotencyKey: const Uuid().v4(),
        gameData: const {'aborted': true},
      ));
    }
  }

  void _quitToHome() {
    _persistAbandonedRun();
    context.go(AppRoutes.home);
  }

  /// Restart the run at the same start level (from pause). No interstitial
  /// — the ad cap logic is for game-over exits only.
  void _restartFromPause() {
    _persistAbandonedRun();
    context.pushReplacement(AppRoutes.game, extra: widget.startLevel);
  }

  /// Relative-drag steering: the ship mirrors the finger's MOVEMENT, not
  /// its position, so the thumb can rest anywhere on screen and never
  /// covers the ship. Sensitivity tuned so a comfortable thumb arc spans
  /// the engagement zone.
  static const double _dragSensitivity = 1.3;

  void _steerBy(Offset delta) {
    _game.steerBy(Vector2(
      delta.dx * _dragSensitivity,
      delta.dy * _dragSensitivity,
    ));
  }

  // ---- Revive ----

  /// The continue was paid (ad or coins) and the run is back: a short gold
  /// flourish + sound + haptic so the reward never lands silently.
  void _celebrateRevive() {
    AudioService().playSound('revive');
    unawaited(HapticService().customHaptic(HapticIntensity.success));
    if (!mounted) return;
    setState(() => _showRevived = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showRevived = false);
    });
  }

  void _reviveWithAd() {
    AdService().showRewarded(onReward: () {
      _game.revive();
      _celebrateRevive();
    }).then((shown) {
      // Ad failed to show (expired between readiness check and tap):
      // keep the offer up; the countdown continues.
      if (!shown && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ad not ready — try coins instead')),
        );
      }
    });
  }

  /// Game-over "watch ad → 2× coins": pays the run's coin earnings out a
  /// second time. Daily-capped in AdService; reward applies on ad dismiss.
  Future<void> _doubleRunCoins() async {
    final coins = context.read<CoinsCubit>();
    final earned = _runCoinsEarned;
    final shown = await AdService().showRewardedCapped(
      capKey: AdService.capDoubleCoins,
      onReward: () {
        unawaited(coins.earnCoins(
          CoinEarningSource.watchedAd,
          customAmount: earned,
          itemName: 'Game over 2× coins',
          metadata: const {'placement': 'game_over_double'},
        ));
        RewardToast.show(title: 'COINS DOUBLED', amount: '+$earned COINS');
        if (mounted) setState(() => _coinsDoubled = true);
      },
    );
    if (!shown && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not ready — try again in a moment')),
      );
    }
  }

  /// Leave the game-over screen through the (frequency-capped)
  /// interstitial: every 3rd game with a 3-minute minimum gap, never in
  /// the first session, never for Pro — all enforced inside AdService.
  /// The navigation always runs, ad or no ad.
  void _exitWithInterstitial(VoidCallback navigate) {
    AdService().maybeShowInterstitialOnGameOver().whenComplete(() {
      if (mounted) navigate();
    });
  }

  Future<void> _reviveWithCoins() async {
    final coins = context.read<CoinsCubit>();
    final ok = await coins.spendCoins(
      200,
      CoinSpendingCategory.extraLives,
      itemName: 'revive',
    );
    if (ok) {
      _game.revive();
      _celebrateRevive();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not enough coins')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dPadOnRight = _dPadEnabled && _dPadPosition == DPadPosition.bottomRight;

    return Scaffold(
      backgroundColor: CosmoPalette.bgDeep,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Relative drag: touching down does NOT teleport the steer
            // target to the finger — only movement steers.
            onPanUpdate: (d) => _steerBy(d.delta),
            onTapDown: (_) {
              if (!_game.autoFire) _game.firePrimary();
            },
            onDoubleTap: _game.fireMissile,
            child: GameWidget(game: _game),
          ),

          // Red edge vignette pulse on every landed hit — shake-setting
          // independent, so a hit ALWAYS reads on screen.
          ValueListenableBuilder<int>(
            valueListenable: _game.hitPulseNotifier,
            builder: (_, pulse, _) {
              if (pulse == 0) return const SizedBox.shrink();
              return IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(pulse),
                  tween: Tween(begin: 1, end: 0),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOut,
                  builder: (_, t, _) {
                    if (t <= 0.01) return const SizedBox.shrink();
                    return Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          radius: 1.15,
                          colors: [
                            const Color(0x00000000),
                            CosmoPalette.hostile.withValues(alpha: 0.30 * t),
                          ],
                          stops: const [0.55, 1.0],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          SafeArea(child: _Hud(game: _game)),

          // Optional on-screen d-pad (settings-driven, snapshotted).
          if (_dPadEnabled)
            SafeArea(
              child: Align(
                alignment: switch (_dPadPosition) {
                  DPadPosition.bottomLeft => Alignment.bottomLeft,
                  DPadPosition.bottomCenter => Alignment.bottomCenter,
                  DPadPosition.bottomRight => Alignment.bottomRight,
                },
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: GameDPad(
                    onDirection: (dir) =>
                        _game.setMoveDirection(Vector2(dir.dx, dir.dy)),
                  ),
                ),
              ),
            ),

          // Missile fire button (docks away from the d-pad).
          SafeArea(
            child: Align(
              alignment:
                  dPadOnRight ? Alignment.bottomLeft : Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _MissileButton(game: _game),
              ),
            ),
          ),

          // Level intro banner (non-blocking).
          ValueListenableBuilder<GamePhase>(
            valueListenable: _game.phaseNotifier,
            builder: (context, phase, _) {
              if (phase != GamePhase.levelIntro) return const SizedBox.shrink();
              return _LevelIntroBanner(game: _game);
            },
          ),

          // Set-piece callout ("CANYON RUN") — small pulsing banner that
          // never blocks input.
          ValueListenableBuilder<String?>(
            valueListenable: _game.calloutNotifier,
            builder: (context, callout, _) {
              if (callout == null) return const SizedBox.shrink();
              return IgnorePointer(
                child: SafeArea(
                  child: Align(
                    alignment: const Alignment(0, -0.55),
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(callout),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      builder: (_, t, child) => Opacity(
                        opacity: t.clamp(0, 1),
                        child: Transform.scale(scale: 0.8 + 0.2 * t, child: child),
                      ),
                      child: Text(
                        callout,
                        style: TextStyle(
                          color: CosmoPalette.highlight,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 5,
                          shadows: [
                            Shadow(
                              color: CosmoPalette.hostile.withValues(alpha: 0.9),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // First-run tutorial prompt — a floating instruction banner at
          // the top of the playfield. Input passes straight through to
          // the game except for the Skip pill.
          ValueListenableBuilder<TutorialPrompt?>(
            valueListenable: _game.tutorialNotifier,
            builder: (context, prompt, _) {
              if (prompt == null) return const SizedBox.shrink();
              return SafeArea(
                child: _TutorialBanner(
                  prompt: prompt,
                  onSkip: _game.skipTutorial,
                ),
              );
            },
          ),

          // PILOT CERTIFIED celebration (tutorial completed) — pure
          // flourish, never blocks input, auto-dismisses.
          if (_showCertified)
            IgnorePointer(
              child: _CertifiedCelebration(coins: _tutorialRewardCoins),
            ),

          // REVIVED flourish after a paid continue — pure celebration,
          // never blocks input, auto-dismisses.
          if (_showRevived)
            const IgnorePointer(child: _ReviveFlourish()),

          ValueListenableBuilder<GamePhase>(
            valueListenable: _game.phaseNotifier,
            builder: (context, phase, _) {
              switch (phase) {
                case GamePhase.paused:
                  return PauseOverlay(
                    game: _game,
                    outcomes: _outcomes,
                    onResume: _game.resumeGame,
                    onRestart: _restartFromPause,
                    onQuit: _quitToHome,
                  );
                case GamePhase.levelClear:
                  return _LevelClearOverlay(
                    game: _game,
                    outcome: _outcomes[_game.levelIndex],
                  );
                case GamePhase.reviveOffer:
                  return _ReviveOverlay(
                    onWatchAd: AdService().isRewardedReady ? _reviveWithAd : null,
                    onSpendCoins:
                        context.read<CoinsCubit>().state.balance.total >= 200
                            ? _reviveWithCoins
                            : null,
                    onGiveUp: _game.declineRevive,
                  );
                case GamePhase.gameOver:
                  final r = _lastResult;
                  if (r == null) return const SizedBox.shrink();
                  final victory = r.cleared;
                  final unlocked = _outcomes.values
                      .where((o) => o.unlockedNextStage)
                      .map((o) => o.stageId + 1)
                      .fold<int>(0, (max, s) => s > max ? s : max);
                  return GameOverOverlay(
                    result: r,
                    victory: victory,
                    previousBest: _prevBestScore,
                    unlockedLevel: unlocked,
                    runCoinsEarned: _runCoinsEarned,
                    runXpEarned: _runXpEarned,
                    coinsDoubled: _coinsDoubled,
                    // "Watch ad → 2× coins": live while coins were earned,
                    // an ad is loaded and the daily cap isn't hit; swaps to
                    // a confirmation once claimed.
                    canDoubleCoins: _runCoinsEarned > 0 &&
                        AdService().canShowCapped(AdService.capDoubleCoins),
                    onDoubleCoins: _doubleRunCoins,
                    onRetry: () => _exitWithInterstitial(
                      () => context.pushReplacement(
                        AppRoutes.game,
                        extra: widget.startLevel,
                      ),
                    ),
                    onExit: () => _exitWithInterstitial(
                      () => victory
                          ? context.go(AppRoutes.levelSelect)
                          : context.go(AppRoutes.home),
                    ),
                    challengeRunStart: _challengeRunStart,
                  );
                case GamePhase.ready:
                case GamePhase.levelIntro:
                case GamePhase.playing:
                  return const SizedBox.shrink();
              }
            },
          ),
        ],
      ),
    );
  }
}

/// HUD skin for the glass frames — Command Cyan matches the cyan CosmoPalette
/// hull so the overlay chrome and the gameplay read as one system.
const GameTheme _hudSkin = GameTheme.classic;

class _Hud extends StatelessWidget {
  const _Hud({required this.game});
  final CosmoStrikeGame game;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(GameTokens.space12),
      child: Column(
        children: [
          // Corner panels keep the central play field clear in landscape.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top-left: score + level/wave.
              GlassPanel(
                theme: _hudSkin,
                radius: GameTokens.radiusMd,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                // One horizontal strip — the HUD stays out of the ship's
                // vertical flight lane (the playfield is short in landscape).
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: game.scoreNotifier,
                      builder: (_, score, _) => Text(
                        '$score',
                        style: const TextStyle(
                          color: CosmoPalette.highlight,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ValueListenableBuilder<int>(
                      valueListenable: game.levelNotifier,
                      builder: (_, level, _) => ValueListenableBuilder<int>(
                        valueListenable: game.waveNotifier,
                        builder: (_, wave, _) => Text(
                          'L$level · W$wave',
                          style: const TextStyle(
                            color: CosmoPalette.hull,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Kill tally — many daily directives are kill-based.
                    // Rendered at 0 too so the panel never jumps.
                    ValueListenableBuilder<int>(
                      valueListenable: game.killsNotifier,
                      builder: (_, kills, _) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.gps_fixed,
                              size: 11, color: CosmoPalette.hullLight),
                          const SizedBox(width: 3),
                          Text(
                            '$kills',
                            style: const TextStyle(
                              color: CosmoPalette.hullLight,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Kill-chain readout — appears from a 2-chain on,
                    // pulses when the multiplier tier rises.
                    ValueListenableBuilder<int>(
                      valueListenable: game.combo.comboNotifier,
                      builder: (_, chain, _) {
                        if (chain < 2) return const SizedBox.shrink();
                        return ValueListenableBuilder<int>(
                          valueListenable: game.combo.multiplierNotifier,
                          builder: (_, mult, _) =>
                              TweenAnimationBuilder<double>(
                            key: ValueKey(mult),
                            tween: Tween(
                                begin: mult > 1 ? 1.35 : 1.0, end: 1.0),
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutBack,
                            builder: (_, s, child) => Transform.scale(
                              scale: s,
                              alignment: Alignment.centerLeft,
                              child: child,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: Text(
                                '×$mult · $chain CHAIN',
                                style: TextStyle(
                                  color: mult >= 2
                                      ? CosmoPalette.hostile
                                      : CosmoPalette.hullLight,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Time Attack countdown — hidden in modes without a clock.
              ValueListenableBuilder<int>(
                valueListenable: game.timeRemainingNotifier,
                builder: (_, secs, _) {
                  if (secs < 0) return const SizedBox.shrink();
                  final m = secs ~/ 60;
                  final s = (secs % 60).toString().padLeft(2, '0');
                  final urgent = secs <= 30;
                  return Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: GlassPanel(
                      theme: _hudSkin,
                      radius: GameTokens.radiusMd,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer,
                            size: 16,
                            color: urgent
                                ? CosmoPalette.hostile
                                : CosmoPalette.hull,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$m:$s',
                            style: TextStyle(
                              color: urgent
                                  ? CosmoPalette.hostile
                                  : CosmoPalette.highlight,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const Spacer(),
              // Top-right: animated lives + pause.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GlassPanel(
                    theme: _hudSkin,
                    radius: GameTokens.radiusMd,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LivesPanel(game: game),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: game.pauseGame,
                          child: const Icon(Icons.pause_circle_outline,
                              color: CosmoPalette.hull, size: 26),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: GameTokens.space8),
          // Slim energy bar under the score panel (left-aligned, not full width).
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 220,
              child: ValueListenableBuilder<double>(
                valueListenable: game.healthNotifier,
                builder: (_, hp, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: hp,
                    minHeight: 6,
                    backgroundColor: CosmoPalette.bgHigh,
                    valueColor:
                        const AlwaysStoppedAnimation(CosmoPalette.energy),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: GameTokens.space8),
          // Active timed-effect chips under the energy bar.
          Align(
            alignment: Alignment.centerLeft,
            child: ValueListenableBuilder<List<ActiveEffectHud>>(
              valueListenable: game.effectsNotifier,
              builder: (_, effects, _) {
                if (effects.isEmpty) return const SizedBox.shrink();
                return Wrap(
                  spacing: 6,
                  children: [
                    for (final e in effects) _EffectChip(effect: e),
                  ],
                );
              },
            ),
          ),
          const Spacer(),
          // Boss bar spans the bottom only while a boss is alive.
          ValueListenableBuilder<double>(
            valueListenable: game.bossHealthNotifier,
            builder: (_, boss, _) {
              if (boss < 0) return const SizedBox.shrink();
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: boss,
                  minHeight: 9,
                  backgroundColor: CosmoPalette.bgHigh,
                  valueColor:
                      const AlwaysStoppedAnimation(CosmoPalette.hostile),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The lives readout with a real death beat: when a ship is lost, the
/// dying icon flares red and blows up in place, and a "SHIP DOWN" tag
/// flashes under the panel — losing a life is never silent again.
class _LivesPanel extends StatefulWidget {
  const _LivesPanel({required this.game});
  final CosmoStrikeGame game;

  @override
  State<_LivesPanel> createState() => _LivesPanelState();
}

class _LivesPanelState extends State<_LivesPanel> {
  late int _shown;
  int _lossEvents = 0;

  @override
  void initState() {
    super.initState();
    _shown = widget.game.livesNotifier.value;
    widget.game.livesNotifier.addListener(_onLivesChanged);
  }

  @override
  void dispose() {
    widget.game.livesNotifier.removeListener(_onLivesChanged);
    super.dispose();
  }

  void _onLivesChanged() {
    final now = widget.game.livesNotifier.value;
    if (!mounted || now == _shown) return;
    setState(() {
      if (now < _shown) _lossEvents++;
      _shown = now;
    });
  }

  @override
  Widget build(BuildContext context) {
    final icons = List<Widget>.generate(
      _shown.clamp(0, 6),
      (i) => const Padding(
        padding: EdgeInsets.only(right: 3),
        child: Icon(Icons.flight, size: 16, color: CosmoPalette.hull),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...icons,
            // The dying ship: flares red, swells, and burns away where
            // its icon used to sit.
            if (_lossEvents > 0)
              TweenAnimationBuilder<double>(
                key: ValueKey(_lossEvents),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOut,
                builder: (_, t, _) {
                  if (t >= 1) return const SizedBox.shrink();
                  return Opacity(
                    opacity: (1 - t).clamp(0, 1),
                    child: Transform.scale(
                      scale: 1 + t * 1.1,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Icon(Icons.flight,
                            size: 16,
                            color: Color.lerp(CosmoPalette.hostile,
                                const Color(0xFFFFE3B3), t)),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        // "SHIP DOWN" tag dropping in under the panel.
        if (_lossEvents > 0)
          Positioned(
            right: 0,
            top: 22,
            child: TweenAnimationBuilder<double>(
              key: ValueKey(-_lossEvents),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1400),
              builder: (_, t, _) {
                // Pop in fast, hold, fade at the tail.
                final inT = (t * 6).clamp(0.0, 1.0);
                final outT = ((t - 0.75) * 4).clamp(0.0, 1.0);
                final alpha = inT * (1 - outT);
                if (alpha <= 0.01) return const SizedBox.shrink();
                return Opacity(
                  opacity: alpha,
                  child: Transform.translate(
                    offset: Offset(0, (1 - inT) * -6),
                    child: Text(
                      'SHIP DOWN',
                      style: TextStyle(
                        color: CosmoPalette.hostile,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                        shadows: [
                          Shadow(
                            color:
                                CosmoPalette.hostile.withValues(alpha: 0.8),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _EffectChip extends StatelessWidget {
  const _EffectChip({required this.effect});
  final ActiveEffectHud effect;

  static const Map<String, IconData> _icons = {
    'weapon': Icons.bolt,
    'x2': Icons.close, // x glyph
    'speed': Icons.speed,
    'slowmo': Icons.slow_motion_video,
    'magnet': Icons.attractions,
    'ghost': Icons.blur_on,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: CosmoPalette.bgHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icons[effect.id] ?? Icons.star,
              size: 13, color: CosmoPalette.hull),
          const SizedBox(width: 4),
          SizedBox(
            width: 26,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: effect.remaining01,
                minHeight: 3,
                backgroundColor: CosmoPalette.bgDeep,
                valueColor: const AlwaysStoppedAnimation(CosmoPalette.energy),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round special-weapon button with the live ammo badge.
class _MissileButton extends StatelessWidget {
  const _MissileButton({required this.game});
  final CosmoStrikeGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: game.missileAmmoNotifier,
      builder: (_, ammo, _) {
        final enabled = ammo > 0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: game.fireMissile,
          child: SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Graze meter: a thin gold arc filling around the disc;
                // a full ring converts to +1 missile.
                ValueListenableBuilder<double>(
                  valueListenable: game.combo.grazeNotifier,
                  builder: (_, g, _) {
                    if (g <= 0) return const SizedBox.shrink();
                    return SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: g,
                        strokeWidth: 3,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation(
                            Color(0xFFFFD37B)),
                      ),
                    );
                  },
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CosmoPalette.bgHigh
                        .withValues(alpha: enabled ? 0.55 : 0.3),
                    boxShadow: enabled
                        ? [
                            BoxShadow(
                              color:
                                  CosmoPalette.energy.withValues(alpha: 0.4),
                              blurRadius: 16,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    Icons.rocket,
                    size: 30,
                    color: enabled
                        ? CosmoPalette.energy
                        : CosmoPalette.hullDark.withValues(alpha: 0.6),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: enabled
                          ? CosmoPalette.energy
                          : CosmoPalette.bgHigh,
                    ),
                    child: Text(
                      '$ammo',
                      style: TextStyle(
                        color: enabled
                            ? CosmoPalette.bgDeep
                            : CosmoPalette.hullDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Animated "LEVEL N — NAME" banner during the level intro phase.
class _LevelIntroBanner extends StatelessWidget {
  const _LevelIntroBanner({required this.game});
  final CosmoStrikeGame game;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - t)),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: game.levelNotifier,
                builder: (_, level, _) => Text(
                  'LEVEL $level',
                  style: const TextStyle(
                    color: CosmoPalette.hull,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ValueListenableBuilder<String>(
                valueListenable: game.levelNameNotifier,
                builder: (_, name, _) => Text(
                  name,
                  style: TextStyle(
                    color: CosmoPalette.highlight.withValues(alpha: 0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// LEVEL CLEAR: star pips for THIS run's performance, auto-continue after
/// a beat, plus an explicit CONTINUE button.
class _LevelClearOverlay extends StatefulWidget {
  const _LevelClearOverlay({required this.game, this.outcome});
  final CosmoStrikeGame game;
  final StageClearOutcome? outcome;

  @override
  State<_LevelClearOverlay> createState() => _LevelClearOverlayState();
}

class _LevelClearOverlayState extends State<_LevelClearOverlay> {
  Timer? _autoContinue;

  @override
  void initState() {
    super.initState();
    _autoContinue = Timer(const Duration(seconds: 3), () {
      widget.game.advanceToNextLevel();
    });
  }

  @override
  void dispose() {
    _autoContinue?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final level = game.levelIndex;
    // This run's per-level performance (the result was just recorded).
    final result = game.buildPartialResult().levelResults.lastWhere(
          (lr) => lr.stageId == level,
          orElse: () => LevelRunResult(
            stageId: level,
            cleared: true,
            score: 0,
            timeSeconds: 0,
            waveReached: 1,
            noHit: false,
          ),
        );
    final stars = CampaignCatalog.starsFor(
      stageId: level,
      cleared: true,
      noHit: result.noHit,
      bestTimeSeconds: result.timeSeconds,
      bestScore: result.score,
    );

    return _CenterOverlay(
      title: 'LEVEL $level CLEAR',
      subtitle: 'Score +${result.score}   •   ${result.timeSeconds}s'
          '${result.noHit ? '   •   NO HIT' : ''}'
          '${(widget.outcome?.unlockedNextStage ?? false) ? '\nLEVEL ${level + 1} UNLOCKED' : ''}',
      extra: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final earned = i < stars;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              earned ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 34,
              color: earned
                  ? const Color(0xFFFFD54F)
                  : CosmoPalette.hullDark.withValues(alpha: 0.6),
            ),
          );
        }),
      ),
      actions: [
        _OverlayButton(
          label: 'CONTINUE TO LEVEL ${level + 1}',
          onTap: () {
            _autoContinue?.cancel();
            game.advanceToNextLevel();
          },
        ),
      ],
    );
  }
}

/// CONTINUE? — one revive per run, paid with a rewarded ad or coins,
/// under a 6-second decision countdown.
class _ReviveOverlay extends StatefulWidget {
  const _ReviveOverlay({
    required this.onWatchAd,
    required this.onSpendCoins,
    required this.onGiveUp,
  });

  final VoidCallback? onWatchAd;
  final VoidCallback? onSpendCoins;
  final VoidCallback onGiveUp;

  @override
  State<_ReviveOverlay> createState() => _ReviveOverlayState();
}

class _ReviveOverlayState extends State<_ReviveOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _countdown;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _countdown = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_resolved) {
          _resolved = true;
          widget.onGiveUp();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  void _resolve(VoidCallback action) {
    if (_resolved) return;
    _resolved = true;
    _countdown.stop();
    action();
  }

  /// Watching an ad pauses the countdown but is NOT final — if the ad
  /// fails to show, the offer stays. The countdown does not restart
  /// (the ad flow takes over pacing).
  void _watchAd() {
    if (_resolved) return;
    _countdown.stop();
    widget.onWatchAd?.call();
  }

  @override
  Widget build(BuildContext context) {
    return _CenterOverlay(
      title: 'CONTINUE?',
      extra: SizedBox(
        width: 52,
        height: 52,
        child: AnimatedBuilder(
          animation: _countdown,
          builder: (_, _) => Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: 1 - _countdown.value,
                strokeWidth: 4,
                backgroundColor: CosmoPalette.bgHigh,
                valueColor: const AlwaysStoppedAnimation(CosmoPalette.hull),
              ),
              Text(
                '${(6 * (1 - _countdown.value)).ceil()}',
                style: const TextStyle(
                  color: CosmoPalette.highlight,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.onWatchAd != null)
          _OverlayButton(
            label: 'WATCH AD',
            onTap: _watchAd,
          ),
        if (widget.onSpendCoins != null)
          _OverlayButton(
            label: 'REVIVE  ·  200 COINS',
            onTap: () => _resolve(widget.onSpendCoins!),
          ),
        _OverlayButton(
          label: 'GIVE UP',
          onTap: () => _resolve(widget.onGiveUp),
          secondary: true,
        ),
      ],
    );
  }
}

class _CenterOverlay extends StatelessWidget {
  const _CenterOverlay({
    required this.title,
    required this.actions,
    this.subtitle,
    this.extra,
  });

  final String title;
  final String? subtitle;
  final Widget? extra;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF05060F).withValues(alpha: 0.86),
      alignment: Alignment.center,
      child: GlassPanel(
        theme: _hudSkin,
        glow: true,
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CosmoPalette.hull,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            if (extra != null) ...[
              const SizedBox(height: 14),
              extra!,
            ],
            if (subtitle != null) ...[
              const SizedBox(height: 12),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: CosmoPalette.highlight, fontSize: 15),
              ),
            ],
            const SizedBox(height: 24),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// First-run tutorial instruction banner: floats top-center over the
/// playfield, borderless per the clean design (neon icon + text + glow).
/// Everything except the SKIP pill ignores pointers so drag-steering
/// works straight through it.
class _TutorialBanner extends StatelessWidget {
  const _TutorialBanner({required this.prompt, required this.onSkip});

  final TutorialPrompt prompt;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.92),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(prompt.title),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutBack,
        builder: (_, t, child) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          prompt.icon,
                          size: 18,
                          color: CosmoPalette.highlight,
                          shadows: [
                            Shadow(
                              color: CosmoPalette.highlight
                                  .withValues(alpha: 0.8),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Text(
                          prompt.title,
                          style: TextStyle(
                            color: CosmoPalette.highlight,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                            shadows: [
                              Shadow(
                                color: CosmoPalette.highlight
                                    .withValues(alpha: 0.7),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      prompt.body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: CosmoPalette.hull,
                        fontSize: 13.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(color: Color(0xCC05060F), blurRadius: 8),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (prompt.showSkip) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onSkip,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    child: Text(
                      'SKIP TUTORIAL',
                      style: TextStyle(
                        color: CosmoPalette.hull.withValues(alpha: 0.65),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "PILOT CERTIFIED" tutorial-complete flourish: a gold banner with the
/// coin payout that scales in, holds, and is removed by the screen after
/// ~3 s. Pure celebration — wrapped in IgnorePointer by the caller.
class _CertifiedCelebration extends StatelessWidget {
  const _CertifiedCelebration({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.45),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        builder: (_, t, child) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.military_tech,
              size: 44,
              color: Color(0xFFFFD37B),
              shadows: [
                Shadow(color: Color(0xAAFFD37B), blurRadius: 22),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'PILOT CERTIFIED',
              style: TextStyle(
                color: Color(0xFFFFD37B),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                shadows: [
                  Shadow(color: Color(0xAAFFD37B), blurRadius: 18),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '+$coins COINS',
              style: const TextStyle(
                color: CosmoPalette.hull,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
                shadows: [
                  Shadow(color: Color(0xCC05060F), blurRadius: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "REVIVED" continue flourish: a gold banner that scales in over the
/// playfield right as the run resumes, removed by the screen after ~1.5 s.
/// Pure celebration — wrapped in IgnorePointer by the caller.
class _ReviveFlourish extends StatelessWidget {
  const _ReviveFlourish();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.45),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutBack,
        builder: (_, t, child) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.rocket_launch,
              size: 40,
              color: Color(0xFFFFD37B),
              shadows: [
                Shadow(color: Color(0xAAFFD37B), blurRadius: 22),
              ],
            ),
            SizedBox(height: 6),
            Text(
              'REVIVED',
              style: TextStyle(
                color: Color(0xFFFFD37B),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                shadows: [
                  Shadow(color: Color(0xAAFFD37B), blurRadius: 18),
                ],
              ),
            ),
            SizedBox(height: 4),
            Text(
              '+1 SHIP',
              style: TextStyle(
                color: CosmoPalette.hull,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
                shadows: [
                  Shadow(color: Color(0xCC05060F), blurRadius: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.label,
    required this.onTap,
    this.secondary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        width: 240,
        child: NeonButton(
          label: label,
          onPressed: onTap,
          theme: _hudSkin,
          variant:
              secondary ? NeonButtonVariant.outline : NeonButtonVariant.solid,
        ),
      ),
    );
  }
}
