import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/utils/privacy_policy.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';

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
    final themeState = context.watch<ThemeCubit>().state;
    final authCubit = context.read<AuthCubit>();
    final theme = themeState.currentTheme;

    return Scaffold(
      body: AnimatedAppBackground(
        theme: theme,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenHeight = constraints.maxHeight;
              // Bumped from <600 to <800 so the tighter layout is the
              // default — most phones (incl. 6.1" / Pixel-class) sit
              // around 800-900 logical pixels, and with three auth
              // buttons + the guest-can't-purchase subtitle the prior
              // large-screen sizing pushed content past the fold.
              final screenWidth = constraints.maxWidth;
              final isSmallScreen = screenHeight < 800;
              final isNarrowScreen = screenWidth < 400;

              if (_showPrivacyPolicy) {
                return _buildPrivacyPolicyView(
                  theme,
                  screenHeight,
                  screenWidth,
                  isSmallScreen,
                  isNarrowScreen,
                );
              }

              // Landscape: branding on the left, sign-in options in a glass
              // card on the right.
              return Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // LEFT — branding + welcome.
                    Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          HoloLogo(size: isSmallScreen ? 60 : 78, theme: theme)
                              .gamePop(),
                          const SizedBox(height: 18),
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [theme.neonPrimary, theme.neonSecondary],
                            ).createShader(bounds),
                            child: const Text(
                              'WELCOME TO\nCOSMO STRIKE',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.15,
                                letterSpacing: 2,
                              ),
                            ),
                          ).gameEntrance(delay: 100.ms),
                          const SizedBox(height: 12),
                          Text(
                            "Pick how you'd like to launch — you can upgrade a "
                            'guest to a full account anytime.',
                            style: TextStyle(
                              color: theme.textMuted,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ).gameEntrance(delay: 200.ms),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    // RIGHT — sign-in options.
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: SingleChildScrollView(
                          primary: false,
                          child: GlassPanel(
                            theme: theme,
                            glow: true,
                            padding: const EdgeInsets.all(20),
                            child: _isLoading
                                ? Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 28),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(
                                          color: theme.neonPrimary,
                                          strokeWidth: 3,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Signing you in...',
                                          style: TextStyle(
                                            color: theme.textMuted,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      NeonButton(
                                        onPressed: () =>
                                            _handleGoogleSignIn(authCubit),
                                        label: 'Sign in with Google',
                                        leading: const FaIcon(
                                          FontAwesomeIcons.google,
                                          size: 18,
                                          color: Color(0xFF03040A),
                                        ),
                                        theme: theme,
                                        expand: true,
                                      ).gameZoomIn(delay: 250.ms),
                                      const SizedBox(height: 12),
                                      NeonButton(
                                        onPressed: () =>
                                            context.push(AppRoutes.emailAuth),
                                        label: 'Sign in with Email',
                                        icon: Icons.email_outlined,
                                        theme: theme,
                                        variant: NeonButtonVariant.outline,
                                        expand: true,
                                      ).gameZoomIn(delay: 300.ms),
                                      const SizedBox(height: 12),
                                      NeonButton(
                                        onPressed: () =>
                                            _confirmGuestLogin(authCubit),
                                        label: 'Continue as Guest',
                                        icon: Icons.person_outline_rounded,
                                        theme: theme,
                                        variant: NeonButtonVariant.ghost,
                                        expand: true,
                                      ).gameZoomIn(delay: 350.ms),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Guests play and save locally but '
                                        "can't make purchases. Sign in with "
                                        'Google or Email when you want to '
                                        'subscribe or buy.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: theme.textMuted
                                              .withValues(alpha: 0.8),
                                          fontSize: 11,
                                          height: 1.4,
                                        ),
                                      ).gameZoomIn(delay: 400.ms),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyPolicyView(
    GameTheme theme,
    double screenHeight,
    double screenWidth,
    bool isSmallScreen,
    bool isNarrowScreen,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT — branding, the accept toggle, and the launch CTA.
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                HoloLogo(size: isSmallScreen ? 52 : 68, theme: theme)
                    .gameEntrance(),
                const SizedBox(height: 14),
                Text(
                  'COSMO STRIKE',
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: isSmallScreen ? 24 : 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Before you launch, take a moment with our Privacy Policy & '
                  "Terms — then you're cleared for takeoff.",
                  style: TextStyle(
                    color: theme.textMuted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const Spacer(),
                // The whole card toggles acceptance.
                GlassPanel(
                  theme: theme,
                  glow: _privacyAccepted,
                  borderColor:
                      _privacyAccepted ? theme.neonPrimary : theme.stroke,
                  padding: const EdgeInsets.all(14),
                  onTap: () {
                    setState(() => _privacyAccepted = !_privacyAccepted);
                    if (_privacyAccepted) PrivacyPolicy.recordAccepted();
                  },
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _privacyAccepted
                              ? theme.neonPrimary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: _privacyAccepted
                                ? theme.neonPrimary
                                : theme.stroke,
                            width: 2,
                          ),
                        ),
                        child: _privacyAccepted
                            ? const Icon(Icons.check,
                                size: 18, color: Color(0xFF03040A))
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'I have read and agree to the Privacy Policy and '
                          'Terms of Service.',
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                NeonButton(
                  onPressed: _privacyAccepted
                      ? () => setState(() => _showPrivacyPolicy = false)
                      : null,
                  label: 'Agree & Continue',
                  icon: Icons.rocket_launch,
                  theme: theme,
                  expand: true,
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          const SizedBox(width: 18),
          // RIGHT — the policy itself, prominent and scrollable.
          Expanded(
            flex: 6,
            child: GlassPanel(
              theme: theme,
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Row(
                      children: [
                        Icon(Icons.privacy_tip_outlined,
                            color: theme.neonPrimary, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Privacy Policy',
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'v${PrivacyPolicy.currentPrivacyPolicyVersion}',
                          style:
                              TextStyle(color: theme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Divider(color: theme.stroke, height: 1),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _privacyPolicyContent.isEmpty
                        ? Center(
                            child: CircularProgressIndicator(
                                color: theme.neonPrimary),
                          )
                        : SingleChildScrollView(
                            primary: false,
                            padding: const EdgeInsets.only(right: 10),
                            child: Text(
                              _privacyPolicyContent,
                              style: TextStyle(
                                color: theme.textMuted,
                                fontSize: isSmallScreen ? 12 : 13,
                                height: 1.5,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ).gameZoomIn(delay: 150.ms),
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
    final theme = context.read<ThemeCubit>().state.currentTheme;

    final confirmed = await showDialog<bool>(
      context: context,
      // Force an explicit choice — the warning matters too much to dismiss
      // by tapping outside the dialog.
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.accentColor.withValues(alpha: 0.3),
          ),
        ),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: theme.foodColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Heads up',
                style: TextStyle(
                  color: theme.accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GuestWarningBullet(
              icon: Icons.delete_outline_rounded,
              text: 'Guest data is automatically deleted from our '
                  'servers after 90 days of inactivity.',
              theme: theme,
            ),
            const SizedBox(height: 14),
            _GuestWarningBullet(
              icon: Icons.cloud_sync_rounded,
              text: 'To save your progress permanently and play across '
                  'devices, sign in with Google or Email instead.',
              theme: theme,
            ),
            const SizedBox(height: 14),
            _GuestWarningBullet(
              icon: Icons.shopping_cart_outlined,
              text: 'Guest accounts cannot purchase products or '
                  'subscriptions. Sign in if you want to upgrade to Pro '
                  'or buy cosmetics.',
              theme: theme,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'I changed my mind',
              style: TextStyle(
                color: theme.accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Proceed anyway',
              style: TextStyle(
                color: theme.foodColor.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

/// Single-line warning row used inside the guest-confirmation dialog —
/// theme-tinted icon on the left, body text on the right. Kept private
/// to this file because no other screen renders the same pattern.
class _GuestWarningBullet extends StatelessWidget {
  const _GuestWarningBullet({
    required this.icon,
    required this.text,
    required this.theme,
  });

  final IconData icon;
  final String text;
  final GameTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: theme.accentColor.withValues(alpha: 0.85),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: theme.accentColor.withValues(alpha: 0.85),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
