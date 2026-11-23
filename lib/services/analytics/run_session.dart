import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

import '../../game/cosmo_strike_game.dart' show GamePhase, GameResult;
import '../../utils/constants.dart' show GameMode;
import '../first_run_service.dart';
import '../review_service.dart';
import '../telemetry/telemetry_service.dart';
import 'analytics_facade.dart';

/// Measurement for one run, so gameplay_screen only needs one-line hooks:
///
/// - `RunSession.begin(...)` at run start: fixes `run_number` (lifetime,
///   FirstRunService.gamesStarted incl. this run) and `onboarding`,
///   counts the telemetry `runs_started`, and listens to the game's phase to
///   catch revive offers (declined) and level clears (review prompt).
/// - `markFirstInput` from the steer/tap handlers → `first_input`
///   (install's first run only).
/// - `recordReviveOffer` from the revive handlers → `revive_offer`.
/// - `recordEnd(result)` at game over → `end_trigger` for `game_over`
///   (picked up by AnalyticsFacade.trackGameOver) + telemetry `runs_finished`.
/// - `recordQuit(partial)` on quit → `game_abandoned` + telemetry `runs_finished`.
class RunSession {
  RunSession._({
    required this.gameMode,
    required this.startLevel,
    required this.runNumber,
    required this.controlScheme,
    required this.previousBest,
    required this.timeLimitSeconds,
    required DateTime Function() clock,
    required AnalyticsFacade? analytics,
    required TelemetryService? telemetry,
    required ReviewService? review,
    required ValueListenable<GamePhase>? phase,
    required ValueListenable<int>? score,
  }) : _clock = clock,
       _analytics = analytics,
       _telemetry = telemetry,
       _review = review,
       _phase = phase,
       _score = score,
       startedAt = clock();

  /// The run being played (or the last one started).
  static RunSession? current;

  /// The last run that ended. game_over is logged a few awaits after the
  /// run ends, so its context comes from here even if a retry already
  /// began a new session.
  static RunSession? lastEnded;

  final String gameMode;
  final int startLevel;

  /// Lifetime run number on this install, 1 = first run ever.
  final int runNumber;

  /// Selected steering scheme: `drag` or `dpad`.
  final String controlScheme;
  final int previousBest;

  /// Time Attack clock length, null for untimed modes.
  final int? timeLimitSeconds;
  final DateTime startedAt;

  final DateTime Function() _clock;
  final AnalyticsFacade? _analytics;
  final TelemetryService? _telemetry;
  final ReviewService? _review;
  final ValueListenable<GamePhase>? _phase;
  final ValueListenable<int>? _score;

  bool _firstInputDone = false;
  bool _reviveOffered = false;
  bool _reviveTracked = false;
  bool _ended = false;
  String? _endTrigger;

  /// One of the install's first [FirstRunService.onboardingGameCount] runs.
  bool get onboarding => runNumber <= FirstRunService.onboardingGameCount;

  /// How the run ended ([EndTrigger]), null while it is running.
  String? get endTrigger => _endTrigger;

  /// Starts measuring a run. Call once per run, after
  /// `FirstRunService.recordGameStarted()` (its counter bumps
  /// synchronously, so it already includes this run).
  static RunSession begin({
    required GameMode mode,
    required int startLevel,
    required String controlScheme,
    int previousBest = 0,
    ValueListenable<GamePhase>? phase,
    ValueListenable<int>? score,
    int? runNumber,
    AnalyticsFacade? analytics,
    TelemetryService? telemetry,
    ReviewService? review,
    DateTime Function()? clock,
  }) {
    current?._detach();
    final getIt = GetIt.I;
    final session = RunSession._(
      gameMode: mode.wireName,
      startLevel: startLevel,
      runNumber: runNumber ?? FirstRunService.instance.gamesStarted,
      controlScheme: controlScheme,
      previousBest: previousBest,
      timeLimitSeconds: mode.timeLimit?.inSeconds,
      clock: clock ?? DateTime.now,
      analytics:
          analytics ??
          (getIt.isRegistered<AnalyticsFacade>()
              ? getIt<AnalyticsFacade>()
              : null),
      telemetry: telemetry ?? TelemetryService.instance,
      review:
          review ??
          (getIt.isRegistered<ReviewService>() ? getIt<ReviewService>() : null),
      phase: phase,
      score: score,
    );
    current = session;
    AnalyticsFacade.runContext = contextForAnalytics;
    session._phase?.addListener(session._onPhase);
    unawaited(session._telemetry?.runStarted(level: startLevel));
    return session;
  }

