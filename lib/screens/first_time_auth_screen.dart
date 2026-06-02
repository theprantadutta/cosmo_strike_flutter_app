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

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isNarrowScreen ? 16.0 : 24.0,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: screenHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Add some top padding for small screens
                        SizedBox(height: isSmallScreen ? 20 : 40),
                        // Welcome Header
                        Container(
                              padding: EdgeInsets.all(isSmallScreen ? 15 : 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    theme.accentColor.withValues(alpha: 0.3),
                                    theme.accentColor.withValues(alpha: 0.1),
                                    Colors.transparent,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.accentColor.withValues(
                                      alpha: 0.4,
                                    ),
                                    blurRadius: isSmallScreen ? 30 : 40,
                                    spreadRadius: isSmallScreen ? 5 : 10,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.videogame_asset_rounded,
                                size: isSmallScreen
                                    ? screenHeight * 0.08
                                    : screenHeight * 0.12,
                                color: theme.primaryColor,
                              ),
                            )
                            .gamePop(),

                        SizedBox(
                          height: isSmallScreen
                              ? screenHeight * 0.02
                              : screenHeight * 0.04,
                        ),

                        // Welcome Text Container
                        Container(
                              padding: EdgeInsets.all(
                                isSmallScreen
                                    ? screenHeight * 0.02
                                    : screenHeight * 0.035,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    theme.backgroundColor.withValues(
                                      alpha: 0.4,
                                    ),
                                    theme.backgroundColor.withValues(
                                      alpha: 0.2,
                                    ),
                                    theme.accentColor.withValues(alpha: 0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: theme.accentColor.withValues(
                                    alpha: 0.3,
                                  ),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  // Title with gradient effect
                                  ShaderMask(
                                    shaderCallback: (bounds) => LinearGradient(
                                      colors: [
                                        theme.primaryColor,
                                        theme.accentColor,
                                      ],
                                    ).createShader(bounds),
                                    child: Text(
                                      'Welcome to\nCosmo Strike!',
                                      style: TextStyle(
                                        fontSize: isSmallScreen
                                            ? screenHeight * 0.03
                                            : screenHeight * 0.04,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        height: 1.2,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  SizedBox(
                                    height: isSmallScreen
                                        ? screenHeight * 0.015
                                        : screenHeight * 0.025,
                                  ),

                                  // Feature highlights
                                  Text(
                                    'Choose how you\'d like to play:',
                                    style: TextStyle(
                                      fontSize: isSmallScreen
                                          ? screenHeight * 0.018
                                          : screenHeight * 0.022,
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      height: 1.4,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  // Feature list removed — the three auth
                                  // buttons below already convey the same
                                  // choices, and freeing the vertical space
                                  // lets all three buttons + the guest
                                  // subtitle fit on standard phones without
                                  // scrolling.
                                ],
                              ),
                            )
                            .gameEntrance(delay: 200.ms),

                        SizedBox(
                          height: isSmallScreen
                              ? screenHeight * 0.03
                              : screenHeight * 0.05,
                        ),

                        // Auth buttons
                        if (_isLoading)
                          // Full-width centered loading block — without an
                          // explicit width and CrossAxisAlignment.center
                          // the Column shrunk to its widest child and
                          // floated to the left edge, leaving the right
                          // half of the screen blank during the Google
                          // sign-in handoff. SizedBox(width: infinity)
                          // pins it to the available width; the Column's
                          // cross-axis center keeps spinner + text aligned.
                          SizedBox(
                            width: double.infinity,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    color: theme.accentColor,
                                    strokeWidth: 3,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Signing you in...',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Column(
                            children: [
                              // Google Sign-In Button
                              _buildAuthButton(
                                    context,
                                    'Sign in with Google',
                                    const FaIcon(
                                      FontAwesomeIcons.google,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    [Colors.red.shade600, Colors.red.shade700],
                                    () => _handleGoogleSignIn(authCubit),
                                  )
                                  .gameZoomIn(delay: 300.ms),

                              const SizedBox(height: 16),

                              // Email Sign-In Button
                              _buildAuthButton(
                                    context,
                                    'Sign in with Email',
                                    const Icon(
                                      Icons.email_outlined,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    [
                                      theme.accentColor.withValues(alpha: 0.85),
                                      theme.accentColor,
                                    ],
                                    () => context.push(AppRoutes.emailAuth),
                                  )
                                  .gameZoomIn(delay: 350.ms),

                              const SizedBox(height: 16),

                              // Guest Button — gated behind a confirm modal
                              // that spells out the guest-account tradeoffs
                              // (90-day data retention, no purchases) so
                              // first-time users can't miss the warning.
                              _buildAuthButton(
                                    context,
                                    'Continue as Guest',
                                    const Icon(
                                      Icons.person_outline_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    [
                                      theme.primaryColor.withValues(alpha: 0.8),
                                      theme.primaryColor,
                                    ],
                                    () => _confirmGuestLogin(authCubit),
                                  )
                                  .gameZoomIn(delay: 400.ms),

                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  'Guests can play and save progress locally, but cannot make purchases. Sign in with Google or Email when you are ready to subscribe or buy.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.65),
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ).gameZoomIn(delay: 450.ms),
                            ],
                          ),

                        // Bottom padding for small screens
                        SizedBox(height: isSmallScreen ? 20 : 40),
                      ],
                    ),
                  ),
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
      padding: EdgeInsets.symmetric(horizontal: isNarrowScreen ? 16.0 : 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT — the actual privacy policy, large and scrollable so the user
          // can read/scroll the whole thing (it was a cramped sliver in the old
          // portrait-stacked layout).
          Expanded(
            flex: 6,
            child:
                Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.backgroundColor.withValues(alpha: 0.4),
                            theme.backgroundColor.withValues(alpha: 0.2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.accentColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Text(
                          _privacyPolicyContent,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: isSmallScreen ? 12 : 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    )
                    .gameZoomIn(delay: 200.ms),
          ),

          const SizedBox(width: 16),

          // RIGHT — title + accept controls.
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  // Header
                  Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.accentColor.withValues(alpha: 0.2),
                              theme.accentColor.withValues(alpha: 0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.accentColor.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.accentColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.privacy_tip_outlined,
                                color: theme.accentColor,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Privacy Policy',
                                    style: TextStyle(
                                      color: theme.accentColor,
                                      fontSize: isSmallScreen ? 20 : 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Please review, then accept to continue',
                                    style: TextStyle(
                                      color: theme.accentColor
                                          .withValues(alpha: 0.7),
                                      fontSize: isSmallScreen ? 12 : 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                      .gameEntrance(),

                  const SizedBox(height: 16),

                  // Acceptance Checkbox
                  Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.accentColor.withValues(alpha: 0.15),
                      theme.accentColor.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.accentColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Transform.scale(
                      scale: 1.2,
                      child: Checkbox(
                        value: _privacyAccepted,
                        onChanged: (value) async {
                          setState(() {
                            _privacyAccepted = value ?? false;
                          });
                          // Save privacy acceptance (by version) when checked.
                          if (_privacyAccepted) {
                            await PrivacyPolicy.recordAccepted();
                          }
                        },
                        activeColor: theme.accentColor,
                        checkColor: Colors.white,
                        side: BorderSide(
                          color: theme.accentColor.withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'I have read and agree to the Privacy Policy and Terms of Service',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: isSmallScreen ? 14 : 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .gameZoomIn(delay: 300.ms),

          const SizedBox(height: 20),

          // Continue Button
          Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _privacyAccepted
                        ? [theme.primaryColor, theme.accentColor]
                        : [Colors.grey.shade600, Colors.grey.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: _privacyAccepted
                      ? [
                          BoxShadow(
                            color: theme.accentColor.withValues(alpha: 0.4),
                            blurRadius: 15,
                            spreadRadius: 1,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _privacyAccepted
                        ? () {
                            setState(() {
                              _showPrivacyPolicy = false;
                            });
                          }
                        : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: _privacyAccepted
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Continue to Sign In',
                          style: TextStyle(
                            color: _privacyAccepted
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .gameZoomIn(delay: 400.ms),
                ],
              ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthButton(
    BuildContext context,
    String text,
    Widget icon,
    List<Color> gradientColors,
    VoidCallback onPressed,
  ) {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: 0.4),
            blurRadius: 15,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 12),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
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
