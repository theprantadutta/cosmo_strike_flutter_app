/// Pure builders for analytics parameter maps and values, kept apart from
/// the Firebase client so tests can check exact GA4 names without Firebase.
///
/// Every parameter name here must be registered in GA4 as a custom
/// definition before it shows in reports:
/// docs/analytics/GA4_CUSTOM_DEFINITIONS.md.
abstract final class AnalyticsParams {
  /// GA4 drops string values longer than 100 characters.
  static const int maxStringLength = 100;

  static String clip(String value) => value.length > maxStringLength
      ? value.substring(0, maxStringLength)
      : value;

  /// `game_over` parameters. The run context (`run_number`, `onboarding`,
  /// `end_trigger`) is only added when known.
  static Map<String, Object> gameOver({
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
  }) => {
    'score': score,
    'duration_seconds': durationSeconds,
    'stage_reached': stageReached,
    'levels_cleared': levelsCleared,
    'enemies_killed': enemiesKilled,
    'max_combo': maxCombo,
    'victory': victory ? 1 : 0,
    'game_mode': gameMode,
    'run_number': ?runNumber,
    if (onboarding != null) 'onboarding': onboarding ? 1 : 0,
    'end_trigger': ?endTrigger,
  };

  /// ISO-8601 year-week of [date], e.g. `2026-W48`. Weeks start on Monday;
  /// week 1 is the week with the year's first Thursday, so the first days
  /// of January can belong to the previous year's last week.
  static String isoWeek(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    // Thursday of this ISO week decides the week-year.
    final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
    final jan1 = DateTime.utc(thursday.year, 1, 1);
    final week = (thursday.difference(jan1).inDays ~/ 7) + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  /// `push_type` for a tapped notification: the payload's `type`, else its
  /// `action`, else its `route`, else [fallback].
  static String pushType(Map<String, dynamic>? data, {String fallback = 'unknown'}) {
    if (data == null) return fallback;
    for (final key in const ['type', 'action', 'route']) {
      final v = data[key];
      if (v is String && v.isNotEmpty) return clip(v);
    }
    return fallback;
  }
}
