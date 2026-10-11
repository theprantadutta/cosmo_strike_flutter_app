import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/utils/privacy_policy.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

class FirstTimeAuthScreen extends StatefulWidget {
  const FirstTimeAuthScreen({super.key});

  @override
  State<FirstTimeAuthScreen> createState() => _FirstTimeAuthScreenState();
}

class _FirstTimeAuthScreenState extends State<FirstTimeAuthScreen> {
  bool _isLoading = false;
  bool _showPrivacyPolicy = true;
  bool _privacyAccepted = false;
  String _privacyPolicyContent = '';

  @override
  void initState() {
    super.initState();
    _loadPrivacyPolicy();
    _checkPreviousPrivacyAcceptance();
  }

  Future<void> _checkPreviousPrivacyAcceptance() async {
    // Accepted only when it's the CURRENT policy version — a version bump in
    // PRIVACY.md re-shows the policy here.
    final alreadyAccepted = await PrivacyPolicy.isCurrentVersionAccepted();
    if (alreadyAccepted && mounted) {
      setState(() {
        _showPrivacyPolicy = false;
        _privacyAccepted = true;
      });
    }
  }

  Future<void> _loadPrivacyPolicy() async {
    try {
      final content = await rootBundle.loadString('PRIVACY.md');
      setState(() {
        _privacyPolicyContent = content;
      });
    } catch (e) {
      // Fallback if file can't be loaded
      setState(() {
        _privacyPolicyContent = '''# Privacy Policy for Cosmo Strike

**Effective Date: January 17, 2025**

## Introduction
Cosmo Strike respects your privacy and is committed to protecting your personal information. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.

## Information We Collect
We collect various types of information to provide and improve our services, including:
- Authentication data when you sign in with Google
- Game data such as scores, achievements, and progress
- Device information for app functionality
- Usage analytics to improve the game experience

## How We Use Your Information
Your information is used to:
- Provide core game functionality
- Save your progress and achievements
- Enable social features and leaderboards
- Improve app performance and user experience

## Data Security
We implement appropriate security measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction.

## Your Rights
You have the right to access, update, or delete your personal information. Contact us for any privacy-related requests.

## Contact Information
For questions about this Privacy Policy, please contact us at: prantadutta1997@gmail.com

By using Cosmo Strike, you acknowledge that you have read, understood, and agree to this Privacy Policy.
''';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authCubit = context.read<AuthCubit>();
    final cs = context.cs;

    return CsScaffold(
      showTopBar: false,
      washes: const [CsWash.cyanLeft, CsWash.pinkBottomRight],
      stars: true,
      body: AnimatedSwitcher(
        duration: CsMotion.base,
        switchInCurve: CsMotion.standard,
        child: _showPrivacyPolicy
            ? KeyedSubtree(key: const ValueKey('privacy'), child: _buildPrivacyPolicyView(context))
            : KeyedSubtree(
                key: const ValueKey('signin'),
                child: CsSplit(
                  leftFlex: 5,
                  gap: cs(44),
                  left: _AuthIntro(
                    eyebrow: 'Pilot registration',
                    headline: const ['Welcome to\nCosmo ', 'Strike'],
                    body: "Pick how you'd like to launch — you can upgrade a "
                        'guest to a full account anytime.',
                  ),
                  right: _buildSignInOptions(context, authCubit),
                ),
              ),
      ),
    );
  }

  Widget _buildSignInOptions(BuildContext context, AuthCubit authCubit) {
    final cs = context.cs;
    if (_isLoading) {
      return const CsLoadingState(label: 'Signing you in');
    }
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cs(380)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const CsLabel('Choose how to sign in'),
              SizedBox(height: cs(14)),
              _GoogleSignInButton(onPressed: () => _handleGoogleSignIn(authCubit)),
              SizedBox(height: cs(12)),
              CsButton.secondary(
                label: 'Sign in with Email',
                icon: Symbols.mail_rounded,
                expand: true,
                onPressed: () => context.push(AppRoutes.emailAuth),
              ),
              SizedBox(height: cs(6)),
              CsButton.text(
                label: 'Continue as Guest',
                icon: Symbols.person_rounded,
                expand: true,
                onPressed: () => _confirmGuestLogin(authCubit),
              ),
              SizedBox(height: cs(12)),
              const CsHairline(),
              SizedBox(height: cs(12)),
              Text(
                'Guests play and save locally but '
                "can't make purchases. Sign in with "
                'Google or Email when you want to '
                'subscribe or buy.',
                textAlign: TextAlign.center,
                style: cs.type.micro.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyPolicyView(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;

    final policy = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CsRadius.card),
        border: Border.all(color: CsColors.lineSubtle),
      ),
      child: _privacyPolicyContent.isEmpty
          ? const CsLoadingState(label: 'Loading policy')
          : ClipRRect(
              borderRadius: BorderRadius.circular(CsRadius.card),
              child: Scrollbar(
                child: SingleChildScrollView(
                  primary: true,
                  padding: EdgeInsets.all(cs(22)),
                  child: Text(
                    _privacyPolicyContent,
                    style: t.body.copyWith(color: CsColors.ink70, height: 1.55),
                  ),
                ),
              ),
            ),
    );

    return CsSplit(
      leftWidth: cs.isTablet ? 340 : 300,
      left: _AuthIntro(
        eyebrow: 'Privacy policy · v${PrivacyPolicy.currentPrivacyPolicyVersion}',
        headline: const ['Cleared for\n', 'takeoff.'],
        body: 'Before you launch, take a moment with our Privacy Policy & '
            "Terms — then you're cleared for takeoff.",
      ),
      right: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: policy),
          SizedBox(height: cs(14)),
          Row(
            children: [
              Expanded(
                child: _ConsentCheck(
                  value: _privacyAccepted,
                  label: 'I have read and agree to the Privacy Policy and '
                      'Terms of Service.',
                  onChanged: (v) {
                    setState(() => _privacyAccepted = v);
                    if (_privacyAccepted) PrivacyPolicy.recordAccepted();
                  },
                ),
              ),
              SizedBox(width: cs(16)),
              CsButton.primary(
                label: 'Agree & Continue',
                icon: Symbols.rocket_launch_rounded,
                onPressed: _privacyAccepted
                    ? () => setState(() => _showPrivacyPolicy = false)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleGoogleSignIn(AuthCubit authCubit) async {
    setState(() => _isLoading = true);

    try {
      final success = await authCubit.signInWithGoogle();

      if (success && mounted) {
        // Mark first-time setup as complete
        await authCubit.markFirstTimeSetupComplete();

        // If the backend just created a fresh account, divert through the
        // username-setup screen so the user can keep or edit the
        // auto-generated name before landing on home. For returning users
        // (cross-device Google login etc.), needsUsernameSetup is false
        // and we go straight home.
        //
        // Second gate: never show the setup screen to a user that already
        // has a non-empty username on file. The backend's username
        // generator (AuthenticateWithFirebaseCommandHandler) always
        // assigns one for new accounts, so this is mostly defense-in-
        // depth — but if needsUsernameSetup ever drifts true for someone
        // with an established name (e.g. a stale flag from a prior
        // session), we don't make them re-pick a name they already have.
        if (mounted) {
          final existingUsername =
              authCubit.state.user?.username.trim() ?? '';
          final showSetup = authCubit.state.needsUsernameSetup &&
              existingUsername.isEmpty;
          final route =
              showSetup ? AppRoutes.usernameSetup : AppRoutes.home;
          context.go(route);
        }
      } else if (mounted) {
        _showError('Failed to sign in with Google. Please try again.');
      }
    } catch (e) {
      if (mounted) {
        _showError('An unexpected error occurred. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Shows a confirmation modal explaining the guest-account tradeoffs
  /// before firing the actual anonymous sign-in. The user has to
  /// explicitly tap "Proceed Anyway" to continue — closing the dialog
  /// or tapping "I Changed My Mind" no-ops and leaves them on the auth
  /// screen so they can pick Google / Email instead.
  Future<void> _confirmGuestLogin(AuthCubit authCubit) async {
    final confirmed = await showCsDialog<bool>(
      context,
      // Force an explicit choice — the warning matters too much to dismiss
      // by tapping outside the dialog.
      barrierDismissible: false,
      builder: (dialogContext) => CsDialog(
        icon: Symbols.warning_rounded,
        iconColor: CsColors.gold,
        eyebrow: 'Guest account',
        title: 'Heads up',
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GuestWarningBullet(
              icon: Symbols.delete_rounded,
              text: 'Guest data is automatically deleted from our '
                  'servers after 90 days of inactivity.',
            ),
            _GuestWarningBullet(
              icon: Symbols.cloud_sync_rounded,
              text: 'To save your progress permanently and play across '
                  'devices, sign in with Google or Email instead.',
            ),
            _GuestWarningBullet(
              icon: Symbols.shopping_cart_rounded,
              text: 'Guest accounts cannot purchase products or '
                  'subscriptions. Sign in if you want to upgrade to Pro '
                  'or buy cosmetics.',
              last: true,
            ),
          ],
        ),
        actions: [
          CsButton.text(
            label: 'Proceed anyway',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
          CsButton.primary(
            label: 'I changed my mind',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _handleGuestLogin(authCubit);
    }
  }

  Future<void> _handleGuestLogin(AuthCubit authCubit) async {
    setState(() => _isLoading = true);

    try {
      await authCubit.signInAnonymously();

      // Mark first-time setup as complete
      await authCubit.markFirstTimeSetupComplete();

      if (mounted) {
        // Same username-setup divert applies to anonymous sign-ins —
        // anonymous users get a generated username server-side too and
        // benefit from picking their own. Same second-gate as the Google
        // path: never show setup to someone with an established username.
        final existingUsername =
            authCubit.state.user?.username.trim() ?? '';
        final showSetup = authCubit.state.needsUsernameSetup &&
            existingUsername.isEmpty;
        final route = showSetup ? AppRoutes.usernameSetup : AppRoutes.home;
        context.go(route);
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to continue as guest. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showCsToast(context, message, kind: CsToastKind.error);
  }
}

/// Left column of the onboarding screens: logo mark, mono eyebrow, a big
/// Syne headline with one prism word, and body copy. Never scrolls — scales
/// down on short phones.
class _AuthIntro extends StatelessWidget {
  const _AuthIntro({required this.eyebrow, required this.headline, required this.body});
  final String eyebrow;

  /// Two parts; the second is painted in prism.
  final List<String> headline;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return CsFitColumn(
      alignment: Alignment.centerLeft,
      children: [
        const CsLogoMark(size: 44),
        SizedBox(height: cs(26)),
        CsLabel(eyebrow),
        SizedBox(height: cs(10)),
        CsHeadline(headline, prismIndex: 1, style: t.title),
        SizedBox(height: cs(14)),
        Text(body, style: t.body.copyWith(fontSize: cs(14))),
      ],
    );
  }
}

/// White primary pill with the Google "G" brand glyph (FontAwesome).
/// [CsButton] only takes an [IconData], and FontAwesome 11 glyphs are
/// [FaIconData], so the pill is composed here with the same metrics.
class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return CsPressable(
      onTap: onPressed,
      semanticLabel: 'Sign in with Google',
      child: Container(
        constraints: BoxConstraints(minHeight: cs(48).clamp(44.0, 64.0)),
        padding: EdgeInsets.symmetric(horizontal: cs(26)),
        decoration: const ShapeDecoration(color: CsColors.ink, shape: StadiumBorder()),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FaIcon(FontAwesomeIcons.google, size: cs(17), color: CsColors.onLight),
            SizedBox(width: cs(10)),
            Flexible(
              child: Text(
                'SIGN IN WITH GOOGLE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cs.type.button.copyWith(color: CsColors.onLight),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Theme checkbox + label; the whole row is the tap target.
class _ConsentCheck extends StatelessWidget {
  const _ConsentCheck({required this.value, required this.label, required this.onChanged});
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return CsPressable(
      scale: 0.99,
      onTap: () => onChanged(!value),
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 32,
              child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            ),
            SizedBox(width: cs(10)),
            Expanded(
              child: Text(
                label,
                style: cs.type.display(13, weight: FontWeight.w600, em: 0, height: 1.3, color: CsColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Warning row inside the guest-confirmation dialog — gold glyph, body text,
/// hairline under each row except the last.
class _GuestWarningBullet extends StatelessWidget {
  const _GuestWarningBullet({required this.icon, required this.text, this.last = false});

  final IconData icon;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: EdgeInsets.symmetric(vertical: cs(10)),
      decoration: BoxDecoration(
        border: Border(bottom: last ? BorderSide.none : const BorderSide(color: CsColors.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: cs(18), color: CsColors.ink60),
          SizedBox(width: cs(12)),
          Expanded(child: Text(text, style: cs.type.body.copyWith(fontSize: cs(14)))),
        ],
      ),
    );
  }
}
