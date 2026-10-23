import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

/// Email/password sign-in, account-creation, and anonymous-account link
/// screen. Segmented switcher between Sign In and Create Account.
///
/// When invoked with [linkFromAnonymous] = true, the action buttons call
/// the link* variants on AuthCubit instead of the standalone sign-in /
/// create methods — keeping the same Firebase UID so backend progress
/// (coins, cosmetics, scores) is preserved.
///
/// Layout: intro (logo, headline, copy) on the left; the segmented control
/// and the underline form on the right (scrolls with the keyboard up).
class EmailAuthScreen extends StatefulWidget {
  final bool linkFromAnonymous;

  const EmailAuthScreen({super.key, this.linkFromAnonymous = false});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  /// 0 = Sign In / Link Existing, 1 = Create Account.
  int _tab = 0;
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
  void dispose() {
    _signInEmail.dispose();
    _signInPassword.dispose();
    _createEmail.dispose();
    _createPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final link = widget.linkFromAnonymous;

    return CsScaffold(
      title: link ? 'Back Up Pilot File' : 'Email Sign-In',
      washes: const [CsWash.cyanLeft],
      body: CsSplit(
        leftFlex: 4,
        gap: cs(44),
        left: _AuthIntro(
          eyebrow: link ? 'Upgrade guest pilot' : 'Email & password',
          headline: link ? const ['Back up your\n', 'Pilot File.'] : const ['Sign in with\n', 'email.'],
          body: link
              ? 'Attach an email and password to restore after a reinstall '
                  'and sign in from any device.'
              : 'Sign in or create an account. Local progress stays on this '
                  'device either way.',
        ),
        right: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: cs(440)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CsSegmented<int>(
                    expand: true,
                    segments: {
                      0: link ? 'Link Existing' : 'Sign In',
                      1: 'Create Account',
                    },
                    selected: _tab,
                    onChanged: (v) => setState(() => _tab = v),
                  ),
                  SizedBox(height: cs(14)),
                  // Both forms stay mounted so their keys/inputs survive
                  // switching segments.
                  IndexedStack(
                    index: _tab,
                    sizing: StackFit.loose,
                    children: [
                      _buildSignInForm(context),
                      _buildCreateForm(context),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignInForm(BuildContext context) {
    final cs = context.cs;
    return Form(
      key: _signInFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _emailField(_signInEmail),
          SizedBox(height: cs(10)),
          _passwordField(
            controller: _signInPassword,
            obscure: !_showSignInPassword,
            onToggle: () =>
                setState(() => _showSignInPassword = !_showSignInPassword),
          ),
          SizedBox(height: cs(6)),
          Align(
            alignment: Alignment.centerRight,
            child: CsButton.text(
              label: 'Forgot password?',
              size: CsButtonSize.small,
              onPressed: _busy ? null : _onForgotPassword,
            ),
          ),
          SizedBox(height: cs(10)),
          CsButton.primary(
            onPressed: _busy ? null : _onSignInOrLink,
            loading: _busy,
            label: widget.linkFromAnonymous ? 'Link to Existing Account' : 'Sign In',
            expand: true,
          ),
        ],
      ),
    );
  }

  Widget _buildCreateForm(BuildContext context) {
    final cs = context.cs;
    return Form(
      key: _createFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _emailField(_createEmail),
          SizedBox(height: cs(10)),
          _passwordField(
            controller: _createPassword,
            obscure: !_showCreatePassword,
            onToggle: () =>
                setState(() => _showCreatePassword = !_showCreatePassword),
            minLength: 8,
            helper: 'At least 8 characters',
          ),
          SizedBox(height: cs(22)),
          CsButton.primary(
            onPressed: _busy ? null : _onCreateOrLink,
            loading: _busy,
            label: widget.linkFromAnonymous ? 'Create & Link Account' : 'Create Account',
            expand: true,
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
      style: context.type.rowTitle.copyWith(fontWeight: FontWeight.w500),
      decoration: _decoration('Email', Symbols.mail_rounded),
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
      style: context.type.rowTitle.copyWith(fontWeight: FontWeight.w500),
      decoration: _decoration(
        'Password',
        Symbols.lock_rounded,
        helperText: helper,
        suffixIcon: CsIconButton(
          icon: obscure ? Symbols.visibility_off_rounded : Symbols.visibility_rounded,
          bordered: false,
          size: 36,
          color: CsColors.ink55,
          tooltip: obscure ? 'Show password' : 'Hide password',
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

  /// Underline field from the theme's InputDecorationTheme (pink micro
  /// errors, mono label); only the glyphs are added here.
  InputDecoration _decoration(
    String label,
    IconData icon, {
    String? helperText,
    Widget? suffixIcon,
  }) {
    final cs = context.cs;
    return InputDecoration(
      labelText: label.toUpperCase(),
      helperText: helperText?.toUpperCase(),
      prefixIcon: Padding(
        padding: EdgeInsets.only(right: cs(10)),
        child: Icon(icon, size: cs(18), color: CsColors.ink45),
      ),
      prefixIconConstraints: BoxConstraints(minWidth: cs(28), minHeight: 44),
      suffixIcon: suffixIcon,
      suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
    showCsToast(context, message, kind: CsToastKind.error);
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showCsToast(context, message, kind: CsToastKind.success);
  }
}

/// Left column of the onboarding screens: logo mark, mono eyebrow, a big
/// Syne headline with one prism word, and body copy. Never scrolls — scales
/// down on short phones (and when the keyboard is up).
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
        const CsLogoMark(size: 40),
        SizedBox(height: cs(22)),
        CsLabel(eyebrow),
        SizedBox(height: cs(10)),
        CsHeadline(headline, prismIndex: 1, style: t.title),
        SizedBox(height: cs(14)),
        Text(body, style: t.body.copyWith(fontSize: cs(14))),
      ],
    );
  }
}
