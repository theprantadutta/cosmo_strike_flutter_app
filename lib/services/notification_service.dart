import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/di/injection.dart';
import '../presentation/bloc/premium/premium_cubit.dart';
import '../utils/logger.dart';
import 'api_service.dart';
import 'data_sync_service.dart';
import 'navigation_service.dart';

enum NotificationType {
  tournament('tournament', 'Tournament Update'),
  social('social', 'Social Notification'),
  achievement('achievement', 'Achievement Unlocked'),
  dailyReminder('daily_reminder', 'Daily Challenge'),
  specialEvent('special_event', 'Special Event');

  const NotificationType(this.key, this.displayName);
  final String key;
  final String displayName;
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String _channelId = 'cosmo_strike_notifications';
  static const String _channelName = 'Cosmo Strike Notifications';
  static const String _channelDescription =
      'Notifications for Cosmo Strike game events';

  // SharedPreferences key for the Hangfire job id of a pending backend-
  // scheduled test push. Persisted by scheduleTestNotificationAt so
  // cancelScheduledTestNotification can DELETE it after an app restart.
  static const String _scheduledTestJobIdKey = 'dev_scheduled_test_job_id';

  late FlutterLocalNotificationsPlugin _localNotifications;
  late FirebaseMessaging _firebaseMessaging;

  String? _fcmToken;
  bool _initialized = false;
  bool _backendIntegrationDone = false;

  // Notification preferences - stored in SharedPreferences via PreferencesService
  final Map<NotificationType, bool> _notificationPreferences = {
    NotificationType.tournament: true,
    NotificationType.social: true,
    NotificationType.achievement: true,
    NotificationType.dailyReminder: true,
    NotificationType.specialEvent: true,
  };

