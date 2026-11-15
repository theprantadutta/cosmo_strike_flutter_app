import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/logger.dart';
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
  static Future<bool> requestOrOpen() async {
    final service = NotificationService();
    if (await service.areNotificationsEnabled()) return true;
    if (await service.requestPermissionFlow()) return true;
    if (service.lastPermissionPromptBlocked) await open();
    return false;
  }
}
