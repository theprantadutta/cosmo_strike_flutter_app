import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../debug/demo_mode.dart';
import '../../utils/logger.dart';
import '../analytics/test_device.dart';
import '../api_service.dart';

/// One local calendar day's CUMULATIVE counters for this install. The
/// server keys rows on (install_id, local_date) and keeps the max of each
/// counter, so resending a row is always safe.
class TelemetryDay {
  TelemetryDay({
    required this.localDate,
    required this.tzOffsetMinutes,
    required this.appVersion,
    this.sessions = 0,
    this.runsStarted = 0,
    this.runsFinished = 0,
    this.secondsPlayed = 0,
    this.maxLevel = 0,
    this.acked = false,
  });

  /// `yyyy-MM-dd`, device-local.
  final String localDate;
  int tzOffsetMinutes;

  /// Version the day started on.
  final String appVersion;
  int sessions;
  int runsStarted;
  int runsFinished;
  int secondsPlayed;
  int maxLevel;

  /// The server accepted this row at least once (it may still grow).
  bool acked;

  /// Wire format of one `days[]` entry (counters clamped to the server's
  /// accepted ranges so one bad value can't 400 the whole body).
  Map<String, Object> toWire() => {
    'local_date': localDate,
    'tz_offset_minutes': tzOffsetMinutes.clamp(-720, 840),
    if (appVersion.isNotEmpty) 'app_version': appVersion,
    'sessions': sessions.clamp(0, 1000),
    'runs_started': runsStarted.clamp(0, 5000),
    'runs_finished': runsFinished.clamp(0, 5000),
    'seconds_played': secondsPlayed.clamp(0, 90000),
    'max_level': maxLevel.clamp(0, 100000),
  };

  Map<String, Object> toStore() => {...toWire(), 'acked': acked};

