import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

/// Why the account dialog is being offered — changes the copy only.
enum AccountUpgradeReason {
  /// Purchase-related nudge: optional — guests can buy without an account.
  purchase,

  /// Deferred nudge (new personal best after onboarding) / profile.
  saveProgress,
}

/// Account dialog for players without a credential: Firebase anonymous
/// users (linked in place, same UID) and the silent local guest every new
/// install starts as (plain sign-in — a brand-new backend account keeps
/// this device's progress and pushes it up; an existing account restores
/// its cloud save).
///
/// Returns `true` from [showAccountUpgradeSheet] if an account was
/// connected, `false` if dismissed or cancelled.
Future<bool> showAccountUpgradeSheet(
  BuildContext context, {
  AccountUpgradeReason reason = AccountUpgradeReason.purchase,
}) async {
  final result = await showCsDialog<bool>(
    context,
    builder: (_) => _AccountUpgradeDialog(reason: reason),
  );
  return result ?? false;
}

class _AccountUpgradeDialog extends StatefulWidget {
  const _AccountUpgradeDialog({required this.reason});
  final AccountUpgradeReason reason;

  @override
  State<_AccountUpgradeDialog> createState() => _AccountUpgradeDialogState();
}

class _AccountUpgradeDialogState extends State<_AccountUpgradeDialog> {
  bool _busy = false;

  /// Which option is in flight, so only its row shows the spinner.
  String? _pending;

  bool get _forPurchase => widget.reason == AccountUpgradeReason.purchase;

  Future<void> _linkGoogle() => _connect(
        'google',
        link: (cubit) => cubit.linkAnonymousToGoogle(),
        signIn: (cubit) => cubit.signInWithGoogle(),
      );

  Future<void> _linkApple() => _connect(
        'apple',
        link: (cubit) => cubit.linkAnonymousToApple(),
        signIn: (cubit) => cubit.signInWithApple(),
      );

  Future<void> _connect(
    String provider, {
    required Future<bool> Function(AuthCubit) link,
    required Future<bool> Function(AuthCubit) signIn,
  }) async {
    // Capture context-bound handles before the await so we can dismiss the
    // dialog and show feedback safely afterwards.
    final cubit = context.read<AuthCubit>();
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _pending = provider;
    });
    final bool ok;
    if (cubit.state.isAnonymous) {
      // Firebase anonymous: link in place so the UID (and backend row) stays.
      ok = await link(cubit);
    } else {
      // Local offline guest: nothing to link, so sign in. First-sign-in
      // keeps local progress for a new account (is_new_user) and restores
      // the cloud save for an existing one.
      ok = await signIn(cubit);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pending = null;
    });
    if (ok) {
      showCsToast(
        context,
        _forPurchase ? 'Signed in. Your purchases now follow you to every device.' : 'Signed in. Your progress is backed up.',
        kind: CsToastKind.success,
      );
      navigator.pop(true);
    } else {
      final code = cubit.state.errorMessage ?? '';
      if (code.isNotEmpty &&
          code != 'link failed' &&
          code != 'Google sign-in failed' &&
          code != 'Apple sign-in failed' &&
          code != 'canceled') {
        showCsToast(context, _linkError(code), kind: CsToastKind.error);
      }
    }
  }

  void _createEmailAccount() {
    final router = GoRouter.of(context);
    final anonymous = context.read<AuthCubit>().state.isAnonymous;
    Navigator.of(context).pop(false);
    // Link mode only applies to a Firebase anonymous user; a local guest
    // just signs in / signs up.
    router.push(anonymous ? '${AppRoutes.emailAuth}?link=1' : AppRoutes.emailAuth);
  }

  @override
  Widget build(BuildContext context) {
    return CsDialog(
      icon: _forPurchase ? Symbols.devices_rounded : Symbols.cloud_upload_rounded,
      eyebrow: _forPurchase ? 'Optional' : 'New personal best',
      title: _forPurchase ? 'Keep purchases on every device' : 'Save your progress',
      message: _forPurchase
          ? 'Signing in is optional. It lets you restore your coins, cosmetics '
              'and Pro on any device. You can keep playing and buying as a guest.'
          : "You're playing as a guest, so your progress lives only on this device. "
              'Sign in to back it up, climb the leaderboards and play on any device.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (appleSignInAvailable)
            _UpgradeOption(
              brandIcon: FontAwesomeIcons.apple,
              title: 'Continue with Apple',
              subtitle: 'Use your Apple Account. You can hide your email.',
              busy: _busy,
              showSpinner: _pending == 'apple',
              dividerTop: true,
              onPressed: _linkApple,
            ),
          _UpgradeOption(
            brandIcon: FontAwesomeIcons.google,
            title: 'Continue with Google',
            subtitle: 'Fastest option. Sign in with your Google account.',
            busy: _busy,
            showSpinner: _pending == 'google',
            dividerTop: !appleSignInAvailable,
            onPressed: _linkGoogle,
          ),
          _UpgradeOption(
            icon: Symbols.mail_rounded,
            title: 'Use Email',
            subtitle: 'Any email and a password you choose. Restore on any device.',
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
  final IconData? icon;

  /// FontAwesome brand glyph (Apple / Google), used instead of [icon].
  /// FontAwesome 11 glyphs are [FaIconData], not [IconData].
  final FaIconData? brandIcon;
  final String title;
  final String subtitle;
  final bool busy;
  final bool showSpinner;
  final bool dividerTop;
  final VoidCallback onPressed;

  const _UpgradeOption({
    this.icon,
    this.brandIcon,
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
        leading: brandIcon == null ? CsIconDisc(icon!) : _BrandDisc(brandIcon!),
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

/// [CsIconDisc] metrics around a FontAwesome brand glyph.
class _BrandDisc extends StatelessWidget {
  const _BrandDisc(this.icon);
  final FaIconData icon;

  @override
  Widget build(BuildContext context) {
    final d = context.cs(36);
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        color: CsColors.raised,
        shape: BoxShape.circle,
        border: Border.all(color: CsColors.hairline),
      ),
      alignment: Alignment.center,
      child: FaIcon(icon, size: d * 0.45, color: CsColors.ink),
    );
  }
}
