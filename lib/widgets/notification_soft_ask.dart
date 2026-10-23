import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';
import '../ui/cs.dart';

/// In-app "soft ask" before the OS notification dialog. Shown once ever,
/// from the Home prompt queue after onboarding; only "Turn on" fires the
/// system prompt, so a "Not now" never burns the one-shot Android dialog.
class NotificationSoftAsk {
  NotificationSoftAsk._();

  static const _kShown = 'notif_soft_ask_shown';

  /// Returns true when the ask was shown (it counts as this visit's
  /// interruption).
  static Future<bool> maybeShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kShown) ?? false) return false;
    if (await NotificationService().areNotificationsEnabled()) {
      await prefs.setBool(_kShown, true);
      return false;
    }
    await prefs.setBool(_kShown, true);
    if (!context.mounted) return false;
    final enable = await showCsDialog<bool>(
      context,
      builder: (dialogContext) => CsDialog(
        icon: Symbols.notifications_active_rounded,
        eyebrow: 'Comms',
        title: 'Open a channel?',
        message: 'We ping you when a Supply Drop is ready, a new Daily Run '
            'posts, or a Sector Cup is closing. Each channel can be muted '
            'in Settings.',
        actions: [
          CsButton.text(label: 'Not now', onPressed: () => Navigator.of(dialogContext).pop(false)),
          CsButton.primary(label: 'Open channel', onPressed: () => Navigator.of(dialogContext).pop(true)),
        ],
      ),
    );
    if (enable == true) await NotificationService().requestPermissionFlow();
    return true;
  }
}
