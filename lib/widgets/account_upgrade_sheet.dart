import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

/// Dialog shown when an anonymous (guest) user tries to make a purchase.
/// Offers two ways to upgrade the account in place — keeping the same
/// Firebase UID so existing game progress, coins, and cosmetics stay
/// attached.
///
/// Returns `true` from [showAccountUpgradeSheet] if the user successfully
/// linked an account (caller should re-check `isAnonymous` and proceed),
/// `false` if they dismissed or cancelled.
Future<bool> showAccountUpgradeSheet(BuildContext context) async {
  final result = await showCsDialog<bool>(
    context,
    builder: (_) => const _AccountUpgradeDialog(),
  );
  return result ?? false;
}

class _AccountUpgradeDialog extends StatefulWidget {
  const _AccountUpgradeDialog();

  @override
  State<_AccountUpgradeDialog> createState() => _AccountUpgradeDialogState();
}

class _AccountUpgradeDialogState extends State<_AccountUpgradeDialog> {
  bool _busy = false;

  Future<void> _linkGoogle() async {
    // Capture context-bound handles before the await so we can dismiss the
    // dialog and show feedback safely afterwards.
    final cubit = context.read<AuthCubit>();
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final ok = await cubit.linkAnonymousToGoogle();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      showCsToast(context, 'Account linked. You can now make purchases.', kind: CsToastKind.success);
      navigator.pop(true);
    } else {
      final code = cubit.state.errorMessage ?? '';
      if (code.isNotEmpty && code != 'link failed') {
        showCsToast(context, _linkError(code), kind: CsToastKind.error);
      }
    }
  }

  void _createEmailAccount() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop(false);
    router.push('${AppRoutes.emailAuth}?link=1');
  }

  @override
  Widget build(BuildContext context) {
    return CsDialog(
      icon: Symbols.lock_rounded,
      eyebrow: 'Guest account',
      title: 'Sign up to make purchases',
      message: 'Guest accounts can play and save progress locally, but cannot buy items or subscribe. '
          'Link a Google or email account to unlock purchases — your existing coins, cosmetics, '
          'and high scores stay attached.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UpgradeOption(
            icon: Symbols.account_circle_rounded,
            title: 'Continue with Google',
            subtitle: 'Fastest option. Sign in with your Google account.',
            busy: _busy,
            showSpinner: _busy,
            dividerTop: true,
            onPressed: _linkGoogle,
          ),
          _UpgradeOption(
            icon: Symbols.mail_rounded,
            title: 'Create an Email Account',
            subtitle: 'Use any email and a password you choose. Restore on any device.',
            busy: _busy,
            onPressed: _createEmailAccount,
          ),
        ],
      ),
      actions: [
        CsButton.text(
          label: 'Not now',
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }

  String _linkError(String code) {
    switch (code) {
      case 'credential-already-in-use':
      case 'email-already-in-use':
        return 'That credential is already linked to another account. Try signing in with it instead.';
      case 'provider-already-linked':
        return 'This account is already linked.';
      case 'requires-recent-login':
        return 'For security, sign in again before linking.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Linking failed. Please try again.';
    }
  }
}

class _UpgradeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final bool showSpinner;
  final bool dividerTop;
  final VoidCallback onPressed;

  const _UpgradeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onPressed,
    this.showSpinner = false,
    this.dividerTop = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Opacity(
      opacity: busy && !showSpinner ? 0.4 : 1,
      child: CsListRow(
        title: title,
        subtitle: subtitle,
        dividerTop: dividerTop,
        leading: CsIconDisc(icon),
        trailing: showSpinner
            ? SizedBox.square(
                dimension: cs(18),
                child: const CircularProgressIndicator(strokeWidth: 2, color: CsColors.ink),
              )
            : Icon(Symbols.chevron_right_rounded, size: cs(22), color: CsColors.ink45),
        onTap: busy ? null : onPressed,
      ),
    );
  }
}
