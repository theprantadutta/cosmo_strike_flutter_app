import 'dart:convert';
import 'dart:io';

import 'package:cosmo_strike_flutter_app/services/telemetry/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DateTime now;
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime(2026, 11, 23, 15);
    requests = [];
    respond = (req) {
      final days = (jsonDecode(req.body)['days'] as List)
          .map((d) => d['local_date'])
          .toList();
      return http.Response(
        jsonEncode({'accepted_days': days.length, 'accepted_dates': days}),
        200,
      );
    };
  });

  TelemetryService make({bool enabled = true, bool isTest = false}) =>
      TelemetryService(
        enabled: enabled,
        scheduleRetries: false,
        autoFlush: false,
        client: MockClient((req) async {
          requests.add(req);
          return respond(req);
        }),
        baseUrl: () => 'https://api.test/api/v1',
        appInfo: () async => (appVersion: '3.7.0', build: 29),
        deviceInfo: () => (
          platform: 'android',
          locale: 'en_US',
          country: 'US',
          deviceClass: 'phone',
        ),
        isTest: () => isTest,
        authToken: () => null,
        clock: () => now,
      );

  Map<String, dynamic> body(http.Request r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  test('launch counts a session and sends today\'s row', () async {
    final t = make(isTest: true);
    await t.noteForeground();
    await t.flush();

    expect(requests, isNotEmpty);
    final r = requests.last;
    expect(r.url.toString(), 'https://api.test/api/v1/telemetry/heartbeat');
    final b = body(r);
    expect(r.headers['X-Install-Id'], b['install_id']);
    expect(r.headers.containsKey('Authorization'), isFalse);
    expect(b['app_version'], '3.7.0');
    expect(b['build'], 29);
    expect(b['platform'], 'android');
    expect(b['is_test'], isTrue);
    final day = (b['days'] as List).single as Map<String, dynamic>;
    expect(day['local_date'], '2026-11-23');
    expect(day['sessions'], 1);
  });

  test('install id is minted once and reused', () async {
    final t = make();
    final a = await t.installId();
    expect(await make().installId(), a);
    expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(a), isTrue);
  });

  test('day rows are cumulative and resent unchanged-safe (no deltas)',
      () async {
    final t = make();
    await t.noteForeground();
    await t.runStarted(level: 1);
    await t.runFinished(level: 3, seconds: 95);
    await t.runStarted(level: 1);
    await t.flush();
    await t.runFinished(level: 2, seconds: 40);
    await t.flush();

    final first = (body(requests[requests.length - 2])['days'] as List).single;
    final second = (body(requests.last)['days'] as List).single;
    expect(first['runs_started'], 2);
    expect(first['runs_finished'], 1);
    expect(second['runs_finished'], 2);
    expect(second['seconds_played'], 135);
    expect(second['max_level'], 3);
    // Today is resent even though it was acknowledged: it keeps growing.
    expect(second['local_date'], first['local_date']);
  });

  test('resume within 30 min is the same session; after 30 min a new one',
      () async {
    final t = make();
    await t.noteForeground();
    await t.noteBackground();
    now = now.add(const Duration(minutes: 10));
    await t.noteForeground();
    expect((await t.storedDays()).single.sessions, 1);
    await t.noteBackground();
    now = now.add(const Duration(minutes: 31));
    await t.noteForeground();
    expect((await t.storedDays()).single.sessions, 2);
  });

  test('backlog over 60 days goes out in batches, oldest first', () async {
    final rows = [
      for (var i = 70; i >= 1; i--)
        {
          'local_date': TelemetryService.localDateOf(
            now.subtract(Duration(days: i)),
          ),
          'sessions': 1,
          'acked': false,
        },
    ];
    SharedPreferences.setMockInitialValues({
      TelemetryService.kDays: jsonEncode(rows),
    });
    final t = make();
    expect(await t.flush(), isTrue);

    expect(requests, hasLength(2));
    final a = body(requests[0])['days'] as List;
    final b = body(requests[1])['days'] as List;
    expect(a, hasLength(60));
    expect(b, hasLength(10));
    expect(a.first['local_date'], rows.first['local_date']);
    expect(
      (a.first['local_date'] as String).compareTo(a.last['local_date'] as String),
      lessThan(0),
    );

    // All acknowledged: the next flush only resends yesterday.
    requests.clear();
    await t.flush();
    final again = body(requests.single)['days'] as List;
    expect(again.map((d) => d['local_date']), [
      TelemetryService.localDateOf(now.subtract(const Duration(days: 1))),
    ]);
  });

  test('offline: keeps the rows, retries later with the same dates', () async {
    respond = (_) => throw const SocketException('offline');
    final t = make();
    await t.noteForeground();
    expect(await t.flush(), isFalse);
    expect(t.failureCount, 1);
    expect((await t.storedDays()).single.acked, isFalse);
    expect(t.backoffFor(1), const Duration(seconds: 30));
    expect(t.backoffFor(3), const Duration(minutes: 2));
    expect(t.backoffFor(20), const Duration(minutes: 30));

    respond = (req) => http.Response(
      jsonEncode({'accepted_days': 1, 'accepted_dates': ['2026-11-23']}),
      200,
    );
    expect(await t.flush(), isTrue);
    expect(t.failureCount, 0);
    expect((await t.storedDays()).single.acked, isTrue);
  });

  test('429 / 5xx keep the data; 400 drops the body', () async {
    final t = make();
    await t.noteForeground();
    respond = (_) => http.Response('slow down', 429);
    expect(await t.flush(), isFalse);
    expect((await t.storedDays()).single.acked, isFalse);

    respond = (_) => http.Response('{"error":"bad"}', 400);
    expect(await t.flush(), isTrue);
    expect((await t.storedDays()).single.acked, isTrue);
  });

  test('acknowledged rows older than 3 days are pruned', () async {
    SharedPreferences.setMockInitialValues({
      TelemetryService.kDays: jsonEncode([
        {'local_date': '2026-11-10', 'sessions': 1, 'acked': true},
        {'local_date': '2026-11-11', 'sessions': 1, 'acked': false},
      ]),
    });
    final t = make();
    await t.flush();
    final dates = (await t.storedDays()).map((d) => d.localDate);
    expect(dates, isNot(contains('2026-11-10')));
    expect(dates, isNot(contains('2026-11-11'))); // acked now, then pruned
  });

  test('disabled (DemoMode) records and sends nothing', () async {
    final t = make(enabled: false);
    await t.noteForeground();
    await t.runStarted(level: 1);
    await t.flush();
    expect(requests, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(TelemetryService.kDays), isNull);
  });
}
