/// Pure scheduling + copy for the one-shot comeback reminder (see
/// `NotificationService.scheduleComebackReminder`). Kept free of plugins so
/// the quiet-hours maths is unit-testable.
class ComebackReminder {
  ComebackReminder._();

  /// How long after the player leaves the nudge fires: far enough to read as
  /// "next day", close enough to land inside the Day-1 retention window.
  static const Duration delay = Duration(hours: 20);

  /// Local quiet window [quietStartHour, quietEndHour) that wraps midnight.
  static const int quietStartHour = 22;
  static const int quietEndHour = 9;

  /// Where a fire time that lands in the quiet window is pushed to.
  static const int morningHour = 10;

  /// When the reminder should fire for a session that ended at [from]
  /// (device-local wall clock): [delay] later, moved to [morningHour] if that
  /// lands between [quietStartHour] and [quietEndHour]. Late evening rolls
  /// to the next morning; small hours move to the same morning.
  static DateTime fireTime(DateTime from) {
    final local = from.toLocal();
    final target = local.add(delay);
    if (target.hour >= quietStartHour) {
      return DateTime(target.year, target.month, target.day + 1, morningHour);
    }
    if (target.hour < quietEndHour) {
      return DateTime(target.year, target.month, target.day, morningHour);
    }
    return target;
  }

  static const String title = 'Ship fueled. Sortie standing by.';

  /// Body copy: a concrete score to beat when the pilot has one.
  static String body(int bestScore) => bestScore > 0
      ? 'Best run on file: ${groupDigits(bestScore)}. Launch and top it.'
      : "Today's Daily Run is live. Launch when ready.";

  /// 12480 -> "12,480".
  static String groupDigits(int value) {
    final digits = value.abs().toString();
    final out = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}
