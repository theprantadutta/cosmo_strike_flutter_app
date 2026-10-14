import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../presentation/bloc/auth/auth_cubit.dart';
import '../services/first_run_service.dart';
import 'account_upgrade_sheet.dart';

/// "Save your progress" nudge for players without an account, offered on a
/// new personal best once onboarding is done — the moment there's something
/// worth protecting. Budgeted: at most [_maxAsks] times, [_cooldown] apart;
/// the budget is spent when shown, not on conversion. Mirrors Snake
/// Classic's DeferredSignInPrompt.
class DeferredSignInPrompt {
  DeferredSignInPrompt._();

  static const _kCount = 'deferred_signin_ask_count';
  static const _kLast = 'deferred_signin_last_ask_ms';
  static const _maxAsks = 3;
  static const _cooldown = Duration(days: 3);

  static Future<void> maybeShow(BuildContext context) async {
    // Guest (local) and Firebase-anonymous both count as "no credential".
    final auth = context.read<AuthCubit>().state;
    final hasCredential = auth.isSignedIn && !auth.isAnonymous && !auth.isGuestUser;
    if (hasCredential || !FirstRunService.instance.hasCompletedOnboarding) return;

    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_kCount) ?? 0;
    final last = prefs.getInt(_kLast);
    if (count >= _maxAsks) return;
    if (last != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) < _cooldown) {
      return;
    }
    await prefs.setInt(_kCount, count + 1);
    await prefs.setInt(_kLast, DateTime.now().millisecondsSinceEpoch);
    if (!context.mounted) return;
    await showAccountUpgradeSheet(context, reason: AccountUpgradeReason.saveProgress);
  }
}