  String? get fcmToken => _fcmToken;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    try {
      AppLogger.info('🔔 Initializing notification service');

      _firebaseMessaging = FirebaseMessaging.instance;
      _localNotifications = FlutterLocalNotificationsPlugin();

      await _initializeLocalNotifications();
      await _initializeFirebaseMessaging().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          AppLogger.warning(
            'Firebase messaging init timed out — continuing without FCM',
          );
        },
      );
      await _loadNotificationPreferences();

      _initialized = true;
      // Align FCM topic subscriptions with the saved toggles. Fire and
      // forget — FCM topic calls can be slow and must not block boot;
      // internally no-ops when the token is unavailable.
      unawaited(_syncTopicSubscriptions());
      AppLogger.success('Notification service initialized successfully');
    } catch (e) {
      AppLogger.error('Failed to initialize notification service', e);
      // Don't rethrow — notification failure shouldn't crash the app
    }
  }

  Future<void> _initializeLocalNotifications() async {
    // Android initialization settings
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel for Android, then explicitly request
    // POST_NOTIFICATIONS at runtime via flutter_local_notifications.
    //
    // Why not rely on firebase_messaging.requestPermission for this?
    // Per the FlutterFire team's tracking issue, FCM's requestPermission
    // does NOT reliably trigger the Android 13+ system dialog — on a
    // newly-installed device targeting API 33+ the user is silently in
    // a "denied" state and every subsequent notification is dropped
    // without any error log. Going through the local-notifications
    // plugin's own request is the documented Android path and is
    // idempotent (returns immediately if already granted/denied).
    if (defaultTargetPlatform == TargetPlatform.android) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidPlugin?.createNotificationChannel(channel);

      final granted = await androidPlugin?.requestNotificationsPermission();
      AppLogger.info(
        '🔔 Android notifications permission requested. Granted: $granted',
      );
    }
  }

  Future<void> _initializeFirebaseMessaging() async {
    // Request permission for iOS
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    AppLogger.info(
      '🔔 Notification permission: ${settings.authorizationStatus}',
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Get FCM token
      _fcmToken = await _firebaseMessaging.getToken();
      AppLogger.info('🎫 FCM Token: $_fcmToken');

      // Development-only: Print FCM token for Firebase Console testing
      if (kDebugMode && _fcmToken != null) {
        debugPrint('');
        debugPrint('🔥 ============ FIREBASE TESTING ============');
        debugPrint('📱 FCM Token for Firebase Console:');
        debugPrint(_fcmToken!);
        debugPrint('🧪 Copy this token to Firebase Console > Cloud Messaging');
        debugPrint('🔥 =========================================');
        debugPrint('');
      }

      // Race fix: if the initial getToken() resolves AFTER
      // _initializeNotificationIntegration() has already run, the
      // backend integration call would have bailed with "no token" and
      // never retry. Treat the first-token arrival like a refresh so
      // _registerTokenWithBackend fires immediately (which queues via
      // DataSyncService if auth isn't ready yet — see Phase 2).
      // Anonymous + Google users both benefit.
      if (_fcmToken != null) {
        unawaited(_registerTokenWithBackend(_fcmToken!));
      }

      // Subscribe to token refresh
      _firebaseMessaging.onTokenRefresh.listen((token) {
        _fcmToken = token;
        AppLogger.info('🔄 FCM Token refreshed: $token');

        // Development-only: Print refreshed token
        if (kDebugMode) {
          debugPrint('');
          debugPrint('🔄 ========= FCM TOKEN REFRESHED =========');
          debugPrint('📱 New FCM Token: $token');
          debugPrint('🔄 ===================================');
          debugPrint('');
        }

        _onTokenRefresh(token);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background message taps
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Handle initial message when app is opened from terminated state
      RemoteMessage? initialMessage = await _firebaseMessaging
          .getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    AppLogger.info('📨 Received foreground message: ${message.messageId}');

    // Silent entitlement ping: the backend changed this user's premium
    // state (subscription renewed/revoked, promo granted/expired, …).
    // Re-pull the targeted premium snapshot — this is the only way an
    // OPEN offline-first app learns about server-side entitlement
    // changes (background/killed delivery is covered by the app-resume
    // sync in main.dart). Nothing is shown to the user.
    if (message.data['action'] == 'entitlements_changed') {
      AppLogger.info('🔄 Entitlements-changed ping — syncing premium state');
      try {
        unawaited(getIt<PremiumCubit>().syncWithBackend());
      } catch (e) {
        AppLogger.error('Entitlement ping sync failed', e);
      }
      return;
    }

    // Show local notification for foreground messages
    await _showLocalNotification(
      title: message.notification?.title ?? 'Cosmo Strike',
      body: message.notification?.body ?? 'You have a new notification',
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    AppLogger.info('👆 App opened from notification: ${message.messageId}');

    final data = message.data;
    // Defensive: data-only pings never create a tray entry, so this path
    // is mostly unreachable for them — but cheap to handle anyway.
    if (data['action'] == 'entitlements_changed') {
      try {
        unawaited(getIt<PremiumCubit>().syncWithBackend());
      } catch (e) {
        AppLogger.error('Entitlement ping sync failed', e);
      }
      return;
    }

    // Handle deep linking based on notification data
    if (data.containsKey('route')) {
      _navigateToScreen(data['route'], data);
    }
  }

  void _onTokenRefresh(String token) {
    // Send updated token to backend
    _registerTokenWithBackend(token);
  }

  void _onNotificationTapped(NotificationResponse response) {
    AppLogger.info('👆 Local notification tapped: ${response.id}');

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        if (data['route'] != null) {
          _navigateToScreen(data['route'], data);
        }
      } catch (e) {
        AppLogger.error('Error parsing notification payload', e);
      }
    }
  }

  void _navigateToScreen(String route, Map<String, dynamic> data) {
    AppLogger.info('🧭 Navigating to: $route with data: $data');

    try {
      // Use the navigation service to handle deep linking
      NavigationService().navigateFromNotification(route: route, params: data);
    } catch (e) {
      AppLogger.error('Navigation failed', e);
      // Fallback to home screen
      NavigationService().navigateToHome();
    }
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    NotificationType? type,
  }) async {
    // Check if notifications are enabled for this type
    if (type != null && !(_notificationPreferences[type] ?? true)) {
      AppLogger.info(
        '🔕 Notification blocked by user preferences: ${type.key}',
      );
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Cosmo Strike',
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  // Topic subscription methods
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      AppLogger.info('📢 Subscribed to topic: $topic');
    } catch (e) {
      AppLogger.error('Failed to subscribe to topic $topic', e);
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      AppLogger.info('🔕 Unsubscribed from topic: $topic');
    } catch (e) {
      AppLogger.error('Failed to unsubscribe from topic $topic', e);
    }
  }

  // Notification preference methods
  bool isNotificationEnabled(NotificationType type) {
    return _notificationPreferences[type] ?? true;
  }

  Future<void> setNotificationEnabled(
    NotificationType type,
    bool enabled,
  ) async {
    _notificationPreferences[type] = enabled;
    AppLogger.info(
      '⚙️ ${type.key} notifications ${enabled ? 'enabled' : 'disabled'}',
    );

    // Save to preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_${type.key}', enabled);
    } catch (e) {
      AppLogger.error('Failed to save notification preference: $e');
    }

    // Push the FULL per-type preference set to the backend. The server's
    // token-based send paths (daily reminder, win-back, promos,
    // tournament results) filter on the matching user_preferences
    // notify_* column — flipping these DB flags is what actually
    // stops/starts pushes in the wild; the local map above only gates
    // foreground rendering.
    //
    // Queued (not direct PUT) so an offline / auth-not-ready toggle still
    // propagates once connectivity returns. DataSyncService's
    // 'preferences' handler forwards this map verbatim as
    // PUT /users/me { preferences: {...} } — partial update.
    // notifications_enabled stays the legacy master alias for the
    // daily-reminder toggle (pre-overhaul servers filter on it alone).
    await DataSyncService().queueSync(
      'preferences',
      {
        'notifications_enabled':
            _notificationPreferences[NotificationType.dailyReminder] ?? true,
        'notify_daily_reminder':
            _notificationPreferences[NotificationType.dailyReminder] ?? true,
        'notify_tournament':
            _notificationPreferences[NotificationType.tournament] ?? true,
        'notify_achievement':
            _notificationPreferences[NotificationType.achievement] ?? true,
        'notify_social':
            _notificationPreferences[NotificationType.social] ?? true,
        'notify_special_event':
            _notificationPreferences[NotificationType.specialEvent] ?? true,
      },
      priority: SyncPriority.normal,
    );
    AppLogger.info(
      '📤 Queued notification preferences (${type.key}=$enabled) for backend sync',
    );

    // Topic-based sends are controlled by SUBSCRIPTION, not a server
    // filter — keep the FCM topics aligned with the toggle live.
    if (type == NotificationType.tournament) {
      await _setTournamentTopics(enabled);
    } else if (type == NotificationType.specialEvent) {
      enabled
          ? await subscribeToTopic(_leaderboardTopic)
          : await unsubscribeFromTopic(_leaderboardTopic);
    }
  }

  // ==================== FCM topic subscriptions ====================

  /// Topic names must match the backend senders exactly
  /// (NotificationJobService: 'tournaments', 'tournament_{id}',
  /// 'leaderboard_updates').
  static const String _tournamentsTopic = 'tournaments';
  static const String _leaderboardTopic = 'leaderboard_updates';

  /// SP key: per-tournament topics we've joined, so a tournament
  /// toggle-off (or back on) can fan out across every joined tournament.
  static const String _tournamentTopicsKey = 'subscribed_tournament_topics';

  /// Align FCM topic subscriptions with the current toggles. Called at
  /// the end of [initialize] and idempotent — Firebase subscribe /
  /// unsubscribe calls are safe to repeat.
  Future<void> _syncTopicSubscriptions() async {
    if (_fcmToken == null) return; // permission denied / FCM unavailable
    final tournamentsOn = isNotificationEnabled(NotificationType.tournament);
    final eventsOn = isNotificationEnabled(NotificationType.specialEvent);
    tournamentsOn
        ? await subscribeToTopic(_tournamentsTopic)
        : await unsubscribeFromTopic(_tournamentsTopic);
    eventsOn
        ? await subscribeToTopic(_leaderboardTopic)
        : await unsubscribeFromTopic(_leaderboardTopic);
    if (tournamentsOn) {
      for (final topic in await _storedTournamentTopics()) {
        await subscribeToTopic(topic);
      }
    }
  }

  /// Toggle-driven fan-out: the broadcast topic plus every joined
  /// per-tournament topic on file.
  Future<void> _setTournamentTopics(bool enabled) async {
    final perTournament = await _storedTournamentTopics();
    if (enabled) {
      await subscribeToTopic(_tournamentsTopic);
      for (final topic in perTournament) {
        await subscribeToTopic(topic);
      }
    } else {
      await unsubscribeFromTopic(_tournamentsTopic);
      for (final topic in perTournament) {
        await unsubscribeFromTopic(topic);
      }
    }
  }

  /// Called by TournamentService on a successful join: remember the
  /// per-tournament topic and subscribe immediately when the tournament
  /// toggle is on (the backend sends reminders to 'tournament_{id}').
  Future<void> onTournamentJoined(String tournamentId) async {
    final topic = 'tournament_$tournamentId';
    try {
      final prefs = await SharedPreferences.getInstance();
      final topics =
          prefs.getStringList(_tournamentTopicsKey) ?? <String>[];
      if (!topics.contains(topic)) {
        topics.add(topic);
        await prefs.setStringList(_tournamentTopicsKey, topics);
      }
    } catch (e) {
      AppLogger.error('Failed to record tournament topic $topic', e);
    }
    if (_initialized && isNotificationEnabled(NotificationType.tournament)) {
      await subscribeToTopic(topic);
    }
  }

  Future<List<String>> _storedTournamentTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_tournamentTopicsKey) ?? <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  Map<NotificationType, bool> get notificationPreferences =>
      Map.from(_notificationPreferences);

  // Game-specific notification methods
  Future<void> showAchievementNotification(String achievementName) async {
    await _showLocalNotification(
      title: '🏆 Achievement Unlocked!',
      body: achievementName,
      type: NotificationType.achievement,
      payload: jsonEncode({
        'route': 'achievements',
        'achievement': achievementName,
      }),
    );
  }

  Future<void> showTournamentNotification(
    String title,
    String body, {
    String? tournamentId,
  }) async {
    await _showLocalNotification(
      title: '🏆 $title',
      body: body,
      type: NotificationType.tournament,
      payload: jsonEncode({
        'route': 'tournament_detail',
        'tournament_id': tournamentId,
      }),
    );
  }

  Future<void> showSocialNotification(
    String title,
    String body, {
    String? userId,
  }) async {
    await _showLocalNotification(
      title: '👥 $title',
      body: body,
      type: NotificationType.social,
      payload: jsonEncode({'route': 'friends_screen', 'user_id': userId}),
    );
  }

  Future<void> showDailyReminderNotification() async {
    await _showLocalNotification(
      title: '🚀 Time to play Cosmo Strike!',
      body: 'Complete your daily challenge and climb the leaderboard!',
      type: NotificationType.dailyReminder,
      payload: jsonEncode({'route': 'home'}),
    );
  }

  /// Schedule a one-shot test notification to fire at [fireAt] (a wall-
  /// clock local time on the device). Hands the moment to the backend's
  /// POST /test/schedule endpoint, which uses Hangfire.BackgroundJob.Schedule
  /// to fire an FCM push at that instant. The returned Hangfire job id is
  /// persisted in SharedPreferences so [cancelScheduledTestNotification]
  /// can DELETE it later — even across app restarts.
  ///
  /// Debug-only feature; called by the Settings test panel. Single stored
  /// id means a subsequent call overwrites the cancel handle for any prior
  /// pending test (the previous backend job is implicitly orphaned, which
  /// is fine — Hangfire fires it on schedule and the user sees the test
  /// they intended to overwrite plus the new one).
  ///
  /// Returns true on confirmed schedule (jobId persisted), false otherwise.
  Future<bool> scheduleTestNotificationAt(DateTime fireAt) async {
    final fireAtUtc = fireAt.toUtc();
    final jobId = await ApiService().scheduleTestNotification(
      fireAtUtc: fireAtUtc,
      title: '⏰ Scheduled test fired',
      body: 'If you\'re seeing this, Hangfire BackgroundJob.Schedule + FCM end-to-end work.',
    );
    if (jobId == null) {
      AppLogger.error('Backend rejected scheduled test request');
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scheduledTestJobIdKey, jobId);
    AppLogger.info(
      '⏰ Test notification scheduled via backend (jobId=$jobId, fireAt=$fireAt)',
    );
    return true;
  }

  /// Cancel a pending backend-scheduled test notification. Reads the
  /// Hangfire jobId from SharedPreferences (persisted by
  /// [scheduleTestNotificationAt]) and DELETEs it via the backend.
  /// No-op if nothing is on file.
  Future<bool> cancelScheduledTestNotification() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString(_scheduledTestJobIdKey);
    if (jobId == null) {
      AppLogger.info('🔕 No scheduled test on file to cancel');
      return true;
    }
    final ok = await ApiService().cancelScheduledTestNotification(jobId);
    await prefs.remove(_scheduledTestJobIdKey);
    AppLogger.info(
      ok
          ? '🔕 Scheduled test notification cancelled (jobId=$jobId)'
          : '⚠️ Backend cancel returned non-200 for jobId=$jobId — cleared local handle anyway',
    );
    return ok;
  }

  // ---------------------------------------------------------------------
  // Daily reminder: server-driven.
  //
  // Scheduling of the daily player ping lives in the .NET backend's
  // Hangfire job `send-daily-reminder` (DailyChallengeJobService.
  // SendDailyReminder, registered in Program.cs). The backend evaluates
  // each user's local time against the 20:00 anchor using their stored
  // `users.time_zone_offset_minutes` and pushes via FCM.
  //
  // Why not local? `flutter_local_notifications`' own README warns that
  // OEM battery optimizations kill backgrounded apps (Xiaomi/Huawei),
  // Samsung caps ~500 pending alarms, and iOS holds only 64 — none of
  // those constraints apply to FCM. The local scheduler also drifts in
  // Doze mode (`inexactAllowWhileIdle` is documented to delay up to
  // ~15 min; exact mode requires SCHEDULE_EXACT_ALARM which the manifest
  // intentionally omits per Play policy).
  //
  // The PREVIEW DAILY REMINDER button in Settings now calls the backend
  // (POST /test/preview-daily-reminder) which reads streak / challenge /
  // high-score state from the DB and sends an FCM with the exact variant
  // a real tick would deliver — see previewDailyReminder() above.
  // ---------------------------------------------------------------------

  /// Fire the daily-reminder content NOW with the exact message variant
  /// this user would receive on the next applicable tick of the backend's
  /// send-daily-reminder Hangfire job. Debug-only — used by the Settings
  /// test panel to preview without waiting for the actual 20:00 local
  /// fire.
  ///
  /// Reads streak / challenge / high-score state from the backend DB
  /// (not local app state) so the previewed variant matches exactly what
  /// the wild user would see. Returns the variant key
  /// (streak_at_risk / daily_challenge / high_score_nudge) or null when
  /// no variant applies / user has no FCM tokens.
  Future<String?> previewDailyReminder() async {
    AppLogger.info('🧪 Requesting daily-reminder preview via backend');
    final variant = await ApiService().previewDailyReminderViaBackend();
    if (variant == null) {
      AppLogger.warning(
        'Backend daily-reminder preview returned no variant '
        '(no FCM token, or no streak / challenge / high-score yet)',
      );
    } else {
      AppLogger.success('Backend daily-reminder preview fired (variant=$variant)');
    }
    return variant;
  }

  Future<void> cancelScheduledNotification(int id) async {
    await _localNotifications.cancel(id: id);
  }

  Future<void> cancelAllScheduledNotifications() async {
    await _localNotifications.cancelAll();
  }

  // Backend integration methods
  /// Register the FCM token with the backend. Returns true on confirmed
  /// success, false on failure. When auth isn't ready yet (common during
  /// first-launch race with FirebaseAuth) the call is queued via
  /// DataSyncService so it retries automatically when auth + connectivity
  /// catch up. Previously this method silently dropped the call.
  Future<bool> _registerTokenWithBackend(String token) async {
    final tzOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;

    try {
      final apiService = ApiService();

      if (!apiService.isAuthenticated) {
        AppLogger.warning(
          'Auth not ready — queueing FCM token registration for later',
        );
        await DataSyncService().queueSync(
          'fcm_token_register',
          {
            'fcmToken': token,
            'platform': 'flutter',
            'timezoneOffsetMinutes': tzOffsetMinutes,
          },
          priority: SyncPriority.high,
        );
        return false;
      }

      final success = await apiService.registerFcmToken(
        fcmToken: token,
        platform: 'flutter',
        timezoneOffsetMinutes: tzOffsetMinutes,
      );

      if (success) {
        AppLogger.network('FCM token registered with backend successfully');
        return true;
      } else {
        AppLogger.error(
          'Failed to register FCM token with backend — queueing for retry',
        );
        await DataSyncService().queueSync(
          'fcm_token_register',
          {
            'fcmToken': token,
            'platform': 'flutter',
            'timezoneOffsetMinutes': tzOffsetMinutes,
          },
          priority: SyncPriority.high,
        );
        return false;
      }
    } catch (e) {
      AppLogger.error('Error registering token with backend', e);
      return false;
    }
  }

  /// Initialize backend integration after user authentication.
  ///
  /// Idempotent — safe to call multiple times. The `_backendIntegrationDone`
  /// latch only flips to true on **confirmed** registration success. Earlier
  /// versions flipped it unconditionally after the call, which permanently
  /// blocked retries when the first attempt failed (auth not ready, offline,
  /// 5xx, etc.) — the symptom the user described as "offline functionality
  /// silently killing notifications."
  Future<void> initializeBackendIntegration() async {
    try {
      if (_backendIntegrationDone) {
        AppLogger.info('Backend integration already completed, skipping');
        return;
      }

      if (_fcmToken == null) {
        AppLogger.warning(
          'Cannot initialize backend integration: No FCM token available',
        );
        return;
      }

      AppLogger.info('🔗 Initializing backend integration');

      if (kDebugMode) {
        debugPrint('');
        debugPrint('🔗 ======== BACKEND INTEGRATION ========');
        debugPrint('📱 FCM Token being registered with backend:');
        debugPrint(_fcmToken!);
        debugPrint('🔗 =====================================');
        debugPrint('');
      }

      // Register token with backend. _registerTokenWithBackend now queues
      // on auth-not-ready / failure, so we don't need to gate on
      // ApiService.isAuthenticated here.
      final success = await _registerTokenWithBackend(_fcmToken!);

      // CRITICAL: only set the latch on real success. A failed attempt
      // gets retried via the DataSyncService queue OR on the next
      // initializeBackendIntegration() call.
      if (success) {
        _backendIntegrationDone = true;
        AppLogger.info('✅ Backend integration initialized');
      } else {
        AppLogger.warning(
          '⚠️ Backend integration deferred (queued for retry)',
        );
      }
    } catch (e) {
      AppLogger.error('Failed to initialize backend integration', e);
    }
  }

  /// Reset the integration latch so a subsequent login / re-init can
  /// re-register the token. Call from auth flow on logout.
  void resetBackendIntegration() {
    _backendIntegrationDone = false;
  }

  /// Fire an achievement notification locally. Pre-refactor this went
  /// through the backend; post-refactor every notification is fired by
  /// the device itself.
  Future<void> triggerAchievementNotification(
    String achievementName,
    String achievementId,
  ) async {
    await showAchievementNotification(achievementName);
  }

  /// No-op in the offline-first build — friends/social features are
  /// disabled. Kept so existing call sites compile until the social
  /// code is cleaned up.
  Future<void> triggerFriendRequestNotification({
    required String targetUserId,
    required String targetFcmToken,
    required String senderName,
    required String senderId,
  }) async {}

  /// Sends an FCM push to every device this user is signed in on, via
  /// the backend's POST /test/send-to-me endpoint. Tests the full
  /// production push path (backend → FCM → device). Returns true on
  /// confirmed 200 from the backend.
  ///
  /// Distinct from [sendTestLocalNotification], which only renders an OS
  /// notification locally and never leaves the device — useful to isolate
  /// "is OS delivery working?" from "is FCM working?" when triaging.
  Future<bool> sendTestNotificationViaBackend() async {
    AppLogger.info('🧪 Requesting test push via backend');
    final ok = await ApiService().sendTestPushToMe(
      title: '🧪 Test push from backend',
      body: 'If you\'re seeing this, FCM delivery + your token registration both work.',
    );
    if (ok) {
      AppLogger.success('Backend test push request acknowledged');
    } else {
      AppLogger.error('Backend test push request failed');
    }
    return ok;
  }

  /// Load notification preferences from storage
  Future<void> _loadNotificationPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      for (final type in NotificationType.values) {
        final key = 'notification_${type.key}';
        final enabled = prefs.getBool(key) ?? true;
        _notificationPreferences[type] = enabled;
      }

      AppLogger.info('📱 Notification preferences loaded');
    } catch (e) {
      AppLogger.error('Error loading notification preferences', e);
    }
  }

  /// Fire a local notification immediately for end-to-end testing of the
  /// permission + channel + display pipeline. Used by the "Send Local
  /// Test" button on the settings screen. If this is invisible, the
  /// problem is local (permission denied, OS blocked the channel, or
  /// notifications disabled in system settings) — no FCM / backend
  /// involvement at all.
  Future<void> sendTestLocalNotification() async {
    AppLogger.info('🧪 Firing test local notification');
    await _showLocalNotification(
      title: '🚀 Cosmo Strike Test',
      body: 'If you see this, local notifications work end-to-end.',
      payload: jsonEncode({'route': 'home', 'source': 'test'}),
    );
  }

  /// Development-only method to print FCM token for Firebase Console testing
  void printFcmTokenForTesting() {
    if (kDebugMode && _fcmToken != null) {
      debugPrint('');
      debugPrint('🔥 ============ FIREBASE TESTING ============');
      debugPrint('📱 Current FCM Token:');
      debugPrint(_fcmToken!);
      debugPrint('🧪 Steps to test:');
      debugPrint('  1. Copy the token above');
      debugPrint('  2. Go to Firebase Console > Cloud Messaging');
      debugPrint('  3. Create a new notification');
      debugPrint('  4. Paste token in "Send test message" field');
      debugPrint('🔥 =========================================');
      debugPrint('');
    } else if (kDebugMode) {
      debugPrint('⚠️ FCM Token not available for testing');
    }
  }

  // Cleanup
  void dispose() {
    // Clean up resources if needed
    AppLogger.info('🧹 Notification service disposed');
  }
}

// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.info('📨 Background message received: ${message.messageId}');

  // Handle background message
  // Note: Limited functionality in background mode.
  //
  // 'entitlements_changed' pings arriving here are intentionally NOT
  // processed: this isolate has no DI/cubits, and the app's resume path
  // (main.dart didChangeAppLifecycleState → PremiumCubit.syncWithBackend)
  // already re-pulls premium state the moment the user comes back.
}
