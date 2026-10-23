import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/game/cosmo_palette.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../game/components/power_up.dart';
import '../game/levels/level_def.dart';
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
import '../models/achievement.dart' show RunCommendationStats;
import '../services/achievement_service.dart';
import '../utils/campaign_catalog.dart';
import '../services/ads/ad_service.dart';
import '../services/analytics/analytics_facade.dart';
import '../services/audio_service.dart';
import '../services/daily_challenge_service.dart';
import '../services/statistics_service.dart';
import '../services/tournament_service.dart';
import '../services/weekly_quest_service.dart';
import '../services/haptic_service.dart';
import '../services/hangar_service.dart';
import '../services/walkthrough_service.dart';
import '../ui/cs.dart';
import '../ui/design/immersive.dart';
import '../widgets/game_dpad.dart';
import '../widgets/gameplay/game_over_overlay.dart';
import '../widgets/gameplay/level_complete_overlay.dart';
import '../widgets/gameplay/pause_overlay.dart';
import '../widgets/gameplay/upgrade_draft_overlay.dart';
import '../game/run_upgrades.dart';
import '../widgets/reward_toast.dart';
import 'package:cosmo_strike_flutter_app/services/first_run_service.dart';
import 'package:cosmo_strike_flutter_app/widgets/deferred_sign_in_prompt.dart';
import 'package:cosmo_strike_flutter_app/utils/privacy_policy.dart';

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
  String _gameModeName = GameMode.sortie.wireName;
  GameMode _mode = GameMode.sortie;
  int? _dailySeed;

  /// First-run tutorial: true when this run opened with the guided beats.
  bool _tutorialRun = false;

  /// Drives the PILOT CERTIFIED celebration overlay after the tutorial's
  /// final beat (auto-dismisses).
  bool _showCertified = false;

  /// Drives the gold REVIVED flourish after a paid continue (auto-dismisses).
  bool _showRevived = false;

  /// The 3 upgrade options shown after CONTINUE on a level clear; null when
  /// the level-complete debrief is showing.
  List<UpgradeDef>? _draft;

  /// Coins granted for finishing the tutorial — the celebration overlay
  /// shows the same number it actually pays out.
  static const int _tutorialRewardCoins = 150;

  /// Coins this run actually earned (set by _submitRun) — the game-over
  /// "watch ad → 2× coins" offer pays out exactly this amount again.
  int _runCoinsEarned = 0;

  /// Overdrive activations this run (counted from [CosmoStrikeGame.onOverdrive]
  /// for lifetime stats + commendations).
  int _runOverdrives = 0;

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
    // detail screen / Daily Run before launching). Held for the screen's
    // lifetime so the game-over submit attributes the score to the right
    // tournament.
    try {
      _tournamentContext = context.read<TournamentContextCubit>();
      _tournamentId = _tournamentContext?.state.tournamentId;
      _dailySeed = _tournamentContext?.state.dailySeed;
    } catch (_) {
      _tournamentContext = null;
      _tournamentId = null;
    }
    // A tournament plays under ITS rules, not the player's chosen mode.
    _mode = _tournamentContext?.state.mode ?? settings.gameMode;
    _gameModeName = _mode.wireName;

    // First-run bookkeeping: counts toward the onboarding window (gates the
    // deferred asks), and starting a run accepts the privacy notice shown
    // on Home (notice-and-continue).
    unawaited(FirstRunService.instance.recordGameStarted());
    unawaited(PrivacyPolicy.recordAccepted());

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

    // Engagement funnel: one game_started per run (game_over fires from
    // _submitRun with the run's results).
    unawaited(
      GetIt.I<AnalyticsFacade>().trackGameStarted(
        gameMode: _gameModeName,
        startLevel: widget.startLevel,
      ),
    );

    // Equipped cosmetics (skin tint + trail stream) — snapshot at run
    // start, same as the control settings.
    final premium = context.read<PremiumCubit>().state;
    final themeState = context.read<ThemeCubit>().state;
    // Pre-run best for the game-over NEW RECORD comparison.
    _prevBestScore = settings.highScore;
    // Purchased colour themes tint gameplay only (menus stay Prism Noir):
    // ship stripe, thrust, shots and the battlefield washes.
    CosmoPalette.applyGameTheme(themeState.currentTheme);

    // The selected game mode is a MODIFIER on top of the campaign level
    // (lives, pacing, enemy fire, drops, one-hit, Time Attack clock).
    // Snapshot at run start.
    _game = CosmoStrikeGame(
      onGameOver: _handleGameOver,
      onLevelCleared: _handleLevelCleared,
      mode: _mode,
      seed: _dailySeed,
      hangar: HangarService.instance.loadout,
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
    _game.onOverdrive = () {
      _runOverdrives++;
      unawaited(GetIt.I<AnalyticsFacade>().trackPowerUpUsed('overdrive'));
    };
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
    unawaited(HangarService.instance.load()); // new ship frames may unlock
    // The run total so far is a real score the moment a level is cleared —
    // record it now so BEST is right even if the player quits from the
    // level-clear screen (which never reaches game over).
    // updateHighScore never lowers the stored value.
    unawaited(_recordRunScore());
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
    // _prevBestScore is the best from BEFORE this run (snapshotted when the
    // run started) — level clears may already have raised the stored value.
    // Capture cubit references synchronously (no BuildContext across awaits).
    _submitRun(
      result,
      context.read<GameSettingsCubit>(),
      context.read<CoinsCubit>(),
      context.read<BattlePassCubit>(),
    );
    // New personal best: after the score reveal, nudge guests to save their
    // progress (budgeted inside the prompt). Skipped if they've already
    // tapped Retry/Exit by then.
    if (result.score > _prevBestScore) {
      Future.delayed(const Duration(milliseconds: 2400), () {
        if (mounted && _game.phaseNotifier.value == GamePhase.gameOver) {
          DeferredSignInPrompt.maybeShow(context);
        }
      });
    }
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
    // enemies_killed wire type.
    final modeName = _mode.wireName;
    unawaited(
      DailyChallengeService().updateProgressBatch([
        (type: ChallengeType.score, value: r.score, gameMode: null),
        (type: ChallengeType.enemiesKilled, value: r.enemiesKilled, gameMode: null),
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
            type: WeeklyQuestType.enemiesKilled,
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
    // Engagement funnel: the run's terminal analytics event (pairs with the
    // game_started fired in initState).
    unawaited(
      GetIt.I<AnalyticsFacade>().trackGameOver(
        score: r.score,
        durationSeconds: r.durationSeconds,
        stageReached: r.stageReached,
        levelsCleared: r.levelsCleared,
        enemiesKilled: r.enemiesKilled,
        maxCombo: r.maxCombo,
        victory: r.cleared,
        gameMode: modeName,
      ),
    );

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
        overdrives: _runOverdrives,
        formationWipes: _game.formationWipes,
        dailyRun: _dailySeed != null,
        cupRun: tournamentId != null,
        gameMode: modeName,
      );
    } catch (_) {}

    // Commendations: evaluated after the stats fold so lifetime metrics
    // include this run (the debrief watches AchievementService).
    try {
      final cleared = r.levelResults.where((lr) => lr.cleared).toList();
      await AchievementService().evaluateRun(
        RunCommendationStats(
          gameMode: modeName,
          score: r.score,
          kills: r.enemiesKilled,
          bosses: r.bossesKilled,
          maxChain: r.maxCombo,
          grazes: r.grazeCount,
          formationWipes: _game.formationWipes,
          durationSeconds: r.durationSeconds,
          levelsCleared: r.levelsCleared,
          upgradesDrafted: r.upgrades.length,
          flawlessCampaign: cleared.length >= CampaignCatalog.totalLevels &&
              cleared.every((lr) => lr.noHit),
          endedAt: DateTime.now(),
        ),
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
          // Enum identifier: display labels ("Zen Mode") fail backend
          // validation and the score was silently dropped.
          'game_mode': _game.mode.wireName,
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
      // Quitting keeps the points earned so far as a high-score candidate.
      unawaited(_recordRunScore());
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

  /// Offline-first high-score update from the live run total.
  Future<void> _recordRunScore() async {
    try {
      await context.read<GameSettingsCubit>().updateHighScore(_game.scoreNotifier.value);
    } catch (_) {}
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
            showCsToast(
              context,
              'Ad not ready. Use credits instead.',
              kind: CsToastKind.error,
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
            itemName: 'Debrief 2× credits',
            metadata: const {'placement': 'game_over_double'},
          ),
        );
        RewardToast.show(title: 'CREDITS DOUBLED', amount: '+$earned CR');
        if (mounted) setState(() => _coinsDoubled = true);
      },
    );
    if (!shown && mounted) {
      showCsToast(
        context,
        'Ad not ready. Try again shortly.',
        kind: CsToastKind.error,
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
  /// CONTINUE on the level-clear debrief: offer the upgrade draft first
  /// (skipped only if every upgrade is maxed).
  void _openDraft() {
    final options = _game.rollDraft();
    if (options.isEmpty) {
      _advanceWithInterstitial();
      return;
    }
    setState(() => _draft = options);
  }

  void _onUpgradePicked(UpgradeId id) {
    _game.takeUpgrade(id);
    unawaited(GetIt.I<AnalyticsFacade>().trackPowerUpUsed('upgrade_${id.name}'));
    setState(() => _draft = null);
    _advanceWithInterstitial();
  }

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
        RewardToast.show(title: 'HULL RESTORED', amount: '+1 SHIP');
      },
    );
    if (!shown && mounted) {
      showCsToast(
        context,
        'Ad not ready. Try again shortly.',
        kind: CsToastKind.error,
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
      showCsToast(context, 'Not enough credits.', kind: CsToastKind.error);
    }
  }

  /// Pink edge vignette for the landed-hit pulse — const so the 450ms pulse
  /// only animates an opacity, never re-allocates a gradient per frame.
  static const RadialGradient _hitVignette = RadialGradient(
    radius: 1.15,
    colors: [Color(0x00FF8AD8), Color(0x4DFF8AD8)],
    stops: [0.55, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final dPadOnRight =
        _dPadEnabled && _dPadPosition == DPadPosition.bottomRight;
    final dPadOnLeft = _dPadEnabled && _dPadPosition == DPadPosition.bottomLeft;
    final dPadCenter =
        _dPadEnabled && _dPadPosition == DPadPosition.bottomCenter;

    // HUD inset (28 in the design frame) and the bottom-corner controls'
    // footprint, so the boss bar never runs under the missile button or
    // the d-pad.
    final inset = cs(CsSpace.hud);
    final missileSize = _OverdriveButton.sizeFor(cs);
    const dPad = GameDPad.defaultDiameter;
    final gap = cs(24);
    final leftReserve = dPadOnRight
        ? missileSize + gap
        : (dPadOnLeft ? dPad + gap : 0.0);
    final rightReserve = dPadOnRight ? dPad + gap : missileSize + gap;
    final bossLift = dPadCenter ? dPad + cs(12) : 0.0;

    return Scaffold(
      backgroundColor: CsColors.bgGame,
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

                // Pink edge vignette pulse on every landed hit — shake-setting
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
                        builder: (_, t, child) {
                          if (t <= 0.01) return const SizedBox.shrink();
                          return Opacity(opacity: t, child: child);
                        },
                        child: const SizedBox.expand(
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: _hitVignette),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Hidden under the full-screen result overlays: their scrim
                // is 95% opaque, so the white HUD ghosted through behind
                // the GAME OVER / revive headers.
                ValueListenableBuilder<GamePhase>(
                  valueListenable: _game.phaseNotifier,
                  builder: (context, phase, hud) => Offstage(
                    offstage: phase == GamePhase.levelClear ||
                        phase == GamePhase.reviveOffer ||
                        phase == GamePhase.gameOver,
                    child: hud,
                  ),
                  child: SafeArea(
                    child: _Hud(
                      game: _game,
                      bossLeftReserve: leftReserve,
                      bossRightReserve: rightReserve,
                      bossLift: bossLift,
                    ),
                  ),
                ),

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
                        padding: EdgeInsets.symmetric(
                          horizontal: inset,
                          vertical: cs(20),
                        ),
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
                      // Same inset on both axes so the cluster sits square
                      // in its corner.
                      padding: EdgeInsets.all(inset),
                      child: _ActionButtons(game: _game),
                    ),
                  ),
                ),

                // White flash (boss kill, Overdrive).
                ValueListenableBuilder<int>(
                  valueListenable: _game.flashNotifier,
                  builder: (_, n, _) {
                    if (n == 0) return const SizedBox.shrink();
                    return IgnorePointer(
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(n),
                        tween: Tween(begin: 0.55, end: 0),
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOut,
                        builder: (_, t, _) {
                          if (t <= 0.01) return const SizedBox.shrink();
                          return ColoredBox(
                            color: Color.fromRGBO(255, 255, 255, t),
                            child: const SizedBox.expand(),
                          );
                        },
                      ),
                    );
                  },
                ),

                // Boss WARNING banner.
                ValueListenableBuilder<bool>(
                  valueListenable: _game.bossWarningNotifier,
                  builder: (_, on, _) {
                    if (!on) return const SizedBox.shrink();
                    return IgnorePointer(
                      child: _BossWarning(name: _bossName(_game.level.boss.type)),
                    );
                  },
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

                // Set-piece callout ("CANYON RUN") — small banner that never
                // blocks input.
                ValueListenableBuilder<String?>(
                  valueListenable: _game.calloutNotifier,
                  builder: (context, callout, _) {
                    if (callout == null) return const SizedBox.shrink();
                    return IgnorePointer(
                      child: SafeArea(child: _Callout(text: callout)),
                    );
                  },
                ),

                // First-run tutorial prompt — a floating instruction caption at
                // the top of the playfield. Input passes straight through to
                // the game except for the Skip button.
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
                  const IgnorePointer(
                    child: _Flourish(
                      icon: Symbols.military_tech_rounded,
                      title: 'Pilot certified',
                      coins: _tutorialRewardCoins,
                    ),
                  ),

                // REVIVED flourish after a paid continue — pure celebration,
                // never blocks input, auto-dismisses.
                if (_showRevived)
                  const IgnorePointer(
                    child: _Flourish(
                      icon: Symbols.rocket_launch_rounded,
                      title: 'Revived',
                      caption: '+1 SHIP',
                    ),
                  ),

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
                        final draft = _draft;
                        if (draft != null) {
                          return UpgradeDraftOverlay(
                            options: draft,
                            upgrades: _game.upgrades,
                            nextLevel: _game.levelIndex + 1,
                            onPick: _onUpgradePicked,
                          );
                        }
                        return LevelCompleteOverlay(
                          game: _game,
                          outcome: _outcomes[_game.levelIndex],
                          priorBest: _priorBest[_game.levelIndex],
                          onContinue: _openDraft,
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
                          // (retry toast). Swaps to a confirmation once claimed.
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

String _two(int v) => v.toString().padLeft(2, '0');

/// Display names for the boss HP readout.
String _bossName(BossType type) => switch (type) {
  BossType.dreadnought => 'Iron Dreadnought',
  BossType.hiveQueen => 'Hive Queen',
  BossType.warMachine => 'War Machine',
  BossType.leviathan => 'Leviathan',
  BossType.mothership => 'Mothership',
};

/// The in-play HUD (Prism Noir s03), inset 28 (scaled) inside the landscape
/// SafeArea:
///   top-left     score (Syne 44) · L03 / W04 + KILLS mono, 200×2 hull bar,
///                active power-up chips
///   top-right    life pips (22×4) + 42px outlined pause, chain popup below
///   bottom       boss name + % mono over a 3px prism HP bar (boss alive only)
/// Only the pause button takes input; every readout ignores pointers so taps
/// fall through to the playfield. Each frequently-changing readout listens
/// to its own notifier inside a RepaintBoundary.
class _Hud extends StatelessWidget {
  const _Hud({
    required this.game,
    required this.bossLeftReserve,
    required this.bossRightReserve,
    required this.bossLift,
  });

  final CosmoStrikeGame game;

  /// Horizontal space kept clear of the boss bar for the bottom-corner
  /// controls (missile button / d-pad).
  final double bossLeftReserve;
  final double bossRightReserve;

  /// Extra lift when a bottom-center d-pad occupies the boss bar's lane.
  final double bossLift;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final inset = cs(CsSpace.hud);
    return Stack(
      children: [
        Positioned(
          left: inset,
          top: cs(20),
          child: IgnorePointer(child: _ScoreBlock(game: game)),
        ),
        Positioned(
          right: inset,
          top: cs(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IgnorePointer(child: _LifePips(game: game)),
                  SizedBox(width: cs(14)),
                  CsIconButton(
                    icon: Symbols.pause_rounded,
                    tooltip: 'Pause',
                    onPressed: game.pauseGame,
                  ),
                ],
              ),
              SizedBox(height: cs(14)),
              IgnorePointer(child: _ChainPopup(game: game)),
            ],
          ),
        ),
        Positioned(
          left: inset + bossLeftReserve,
          right: inset + bossRightReserve,
          bottom: cs(26) + bossLift,
          child: IgnorePointer(child: _BossBar(game: game)),
        ),
      ],
    );
  }
}

