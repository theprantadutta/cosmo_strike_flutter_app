import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/logger.dart';
import 'analytics/analytics_facade.dart';
import 'notification_service.dart';

/// Opens the OS page where the player can turn this app's notifications on.
///
/// Needed once POST_NOTIFICATIONS has been permanently denied: Android never
/// shows the system prompt again, so the settings page is the only way back.
/// Android uses a native channel (`MainActivity.configureFlutterEngine`) to
/// open Settings.ACTION_APP_NOTIFICATION_SETTINGS for this package; iOS opens
/// the app's Settings page via the `app-settings:` URL.
class NotificationSettingsOpener {
  NotificationSettingsOpener._();

  static const MethodChannel _channel =
      MethodChannel('cosmo_strike/notification_settings');

  /// Returns true when a settings page was opened.
  static Future<bool> open() async {
    try {
      if (kIsWeb) return false;
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _channel.invokeMethod<bool>('open') ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await launchUrl(Uri.parse('app-settings:'));
      }
    } catch (e) {
      AppLogger.error('Could not open notification settings', e);
    }
    return false;
  }

  /// Turns notifications on the best way available: the OS prompt when it
  /// can still appear, otherwise this app's settings page. Returns true when
  /// notifications are enabled afterwards (false also when the settings page
  /// was opened: the caller re-checks when the app resumes).
  ///
  /// Logs `notification_permission` with [placement] (where the ask was:
  /// `home_soft_ask`, `settings`, `new_best`...) and the result
  /// (`already_enabled` / `granted` / `denied` / `settings_opened`).
  static Future<bool> requestOrOpen({String placement = 'unknown'}) async {
    final service = NotificationService();
    if (await service.areNotificationsEnabled()) {
      track(placement, 'already_enabled');
      return true;
    }
    if (await service.requestPermissionFlow()) {
      track(placement, 'granted');
      return true;
    }
    if (service.lastPermissionPromptBlocked) {
      final opened = await open();
      track(placement, opened ? 'settings_opened' : 'denied');
    } else {
      track(placement, 'denied');
    }
    return false;
  }

  /// Fire-and-forget `notification_permission` event.
  static void track(String placement, String result) {
    if (!GetIt.I.isRegistered<AnalyticsFacade>()) return;
    GetIt.I<AnalyticsFacade>().trackNotificationPermission(
      placement: placement,
      result: result,
    );
  }
}
