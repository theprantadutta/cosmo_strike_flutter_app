/// Daily Directives streak maths: the number of LOCAL calendar days in a row
/// on which the pilot completed at least one directive.
///
/// Pure functions over a list of day anchors so they can be unit tested; the
/// days come from the retained Drift history
/// (`GameDao.getCompletedChallengeDays`), see `DailyChallengeService`.
///
/// A streak is still alive when today has no completion yet: it counts up to
/// yesterday and is "at risk" until a directive is cleared today. It breaks
/// only once a whole day passes with nothing completed.
class DirectiveStreak {
  DirectiveStreak._();

  /// How far back the history is kept and read. The streak can't count past
  /// it (it plateaus at about this many days).
  static const Duration historyWindow = Duration(days: 400);

  static DateTime _day(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// Consecutive days with a completion, ending YESTERDAY (today ignored).
  static int pastRun(Iterable<DateTime> completedDays, DateTime now) {
    final days = {for (final d in completedDays) _day(d)};
    final today = _day(now);
    var run = 0;
    // DateTime(y, m, d - i) normalises month/year rollover and is DST-safe
    // (unlike subtracting 24 h).
    while (days.contains(DateTime(today.year, today.month, today.day - run - 1))) {
      run++;
    }
    return run;
  }

  /// Whether [completedDays] includes today.
  static bool securedToday(Iterable<DateTime> completedDays, DateTime now) {
    final today = _day(now);
    return completedDays.any((d) => _day(d) == today);
  }

  /// The full streak: [pastRun] plus today when today is already secured.
  static int compute(Iterable<DateTime> completedDays, DateTime now) =>
      pastRun(completedDays, now) + (securedToday(completedDays, now) ? 1 : 0);
}
