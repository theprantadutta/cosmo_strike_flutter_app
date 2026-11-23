import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/first_run_service.dart';
import 'package:cosmo_strike_flutter_app/services/update_policy.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// In-app updates from the Play Store (Android only; every entry point is a
/// no-op on iOS and other platforms).
///
/// Runs ONE check per process, kicked off by Home after its first frame
/// (never in the start-up bootstrap), and picks the flow with
/// [UpdatePolicy]:
///
/// * **offer** (routine release): [checkForUpdate] resolves to
///   [UpdateFlow.offer] and Home's prompt queue shows our "Update now /
///   Later" dialog (`showPlayUpdateOfferDialog`) as the visit's only popup.
///   "Update now" calls [acceptOffer]: Play's blocking flow downloads with
///   progress, then installs and restarts the app itself. The flexible flow
///   it replaced needed the player to tap Restart after the download, and
///   most never did.
/// * **immediate** (urgent release, priority >= 4): the blocking flow
///   straight away, even in a first session.
/// * **flexible**: fallback when Play won't run the blocking flow.
///
/// A download that already finished (an older build's flexible flow, or the
/// fallback) is installed at the next launch on Home, before a run starts.
/// Deliberately NOT when the app goes to the background or resumes: a
/// rewarded ad or a paused mid-run game also backgrounds the app, and the
/// install kills the process.
///
/// Analytics: `app_update` {stage, result?}; stages `offered`, `accepted`,
/// `snoozed`, `urgent`, `flexible_fallback`, `immediate_result` (result =
/// `AppUpdateResult.name` or `error`), `auto_completed` (result `home`).
///
/// Device-only state (the snooze stamp) lives in SharedPreferences: it is
/// about this handset's last refusal, nothing another device should see.
class InAppUpdateService {
  static final InAppUpdateService _instance = InAppUpdateService._internal();
  factory InAppUpdateService() => _instance;
  InAppUpdateService._internal();

  static const kDeclinedAtMs = 'in_app_update_declined_ms';

  AppUpdateInfo? _updateInfo;

  AnalyticsFacade? get _analytics => GetIt.I.isRegistered<AnalyticsFacade>()
      ? GetIt.I<AnalyticsFacade>()
      : null;

  void _log(String stage, {String? result}) =>
      unawaited(_analytics?.trackAppUpdate(stage: stage, result: result));

  /// Check once per session. Runs the flows that need no UI from us
  /// (immediate, flexible, installing a finished download) and resolves to
  /// [UpdateFlow.offer] when Home should show the offer dialog. Later calls
  /// get the same future, so Home's kick-off and its prompt queue share one
  /// check. Never throws; a failed check is a log line and
  /// [UpdateFlow.none].
  ///
  /// [canRestartNow] is asked right before a finished download is installed
  /// (which restarts the app): Home passes "still mounted and on top", so a
  /// player who already tapped Play is never yanked out of a run. Only the
  /// first caller's callback is used.
  Future<UpdateFlow> checkForUpdate({bool Function()? canRestartNow}) =>
      _check ??= _runCheck(canRestartNow);
  Future<UpdateFlow>? _check;

  /// True from an offer until the player answers it, so a re-created Home
  /// doesn't ask twice in one session.
  bool get offerPending => _offerPending;
  bool _offerPending = false;

