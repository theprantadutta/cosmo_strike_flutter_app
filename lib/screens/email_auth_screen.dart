import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';

/// Email/password sign-in, account-creation, and anonymous-account link
/// screen. Tab switcher between Sign In and Create Account.
///
/// When invoked with [linkFromAnonymous] = true, the action buttons call
/// the link* variants on AuthCubit instead of the standalone sign-in /
/// create methods — keeping the same Firebase UID so backend progress
/// (coins, cosmetics, scores) is preserved.
class EmailAuthScreen extends StatefulWidget {
  final bool linkFromAnonymous;

  const EmailAuthScreen({super.key, this.linkFromAnonymous = false});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _signInFormKey = GlobalKey<FormState>();
  final _createFormKey = GlobalKey<FormState>();
  final _signInEmail = TextEditingController();
  final _signInPassword = TextEditingController();
  final _createEmail = TextEditingController();
  final _createPassword = TextEditingController();
  bool _busy = false;
  bool _showSignInPassword = false;
  bool _showCreatePassword = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _signInEmail.dispose();
    _signInPassword.dispose();
    _createEmail.dispose();
    _createPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeCubit>().state.currentTheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.linkFromAnonymous ? 'Save Your Progress' : 'Email Sign-In',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: AppBackground(
        theme: theme,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.linkFromAnonymous) ...[
                    Text(
                      'Add an email and password to your account so you can buy items, restore on reinstall, and sign in from any device.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabs,
                      indicator: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor:
                          Colors.white.withValues(alpha: 0.7),
                      labelStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: [
                        Tab(
                          text: widget.linkFromAnonymous
                              ? 'Link Existing'
                              : 'Sign In',
                        ),
                        const Tab(text: 'Create Account'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 360,
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _buildSignInForm(theme.accentColor),
                        _buildCreateForm(theme.accentColor),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignInForm(Color accent) {
    return Form(
      key: _signInFormKey,
      child: Column(
        children: [
          _emailField(_signInEmail),
          const SizedBox(height: 16),
          _passwordField(
            controller: _signInPassword,
            obscure: !_showSignInPassword,
            onToggle: () =>
                setState(() => _showSignInPassword = !_showSignInPassword),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _onForgotPassword,
              child: Text(
                'Forgot password?',
                style: TextStyle(color: accent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _primaryButton(
            label: widget.linkFromAnonymous
                ? 'Link to Existing Account'
                : 'Sign In',
            color: accent,
            onPressed: _busy ? null : _onSignInOrLink,
          ),
        ],
      ),
    );
  }

  Widget _buildCreateForm(Color accent) {
    return Form(
      key: _createFormKey,
      child: Column(
        children: [
          _emailField(_createEmail),
          const SizedBox(height: 16),
          _passwordField(
            controller: _createPassword,
            obscure: !_showCreatePassword,
            onToggle: () =>
                setState(() => _showCreatePassword = !_showCreatePassword),
            minLength: 8,
            helper: 'At least 8 characters',
          ),
          const SizedBox(height: 24),
          _primaryButton(
            label: widget.linkFromAnonymous
                ? 'Create & Link Account'
                : 'Create Account',
            color: accent,
            onPressed: _busy ? null : _onCreateOrLink,
          ),
        ],
      ),
    );
  }

  Widget _emailField(TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.next,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration('Email', Icons.email_outlined),
      validator: (v) {
        final s = (v ?? '').trim();
        if (s.isEmpty) return 'Email is required';
        final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
        if (!re.hasMatch(s)) return 'Enter a valid email';
        return null;
      },
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    int minLength = 1,
    String? helper,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration(
        'Password',
        Icons.lock_outline,
        helperText: helper,
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          onPressed: onToggle,
        ),
      ),
      validator: (v) {
        final s = v ?? '';
        if (s.isEmpty) return 'Password is required';
        if (s.length < minLength) return 'At least $minLength characters';
        return null;
      },
    );
  }

  InputDecoration _decoration(
    String label,
    IconData icon, {
    String? helperText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
      helperText: helperText,
      helperStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
      prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.8)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Future<void> _onSignInOrLink() async {
    if (!_signInFormKey.currentState!.validate()) return;
    final email = _signInEmail.text.trim();
    final password = _signInPassword.text;
    final cubit = context.read<AuthCubit>();

    setState(() => _busy = true);
    final ok = widget.linkFromAnonymous
        ? await cubit.linkAnonymousToEmailPassword(
            email: email,
            password: password,
          )
        : await cubit.signInWithEmailPassword(
            email: email,
            password: password,
          );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      await _routeAfterSuccess(cubit);
    } else {
      _showError(_friendlyError(cubit.state.errorMessage));
    }
  }

  Future<void> _onCreateOrLink() async {
    if (!_createFormKey.currentState!.validate()) return;
    final email = _createEmail.text.trim();
    final password = _createPassword.text;
    final cubit = context.read<AuthCubit>();

    setState(() => _busy = true);
    final ok = widget.linkFromAnonymous
        ? await cubit.linkAnonymousToEmailPassword(
            email: email,
            password: password,
          )
        : await cubit.createAccountWithEmailPassword(
            email: email,
            password: password,
          );
    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      await _routeAfterSuccess(cubit);
    } else {
      _showError(_friendlyError(cubit.state.errorMessage));
    }
  }

  Future<void> _onForgotPassword() async {
    final email = _signInEmail.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email above first, then tap Forgot password.');
      return;
    }
    final cubit = context.read<AuthCubit>();
    setState(() => _busy = true);
    final ok = await cubit.sendPasswordResetEmail(email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _showInfo('Password reset email sent to $email.');
    } else {
      _showError(_friendlyError(cubit.state.errorMessage));
    }
  }

  Future<void> _routeAfterSuccess(AuthCubit cubit) async {
    if (widget.linkFromAnonymous) {
      // Link path keeps the existing user and username intact — pop back
      // to whichever screen triggered the upgrade (typically the store).
      if (mounted) context.pop();
      return;
    }

    await cubit.markFirstTimeSetupComplete();
    if (!mounted) return;

    final existingUsername = cubit.state.user?.username.trim() ?? '';
    final showSetup =
        cubit.state.needsUsernameSetup && existingUsername.isEmpty;
    context.go(showSetup ? AppRoutes.usernameSetup : AppRoutes.home);
  }

  // Maps Firebase Auth error codes to user-facing strings. Anything we don't
  // recognise falls through with the raw code so we still surface something.
  String _friendlyError(String? code) {
    switch (code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found with that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Wrong email or password.';
      case 'email-already-in-use':
      case 'credential-already-in-use':
        return 'An account with that email already exists. Try signing in instead.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled. Contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      case 'provider-already-linked':
        return 'This account is already linked to email/password.';
      case 'requires-recent-login':
        return 'For security, please sign in again before linking.';
      case null:
      case '':
        return 'Something went wrong. Please try again.';
      default:
        return code;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }
}
