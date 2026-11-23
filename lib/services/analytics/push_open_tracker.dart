import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_it/get_it.dart';

import '../../utils/logger.dart';
import 'analytics_facade.dart';
import 'analytics_params.dart';

/// `push_opened` for every notification tap — FCM pushes and local ones
/// (the comeback reminder) — with the payload's `type` as `push_type`.
/// GA4's automatic `notification_open` covers FCM only and has no type.
///
/// One-line hooks live in NotificationService: [fcm] in
/// `_handleMessageOpenedApp`, [local] in `_onNotificationTapped`, and
/// [trackLocalLaunch] after the local plugin initialises (a tap that
/// launches a killed app never reaches `_onNotificationTapped`).
abstract final class PushOpenTracker {
  static AnalyticsFacade? get _analytics =>
      GetIt.I.isRegistered<AnalyticsFacade>() ? GetIt.I<AnalyticsFacade>() : null;

  /// An FCM notification was tapped. Data-only pings are ignored.
  static void fcm(Map<String, dynamic> data, {bool? coldStart}) {
    if (data['action'] == 'entitlements_changed') return;
    unawaited(
      _analytics?.trackPushOpened(
        pushType: AnalyticsParams.pushType(data, fallback: 'fcm'),
        source: 'fcm',
        coldStart: coldStart,
      ),
    );
  }

  /// A local notification was tapped; [payload] is its JSON payload.
  static void local(String? payload, {bool? coldStart}) {
    unawaited(
      _analytics?.trackPushOpened(
        pushType: AnalyticsParams.pushType(decode(payload), fallback: 'local'),
        source: 'local',
        coldStart: coldStart,
      ),
    );
  }

  static bool _launchChecked = false;

  /// Logs the tap that launched the app from a killed state, if any
  /// (checked once per process).
  static Future<void> trackLocalLaunch(
    FlutterLocalNotificationsPlugin plugin,
  ) async {
    if (_launchChecked) return;
    _launchChecked = true;
    try {
      final details = await plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        local(details!.notificationResponse?.payload, coldStart: true);
      }
    } catch (e) {
      AppLogger.info('[PushOpenTracker] launch details failed: $e');
    }
  }

  static Map<String, dynamic>? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final v = jsonDecode(payload);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
