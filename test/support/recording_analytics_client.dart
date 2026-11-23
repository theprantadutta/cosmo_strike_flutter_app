import 'package:cosmo_strike_flutter_app/services/analytics/analytics_client.dart';

/// Test double that records the calls the measurement tests check and
/// no-ops everything else.
class RecordingAnalyticsClient implements AnalyticsClient {
  final List<(String, Map<String, Object>)> events = [];
  final Map<String, String?> userProperties = {};
  final List<bool> collection = [];
  final List<Map<String, Object?>> gameOvers = [];

  List<Map<String, Object>> named(String name) => [
    for (final e in events)
      if (e.$1 == name) e.$2,
  ];

  @override
  Future<void> trackEvent(String name, Map<String, Object> parameters) async =>
      events.add((name, parameters));

  @override
  Future<void> setUserProperty(String name, String? value) async =>
      userProperties[name] = value;

  @override
  Future<void> setCollectionEnabled(bool enabled) async =>
      collection.add(enabled);

  @override
  Future<void> trackGameOver({
    required int score,
    required int durationSeconds,
    required int stageReached,
    required int levelsCleared,
    required int enemiesKilled,
    required int maxCombo,
    required bool victory,
    required String gameMode,
    int? runNumber,
    bool? onboarding,
    String? endTrigger,
  }) async => gameOvers.add({
    'score': score,
    'game_mode': gameMode,
    'run_number': runNumber,
    'onboarding': onboarding,
    'end_trigger': endTrigger,
  });

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
