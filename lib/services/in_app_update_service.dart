import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:cosmo_strike_flutter_app/router/app_router.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Handles Play Store in-app updates (Android only).
///
/// Policy is PRIORITY-BASED:
/// - High-priority or very stale updates use an IMMEDIATE (blocking) update —
///   Play takes over the screen until the user updates.
/// - Everything else uses a FLEXIBLE background download, then a non-intrusive
///   "Restart to update" prompt. We NEVER force a surprise restart.
///
/// Both [checkForUpdate] (startup) and [resumeUpdateIfNeeded] (app resume) are
/// safe to call repeatedly: they resume interrupted immediate updates and
/// complete flexible downloads that finished while the app was backgrounded,
/// per Google's in-app-update guidance.
class InAppUpdateService {
  static final InAppUpdateService _instance = InAppUpdateService._internal();
  factory InAppUpdateService() => _instance;
  InAppUpdateService._internal();

  /// updatePriority (0-5, set per release in the Play Console) at or above
  /// which we force a blocking immediate update.
  static const int _immediatePriorityThreshold = 4;

  /// ...or when the user has been on the stale version at least this many days.
  static const int _immediateStalenessDays = 14;

  bool _initialized = false;
  bool _checking = false;
  AppUpdateInfo? _updateInfo;

  /// Startup check: decides immediate vs flexible and kicks off the flow.
  Future<void> checkForUpdate() async {
    if (!Platform.isAndroid) {
      AppLogger.info('In-app update only available on Android');
      return;
    }
    if (kDebugMode) {
      AppLogger.info('Skipping in-app update check in debug mode');
      return;
    }
    if (_checking) return; // guard against overlapping startup/resume calls
    _checking = true;

    try {
      AppLogger.info('Checking for app updates...');
      final info =
          await InAppUpdate.checkForUpdate().timeout(const Duration(seconds: 5));
      _updateInfo = info;

      AppLogger.info(
        'Update check: availability=${info.updateAvailability}, '
        'priority=${info.updatePriority}, '
        'staleness=${info.clientVersionStalenessDays}, '
        'installStatus=${info.installStatus}, '
        'immediate=${info.immediateUpdateAllowed}, '
        'flexible=${info.flexibleUpdateAllowed}',
      );

      // A flexible update already finished downloading (e.g. a prior session) —
      // prompt to install rather than re-downloading or force-restarting.
      if (info.installStatus == InstallStatus.downloaded) {
        _promptCompleteFlexibleUpdate();
        return;
      }

      switch (info.updateAvailability) {
        case UpdateAvailability.developerTriggeredUpdateInProgress:
          // An immediate update was interrupted — resume it.
          if (info.immediateUpdateAllowed) {
            await _performImmediateUpdate();
          }
          break;
        case UpdateAvailability.updateAvailable:
          if (_shouldUpdateImmediately(info) && info.immediateUpdateAllowed) {
            await _performImmediateUpdate();
          } else if (info.flexibleUpdateAllowed) {
            await _startFlexibleUpdate();
          } else if (info.immediateUpdateAllowed) {
            // Play didn't offer a flexible path — fall back to immediate.
            await _performImmediateUpdate();
          }
          break;
        case UpdateAvailability.updateNotAvailable:
        case UpdateAvailability.unknown:
          AppLogger.info('App is up to date');
          break;
      }

      _initialized = true;
    } catch (e, stackTrace) {
      AppLogger.error('Error checking for updates', e, stackTrace);
    } finally {
      _checking = false;
    }
  }

  /// Call from the app's `resumed` lifecycle hook. Unlike [checkForUpdate] this
  /// never STARTS a new update (so it can't hijack an in-progress game) — it
  /// only finishes work already underway: resumes an interrupted immediate
  /// update and prompts to install a flexible download that completed in the
  /// background.
  Future<void> resumeUpdateIfNeeded() async {
    if (!Platform.isAndroid || kDebugMode || _checking) return;
    _checking = true;
    try {
      final info =
          await InAppUpdate.checkForUpdate().timeout(const Duration(seconds: 5));
      _updateInfo = info;

      if (info.installStatus == InstallStatus.downloaded) {
        _promptCompleteFlexibleUpdate();
      } else if (info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress &&
          info.immediateUpdateAllowed) {
        await _performImmediateUpdate();
      }
    } catch (e, stackTrace) {
      AppLogger.error('Resume update check failed', e, stackTrace);
    } finally {
      _checking = false;
    }
  }

  bool _shouldUpdateImmediately(AppUpdateInfo info) {
    final highPriority = info.updatePriority >= _immediatePriorityThreshold;
    final staleEnough =
        (info.clientVersionStalenessDays ?? 0) >= _immediateStalenessDays;
    return highPriority || staleEnough;
  }

  /// Immediate update — Play blocks the app full-screen until it's installed.
  Future<void> _performImmediateUpdate() async {
    try {
      AppLogger.info('Starting immediate update...');
      await InAppUpdate.performImmediateUpdate();
      AppLogger.success('Immediate update completed');
    } catch (e, stackTrace) {
      AppLogger.error('Immediate update failed', e, stackTrace);
    }
  }

  /// Flexible update — downloads in the background while the user keeps
  /// playing. When the download finishes we PROMPT (we do not auto-restart).
  Future<void> _startFlexibleUpdate() async {
    try {
      AppLogger.info('Starting flexible (background) update download...');
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) {
        AppLogger.success('Flexible update downloaded');
        _promptCompleteFlexibleUpdate();
      } else {
        AppLogger.info('Flexible update not completed: $result');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Flexible update failed', e, stackTrace);
    }
  }

  /// Non-intrusive "ready to install" prompt: a persistent SnackBar with a
  /// RESTART action. Installing a flexible update restarts the app, so we only
  /// do it on the user's tap. If there's no UI yet (boot race), we bail — the
  /// resume check re-prompts next time the app comes to the foreground.
  void _promptCompleteFlexibleUpdate() {
    final context = rootNavigatorKey.currentContext;
    if (context == null) {
      AppLogger.warning(
          'Update ready but no context to prompt — will retry on resume');
      return;
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Update downloaded and ready to install.'),
          duration: const Duration(days: 1), // persists until acted on
          action: SnackBarAction(
            label: 'RESTART',
            onPressed: () => unawaited(InAppUpdate.completeFlexibleUpdate()),
          ),
        ),
      );
  }

  /// Whether the most recent check saw an available update (for UI purposes).
  bool get isUpdateAvailable =>
      _updateInfo?.updateAvailability == UpdateAvailability.updateAvailable;

  /// Whether a startup check has completed at least once.
  bool get isInitialized => _initialized;
}
