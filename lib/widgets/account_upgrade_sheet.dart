import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';

/// Bottom sheet shown when an anonymous (guest) user tries to make a
/// purchase. Offers two ways to upgrade the account in place — keeping
/// the same Firebase UID so existing game progress, coins, and cosmetics
/// stay attached.
///
/// Returns `true` from [showAccountUpgradeSheet] if the user successfully
/// linked an account (caller should re-check `isAnonymous` and proceed),
/// `false` if they dismissed or cancelled.
Future<bool> showAccountUpgradeSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AccountUpgradeSheet(),
  );
  return result ?? false;
}

class _AccountUpgradeSheet extends StatefulWidget {
  const _AccountUpgradeSheet();

  @override
  State<_AccountUpgradeSheet> createState() => _AccountUpgradeSheetState();
}

class _AccountUpgradeSheetState extends State<_AccountUpgradeSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeCubit>().state.currentTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1F),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: theme.accentColor.withValues(alpha: 0.25),
              width: 1.5,
            ),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      color: theme.accentColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sign up to make purchases',
                      style: TextStyle(
                        color: theme.accentColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Guest accounts can play and save progress locally, but cannot buy items or subscribe. Link a Google or email account to unlock purchases — your existing coins, cosmetics, and high scores stay attached.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              _UpgradeOption(
                icon: Icons.g_mobiledata_outlined,
                title: 'Continue with Google',
                subtitle:
                    'Fastest option. Sign in with your Google account.',
                color: Colors.red.shade700,
                busy: _busy,
                onPressed: () async {
                  // Capture context-bound handles before the await so we can
                  // dismiss the sheet and show feedback safely afterwards.
                  final cubit = context.read<AuthCubit>();
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  setState(() => _busy = true);
                  final ok = await cubit.linkAnonymousToGoogle();
                  if (!mounted) return;
                  setState(() => _busy = false);
                  if (ok) {
                    navigator.pop(true);
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.green.shade700,
                        content: const Text(
                          'Account linked. You can now make purchases.',
                        ),
                      ),
                    );
                  } else {
                    final code = cubit.state.errorMessage ?? '';
                    if (code.isNotEmpty && code != 'link failed') {
                      messenger.showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.red.shade700,
                          content: Text(_linkError(code)),
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
              _UpgradeOption(
                icon: Icons.email_outlined,
                title: 'Create an Email Account',
                subtitle:
                    'Use any email and a password you choose. Restore on any device.',
                color: theme.accentColor,
                busy: _busy,
                onPressed: () {
                  Navigator.of(context).pop(false);
                  context.push('${AppRoutes.emailAuth}?link=1');
                },
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: Text(
                  'Not now',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
  final Color color;
  final bool busy;
  final VoidCallback onPressed;

  const _UpgradeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
