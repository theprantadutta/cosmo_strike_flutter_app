import 'dart:async';

import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// What positive moment is asking for a review.
///
/// Each trigger has its own eligibility threshold so we don't burn the
/// platform's annual prompt cap on weak signals. Cap is shared across triggers
/// (one prompt per [_minDaysBetweenPrompts] regardless of which fired it).
enum ReviewTrigger {
  /// User just beat their personal best. Strongest positive signal.
  newHighScore,

  /// User just unlocked a non-trivial achievement (rare+).
  achievementUnlocked,
}

/// Wraps the platform in-app review API with a local eligibility gate.
///
/// Google Play / StoreKit each throttle to ~3–4 prompts/year and silently
/// no-op if exceeded — neither store reports whether the dialog actually
/// rendered or what the rating was. This service adds a thinner local gate on
/// top so we never *ask* the platform during a bad moment.
///
/// Wire callers via [maybeRequestReview]; eligibility, delay, and dispatch
/// all live in this class. The platform decides if a dialog actually shows.
class ReviewService {
  /// Stop asking once the platform's annual cap is likely hit. The Play
  /// store typically caps ~3–4 in-app reviews per year per user, so 60 days
  /// between local prompts leaves headroom.
  static const Duration _minDaysBetweenPrompts = Duration(days: 60);

  /// New installs need a baseline of play before being prompted.
  /// 8 lifetime games × ~2 min each ≈ 15+ minutes of engagement.
  static const int _minLifetimeGames = 8;

  /// Don't prompt anyone who installed less than this ago — even if they
  /// somehow blasted through 8 games on day 1, that's not "I love this app"
  /// territory yet.
  static const Duration _minDaysSinceFirstPlay = Duration(days: 3);

  /// Delay before triggering the OS dialog after the eligibility check
  /// passes. Lets celebration audio + animation finish first so the prompt
  /// lands during a satisfied moment instead of interrupting one.
  static const Duration _promptDelay = Duration(milliseconds: 1800);

  static const String _kLastPromptedAtMillisKey = 'review_last_prompted_at';
  static const String _kEligibilityTag = '[ReviewService]';

  final InAppReview _inAppReview;
  final StatisticsService _statisticsService;
  final AnalyticsFacade _analytics;

  Timer? _pendingPromptTimer;

  ReviewService({
    InAppReview? inAppReview,
    required StatisticsService statisticsService,
    required AnalyticsFacade analytics,
  })  : _inAppReview = inAppReview ?? InAppReview.instance,
        _statisticsService = statisticsService,
        _analytics = analytics;

  /// Ask the platform to consider showing a review prompt, if [trigger] is
  /// strong enough and the user has crossed the local eligibility gates.
  ///
  /// Always fire-and-forget safe. Returns whether the request was actually
  /// dispatched to the platform — `false` means we filtered it locally.
  /// A `true` return does *not* guarantee a dialog was shown; the platform
  /// silently no-ops if its own cap is hit.
  Future<bool> maybeRequestReview(ReviewTrigger trigger) async {
    try {
      if (!await _isEligible(trigger)) return false;

      // Stamp the timestamp BEFORE the delayed call. If anything cancels or
      // crashes the timer, we'd rather skip the next eligible moment than
      // risk firing twice in a row.
      await _recordPromptScheduled();

      _pendingPromptTimer?.cancel();
      _pendingPromptTimer = Timer(_promptDelay, () => _dispatch(trigger));
      return true;
    } catch (e) {
      AppLogger.info('$_kEligibilityTag request errored: $e');
      return false;
    }
  }

  Future<bool> _isEligible(ReviewTrigger trigger) async {
    // Per-trigger guards — keeps weak signals from burning the local cap.
    if (trigger == ReviewTrigger.achievementUnlocked) {
      // newHighScore is always a strong-enough signal on its own; the caller
      // for achievementUnlocked has already filtered by rarity ≥ rare. No
      // extra per-trigger gate to add here yet, but the branch is here so
      // future triggers can plug in their own conditions.
    }

    final stats = _statisticsService.statistics;

    if (stats.totalGamesPlayed < _minLifetimeGames) {
      AppLogger.info(
        '$_kEligibilityTag skip ($trigger): only ${stats.totalGamesPlayed} '
        'games played, need $_minLifetimeGames',
      );
      return false;
    }

    final firstPlayed = stats.firstPlayedDate;
    if (firstPlayed != null &&
        DateTime.now().difference(firstPlayed) < _minDaysSinceFirstPlay) {
      AppLogger.info(
        '$_kEligibilityTag skip ($trigger): first played '
        '${DateTime.now().difference(firstPlayed).inHours}h ago, need '
        '${_minDaysSinceFirstPlay.inDays}d',
      );
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastPromptedMillis = prefs.getInt(_kLastPromptedAtMillisKey);
    if (lastPromptedMillis != null) {
      final lastPrompted =
          DateTime.fromMillisecondsSinceEpoch(lastPromptedMillis);
      final sinceLast = DateTime.now().difference(lastPrompted);
      if (sinceLast < _minDaysBetweenPrompts) {
        AppLogger.info(
          '$_kEligibilityTag skip ($trigger): last prompt '
          '${sinceLast.inDays}d ago, need ${_minDaysBetweenPrompts.inDays}d',
        );
        return false;
      }
    }

    // Platform availability check last — it's the only async I/O we don't
    // already need, and the cheaper gates above filter most calls.
    if (!await _inAppReview.isAvailable()) {
      AppLogger.info(
        '$_kEligibilityTag skip ($trigger): platform reports review API '
        'unavailable (debug build, sideloaded APK, or device without Play)',
      );
      return false;
    }

    return true;
  }

  Future<void> _recordPromptScheduled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kLastPromptedAtMillisKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _dispatch(ReviewTrigger trigger) async {
    try {
      AppLogger.info('$_kEligibilityTag requesting review (trigger: $trigger)');
      _analytics.trackReviewRequested(trigger.name);
      await _inAppReview.requestReview();
    } catch (e) {
      AppLogger.info('$_kEligibilityTag platform request failed: $e');
    }
  }

  void dispose() {
    _pendingPromptTimer?.cancel();
    _pendingPromptTimer = null;
  }
}
