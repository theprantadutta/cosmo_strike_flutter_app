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
        eyebrow: 'Stay in the loop',
        title: 'Never miss a reward',
        message: 'Get a heads-up when your daily bonus is ready, a new Daily Run '
            'drops, or an event is about to end. No spam — you can turn '
            'each type off in Settings.',
        actions: [
          CsButton.text(label: 'Not now', onPressed: () => Navigator.of(dialogContext).pop(false)),
          CsButton.primary(label: 'Turn on', onPressed: () => Navigator.of(dialogContext).pop(true)),
        ],
      ),
    );
    if (enable == true) await NotificationService().requestPermissionFlow();
    return true;
  }
}
