import 'package:flutter/foundation.dart';

import '../../debug/demo_mode.dart';
import 'analytics_client.dart';
import 'firebase_analytics_client.dart';
import 'logger_analytics_client.dart';

/// Decides which devices/builds may feed production analytics.
///
/// - Debug builds and DemoMode (autopilot / profiling) builds only ever log
///   locally: autopilot runs are release-signed and used to send
///   `power_up_used` etc. into the real property.
/// - A device marked as a test device (`TestDevice`, hidden switch in
///   About & Credits) keeps the Firebase client but has collection
///   switched off, so its events never reach GA4.
abstract final class AnalyticsGate {
  /// True when only the console logger client may be registered.
  static bool loggerOnly({
    bool debug = kDebugMode,
    bool demo = DemoMode.enabled,
  }) => debug || demo;

  /// The clients the [AnalyticsFacade] fans out to.
  static List<AnalyticsClient> buildClients({
    bool debug = kDebugMode,
    bool demo = DemoMode.enabled,
  }) => [
    if (loggerOnly(debug: debug, demo: demo))
      LoggerAnalyticsClient()
    else
      FirebaseAnalyticsClient(),
  ];

  /// Whether native Firebase Analytics collection (incl. automatic events
  /// like first_open / session_start) may be on for this device.
  static bool collectionEnabled({
    required bool testDevice,
    bool debug = kDebugMode,
    bool demo = DemoMode.enabled,
  }) => !debug && !demo && !testDevice;
}
