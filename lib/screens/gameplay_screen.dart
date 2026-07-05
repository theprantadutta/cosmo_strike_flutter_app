import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../game/components/power_up.dart';
import '../game/cosmo_palette.dart';
import '../game/cosmo_strike_game.dart';
import '../game/tutorial_director.dart';
import '../models/daily_challenge.dart';
import '../models/level_run_result.dart';
import '../models/weekly_quest.dart';
import '../models/ship_coins.dart';
import '../presentation/bloc/coins/coins_cubit.dart';
import '../presentation/bloc/game/game_settings_cubit.dart';
import '../presentation/bloc/power_up/power_up_cubit.dart';
import '../presentation/bloc/premium/battle_pass_cubit.dart';
import '../presentation/bloc/premium/premium_cubit.dart';
import '../presentation/bloc/theme/theme_cubit.dart';
import '../presentation/bloc/tournament/tournament_context_cubit.dart';
import '../router/routes.dart';
import '../services/achievement_service.dart';
import '../services/ads/ad_service.dart';
import '../services/analytics/analytics_facade.dart';
import '../services/audio_service.dart';
import '../services/daily_challenge_service.dart';
import '../services/statistics_service.dart';
import '../services/tournament_service.dart';
import '../services/weekly_quest_service.dart';
import '../services/haptic_service.dart';
import '../services/walkthrough_service.dart';
import '../ui/design.dart';
import '../utils/constants.dart';
import '../widgets/game_dpad.dart';
import '../widgets/gameplay/game_over_overlay.dart';
import '../widgets/gameplay/level_complete_overlay.dart';
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

  /// Per-level persisted best snapshot captured the instant before this run
  /// merged in — lets the level-complete summary show accurate NEW BEST /
  /// FASTEST / FIRST NO-HIT badges (the merge overwrites the stored best).
  final Map<int, StageProgressRow?> _priorBest = {};

  bool _quitPersisted = false;

  /// The tree-provided tournament context. Captured in initState so we read
  /// THIS run's tournament id and can clear it on dispose — tournament mode
  /// is otherwise never reset and would leak into the next run,
  /// mis-attributing a normal game's score to the tournament.
  TournamentContextCubit? _tournamentContext;

  /// Tournament this run counts toward (null for a normal game). Captured at
  /// run start; the final score is submitted to it in [_submitRun].
  String? _tournamentId;

  /// Game mode name for this run (for the per-mode leaderboard tag). Captured
  /// at run start so the abandoned-run path doesn't need a live context.
  String _gameModeName = 'classic';

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
    _gameModeName = settings.gameMode.name;

    // Capture the tournament context for this run (set by the tournament
    // detail screen before launching). Held for the screen's lifetime so the
    // game-over submit attributes the score to the right tournament.
    try {
      _tournamentContext = context.read<TournamentContextCubit>();
      _tournamentId = _tournamentContext?.state.tournamentId;
    } catch (_) {
      _tournamentContext = null;
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
    GetIt.I<AdService>().preloadRewarded();
    GetIt.I<AdService>().preloadInterstitial();

    // First-run tutorial: only on a Level-1 start, only until completed
    // or skipped once (the flag is prefs-backed and resettable from
    // Settings). The service is hydrated in main() so this sync read is
    // always safe.
    final walkthroughs = WalkthroughService();
    _tutorialRun =
        widget.startLevel == 1 &&
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
    unawaited(
      WalkthroughService().markComplete(WalkthroughService.gameTutorialId),
    );
    final analytics = GetIt.I<AnalyticsFacade>();
    if (!completed) {
      unawaited(analytics.trackGameTutorialSkipped());
      return;
    }
    unawaited(analytics.trackGameTutorialCompleted());
    if (!mounted) return;
    unawaited(
      context.read<CoinsCubit>().earnCoins(
        CoinEarningSource.achievementUnlocked,
        customAmount: _tutorialRewardCoins,
      ),
    );
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
    _tournamentContext?.exitTournament();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Crash-safe incremental persistence: each level clear merges into
  /// Drift (and enqueues sync) the moment the boss falls.
  void _handleLevelCleared(LevelRunResult result) {
    _persistedClears.add(result.stageId);
    // Re-warm the interstitial/rewarded the instant the boss falls — the
    // level-clear summary buys a few seconds of lead time before the player
    // taps Continue, so the ad is already loaded at the break instead of
    // starting to load on-demand (no-op if one's already in hand).
    GetIt.I<AdService>().preloadInterstitial();
    GetIt.I<AdService>().preloadRewarded();
    unawaited(() async {
      try {
        final dao = GetIt.I<AppDatabase>().stageProgressDao;
        // Snapshot the prior best BEFORE merging this run, so the
        // level-complete summary can flag genuine new records.
        final prior = await dao.getStage(result.stageId);
        final outcomes = await dao.applyRunResults([result]);
        if (!mounted) return;
        setState(() {
          _priorBest[result.stageId] = prior;
          for (final o in outcomes) {
            _outcomes[o.stageId] = o;
          }
        });
      } catch (_) {
        // Forget the optimistic mark so the game-over apply (which skips
        // stages in _persistedClears) retries this row — otherwise a failed
        // write here silently lost the clear for the whole run.
        _persistedClears.remove(result.stageId);
      }
    }());
  }

  void _handleGameOver(GameResult result) {
    _lastResult = result;
    widget.onRunComplete?.call(result);
    // Re-warm both ad types now so the game-over screen's "2× coins" rewarded
    // and the Retry/Exit interstitial are already loaded by the time the
    // player taps — never loaded on-demand at the tap.
    GetIt.I<AdService>().preloadInterstitial();
    GetIt.I<AdService>().preloadRewarded();
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
        final outcomes = await GetIt.I<AppDatabase>().stageProgressDao
            .applyRunResults(pending);
        for (final o in outcomes) {
          _outcomes[o.stageId] = o;
        }
      }
      firstClears = _outcomes.values.where((o) => o.firstClear).length;
    } catch (_) {}

    // Offline-first: queue the run to the sync outbox (drained to
    // /scores/batch by SyncEngine) instead of a live fire-and-forget call, so
    // a run played offline still reaches the leaderboards on reconnect.
    unawaited(_enqueueScore(r, runIdempotencyKey));

    // Tournament run: submit the score to the live leaderboard. Reuses the
    // run's idempotency key so a retry de-dupes server-side (BestScore is
    // max-merged, GamesPlayed is guarded by the key).
    final tournamentId = _tournamentId;
    if (tournamentId != null) {
      unawaited(
        TournamentService().submitScore(tournamentId, r.score, {
          'gameDurationSeconds': r.durationSeconds,
          'enemiesKilled': r.enemiesKilled,
        }, idempotencyKey: runIdempotencyKey),
      );
    }

    try {
      final coinsEarned =
          10 +
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
    // legacy FoodEaten wire type (the kills -> foodEaten challenge mapping).
    final modeName = settings.state.gameMode.name;
    unawaited(
      DailyChallengeService().updateProgressBatch([
        (type: ChallengeType.score, value: r.score, gameMode: null),
        (type: ChallengeType.foodEaten, value: r.enemiesKilled, gameMode: null),
        (
          type: ChallengeType.survival,
          value: r.durationSeconds,
          gameMode: null,
        ),
        (type: ChallengeType.gamesPlayed, value: 1, gameMode: null),
        (type: ChallengeType.gameMode, value: 1, gameMode: modeName),
      ]),
    );
    unawaited(() async {
      final weekly = WeeklyQuestService();
      // Hydrate first: reportProgressBatch no-ops on an empty quest list.
      await weekly.initialize();
      await weekly.reportProgressBatch([
        if (r.score > 0)
          (type: WeeklyQuestType.score, incrementBy: r.score, gameMode: null),
        if (r.enemiesKilled > 0)
          (
            type: WeeklyQuestType.foodEaten,
            incrementBy: r.enemiesKilled,
            gameMode: null,
          ),
        if (r.durationSeconds > 0)
          (
            type: WeeklyQuestType.survival,
            incrementBy: r.durationSeconds,
            gameMode: null,
          ),
        (type: WeeklyQuestType.gamesPlayed, incrementBy: 1, gameMode: null),
        if (tournamentId != null)
          (
            type: WeeklyQuestType.tournamentParticipation,
            incrementBy: 1,
            gameMode: null,
          ),
      ]);
    }());
    try {
      AchievementService()
        ..checkScoreAchievements(
          r.score,
          gameMode: modeName,
          difficulty: 'normal',
        )
        ..checkSurvivalAchievements(
          r.durationSeconds,
          gameMode: modeName,
          difficulty: 'normal',
        );
    } catch (_) {}

    // Fold this run into lifetime statistics. This is the ONLY place the live
    // single-player shmup records stats — the run lives in Flame, so the
    // legacy GameCubit recording path never fires for it. Writing here keeps
    // totalGamesPlayed / score / enemies / stage / play-time accurate, and
    // StatisticsService persists to Drift + enqueues the statistics sync.
    try {
      final noHitClears = r.levelResults
          .where((lr) => lr.cleared && lr.noHit)
          .length;
      await StatisticsService().recordGameResult(
        score: r.score,
        durationSeconds: r.durationSeconds,
        stageReached: r.stageReached,
        waveReached: r.waveReached,
        enemiesKilled: r.enemiesKilled,
        bossesKilled: r.bossesKilled,
        levelsCleared: r.levelsCleared,
        missilesFired: r.missilesFired,
        revivesUsed: r.revivesUsed,
        victory: r.cleared,
        noHitClears: noHitClears,
        maxCombo: r.maxCombo,
        grazeCount: r.grazeCount,
        gameMode: modeName,
      );
    } catch (_) {}
  }

  /// Queue a finished/aborted run to the sync outbox (drained to
  /// /scores/batch). Frozen-payload event type — `played_at` is stamped now so
  /// a run synced later still lands in the weekly/daily window it was played
  /// in; the idempotency key dedupes retries server-side.
  Future<void> _enqueueScore(
    GameResult r,
    String idempotencyKey, {
    bool aborted = false,
  }) async {
    try {
      await GetIt.I<AppDatabase>().enqueueSyncOutbox(
        dataType: SyncDataType.gameScore,
        entityKey: idempotencyKey,
        priority: 1,
        payload: {
          'score': r.score,
          'game_duration_seconds': r.durationSeconds,
          'enemies_killed': r.enemiesKilled,
          'stage_reached': r.stageReached,
          'wave_reached': r.waveReached,
          'bosses_killed': r.bossesKilled,
          'game_mode': _gameModeName,
          'difficulty': 'Normal',
          'idempotency_key': idempotencyKey,
          'played_at': DateTime.now().toUtc().toIso8601String(),
          'game_data': aborted
              ? const {'aborted': true}
              : {
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
        },
      );
    } catch (_) {
      // A queue write shouldn't ever fail, but never let it block game-over.
    }
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
        unawaited(
          GetIt.I<AppDatabase>().stageProgressDao
              .applyRunResults(pending)
              .catchError((_) => const <StageClearOutcome>[]),
        );
      }
      unawaited(_enqueueScore(partial, const Uuid().v4(), aborted: true));
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
    _game.steerBy(
      Vector2(delta.dx * _dragSensitivity, delta.dy * _dragSensitivity),
    );
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

  /// Premium perk: revive with no ad and no coins (still one-per-run, gated
  /// by the game's `_reviveUsed`). Premium users can't watch ads, so this is
  /// their continue path.
  void _reviveFree() {
    _game.revive();
    _celebrateRevive();
  }

  void _reviveWithAd() {
    GetIt.I<AdService>()
        .showRewarded(
          onReward: () {
            _game.revive();
            _celebrateRevive();
          },
        )
        .then((shown) {
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
    final shown = await GetIt.I<AdService>().showRewardedCapped(
      capKey: AdService.capDoubleCoins,
      onReward: () {
        unawaited(
          coins.earnCoins(
            CoinEarningSource.watchedAd,
            customAmount: earned,
            itemName: 'Game over 2× coins',
            metadata: const {'placement': 'game_over_double'},
          ),
        );
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
    GetIt.I<AdService>().maybeShowInterstitialOnGameOver().whenComplete(() {
      if (mounted) navigate();
    });
  }

  /// Continue past a cleared level through the (frequency-capped) level-clear
  /// interstitial — the busiest natural break. Cadence is remote-tunable
  /// (AdTuning; default every 3rd clear), shares the min gap with the
  /// game-over interstitial, never the first session, never for Pro (all
  /// enforced in AdService). The engine is frozen during `levelClear`, so
  /// nothing runs behind the ad; the next level always loads afterwards
  /// whether an ad showed or not.
  void _advanceWithInterstitial() {
    GetIt.I<AdService>().maybeShowInterstitialOnLevelClear().whenComplete(() {
      if (mounted) _game.advanceToNextLevel();
    });
  }

  /// Pause-menu opt-in rewarded perk: watch an ad → +1 life. Reuses the
  /// existing power-up grant and the daily-capped power-up placement, so it
  /// can't be ground infinitely. The engine stays frozen on the pause overlay
  /// throughout; the lives HUD animates the gain when play resumes.
  Future<void> _watchAdForLife() async {
    final shown = await GetIt.I<AdService>().showRewardedCapped(
      capKey: AdService.capFreePowerUp,
      onReward: () {
        _game.applyPowerUp(PowerUpKind.life);
        RewardToast.show(title: 'EXTRA LIFE', amount: '+1 SHIP');
      },
    );
    if (!shown && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not ready — try again in a moment')),
      );
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not enough coins')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dPadOnRight =
        _dPadEnabled && _dPadPosition == DPadPosition.bottomRight;

    return Scaffold(
      backgroundColor: CosmoPalette.bgDeep,
      // NO banner during active play: the steering pan gesture covers the
      // whole screen, so an in-play banner is an accidental-click (invalid
      // traffic) risk and eats vertical dodge space. Banners float INSIDE the
      // pause / level-clear / game-over overlays instead — and because the
      // playfield always gets the full height, the Flame world (which uses
      // the raw widget size for coordinates) never resizes mid-run.
      body: Column(
        children: [
          Expanded(
            child: Stack(
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
                                  CosmoPalette.hostile.withValues(
                                    alpha: 0.30 * t,
                                  ),
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
                    alignment: dPadOnRight
                        ? Alignment.bottomLeft
                        : Alignment.bottomRight,
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
                    if (phase != GamePhase.levelIntro) {
                      return const SizedBox.shrink();
                    }
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
                              child: Transform.scale(
                                scale: 0.8 + 0.2 * t,
                                child: child,
                              ),
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
                                    color: CosmoPalette.hostile.withValues(
                                      alpha: 0.9,
                                    ),
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
                if (_showRevived) const IgnorePointer(child: _ReviveFlourish()),

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
                          // Opt-in rewarded "+1 life" perk — shown only when an ad
                          // is loaded and the daily power-up cap isn't hit.
                          lifeAdReady: GetIt.I<AdService>().canShowCapped(
                            AdService.capFreePowerUp,
                          ),
                          onWatchAdForLife: _watchAdForLife,
                        );
                      case GamePhase.levelClear:
                        return LevelCompleteOverlay(
                          game: _game,
                          outcome: _outcomes[_game.levelIndex],
                          priorBest: _priorBest[_game.levelIndex],
                          onContinue: _advanceWithInterstitial,
                          onQuit: _quitToHome,
                        );
                      case GamePhase.reviveOffer:
                        final isPremium =
                            GetIt.I.isRegistered<PremiumCubit>() &&
                            GetIt.I<PremiumCubit>().state.hasPremium;
                        final coinsEnough =
                            context.read<CoinsCubit>().state.balance.total >=
                            200;
                        return _ReviveOverlay(
                          isPremium: isPremium,
                          adReady: GetIt.I<AdService>().isRewardedReady,
                          level: _game.levelIndex,
                          score: _game.scoreNotifier.value,
                          wave: _game.wave,
                          onWatchAd: _reviveWithAd,
                          onFreeRevive: _reviveFree,
                          onSpendCoins: _reviveWithCoins,
                          coinsEnough: coinsEnough,
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
                          // "Watch ad → 2× coins": offered whenever coins were
                          // earned, ads are on (not Pro/offline) and the daily cap
                          // isn't hit. Deliberately NOT gated on the ad being loaded
                          // *this instant* — that snapshot isn't reactive, so the
                          // button could otherwise never appear if the ad finished
                          // loading a beat later. The tap handles a not-yet-ready ad
                          // (retry snackbar). Swaps to a confirmation once claimed.
                          canDoubleCoins:
                              _runCoinsEarned > 0 &&
                              GetIt.I<AdService>().adsEnabled &&
                              GetIt.I<AdService>().dailyRemaining(
                                    AdService.capDoubleCoins,
                                  ) >
                                  0,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
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
                          const Icon(
                            Icons.gps_fixed,
                            size: 11,
                            color: CosmoPalette.hullLight,
                          ),
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
                                  begin: mult > 1 ? 1.35 : 1.0,
                                  end: 1.0,
                                ),
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
                        horizontal: 12,
                        vertical: 8,
                      ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LivesPanel(game: game),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: game.pauseGame,
                          child: const Icon(
                            Icons.pause_circle_outline,
                            color: CosmoPalette.hull,
                            size: 26,
                          ),
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
                    valueColor: const AlwaysStoppedAnimation(
                      CosmoPalette.energy,
                    ),
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
                  children: [for (final e in effects) _EffectChip(effect: e)],
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
                  valueColor: const AlwaysStoppedAnimation(
                    CosmoPalette.hostile,
                  ),
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
                        child: Icon(
                          Icons.flight,
                          size: 16,
                          color: Color.lerp(
                            CosmoPalette.hostile,
                            const Color(0xFFFFE3B3),
                            t,
                          ),
                        ),
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
                            color: CosmoPalette.hostile.withValues(alpha: 0.8),
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
    'shield': Icons.shield, // post-revive protection window
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
          Icon(
            _icons[effect.id] ?? Icons.star,
            size: 13,
            color: CosmoPalette.hull,
          ),
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
                          Color(0xFFFFD37B),
                        ),
                      ),
                    );
                  },
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CosmoPalette.bgHigh.withValues(
                      alpha: enabled ? 0.55 : 0.3,
                    ),
                    boxShadow: enabled
                        ? [
                            BoxShadow(
                              color: CosmoPalette.energy.withValues(alpha: 0.4),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
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

/// SHIP DOWN — the one-revive-per-run continue offer, under a decision
/// countdown. Free users revive by watching a rewarded ad; premium users get
/// a free revive (no ad); coins are the universal fallback.
class _ReviveOverlay extends StatefulWidget {
  const _ReviveOverlay({
    required this.isPremium,
    required this.adReady,
    required this.level,
    required this.score,
    required this.wave,
    required this.onWatchAd,
    required this.onFreeRevive,
    required this.onSpendCoins,
    required this.coinsEnough,
    required this.onGiveUp,
  });

  /// Premium users see a free revive instead of the ad path (ads are off
  /// for them).
  final bool isPremium;

  /// A rewarded ad is loaded right now (free users only).
  final bool adReady;

  final int level;
  final int score;
  final int wave;

  final VoidCallback onWatchAd;
  final VoidCallback onFreeRevive;
  final VoidCallback onSpendCoins;
  final bool coinsEnough;
  final VoidCallback onGiveUp;

  @override
  State<_ReviveOverlay> createState() => _ReviveOverlayState();
}

class _ReviveOverlayState extends State<_ReviveOverlay>
    with SingleTickerProviderStateMixin {
  static const int _seconds = 8;
  late final AnimationController _countdown;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _countdown =
        AnimationController(
            vsync: this,
            duration: const Duration(seconds: _seconds),
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
    widget.onWatchAd();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Container(
              color: const Color(0xFF05060F).withValues(alpha: 0.86),
            ),
          ),
        ),
        Center(
          // Landscape card: status/countdown on the LEFT, the continue
          // actions on the RIGHT — uses the wide-short viewport instead of
          // stacking everything into a column that overflows. FittedBox is
          // a safety net for very short screens.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: GlassPanel(
              theme: _hudSkin,
              glow: true,
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 26),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 230,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _countdownRing(),
                        const SizedBox(height: 16),
                        Text(
                          'SHIP DOWN',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: CosmoPalette.hostile,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 3,
                            shadows: [
                              Shadow(
                                color: CosmoPalette.hostile.withValues(
                                  alpha: 0.6,
                                ),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Resume Level ${widget.level}\n'
                          'Score ${widget.score}  •  Wave ${widget.wave}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: CosmoPalette.highlight,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 28),
                  Container(
                    width: 1,
                    height: 150,
                    color: CosmoPalette.hull.withValues(alpha: 0.15),
                  ),
                  const SizedBox(width: 28),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Primary continue path: premium → free revive; free →
                      // watch an ad (kept visible but disabled while the ad
                      // loads, so the path is always discoverable).
                      if (widget.isPremium)
                        _OverlayButton(
                          label: '✦ FREE REVIVE',
                          onTap: () => _resolve(widget.onFreeRevive),
                        )
                      else if (widget.adReady)
                        _OverlayButton(
                          label: '▶ WATCH AD — REVIVE',
                          onTap: _watchAd,
                        )
                      else
                        _disabledButton('WATCH AD — LOADING…'),
                      // Universal coin fallback.
                      if (widget.coinsEnough)
                        _OverlayButton(
                          label: 'REVIVE  ·  200 COINS',
                          onTap: () => _resolve(widget.onSpendCoins),
                          secondary: true,
                        )
                      else
                        _disabledButton('REVIVE  ·  NEED 200 COINS'),
                      _OverlayButton(
                        label: 'GIVE UP',
                        onTap: () => _resolve(widget.onGiveUp),
                        secondary: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _countdownRing() {
    return SizedBox(
      width: 60,
      height: 60,
      child: AnimatedBuilder(
        animation: _countdown,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: 1 - _countdown.value,
              strokeWidth: 4,
              backgroundColor: CosmoPalette.bgHigh,
              valueColor: const AlwaysStoppedAnimation(CosmoPalette.hostile),
            ),
            Text(
              '${(_seconds * (1 - _countdown.value)).ceil()}',
              style: const TextStyle(
                color: CosmoPalette.highlight,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A dimmed, non-tappable button — keeps an option visible (ad still
  /// loading, or not enough coins) so the path is discoverable, without
  /// letting it fire.
  Widget _disabledButton(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Opacity(
        opacity: 0.45,
        child: AbsorbPointer(
          child: SizedBox(
            width: 240,
            child: NeonButton(
              label: label,
              onPressed: () {},
              theme: _hudSkin,
              variant: NeonButtonVariant.outline,
            ),
          ),
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
                              color: CosmoPalette.highlight.withValues(
                                alpha: 0.8,
                              ),
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
                                color: CosmoPalette.highlight.withValues(
                                  alpha: 0.7,
                                ),
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
                      horizontal: 14,
                      vertical: 6,
                    ),
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
              shadows: [Shadow(color: Color(0xAAFFD37B), blurRadius: 22)],
            ),
            const SizedBox(height: 6),
            const Text(
              'PILOT CERTIFIED',
              style: TextStyle(
                color: Color(0xFFFFD37B),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                shadows: [Shadow(color: Color(0xAAFFD37B), blurRadius: 18)],
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
                shadows: [Shadow(color: Color(0xCC05060F), blurRadius: 8)],
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
              shadows: [Shadow(color: Color(0xAAFFD37B), blurRadius: 22)],
            ),
            SizedBox(height: 6),
            Text(
              'REVIVED',
              style: TextStyle(
                color: Color(0xFFFFD37B),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                shadows: [Shadow(color: Color(0xAAFFD37B), blurRadius: 18)],
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
                shadows: [Shadow(color: Color(0xCC05060F), blurRadius: 8)],
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
          variant: secondary
              ? NeonButtonVariant.outline
              : NeonButtonVariant.solid,
        ),
      ),
    );
  }
}