  Future<UpdateFlow> _runCheck(bool Function()? canRestartNow) async {
    if (kIsWeb || !Platform.isAndroid) return UpdateFlow.none;
    if (kDebugMode) {
      AppLogger.info('Skipping in-app update check in debug mode');
      return UpdateFlow.none;
    }

    // Captured before any run of this process: true until the install has
    // started its first run (or while FirstRunService isn't loaded yet).
    final firstRun = FirstRunService.instance;
    final firstSession = firstRun.installedAt == null || firstRun.isFirstGame;

    try {
      final info = await InAppUpdate.checkForUpdate().timeout(
        const Duration(seconds: 5),
      );
      _updateInfo = info;

      // A download from a previous session that finished while we were
      // away. We are on Home at launch, before any run: install it now
      // (Play restarts into the new version) instead of waiting for a
      // Restart tap that rarely comes.
      if (info.installStatus == InstallStatus.downloaded) {
        if (canRestartNow == null || canRestartNow()) {
          _log('auto_completed', result: 'home');
          await completeUpdate();
        } else {
          AppLogger.info('Update downloaded; installing at the next launch');
        }
        return UpdateFlow.none;
      }

      final prefs = await SharedPreferences.getInstance();
      final declinedMs = prefs.getInt(kDeclinedAtMs);
      final sinceDeclined = declinedMs == null
          ? null
          : Duration(
              milliseconds: DateTime.now().millisecondsSinceEpoch - declinedMs,
            );

      final flow = UpdatePolicy.decide(
        updateAvailable:
            info.updateAvailability == UpdateAvailability.updateAvailable,
        priority: info.updatePriority,
        immediateAllowed: info.immediateUpdateAllowed,
        flexibleAllowed: info.flexibleUpdateAllowed,
        sinceDeclined: sinceDeclined,
        firstSession: firstSession,
      );
      AppLogger.info(
        'In-app update: available=${info.updateAvailability.name}, '
        'priority=${info.updatePriority}, firstSession=$firstSession, '
        'flow=${flow.name}',
      );

      switch (flow) {
        case UpdateFlow.none:
          return UpdateFlow.none;
        case UpdateFlow.offer:
          _offerPending = true;
          return UpdateFlow.offer;
        case UpdateFlow.immediate:
          _log('urgent');
          await _runImmediate(prefs);
          return UpdateFlow.none;
        case UpdateFlow.flexible:
          _log('flexible_fallback');
          await _runFlexible(prefs);
          return UpdateFlow.none;
      }
    } catch (e, stackTrace) {
      AppLogger.error('In-app update check failed', e, stackTrace);
      return UpdateFlow.none;
    }
  }

  /// Our dialog is on screen (logged here, not at decision time, so
  /// `offered` counts players who actually saw it).
  void markOfferShown() => _log('offered');

  /// "Update now" on the offer dialog: Play's blocking flow.
  Future<void> acceptOffer() async {
    _offerPending = false;
    _log('accepted');
    final prefs = await SharedPreferences.getInstance();
    await _runImmediate(prefs);
  }

  /// "Later" (or outside tap / back) on the offer dialog.
  Future<void> snoozeOffer() async {
    _offerPending = false;
    _log('snoozed');
    final prefs = await SharedPreferences.getInstance();
    await _recordDeclined(prefs);
  }

  Future<void> _recordDeclined(SharedPreferences prefs) =>
      prefs.setInt(kDeclinedAtMs, DateTime.now().millisecondsSinceEpoch);

  /// The blocking Play flow. On success Play installs and restarts the app,
  /// so this usually never returns; it does when the player backs out of
  /// Play's screen (snoozed like "Later") or it fails.
  Future<void> _runImmediate(SharedPreferences prefs) async {
    try {
      final result = await InAppUpdate.performImmediateUpdate();
      AppLogger.info('Immediate update: ${result.name}');
      _log('immediate_result', result: result.name);
      if (result == AppUpdateResult.userDeniedUpdate) {
        await _recordDeclined(prefs);
      }
    } catch (e, stackTrace) {
      AppLogger.error('Immediate update failed', e, stackTrace);
      _log('immediate_result', result: 'error');
    }
  }

  /// Fallback: ask Play to download in the background. The player sees one
  /// small Play dialog; "No thanks" is remembered for [UpdatePolicy.snooze].
  /// No restart prompt of ours follows (and never a blocking popup over the
  /// download): the finished download installs at the next launch on Home.
  Future<void> _runFlexible(SharedPreferences prefs) async {
    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      AppLogger.info('Flexible update: ${result.name}');
      if (result == AppUpdateResult.userDeniedUpdate) {
        await _recordDeclined(prefs);
      }
    } catch (e, stackTrace) {
      AppLogger.error('Flexible update failed to start', e, stackTrace);
    }
  }

  /// Apply a downloaded flexible update. Play restarts the app.
  Future<void> completeUpdate() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e, stackTrace) {
      AppLogger.error('Completing the update failed', e, stackTrace);
    }
  }

  /// Whether Play reported an update on the last check (for UI purposes).
  bool get isUpdateAvailable =>
      _updateInfo?.updateAvailability == UpdateAvailability.updateAvailable;

  @visibleForTesting
  void debugReset() {
    _check = null;
    _offerPending = false;
    _updateInfo = null;
  }
}
