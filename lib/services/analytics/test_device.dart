import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../debug/demo_mode.dart';
import '../../utils/logger.dart';
import 'analytics_facade.dart';
import 'analytics_gate.dart';

/// Hidden developer switch that marks this device as one of our own test
/// devices, so device testing stops polluting GA4 (a Nov 19 2026 spike was
/// just us testing).
///
/// Turn it on: Settings → About & Credits → tap the version chip 7 times
/// ("Test device: on"). Same again turns it off. Persisted in
/// SharedPreferences (device-only).
///
/// While on: Firebase Analytics collection is disabled
/// (`setAnalyticsCollectionEnabled(false)`, re-applied on every launch in
/// main.dart), the user property `test_device=1` is set just before, and
/// backend telemetry heartbeats carry `isTest: true` so the server can
/// exclude them.
class TestDevice {
  TestDevice._();
  static final TestDevice instance = TestDevice._();

  static const String prefsKey = 'analytics_test_device';

  bool _on = false;

  /// Whether this device is marked as a test device (false until [load]).
  bool get isOn => _on;

  /// Reads the persisted flag. Returns it.
  Future<bool> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _on = prefs.getBool(prefsKey) ?? false;
    } catch (e) {
      AppLogger.error('TestDevice load failed', e);
    }
    return _on;
  }

  /// Flips the switch, persists it and applies it to analytics.
  Future<void> setOn(
    bool on, {
    AnalyticsFacade? analytics,
    bool debug = kDebugMode,
    bool demo = DemoMode.enabled,
  }) async {
    _on = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefsKey, on);
    } catch (e) {
      AppLogger.error('TestDevice persist failed', e);
    }
    final a =
        analytics ??
        (GetIt.I.isRegistered<AnalyticsFacade>()
            ? GetIt.I<AnalyticsFacade>()
            : null);
    if (a == null) return;
    if (on) {
      // Property first: it rides out with whatever is still queued.
      await a.setUserProperty('test_device', '1');
      await a.setCollectionEnabled(false);
    } else {
      await a.setCollectionEnabled(
        AnalyticsGate.collectionEnabled(
          testDevice: false,
          debug: debug,
          demo: demo,
        ),
      );
      await a.setUserProperty('test_device', null);
    }
  }

  /// Tap-to-toggle used by the hidden switch.
  Future<bool> toggle() async {
    await setOn(!_on);
    return _on;
  }

  @visibleForTesting
  void debugReset() => _on = false;
}
