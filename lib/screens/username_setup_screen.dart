import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/username_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

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
    final cs = context.cs;
    final t = cs.type;

    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          style: t.display(22, weight: FontWeight.w700, em: -0.01),
          decoration: InputDecoration(
            labelText: 'USERNAME',
            prefixIcon: Padding(
              padding: EdgeInsets.only(right: cs(10)),
              child: Icon(Symbols.badge_rounded, size: cs(20), color: CsColors.ink45),
            ),
            prefixIconConstraints: BoxConstraints(minWidth: cs(30), minHeight: 44),
            errorText: _errorMessage,
            counterStyle: t.micro,
          ),
          maxLength: 20,
          onSubmitted: (_) {
            if (!_isLoading) _onContinue();
          },
        ),
        SizedBox(height: cs(10)),
        for (final rule in const [
          '3-20 characters',
          'Must start with a letter',
          'Letters, numbers, and underscores only',
        ])
          Padding(
            padding: EdgeInsets.only(bottom: cs(4)),
            child: Row(
              children: [
                Container(width: cs(10), height: 1, color: CsColors.ink30),
                SizedBox(width: cs(8)),
                Expanded(
                  child: Text(rule.toUpperCase(), style: t.micro),
                ),
              ],
            ),
          ),
        SizedBox(height: cs(20)),
        CsButton.primary(
          onPressed: _isLoading ? null : _onContinue,
          loading: _isLoading,
          label: _isLoading ? 'Saving' : 'Continue',
          trailingIcon: _isLoading ? null : Symbols.arrow_forward_rounded,
          expand: true,
        ),
        SizedBox(height: cs(12)),
        Text(
          'You can change this anytime in Settings.'.toUpperCase(),
          textAlign: TextAlign.center,
          style: t.micro,
        ),
      ],
    );

    return CsScaffold(
      showTopBar: false,
      washes: const [CsWash.violetTopRight],
      body: CsSplit(
        leftFlex: 5,
        left: CsFitColumn(
          alignment: Alignment.centerLeft,
          children: [
            const CsLogoMark(size: 40),
            SizedBox(height: cs(22)),
            const CsLabel('Call sign'),
            SizedBox(height: cs(10)),
            CsHeadline(const ['Pick your\n', 'username.'], prismIndex: 1, style: t.title),
            SizedBox(height: cs(14)),
            Text(
              "It's how you'll show up on the leaderboard. "
              "We've picked one for you — keep it or change it.",
              style: t.body.copyWith(fontSize: cs(14)),
            ),
          ],
        ),
        right: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: cs(400)),
              child: form,
            ),
          ),
        ),
      ),
    );
  }
}
