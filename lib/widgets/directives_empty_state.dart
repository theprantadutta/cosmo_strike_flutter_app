import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cosmo_strike_flutter_app/providers/providers.dart';
import 'package:cosmo_strike_flutter_app/services/daily_challenge_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/account_upgrade_sheet.dart';

/// Which recurring set the empty state speaks for.
enum DirectivesKind { daily, weekly }

/// The ONE truthful empty state for Daily Directives / Weekly Ops, shared by
/// the Directives hub and the pause / game-over directives panel so every
/// surface gives the same reason:
///
/// - accountless pilot + Weekly Ops → "Sign in for Weekly Ops" + account
///   button (ops come from the backend; guests get Daily Directives locally);
/// - actually offline → "Offline · arrives when you reconnect";
/// - otherwise → the set hasn't posted yet, with an optional retry.
class DirectivesEmptyState extends ConsumerWidget {
  const DirectivesEmptyState({
    super.key,
    this.kind = DirectivesKind.daily,
    this.compact = false,
    this.onRetry,
  });

  final DirectivesKind kind;
  final bool compact;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).value ?? true;
    final daily = kind == DirectivesKind.daily;
    final noun = daily ? 'directives' : 'Weekly Ops';

    if (DailyChallengeService.isAccountlessPilot() && !daily) {
      return CsEmptyState(
        compact: compact,
        icon: Symbols.event_repeat_rounded,
        title: 'Sign in for Weekly Ops',
        message: 'Weekly Ops are issued to pilots with an account. '
            'Your progress on this device comes with you.',
        action: CsButton.secondary(
          label: 'Sign in',
          icon: Symbols.person_add_rounded,
          onPressed: () => showAccountUpgradeSheet(
            context,
            reason: AccountUpgradeReason.saveProgress,
          ),
        ),
      );
    }

    final retry = onRetry == null
        ? null
        : CsButton.secondary(
            label: 'Retry',
            icon: Symbols.refresh_rounded,
            onPressed: onRetry,
          );

    if (!online) {
      return CsEmptyState(
        compact: compact,
        icon: Symbols.cloud_off_rounded,
        title: 'Offline',
        message: daily
            ? "Today's directives arrive when you reconnect."
            : "This week's ops arrive when you reconnect.",
        action: retry,
      );
    }

    return CsEmptyState(
      compact: compact,
      icon: daily ? Symbols.calendar_today_rounded : Symbols.event_repeat_rounded,
      title: 'No $noun yet',
      message: daily
          ? "Today's orders haven't posted. Check back shortly."
          : "This week's ops haven't posted. Check back shortly.",
      action: retry,
    );
  }
}
