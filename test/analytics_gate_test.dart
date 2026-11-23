import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_gate.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/firebase_analytics_client.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/logger_analytics_client.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/test_device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_analytics_client.dart';

void main() {
  group('AnalyticsGate', () {
    test('DemoMode (autopilot) release builds only get the logger client', () {
      final clients = AnalyticsGate.buildClients(debug: false, demo: true);
      expect(clients, hasLength(1));
      expect(clients.single, isA<LoggerAnalyticsClient>());
    });

    test('debug builds only get the logger client', () {
      final clients = AnalyticsGate.buildClients(debug: true, demo: false);
      expect(clients.single, isA<LoggerAnalyticsClient>());
    });

    test('plain release builds get the Firebase client', () {
      final clients = AnalyticsGate.buildClients(debug: false, demo: false);
      expect(clients.single, isA<FirebaseAnalyticsClient>());
    });

    test('native collection is off for debug, demo and test devices', () {
      expect(
        AnalyticsGate.collectionEnabled(testDevice: false, debug: false, demo: false),
        isTrue,
      );
      expect(
        AnalyticsGate.collectionEnabled(testDevice: true, debug: false, demo: false),
        isFalse,
      );
      expect(
        AnalyticsGate.collectionEnabled(testDevice: false, debug: false, demo: true),
        isFalse,
      );
      expect(
        AnalyticsGate.collectionEnabled(testDevice: false, debug: true, demo: false),
        isFalse,
      );
    });
  });

  group('TestDevice switch', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDevice.instance.debugReset();
    });

    test('turning it on disables collection, sets test_device=1 and persists',
        () async {
      final client = RecordingAnalyticsClient();
      await TestDevice.instance.setOn(
        true,
        analytics: AnalyticsFacade([client]),
        debug: false,
        demo: false,
      );

      expect(TestDevice.instance.isOn, isTrue);
      expect(client.userProperties['test_device'], '1');
      expect(client.collection, [false]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(TestDevice.prefsKey), isTrue);

      // A fresh launch reads it back and keeps collection off.
      TestDevice.instance.debugReset();
      expect(await TestDevice.instance.load(), isTrue);
      expect(AnalyticsGate.collectionEnabled(testDevice: true, debug: false, demo: false), isFalse);
    });

    test('turning it off re-enables collection and clears the property', () async {
      final client = RecordingAnalyticsClient();
      final facade = AnalyticsFacade([client]);
      await TestDevice.instance.setOn(true, analytics: facade, debug: false, demo: false);
      await TestDevice.instance.setOn(false, analytics: facade, debug: false, demo: false);

      expect(TestDevice.instance.isOn, isFalse);
      expect(client.collection, [false, true]);
      expect(client.userProperties.containsKey('test_device'), isTrue);
      expect(client.userProperties['test_device'], isNull);
    });

    test('off in a debug build keeps collection off', () async {
      final client = RecordingAnalyticsClient();
      await TestDevice.instance.setOn(
        false,
        analytics: AnalyticsFacade([client]),
        debug: true,
        demo: false,
      );
      expect(client.collection, [false]);
    });
  });
}
