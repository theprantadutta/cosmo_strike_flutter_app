import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/username_service.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';
import 'package:cosmo_strike_flutter_app/widgets/gradient_button.dart';

/// First-time username confirmation screen.
///
/// Shown immediately after a brand-new backend account is created (the
/// `IsNewUser` flag from the AuthResponse). Pre-fills the input with the
/// auto-generated username from the server so the user can keep it with
/// a single tap, or type something custom before continuing.
///
/// Continue is the only exit — there's no Skip button. Once the user
/// proceeds, `clearNeedsUsernameSetup` is called and routing falls
/// through to /home for all subsequent app launches.
class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  final TextEditingController _controller = TextEditingController();
  final UsernameService _usernameService = UsernameService();
  String? _errorMessage;
  bool _isLoading = false;
  String _initialUsername = '';

  @override
  void initState() {
    super.initState();
    // Pre-fill with the backend-assigned username so users who don't care
    // can just tap Continue. The auto-generated names are intentionally
    // game-on-brand (Swift_Ship_4231 etc.) so they're acceptable defaults.
    final authState = context.read<AuthCubit>().state;
    _initialUsername = authState.user?.username ?? '';
    _controller.text = _initialUsername;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    final newUsername = _controller.text.trim();
    if (newUsername.isEmpty) {
      setState(() => _errorMessage = 'Username cannot be empty');
      return;
    }

    // If they kept the pre-filled name as-is, the server already has it —
    // no need for an extra round trip. Just clear the flag and proceed.
    if (newUsername == _initialUsername) {
      _finish();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authCubit = context.read<AuthCubit>();
    // Use Firebase auth as the source of truth for which update path to
    // take. state.isGuestUser reads off the cached UnifiedUser, which can
    // briefly be the offline-guest stub mid-handoff and would route us
    // into updateGuestUsername — a local-only mutation that gets
    // overwritten the moment the backend sync settles. Firebase's
    // currentUser is authoritative: if a real (non-anonymous) Firebase
    // user is signed in, we MUST hit the authenticated update endpoint.
    final firebaseUser = FirebaseAuth.instance.currentUser;
    final isAuthenticated =
        firebaseUser != null && !firebaseUser.isAnonymous;
    final success = isAuthenticated
        ? await authCubit.updateAuthenticatedUsername(newUsername)
        : await authCubit.updateGuestUsername(newUsername);

    if (!mounted) return;

    if (success) {
      _finish();
    } else {
      final validation = await _usernameService.validateUsernameComplete(
        newUsername,
      );
      setState(() {
        _isLoading = false;
        _errorMessage = validation.error ?? 'Failed to set username';
      });
    }
  }

  void _finish() {
    context.read<AuthCubit>().clearNeedsUsernameSetup();
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;
        return Scaffold(
          backgroundColor: theme.backgroundColor,
          body: AppBackground(
            theme: theme,
            child: SafeArea(
              // SingleChildScrollView so the keyboard opening (autofocused
              // TextField) on a short screen doesn't overflow the Column.
              // LayoutBuilder + ConstrainedBox keeps the Spacers working at
              // tall heights — content centres vertically when it fits and
              // scrolls when it doesn't.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    Icon(
                      Icons.person_pin,
                      size: 64,
                      color: theme.accentColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Pick your username',
                      style: TextStyle(
                        color: theme.accentColor,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "It's how you'll show up on the leaderboard. "
                      "We've picked one for you — keep it or change it.",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _controller,
                      enabled: !_isLoading,
                      autofocus: true,
                      textCapitalization: TextCapitalization.none,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_]'),
                        ),
                        LengthLimitingTextInputFormatter(20),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: TextStyle(
                          color: theme.accentColor.withValues(alpha: 0.7),
                        ),
                        filled: true,
                        fillColor: theme.backgroundColor.withValues(alpha: 0.3),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: theme.accentColor.withValues(alpha: 0.3),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: theme.accentColor.withValues(alpha: 0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.accentColor),
                        ),
                        errorText: _errorMessage,
                        errorStyle: const TextStyle(color: Colors.red),
                      ),
                      style: const TextStyle(color: Colors.white),
                      maxLength: 20,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 3-20 characters\n'
                      '• Must start with a letter\n'
                      '• Letters, numbers, and underscores only',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    GradientButton(
                      onPressed: _isLoading ? null : _onContinue,
                      text: _isLoading ? 'SAVING...' : 'CONTINUE',
                      primaryColor: theme.accentColor,
                      secondaryColor: theme.foodColor,
                      icon: Icons.arrow_forward,
                      width: double.infinity,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You can change this anytime in Settings.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
