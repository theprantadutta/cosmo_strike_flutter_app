import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'package:cosmo_strike_flutter_app/core/startup/startup_guard.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Startup-window crash reporting on top of Crashlytics.
///
/// Crashlytics can only run once Firebase is up, which is AFTER `.env` loads
/// and after `Firebase.initializeApp` — so the startup failures that matter
/// most were the ones it could never see. Everything here is safe to call at
/// any point: before [markCrashlyticsReady] errors are buffered (bounded) and
/// keys are remembered; once it is called, both are flushed to Crashlytics
/// and later calls go straight through.
///
/// Debug builds never report (Crashlytics collection is disabled there), they
/// only log — matching the app's existing release-only policy.
class StartupReporter {
  StartupReporter._();

  static final EarlyErrorBuffer _buffer = EarlyErrorBuffer();
  static final Map<String, Object> _pendingKeys = {};
  static final List<String> _pendingLogs = [];
  static bool _ready = false;

  /// Whether Crashlytics is initialized and receiving reports.
  static bool get isReady => _ready;

  static bool get _reporting => !kDebugMode;

  /// Records [error]. Buffered until Crashlytics is ready.
  static void recordError(
    Object error,
    StackTrace? stack, {
    required String reason,
    bool fatal = false,
  }) {
    if (!_reporting) return;
    _buffer.add(
      BufferedStartupError(error, stack, reason: reason, fatal: fatal),
    );
  }

  /// Like [recordError], but resolves once the report has been handed to
  /// Crashlytics (or immediately when it is only buffered). Use on paths that
  /// are about to replace the whole app, so the report is not lost.
  static Future<void> recordErrorNow(
    Object error,
    StackTrace? stack, {
    required String reason,
    bool fatal = false,
  }) async {
    if (!_reporting) return;
    if (!_ready) {
      recordError(error, stack, reason: reason, fatal: fatal);
      return;
    }
    try {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, reason: reason, fatal: fatal)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// Records a framework error from `FlutterError.onError`.
  static void recordFlutterError(FlutterErrorDetails details) {
    if (!_reporting) return;
    if (_ready) {
      unawaited(
        FirebaseCrashlytics.instance
            .recordFlutterFatalError(details)
            .catchError((Object _) {}),
      );
      return;
    }
    _buffer.add(
      BufferedStartupError(
        details.exception,
        details.stack,
        reason: 'Early Flutter error: ${details.context ?? details.library}',
        fatal: true,
      ),
    );
  }

  /// Sets a Crashlytics custom key (remembered until ready).
  static void setKey(String key, Object value) {
    if (!_reporting) return;
    if (_ready) {
      unawaited(
        FirebaseCrashlytics.instance
            .setCustomKey(key, value)
            .catchError((Object _) {}),
      );
    } else {
      _pendingKeys[key] = value;
    }
  }

  /// Adds a breadcrumb to the next crash report (remembered until ready).
  static void log(String message) {
    if (!_reporting) return;
    if (_ready) {
      unawaited(
        FirebaseCrashlytics.instance.log(message).catchError((Object _) {}),
      );
    } else if (_pendingLogs.length < 50) {
      _pendingLogs.add(message);
    }
  }

  /// Publishes a phase tracker's state: the phase that was running/last ran,
  /// every completed phase's duration and the total elapsed time.
  static void publishPhases(
    StartupPhaseTracker tracker, {
    required String outcome,
  }) {
    setKey('startup_outcome', outcome);
    setKey('startup_phase', tracker.currentPhase ?? 'none');
    setKey('startup_total_ms', tracker.elapsedMs);
    tracker.durationsMs.forEach((phase, ms) {
      setKey('startup_ms_$phase', ms);
    });
  }

  /// Call once Crashlytics collection is configured. Flushes buffered keys,
  /// breadcrumbs and errors (oldest first). Idempotent.
  static void markCrashlyticsReady() {
    if (_ready) return;
    _ready = true;
    if (!_reporting) return;
    final crashlytics = FirebaseCrashlytics.instance;
    for (final message in _pendingLogs) {
      unawaited(crashlytics.log(message).catchError((Object _) {}));
    }
    _pendingLogs.clear();
    _pendingKeys.forEach((key, value) {
      unawaited(crashlytics.setCustomKey(key, value).catchError((Object _) {}));
    });
    _pendingKeys.clear();
    if (_buffer.dropped > 0) {
      setKey('startup_errors_dropped', _buffer.dropped);
    }
    _buffer.attach((entry) {
      unawaited(
        crashlytics
            .recordError(
              entry.error,
              entry.stack,
              reason: entry.reason,
              fatal: entry.fatal,
            )
            .catchError((Object e) {
          AppLogger.warning('Crashlytics report failed: $e');
        }),
      );
    });
  }
}
