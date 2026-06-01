import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Service to handle in-app updates from Play Store (Android only)
class InAppUpdateService {
  static final InAppUpdateService _instance = InAppUpdateService._internal();
  factory InAppUpdateService() => _instance;
  InAppUpdateService._internal();

  bool _initialized = false;
  AppUpdateInfo? _updateInfo;

  /// Check for available updates and prompt user if available
  Future<void> checkForUpdate() async {
    // Only works on Android
    if (!Platform.isAndroid) {
      AppLogger.info('In-app update only available on Android');
      return;
    }

    if (kDebugMode) {
      AppLogger.info('Skipping in-app update check in debug mode');
      return;
    }

    try {
      AppLogger.info('Checking for app updates...');
      _updateInfo = await InAppUpdate.checkForUpdate()
          .timeout(const Duration(seconds: 5));

      if (_updateInfo == null) {
        AppLogger.info('No update info available');
        return;
      }

      AppLogger.info(
        'Update check complete: '
        'available=${_updateInfo!.updateAvailability == UpdateAvailability.updateAvailable}, '
        'immediate=${_updateInfo!.immediateUpdateAllowed}, '
        'flexible=${_updateInfo!.flexibleUpdateAllowed}',
      );

      if (_updateInfo!.updateAvailability == UpdateAvailability.updateAvailable) {
        // Prefer immediate update for critical updates, otherwise use flexible
        if (_updateInfo!.immediateUpdateAllowed) {
          await _performImmediateUpdate();
        } else if (_updateInfo!.flexibleUpdateAllowed) {
          await _performFlexibleUpdate();
        }
      } else {
        AppLogger.info('App is up to date');
      }

      _initialized = true;
    } catch (e, stackTrace) {
      AppLogger.error('Error checking for updates', e, stackTrace);
    }
  }

  /// Perform immediate update (blocks app until update is complete)
  Future<void> _performImmediateUpdate() async {
    try {
      AppLogger.info('Starting immediate update...');
      await InAppUpdate.performImmediateUpdate();
      AppLogger.success('Immediate update completed');
    } catch (e, stackTrace) {
      AppLogger.error('Immediate update failed', e, stackTrace);
    }
  }

  /// Perform flexible update (downloads in background)
  Future<void> _performFlexibleUpdate() async {
    try {
      AppLogger.info('Starting flexible update...');
      await InAppUpdate.startFlexibleUpdate();
      AppLogger.success('Flexible update downloaded');

      // Complete the update when downloaded
      await InAppUpdate.completeFlexibleUpdate();
      AppLogger.success('Flexible update installed');
    } catch (e, stackTrace) {
      AppLogger.error('Flexible update failed', e, stackTrace);
    }
  }

  /// Check if an update is available (for UI purposes)
  bool get isUpdateAvailable =>
      _updateInfo?.updateAvailability == UpdateAvailability.updateAvailable;

  /// Check if service has been initialized
  bool get isInitialized => _initialized;
}
