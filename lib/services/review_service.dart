import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/debug/demo_mode.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/first_run_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// What positive moment is asking for a review.
enum ReviewTrigger {
  /// The run's score passed the player's previous best at a level clear.
  newHighScore,

  /// A campaign level's boss fell (level-clear summary on screen).
  levelCleared,

  /// The whole campaign was cleared (victory debrief, no death).
  victory,

  /// A non-trivial achievement unlocked (rare+). Not wired yet.
  achievementUnlocked,
}

/// The automatic review prompt's local gate, as a pure function so the
/// rules are testable. Returns null when a prompt may be requested, else a
/// short reason it was skipped.
///
/// Rules (chosen Nov 2026, see CLAUDE.md "Ratings"):
/// - never in DemoMode builds;
/// - the player finished onboarding (3 runs) AND has started at least
///   [minRuns] runs (FirstRunService, device-only) — the "6 runs" option,
///   not "3 sessions on different days": with D1 around 14% the day rule
///   would gate out almost everyone we can ask;
/// - at most once per [cooldown] (60 days; Play/StoreKit also throttle);
/// - not within [quietAfterInterruption] of a full-screen ad, a purchase
///   sheet or a lost ship (revive offer) — never right after a death, ad
///   or purchase.
abstract final class ReviewGate {
  static const int minRuns = 6;
  static const Duration cooldown = Duration(days: 60);
  static const Duration quietAfterInterruption = Duration(seconds: 90);

  static String? skipReason({
    required bool onboardingDone,
    required int runsStarted,
    required DateTime now,
    DateTime? lastPromptAt,
    DateTime? lastInterruptionAt,
    bool demo = DemoMode.enabled,
  }) {
    if (demo) return 'demo_mode';
    if (!onboardingDone) return 'onboarding';
    if (runsStarted < minRuns) return 'runs<$minRuns';
    if (lastPromptAt != null && now.difference(lastPromptAt) < cooldown) {
      return 'cooldown';
    }
    if (lastInterruptionAt != null &&
        now.difference(lastInterruptionAt) < quietAfterInterruption) {
      return 'recent_interruption';
    }
    return null;
  }
}

/// Wraps the platform in-app review API (Play In-App Review / StoreKit)
/// with the [ReviewGate].
///
/// Policy: we only ever call the native `requestReview()`. There is NO
/// custom "Do you like the game?" pre-dialog — filtering unhappy players
/// before the store sheet violates Google Play policy. The platform
/// decides whether a sheet actually shows and never tells us the result.
class ReviewService {
  /// Lets celebration audio/animation land before the OS sheet.
  static const Duration defaultPromptDelay = Duration(milliseconds: 1800);

  static const String _kLastPromptedAtMillisKey = 'review_last_prompted_at';
  static const String _tag = '[ReviewService]';

  static DateTime? _lastInterruptionAt;

  /// Marks a moment the review prompt must not follow closely: a
  /// full-screen ad, a purchase sheet, a lost ship. Called from AdService,
  /// PurchaseService and RunSession.
  static void noteInterruption([DateTime? at]) =>
      _lastInterruptionAt = at ?? DateTime.now();

  @visibleForTesting
  static void debugResetInterruption() => _lastInterruptionAt = null;

  final InAppReview _inAppReview;
  final AnalyticsFacade _analytics;
  final int Function() _runsStarted;
  final bool Function() _onboardingDone;
  final DateTime Function() _clock;
  final Duration _promptDelay;
  final bool _demo;

  bool _pending = false;
  Future<bool>? _pendingDispatch;

  ReviewService({
    InAppReview? inAppReview,
    required AnalyticsFacade analytics,
    int Function()? runsStarted,
    bool Function()? onboardingDone,
    DateTime Function()? clock,
    Duration promptDelay = defaultPromptDelay,
    bool demo = DemoMode.enabled,
  }) : _inAppReview = inAppReview ?? InAppReview.instance,
       _analytics = analytics,
       _runsStarted = runsStarted ?? (() => FirstRunService.instance.gamesStarted),
       _onboardingDone =
           onboardingDone ??
           (() => FirstRunService.instance.hasCompletedOnboarding),
       _clock = clock ?? DateTime.now,
       _promptDelay = promptDelay,
       _demo = demo;

  /// The single entry point for the automatic prompt. Call it at a
  /// positive moment (level clear, new best at a level clear, victory).
  ///
  /// Fire-and-forget safe. Returns true when a request was scheduled; the
  /// native call happens after [defaultPromptDelay], and only if
  /// [stillAppropriate] (when given) still holds then — e.g. the
  /// level-clear summary is still on screen. A true return does not mean a
  /// sheet showed; the platform silently no-ops past its own quota.
  Future<bool> maybeAskForReview(
    ReviewTrigger trigger, {
    bool Function()? stillAppropriate,
  }) async {
    try {
      if (_pending) return false;
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt(_kLastPromptedAtMillisKey);
      final reason = ReviewGate.skipReason(
        onboardingDone: _onboardingDone(),
        runsStarted: _runsStarted(),
        now: _clock(),
        lastPromptAt: lastMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastMs),
        lastInterruptionAt: _lastInterruptionAt,
        demo: _demo,
      );
      if (reason != null) {
        AppLogger.info('$_tag skip (${trigger.name}): $reason');
        return false;
      }
      if (!await _inAppReview.isAvailable()) {
        AppLogger.info('$_tag skip (${trigger.name}): API unavailable');
        return false;
      }
      _pending = true;
      _pendingDispatch = Future.delayed(
        _promptDelay,
        () => _dispatch(trigger, stillAppropriate),
      ).whenComplete(() => _pending = false);
      return true;
    } catch (e) {
      AppLogger.info('$_tag request errored: $e');
      return false;
    }
  }

  /// Completes when the scheduled native request ran (or was dropped).
  @visibleForTesting
  Future<bool>? get debugPendingDispatch => _pendingDispatch;

  Future<bool> _dispatch(
    ReviewTrigger trigger,
    bool Function()? stillAppropriate,
  ) async {
    try {
      if (stillAppropriate != null && !stillAppropriate()) return false;
      // Re-check: an ad/purchase may have started during the delay.
      final lastInt = _lastInterruptionAt;
      if (lastInt != null &&
          _clock().difference(lastInt) < ReviewGate.quietAfterInterruption) {
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _kLastPromptedAtMillisKey,
        _clock().millisecondsSinceEpoch,
      );
      AppLogger.info('$_tag requesting review (trigger: ${trigger.name})');
      unawaited(_analytics.trackReviewRequested(trigger.name));
      await _inAppReview.requestReview();
      return true;
    } catch (e) {
      AppLogger.info('$_tag platform request failed: $e');
      return false;
    }
  }

  /// User-initiated rating (Settings "Rate app"). Not gated — the player
  /// asked. Prefers the native sheet; falls back to the store listing when
  /// the platform reports the API unavailable (debug, sideloaded APK...).
  Future<void> rateAppManually() async {
    try {
      unawaited(_analytics.trackReviewRequested('manual'));
      if (await _inAppReview.isAvailable()) {
        await _inAppReview.requestReview();
      } else {
        await _inAppReview.openStoreListing();
      }
    } catch (e) {
      AppLogger.info('$_tag manual rate failed: $e');
      try {
        await _inAppReview.openStoreListing();
      } catch (_) {}
    }
  }
}
