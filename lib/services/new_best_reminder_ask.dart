import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/notification_soft_ask.dart';
import 'notification_service.dart';
import 'notification_settings_opener.dart';

/// The session-one notification ask: an inline "Remind me tomorrow to beat
/// 9,170?" row on the game over of the first run that sets a new personal
/// best (any run, the onboarding ones included). Most players who leave on
/// day 0 never reach the Home queue's post-onboarding soft-ask, so without
/// this the comeback reminder ([NotificationService.scheduleComebackReminder])
/// silently does nothing for them.
///
/// Rules: offered at most once per install (persisted when shown), never as
/// a dialog and never mid-run (the game over only). The row IS the soft ask:
/// the OS prompt appears only after "Remind me". A player who answers it
/// (either way) is not asked again by the Home queue; one who ignores it
/// still gets that Home soft-ask as the fallback.
abstract final class NewBestReminderAsk {
  static const String _kShown = 'new_best_reminder_ask_shown';
  static const String _kAnswered = 'new_best_reminder_ask_answered';

  /// Whether this game over should show the row. [notificationsEnabled]
  /// overrides the OS check (tests).
  static Future<bool> shouldOffer({
    required bool isNewBest,
    Future<bool> Function()? notificationsEnabled,
  }) async {
    if (!isNewBest) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getBool(_kShown) ?? false) ||
          (prefs.getBool(_kAnswered) ?? false)) {
        return false;
      }
      final enabled = await (notificationsEnabled ??
          NotificationService().areNotificationsEnabled)();
      return !enabled;
    } catch (_) {
      return false;
    }
  }

  /// Marks the one impression as used.
  static Future<void> recordShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kShown, true);
    } catch (_) {}
  }

  /// The pilot tapped "Remind me" or dismissed the row: never ask here
  /// again, and retire the Home soft-ask too (they already answered).
  static Future<void> recordAnswered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAnswered, true);
      await NotificationSoftAsk.markShown();
    } catch (_) {}
  }

  /// "Remind me": the OS prompt (or the app's notification settings when
  /// the prompt is blocked), then — if granted — arms the comeback reminder
  /// quoting [bestScore]. Returns whether notifications are now on.
  static Future<bool> accept({required int bestScore}) async {
    await recordAnswered();
    final granted = await NotificationSettingsOpener.requestOrOpen();
    if (granted) {
      await NotificationService().scheduleComebackReminder(bestScore: bestScore);
    }
    return granted;
  }
}