  /// Context AnalyticsFacade adds to game_over / game_abandoned.
  static RunAnalyticsContext? contextForAnalytics() {
    final s = lastEnded ?? current;
    if (s == null) return null;
    return (
      runNumber: s.runNumber,
      onboarding: s.onboarding,
      endTrigger: s._endTrigger,
    );
  }

  /// First steer / tap of the run; logs `first_input` on the install's
  /// first run only. Cheap after the first call (called per pan update).
  void markFirstInput(String input) {
    if (_firstInputDone) return;
    _firstInputDone = true;
    if (runNumber != 1) return;
    unawaited(
      _analytics?.trackFirstInput(
        secondsSinceRunStart: _clock().difference(startedAt).inSeconds,
        controlScheme: controlScheme,
        input: input,
      ),
    );
  }

  /// How the revive offer ended ([ReviveOutcome]). First call wins, so the
  /// countdown's `timeout` isn't overwritten by the `declined` that follows.
  void recordReviveOffer(String outcome) {
    if (_reviveTracked) return;
    _reviveTracked = true;
    if (outcome != ReviveOutcome.skippedOnboarding) {
      // A paid continue is an ad/purchase moment: keep the review prompt off.
      ReviewService.noteInterruption();
    }
    unawaited(
      _analytics?.trackReviveOffer(outcome: outcome, runNumber: runNumber),
    );
  }

  /// The run reached game over (death, time-out or victory).
  void recordEnd(GameResult result) {
    if (_ended) return;
    _ended = true;
    _endTrigger = endTriggerFor(
      cleared: result.cleared,
      durationSeconds: result.durationSeconds,
      timeLimitSeconds: timeLimitSeconds,
    );
    lastEnded = this;
    unawaited(
      _telemetry?.runFinished(
        level: result.stageReached,
        seconds: result.durationSeconds,
      ),
    );
    // Victory is a positive end with no death. Skipped on a new best: the
    // deferred sign-in prompt owns that game-over moment.
    if (result.cleared && result.score <= previousBest) {
      unawaited(
        _review?.maybeAskForReview(
          ReviewTrigger.victory,
          stillAppropriate: () =>
              identical(current, this) &&
              _phase?.value == GamePhase.gameOver,
        ),
      );
    }
  }

  /// The run was abandoned mid-play (quit / restart from pause).
  void recordQuit(GameResult partial) {
    if (_ended) return;
    _ended = true;
    _endTrigger = EndTrigger.quit;
    lastEnded = this;
    unawaited(
      _analytics?.trackGameAbandoned(
        score: partial.score,
        durationSeconds: partial.durationSeconds,
        stageReached: partial.stageReached,
        levelsCleared: partial.levelsCleared,
        gameMode: gameMode,
        runNumber: runNumber,
        onboarding: onboarding,
      ),
    );
    unawaited(
      _telemetry?.runFinished(
        level: partial.stageReached,
        seconds: partial.durationSeconds,
      ),
    );
  }

  /// `end_trigger` for a finished run.
  static String endTriggerFor({
    required bool cleared,
    required int durationSeconds,
    int? timeLimitSeconds,
  }) {
    if (cleared) return EndTrigger.victory;
    // Time Attack: the clock ending the run (allow a second of rounding).
    if (timeLimitSeconds != null && durationSeconds >= timeLimitSeconds - 1) {
      return EndTrigger.time;
    }
    return EndTrigger.death;
  }

  void _onPhase() {
    final phase = _phase?.value;
    switch (phase) {
      case GamePhase.reviveOffer:
        _reviveOffered = true;
        // A lost ship: never ask for a review right after it.
        ReviewService.noteInterruption();
      case GamePhase.gameOver:
        if (_reviveOffered && !_reviveTracked) {
          recordReviveOffer(ReviveOutcome.declined);
        }
      case GamePhase.levelClear:
        _askReviewAtLevelClear();
      default:
        break;
    }
  }

  void _askReviewAtLevelClear() {
    final review = _review;
    if (review == null) return;
    final score = _score?.value ?? 0;
    final trigger = previousBest > 0 && score > previousBest
        ? ReviewTrigger.newHighScore
        : ReviewTrigger.levelCleared;
    unawaited(
      review.maybeAskForReview(
        trigger,
        stillAppropriate: () =>
            identical(current, this) && _phase?.value == GamePhase.levelClear,
      ),
    );
  }

  void _detach() => _phase?.removeListener(_onPhase);

  @visibleForTesting
  static void debugReset() {
    current?._detach();
    current = null;
    lastEnded = null;
    AnalyticsFacade.runContext = null;
  }
}