  static TelemetryDay? fromStore(Object? raw) {
    try {
      final m = raw! as Map<String, dynamic>;
      return TelemetryDay(
        localDate: m['local_date'] as String,
        tzOffsetMinutes: (m['tz_offset_minutes'] as int?) ?? 0,
        appVersion: (m['app_version'] as String?) ?? '',
        sessions: (m['sessions'] as int?) ?? 0,
        runsStarted: (m['runs_started'] as int?) ?? 0,
        runsFinished: (m['runs_finished'] as int?) ?? 0,
        secondsPlayed: (m['seconds_played'] as int?) ?? 0,
        maxLevel: (m['max_level'] as int?) ?? 0,
        acked: (m['acked'] as bool?) ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Static facts about this install sent with every heartbeat.
typedef TelemetryAppInfo = ({String appVersion, int build});

/// Device facts sent with every heartbeat.
typedef TelemetryDeviceInfo = ({
  String platform,
  String? locale,
  String? country,
  String? deviceClass,
});

/// Per-install retention telemetry to the backend: every install, guests
/// included, so we can compute our own D1/D7/D30 and day-0 runs.
///
/// Contract: cosmo-strike-dotnet-api `docs/TELEMETRY_CONTRACT.md`.
/// Everything wire-specific lives in [buildBody] and [_post].
///
/// ```
/// POST {ApiService.baseUrl}/telemetry/heartbeat   (baseUrl ends in /api/v1)
/// Content-Type: application/json
/// X-Install-Id: <install_id>
/// Authorization: Bearer <app JWT>                 (only when signed in)
/// { install_id, app_version, build, platform, locale, country,
///   device_class, tz_offset_minutes, is_test,
///   days: [ { local_date, tz_offset_minutes, app_version, sessions,
///             runs_started, runs_finished, seconds_played, max_level } ] }
/// ```
///
/// - **One counter row per local date** in SharedPreferences (device-only),
///   holding CUMULATIVE totals for that day — never deltas.
/// - **Sessions:** +1 on launch and on a resume after [sessionTimeout]
///   (30 min, same rule as GA4) in the background, so the pause/resume
///   around ads and purchase sheets isn't counted as a session.
/// - **Runs:** `runs_started` on run start; `runs_finished` on game over
///   AND quit; `seconds_played` adds each run's duration; `max_level` is
///   the highest level reached that day.
/// - **Flush** on launch, on going to the background and when
///   connectivity returns (no polling timer; well under the server's
///   30 req / 10 min). Sends every unacknowledged day plus today and
///   yesterday, oldest first, ≤ [maxDaysPerRequest] per request.
/// - **Responses:** 200 marks `accepted_dates` acknowledged (today and
///   yesterday are still resent later, they keep growing); 400 drops the
///   body (marked acknowledged, never retried as-is); 413 / 429 / 5xx /
///   network keep the rows and retry with exponential backoff.
/// - **Test traffic:** DemoMode builds never send. `is_test` is true in
///   debug builds and on devices marked with the hidden test-device switch
///   (sticky server-side: the install leaves every retention number).
class TelemetryService {
  TelemetryService({
    http.Client? client,
    String Function()? baseUrl,
    Future<TelemetryAppInfo> Function()? appInfo,
    TelemetryDeviceInfo Function()? deviceInfo,
    bool Function()? isTest,
    String? Function()? authToken,
    DateTime Function()? clock,
    bool? enabled,
    this.scheduleRetries = true,
    this.autoFlush = true,
    this.initialBackoff = const Duration(seconds: 30),
    this.maxBackoff = const Duration(minutes: 30),
    this.requestTimeout = const Duration(seconds: 15),
  }) : enabled = enabled ?? (!DemoMode.enabled && _isMobile()),
       _client = client,
       _baseUrl = baseUrl ?? (() => ApiService.baseUrl),
       _appInfo = appInfo ?? _platformAppInfo,
       _deviceInfo = deviceInfo ?? _platformDeviceInfo,
       _isTest = isTest ?? (() => kDebugMode || TestDevice.instance.isOn),
       _authToken = authToken ?? _defaultAuthToken,
       _clock = clock ?? DateTime.now;

  static TelemetryService? _instance;

  /// App-wide instance (created on first use).
  static TelemetryService get instance => _instance ??= TelemetryService();

  @visibleForTesting
  static set debugInstance(TelemetryService? value) => _instance = value;

  static const int maxDaysPerRequest = 60;
  static const Duration sessionTimeout = Duration(minutes: 30);

  /// Acknowledged rows older than this many days are pruned.
  static const int keepAckedDays = 3;

  static const String kInstallId = 'telemetry_install_id';
  static const String kDays = 'telemetry_days_v1';

  final bool enabled;
  final bool scheduleRetries;

  /// Flush automatically on foreground / background / online (off in tests).
  final bool autoFlush;
  final Duration initialBackoff;
  final Duration maxBackoff;
  final Duration requestTimeout;

  final http.Client? _client;
  final String Function() _baseUrl;
  final Future<TelemetryAppInfo> Function() _appInfo;
  final TelemetryDeviceInfo Function() _deviceInfo;
  final bool Function() _isTest;
  final String? Function() _authToken;
  final DateTime Function() _clock;

  Map<String, TelemetryDay>? _days;
  Future<void> _lock = Future.value();
  Future<bool>? _flushing;
  Timer? _retry;
  int _failures = 0;
  DateTime? _backgroundedAt;
  bool _sessionOpen = false;
  TelemetryAppInfo? _info;

  /// Consecutive failed flushes (0 after a success).
  int get failureCount => _failures;

  /// Delay before the next retry after [failures] consecutive failures.
  Duration backoffFor(int failures) {
    if (failures <= 0) return Duration.zero;
    final ms = initialBackoff.inMilliseconds * math.pow(2, failures - 1);
    return Duration(
      milliseconds: math.min(ms.toInt(), maxBackoff.inMilliseconds),
    );
  }

  static String localDateOf(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  // ------------------------------------------------------------- counting

  /// App came to the foreground (launch or resume). Counts a session when
  /// none is open or the app sat in the background for [sessionTimeout],
  /// then flushes (launch always sends today's row with sessions ≥ 1).
  Future<void> noteForeground() async {
    if (!enabled) return;
    final away = _backgroundedAt;
    _backgroundedAt = null;
    final newSession =
        !_sessionOpen ||
        (away != null && _clock().difference(away) >= sessionTimeout);
    if (newSession) {
      _sessionOpen = true;
      await _update((d) => d.sessions++);
      if (autoFlush) unawaited(flush());
    }
  }

  /// App went to the background: remember when, and send now.
  Future<void> noteBackground() async {
    if (!enabled) return;
    _backgroundedAt ??= _clock();
    if (autoFlush) unawaited(flush());
  }

  /// Connectivity came back: send what's waiting.
  void noteOnline() {
    if (!enabled || !autoFlush) return;
    unawaited(flush());
  }

  /// A run started at campaign [level].
  Future<void> runStarted({int? level}) async {
    if (!enabled) return;
    await _update((d) {
      d.runsStarted++;
      if (level != null && level > d.maxLevel) d.maxLevel = level;
    });
  }

  /// A run ended (game over, victory or quit) after [seconds] of play,
  /// having reached [level].
  Future<void> runFinished({int? level, int? seconds}) async {
    if (!enabled) return;
    await _update((d) {
      d.runsFinished++;
      if (seconds != null && seconds > 0) d.secondsPlayed += seconds;
      if (level != null && level > d.maxLevel) d.maxLevel = level;
    });
  }

  Future<void> _update(void Function(TelemetryDay day) change) async {
    try {
      final info = _info ??= await _appInfo();
      await _locked(() async {
        final days = await _loadDays();
        final now = _clock();
        final key = localDateOf(now);
        final day = days[key] ??= TelemetryDay(
          localDate: key,
          tzOffsetMinutes: now.timeZoneOffset.inMinutes,
          appVersion: info.appVersion,
        );
        day.tzOffsetMinutes = now.timeZoneOffset.inMinutes;
        change(day);
        await _persist();
      });
    } catch (e) {
      AppLogger.info('[Telemetry] update failed: $e');
    }
  }

  // ----------------------------------------------------------------- flush

  /// Sends the pending days. Returns true when everything due was
  /// accepted. Concurrent calls share one in-flight flush.
  Future<bool> flush() {
    if (!enabled) return Future.value(true);
    return _flushing ??= _doFlush().whenComplete(() => _flushing = null);
  }

  /// Rows due for sending: every unacknowledged day plus today and
  /// yesterday, oldest first.
  Future<List<TelemetryDay>> dueDays() => _locked(() async {
    final days = await _loadDays();
    final now = _clock();
    final today = localDateOf(now);
    final yesterday = localDateOf(now.subtract(const Duration(days: 1)));
    final due = days.values
        .where(
          (d) => !d.acked || d.localDate == today || d.localDate == yesterday,
        )
        .toList()
      ..sort((a, b) => a.localDate.compareTo(b.localDate));
    return due;
  });

  Future<bool> _doFlush() async {
    _retry?.cancel();
    _retry = null;
    try {
      final due = await dueDays();
      for (var i = 0; i < due.length; i += maxDaysPerRequest) {
        final chunk = due.sublist(i, math.min(i + maxDaysPerRequest, due.length));
        final result = await _post(chunk);
        if (result == null) {
          _failures++;
          if (scheduleRetries) {
            _retry = Timer(backoffFor(_failures), () => unawaited(flush()));
          }
          return false;
        }
        await _locked(() async {
          final days = await _loadDays();
          for (final date in result) {
            days[date]?.acked = true;
          }
          _prune(days);
          await _persist();
        });
      }
      _failures = 0;
      return true;
    } catch (e) {
      AppLogger.info('[Telemetry] flush failed: $e');
      _failures++;
      return false;
    }
  }

  void _prune(Map<String, TelemetryDay> days) {
    final cutoff = localDateOf(
      _clock().subtract(const Duration(days: keepAckedDays)),
    );
    days.removeWhere((k, d) => d.acked && k.compareTo(cutoff) < 0);
  }

  /// The heartbeat body for [days]. Wire format lives here.
  Future<Map<String, Object>> buildBody(List<TelemetryDay> days) async {
    final info = _info ??= await _appInfo();
    final device = _deviceInfo();
    return {
      'install_id': await installId(),
      'app_version': info.appVersion,
      'build': info.build,
      'platform': device.platform,
      'locale': ?device.locale,
      'country': ?device.country,
      'device_class': ?device.deviceClass,
      'tz_offset_minutes': _clock().timeZoneOffset.inMinutes.clamp(-720, 840),
      'is_test': _isTest(),
      'days': [for (final d in days) d.toWire()],
    };
  }

  /// Posts one request. Returns the dates to mark acknowledged, or null
  /// to keep everything and retry later.
  Future<List<String>?> _post(List<TelemetryDay> days) async {
    final Uri uri;
    try {
      uri = Uri.parse('${_baseUrl()}/telemetry/heartbeat');
    } catch (_) {
      return null; // no base URL yet (e.g. .env not loaded)
    }
    final id = await installId();
    final token = _authToken();
    final headers = {
      'Content-Type': 'application/json',
      'X-Install-Id': id,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final body = jsonEncode(await buildBody(days));
    try {
      final client = _client;
      final res =
          await (client != null
                  ? client.post(uri, headers: headers, body: body)
                  : http.post(uri, headers: headers, body: body))
              .timeout(requestTimeout);
      final code = res.statusCode;
      if (code >= 200 && code < 300) {
        try {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          final accepted = json['accepted_dates'];
          if (accepted is List) return [for (final d in accepted) '$d'];
        } catch (_) {}
        return [for (final d in days) d.localDate];
      }
      if (code == 400) {
        // The body will never pass: drop it (today is still resent later).
        AppLogger.info('[Telemetry] heartbeat rejected (400): ${res.body}');
        return [for (final d in days) d.localDate];
      }
      return null; // 413 / 429 / 5xx / anything else: retry
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- identity

  /// This install's id: a UUID v4 minted on first use, kept in
  /// SharedPreferences (device-only), never reset on sign-out.
  Future<String> installId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(kInstallId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await prefs.setString(kInstallId, id);
    return id;
  }

  // ------------------------------------------------------------- plumbing

  /// Snapshot of the stored day rows (tests / debugging).
  Future<List<TelemetryDay>> storedDays() => _locked(() async {
    final days = await _loadDays();
    return days.values.toList()
      ..sort((a, b) => a.localDate.compareTo(b.localDate));
  });

  Future<Map<String, TelemetryDay>> _loadDays() async {
    final cached = _days;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final map = <String, TelemetryDay>{};
    final raw = prefs.getString(kDays);
    if (raw != null) {
      try {
        for (final e in (jsonDecode(raw) as List)) {
          final d = TelemetryDay.fromStore(e);
          if (d != null) map[d.localDate] = d;
        }
      } catch (_) {}
    }
    return _days = map;
  }

  Future<void> _persist() async {
    final days = _days;
    if (days == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kDays,
      jsonEncode([for (final d in days.values) d.toStore()]),
    );
  }

  /// Serialises access to the day rows (updates and flushes interleave).
  Future<T> _locked<T>(Future<T> Function() body) {
    final result = _lock.then((_) => body());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  @visibleForTesting
  void dispose() => _retry?.cancel();

  /// The backend accepts android / ios only.
  static bool _isMobile() =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<TelemetryAppInfo> _platformAppInfo() async {
    try {
      final p = await PackageInfo.fromPlatform();
      return (appVersion: p.version, build: int.tryParse(p.buildNumber) ?? 0);
    } catch (_) {
      return (appVersion: '0.0.0', build: 0);
    }
  }

  static String? _defaultAuthToken() {
    try {
      final api = ApiService();
      return api.isAuthenticated ? api.accessToken : null;
    } catch (_) {
      return null;
    }
  }

  static TelemetryDeviceInfo _platformDeviceInfo() {
    final dispatcher = PlatformDispatcher.instance;
    final locale = dispatcher.locale;
    String? deviceClass;
    try {
      final view = dispatcher.views.first;
      final size = view.physicalSize / view.devicePixelRatio;
      deviceClass = size.shortestSide >= 600 ? 'tablet' : 'phone';
    } catch (_) {}
    final country = locale.countryCode;
    return (
      platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      locale: locale.toString(),
      country: (country != null && country.length == 2) ? country : null,
      deviceClass: deviceClass,
    );
  }
}