/// Score + level/wave/kills meta (+ Time Attack clock) over the 200×2 hull
/// energy bar, then the active timed-effect chips.
class _ScoreBlock extends StatelessWidget {
  const _ScoreBlock({required this.game});
  final CosmoStrikeGame game;

  static const LinearGradient _lowHull = LinearGradient(
    colors: [CsColors.pink, CsColors.pink],
  );

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final meta = t.mono(11, em: 0.12, color: CsColors.ink60, height: 1.2);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            RepaintBoundary(
              child: ValueListenableBuilder<int>(
                valueListenable: game.scoreNotifier,
                builder: (_, score, _) =>
                    Text('$score', maxLines: 1, style: t.hudScore),
              ),
            ),
            SizedBox(width: cs(18)),
            Padding(
              padding: EdgeInsets.only(bottom: cs(3)),
              child: RepaintBoundary(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        game.levelNotifier,
                        game.waveNotifier,
                      ]),
                      builder: (_, _) => Text(
                        'L${_two(game.levelNotifier.value)} / '
                        'W${_two(game.waveNotifier.value)}',
                        style: meta,
                      ),
                    ),
                    SizedBox(height: cs(4)),
                    // Kill tally — many daily directives are kill-based.
                    ValueListenableBuilder<int>(
                      valueListenable: game.killsNotifier,
                      builder: (_, kills, _) =>
                          Text('KILLS $kills', style: meta),
                    ),
                    // Time Attack countdown — hidden in modes without a clock.
                    ValueListenableBuilder<int>(
                      valueListenable: game.timeRemainingNotifier,
                      builder: (_, secs, _) {
                        if (secs < 0) return const SizedBox.shrink();
                        final m = secs ~/ 60;
                        final s = _two(secs % 60);
                        return Padding(
                          padding: EdgeInsets.only(top: cs(4)),
                          child: Text(
                            'TIME $m:$s',
                            style: meta.copyWith(
                              color: secs <= 30 ? CsColors.pink : CsColors.ink,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: cs(10)),
        // Hull energy — the 200×2 line under the score; turns pink when low.
        ValueListenableBuilder<double>(
          valueListenable: game.healthNotifier,
          builder: (_, hp, _) => CsProgressLine(
            value: hp,
            width: cs(200),
            gradient: hp <= 0.3 ? _lowHull : CsGradients.progress,
          ),
        ),
        SizedBox(height: cs(10)),
        RepaintBoundary(
          child: ValueListenableBuilder<List<ActiveEffectHud>>(
            valueListenable: game.effectsNotifier,
            builder: (_, effects, _) {
              if (effects.isEmpty) return const SizedBox.shrink();
              return Wrap(
                spacing: cs(6),
                runSpacing: cs(6),
                children: [for (final e in effects) _EffectChip(effect: e)],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Life pips: 22×4 bars, lit = ink, lost = 18% white. A lost life flashes
/// pink and fades out in its slot, with a mono "SHIP DOWN" tag dropping in
/// below — losing a life is never silent.
class _LifePips extends StatefulWidget {
  const _LifePips({required this.game});
  final CosmoStrikeGame game;

  @override
  State<_LifePips> createState() => _LifePipsState();
}

class _LifePipsState extends State<_LifePips> {
  late int _shown;
  int _lossEvents = 0;

  static const Color _lost = Color(0x2EFFFFFF);

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
    final cs = context.cs;
    final total = math.max(widget.game.mode.runLives, _shown).clamp(1, 6);
    final w = cs(22);
    final h = cs(4).clamp(3.0, 6.0);

    Widget pip(int i) {
      final lit = i < _shown;
      // The slot that just emptied flashes pink before settling dim.
      if (!lit && i == _shown && _lossEvents > 0) {
        return TweenAnimationBuilder<double>(
          key: ValueKey(_lossEvents),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: CsMotion.standard,
          builder: (_, t, _) => Container(
            width: w,
            height: h,
            color: Color.lerp(CsColors.pink, _lost, t),
          ),
        );
      }
      return AnimatedContainer(
        duration: CsMotion.slow,
        curve: CsMotion.standard,
        width: w,
        height: h,
        color: lit ? CsColors.ink : _lost,
      );
    }

    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) SizedBox(width: cs(6)),
                pip(i),
              ],
            ],
          ),
          if (_lossEvents > 0)
            Positioned(
              right: 0,
              top: h + cs(8),
              child: TweenAnimationBuilder<double>(
                key: ValueKey(-_lossEvents),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1400),
                builder: (_, t, child) {
                  // Pop in fast, hold, fade at the tail.
                  final inT = (t * 6).clamp(0.0, 1.0);
                  final outT = ((t - 0.75) * 4).clamp(0.0, 1.0);
                  final alpha = inT * (1 - outT);
                  if (alpha <= 0.01) return const SizedBox.shrink();
                  return Opacity(
                    opacity: alpha,
                    child: Transform.translate(
                      offset: Offset(0, (1 - inT) * -6),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  'SHIP DOWN',
                  maxLines: 1,
                  style: cs.type.mono(10, em: 0.16, color: CsColors.pink),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kill-chain popup: prism "×2" (ink at ×1) + mono "CHAIN 12". Appears from
/// a 2-chain on and pops when the multiplier tier rises.
class _ChainPopup extends StatelessWidget {
  const _ChainPopup({required this.game});
  final CosmoStrikeGame game;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final multStyle = t.display(26, height: 1);
    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: game.combo.comboNotifier,
        builder: (_, chain, _) {
          if (chain < 2) return const SizedBox.shrink();
          return ValueListenableBuilder<int>(
            valueListenable: game.combo.multiplierNotifier,
            builder: (_, mult, _) => TweenAnimationBuilder<double>(
              key: ValueKey(mult),
              tween: Tween(begin: mult > 1 ? 1.3 : 1.0, end: 1.0),
              duration: CsMotion.base,
              curve: CsMotion.emphasis,
              builder: (_, s, child) => Transform.scale(
                scale: s,
                alignment: Alignment.centerRight,
                child: child,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (mult >= 2)
                    CsPrismText('×$mult', style: multStyle)
                  else
                    Text('×$mult', style: multStyle),
                  SizedBox(width: cs(10)),
                  Text(
                    'CHAIN $chain',
                    style: t.mono(12, em: 0.1, color: CsColors.ink),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Boss name + HP % (mono) over a 3px prism HP bar — only while a boss is
/// alive.
class _BossBar extends StatelessWidget {
  const _BossBar({required this.game});
  final CosmoStrikeGame game;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final style = cs.type.mono(11, em: 0.14, color: const Color(0xA6F4F3F7));
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: game.bossHealthNotifier,
        builder: (_, boss, _) {
          if (boss < 0) return const SizedBox.shrink();
          final hp = boss.clamp(0.0, 1.0);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _bossName(game.level.boss.type).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  SizedBox(width: cs(12)),
                  Text('${(hp * 100).round()}%', style: style),
                ],
              ),
              SizedBox(height: cs(8)),
              CsProgressLine(
                value: hp,
                height: cs(3).clamp(2.0, 4.0),
                gradient: CsGradients.prism,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Active timed power-up: glyph + a tiny 2px remaining-time line. Not
/// tweened — the notifier already updates continuously.
class _EffectChip extends StatelessWidget {
  const _EffectChip({required this.effect});
  final ActiveEffectHud effect;

  static const Map<String, IconData> _icons = {
    'weapon': Symbols.bolt_rounded,
    'x2': Symbols.close_rounded, // x glyph
    'speed': Symbols.speed_rounded,
    'slowmo': Symbols.slow_motion_video_rounded,
    'magnet': Symbols.attractions_rounded,
    'ghost': Symbols.blur_on_rounded,
    'shield': Symbols.shield_rounded, // post-revive protection window
  };

  static const ShapeDecoration _chip = ShapeDecoration(
    color: Color(0xB30A0A0D),
    shape: StadiumBorder(side: BorderSide(color: CsColors.hairline)),
  );

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final barW = cs(26);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: cs(9), vertical: cs(5)),
      decoration: _chip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _icons[effect.id] ?? Symbols.star_rounded,
            size: cs(13),
            color: CsColors.ink,
          ),
          SizedBox(width: cs(6)),
          SizedBox(
            width: barW,
            height: 2,
            child: ColoredBox(
              color: CsColors.track,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: barW * effect.remaining01.clamp(0.0, 1.0),
                  height: 2,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(gradient: CsGradients.progress),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 72px missile button: near-black disc, rocket glyph + "×N" ammo count,
/// ringed by the graze meter as a prism conic arc on a hairline track (a
/// full ring converts to +1 missile).
/// Bottom-corner actions: the Overdrive button (big, ring = meter) with the
/// missile launcher stacked above it.
class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.game});
  final CosmoStrikeGame game;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    // The smaller missile chip shares the Overdrive button's centre line;
    // edge-aligning both left them 13pt off-axis in the corner.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MissileChip(game: game),
        SizedBox(height: cs(10)),
        _OverdriveButton(game: game),
      ],
    );
  }
}

/// Small missile launcher: rocket + ammo; double-tap anywhere also fires.
class _MissileChip extends StatelessWidget {
  const _MissileChip({required this.game});
  final CosmoStrikeGame game;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final d = cs(46).clamp(44.0, 60.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: game.fireMissile,
      child: ValueListenableBuilder<int>(
        valueListenable: game.missileAmmoNotifier,
        builder: (_, ammo, _) {
          final c = ammo > 0 ? CsColors.ink : CsColors.ink30;
          return Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CsColors.bg.withValues(alpha: 0.6),
              border: Border.all(color: ammo > 0 ? CsColors.lineStrong : CsColors.hairline),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Symbols.rocket_rounded, size: d * 0.36, color: c),
                Text('×$ammo', style: cs.type.mono(9, em: 0.04, color: c, height: 1.1)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Overdrive: the ring fills from grazes; when full it spins prism and
/// pulses "TAP"; while active the ring drains in gold.
class _OverdriveButton extends StatelessWidget {
  const _OverdriveButton({required this.game});
  final CosmoStrikeGame game;

  /// Visual size, scaled but kept a comfortable thumb target.
  static double sizeFor(CsLayout cs) => cs(72).clamp(64.0, 96.0);

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final size = sizeFor(cs);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: game.activateOverdrive,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: size,
          child: ValueListenableBuilder<double>(
            valueListenable: game.overdriveNotifier,
            builder: (_, active, _) => ValueListenableBuilder<double>(
              valueListenable: game.combo.grazeNotifier,
              builder: (_, meter, _) {
                if (active > 0) {
                  return CsRingProgress(
                    value: active,
                    size: size,
                    stroke: 3,
                    trackColor: CsColors.hairline,
                    fill: CsColors.gold.withValues(alpha: 0.18),
                    child: _label(cs, size, Symbols.bolt_rounded, 'ACTIVE', CsColors.gold),
                  );
                }
                if (meter >= 1) {
                  return CsPrismRing(
                    circle: true,
                    rotate: true,
                    width: 3,
                    fill: CsColors.bg,
                    child: _ReadyPulse(
                      child: _label(cs, size, Symbols.bolt_rounded, 'TAP', CsColors.ink),
                    ),
                  );
                }
                return CsRingProgress(
                  value: meter,
                  size: size,
                  stroke: 2,
                  trackColor: CsColors.hairline,
                  fill: CsColors.bg.withValues(alpha: 0.6),
                  child: _label(cs, size, Symbols.bolt_rounded,
                      '${(meter * 100).round()}%', CsColors.ink45),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // Centered explicitly: CsPrismRing hands its child tight constraints, so
  // a bare Column would fill the ring and stack from the top.
  Widget _label(CsLayout cs, double size, IconData icon, String text, Color c) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: size * 0.36, color: c),
            Text(text, style: cs.type.mono(9, em: 0.1, color: c, height: 1.2)),
          ],
        ),
      );
}

class _ReadyPulse extends StatefulWidget {
  const _ReadyPulse({required this.child});
  final Widget child;

  @override
  State<_ReadyPulse> createState() => _ReadyPulseState();
}

class _ReadyPulseState extends State<_ReadyPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.06).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: widget.child,
      );
}

/// Boss WARNING: pink hazard rules around a Syne headline with the boss
/// name, sliding in mid-screen for the warning window.
class _BossWarning extends StatelessWidget {
  const _BossWarning({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return Align(
      alignment: const Alignment(0, -0.15),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: CsMotion.slow,
        curve: CsMotion.emphasis,
        builder: (_, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: 1.15 - 0.15 * v, child: child),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _hazardRule(cs),
            SizedBox(height: cs(12)),
            Text('WARNING', style: t.display(44, em: 0.12, height: 1, color: CsColors.pink)),
            SizedBox(height: cs(8)),
            Text(name.toUpperCase(), style: t.mono(13, em: 0.3, color: CsColors.ink)),
            SizedBox(height: cs(12)),
            _hazardRule(cs),
          ],
        ),
      ),
    );
  }

  Widget _hazardRule(CsLayout cs) => Container(
        width: cs(320),
        height: 2,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [
            Color(0x00FF8AD8),
            CsColors.pink,
            Color(0x00FF8AD8),
          ]),
        ),
      );
}

/// "LEVEL 03" mono + level name headline during the level intro phase.
class _LevelIntroBanner extends StatelessWidget {
  const _LevelIntroBanner({required this.game});
  final CosmoStrikeGame game;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: CsMotion.slow,
          curve: CsMotion.standard,
          builder: (context, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, cs(16) * (1 - v)),
              child: child,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: cs(48)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: game.levelNotifier,
                  builder: (_, level, _) => CsLabel(
                    'Level ${_two(level)} · ${game.seed != null ? 'Daily Run' : game.mode.name}',
                    color: CsColors.ink60,
                    size: 12,
                  ),
                ),
                SizedBox(height: cs(10)),
                ValueListenableBuilder<String>(
                  valueListenable: game.levelNameNotifier,
                  builder: (_, name, _) => FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      name,
                      maxLines: 1,
                      style: t.display(48, em: -0.04, height: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Set-piece callout ("CANYON RUN"): a short pink danger rule over a Syne
/// caption, popping in mid-upper playfield.
class _Callout extends StatelessWidget {
  const _Callout({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Align(
      alignment: const Alignment(0, -0.4),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(text),
        tween: Tween(begin: 0, end: 1),
        duration: CsMotion.slow,
        curve: CsMotion.emphasis,
        builder: (_, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.9 + 0.1 * v, child: child),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: cs(28), height: 2, color: CsColors.pink),
            SizedBox(height: cs(10)),
            Text(
              text.toUpperCase(),
              maxLines: 1,
              style: cs.type.display(24, em: 0.08, height: 1),
            ),
          ],
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
    final cs = context.cs;
    final t = cs.type;

    // Primary continue path: premium → free revive; free → watch an ad
    // (kept visible with a spinner while the ad loads, so the path is
    // always discoverable).
    final Widget primary;
    if (widget.isPremium) {
      primary = CsButton.primary(
        label: 'Free revive',
        icon: Symbols.workspace_premium_rounded,
        expand: true,
        onPressed: () => _resolve(widget.onFreeRevive),
      );
    } else if (widget.adReady) {
      primary = CsButton.primary(
        label: 'Watch ad · revive',
        icon: Symbols.play_arrow_rounded,
        expand: true,
        onPressed: _watchAd,
      );
    } else {
      primary = const CsButton.primary(
        label: 'Watch ad · loading',
        loading: true,
        expand: true,
      );
    }

    final status = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: cs(96),
          child: CustomPaint(
            painter: _CountdownPainter(_countdown, stroke: cs(3)),
            child: Center(
              child: AnimatedBuilder(
                animation: _countdown,
                builder: (_, _) => Text(
                  '${(_seconds * (1 - _countdown.value)).ceil()}',
                  style: t.display(34, height: 1),
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: cs(18)),
        const CsLabel('Ship down', color: CsColors.pink),
        SizedBox(height: cs(6)),
        Text(
          'Resume level ${widget.level}',
          maxLines: 1,
          style: t.display(36, em: -0.03, height: 1.05),
        ),
        SizedBox(height: cs(10)),
        Text(
          'SCORE ${widget.score}  ·  WAVE ${widget.wave}',
          maxLines: 1,
          style: t.mono(11, em: 0.12, color: CsColors.ink55),
        ),
      ],
    );

    final actions = SizedBox(
      width: cs(280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          SizedBox(height: cs(12)),
          // Universal credit fallback.
          CsButton.secondary(
            label: widget.coinsEnough ? 'Revive' : 'Not enough credits',
            expand: true,
            trailing: const CsCoins(200, size: 11),
            onPressed: widget.coinsEnough
                ? () => _resolve(widget.onSpendCoins)
                : null,
          ),
          SizedBox(height: cs(6)),
          CsButton.text(
            label: 'Give up',
            expand: true,
            onPressed: () => _resolve(widget.onGiveUp),
          ),
        ],
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const ColoredBox(color: CsColors.scrim),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.all(cs(24)),
            child: Center(
              // Landscape: status/countdown LEFT, continue actions RIGHT.
              // FittedBox is a safety net for very short screens.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    status,
                    SizedBox(width: cs(48)),
                    Container(
                      width: 1,
                      height: cs(170),
                      color: CsColors.hairline,
                    ),
                    SizedBox(width: cs(48)),
                    actions,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pink countdown arc on a hairline track; repaints straight off the
/// animation (no widget rebuilds, no shader allocation).
class _CountdownPainter extends CustomPainter {
  _CountdownPainter(this.animation, {required this.stroke})
    : super(repaint: animation);

  final Animation<double> animation;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = CsColors.track;
    canvas.drawCircle(c, r, track);
    final left = 1 - animation.value;
    if (left <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = CsColors.pink;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * left,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_CountdownPainter old) =>
      old.animation != animation || old.stroke != stroke;
}

/// First-run tutorial caption: a compact raised panel top-center (icon,
/// Syne title, body) with a text-button SKIP under it. The panel ignores
/// pointers so drag-steering and tap-to-fire work straight through it.
class _TutorialBanner extends StatelessWidget {
  const _TutorialBanner({required this.prompt, required this.onSkip});

  final TutorialPrompt prompt;
  final VoidCallback onSkip;

  static const ShapeDecoration _panel = ShapeDecoration(
    color: Color(0xE6141419),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(CsRadius.tile)),
      side: BorderSide(color: CsColors.lineSubtle),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: cs(16)),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(prompt.title),
          tween: Tween(begin: 0, end: 1),
          duration: CsMotion.slow,
          curve: CsMotion.standard,
          builder: (_, v, child) => Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -cs(8) * (1 - v)),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
                child: Container(
                  constraints: BoxConstraints(maxWidth: cs(440)),
                  padding: EdgeInsets.symmetric(
                    horizontal: cs(16),
                    vertical: cs(12),
                  ),
                  decoration: _panel,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(prompt.icon, size: cs(20), color: CsColors.cyan),
                      SizedBox(width: cs(12)),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              prompt.title.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.display(
                                14,
                                weight: FontWeight.w700,
                                em: 0.1,
                                height: 1.2,
                              ),
                            ),
                            SizedBox(height: cs(4)),
                            Text(
                              prompt.body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: t.body.copyWith(color: CsColors.ink70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (prompt.showSkip) ...[
                SizedBox(height: cs(4)),
                CsButton.text(
                  label: 'Skip tutorial',
                  size: CsButtonSize.small,
                  onPressed: onSkip,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Celebration flourish (PILOT CERTIFIED / REVIVED): gold glyph, Syne
/// headline and a coin or mono caption that scales in over the playfield;
/// removed by the screen after a beat. Wrapped in IgnorePointer by the caller.
class _Flourish extends StatelessWidget {
  const _Flourish({
    required this.icon,
    required this.title,
    this.coins,
    this.caption,
  });

  final IconData icon;
  final String title;
  final int? coins;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return Align(
      alignment: const Alignment(0, -0.4),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: CsMotion.slow,
        curve: CsMotion.emphasis,
        builder: (_, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.85 + 0.15 * v, child: child),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: cs(40), color: CsColors.gold),
            SizedBox(height: cs(8)),
            Text(title, maxLines: 1, style: t.display(34, height: 1)),
            SizedBox(height: cs(8)),
            if (coins != null)
              CsCoins(coins!, prefix: '+', suffix: ' CR', size: 12)
            else if (caption != null)
              Text(caption!, style: t.mono(12, em: 0.14, color: CsColors.gold)),
          ],
        ),
      ),
    );
  }
}
