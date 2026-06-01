import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/utils/privacy_policy.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';

/// Re-consent gate shown to EXISTING (already-onboarded) users when the
/// privacy policy version has changed since they last accepted it. New users
/// accept the policy inside [FirstTimeAuthScreen]; this screen handles the
/// "policy updated, please review again" case for returning users and then
/// sends them home. Back navigation is blocked so acceptance can't be skipped.
class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key});

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  String _content = '';
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _loadPolicy();
  }

  Future<void> _loadPolicy() async {
    try {
      final content = await rootBundle.loadString('PRIVACY.md');
      if (mounted) setState(() => _content = content);
    } catch (_) {
      if (mounted) {
        setState(() => _content =
            'We have updated our Privacy Policy. Please review it in Settings. '
            'By continuing you accept the updated policy.');
      }
    }
  }

  Future<void> _accept() async {
    await PrivacyPolicy.recordAccepted();
    if (mounted) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeCubit>().state.currentTheme;
    final isSmall = MediaQuery.of(context).size.height < 800;

    return PopScope(
      // Block back-out — the user must accept the updated policy to proceed.
      canPop: false,
      child: Scaffold(
        body: AnimatedAppBackground(
          theme: theme,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(isSmall ? 16 : 20),
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
                          child: Icon(Icons.privacy_tip_outlined,
                              color: theme.accentColor, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Privacy Policy Updated',
                                style: TextStyle(
                                  color: theme.accentColor,
                                  fontSize: isSmall ? 20 : 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Version ${PrivacyPolicy.currentPrivacyPolicyVersion} · please review and accept to continue',
                                style: TextStyle(
                                  color: theme.accentColor.withValues(alpha: 0.7),
                                  fontSize: isSmall ? 12 : 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Policy content
                  Expanded(
                    child: Container(
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
                      child: _content.isEmpty
                          ? Center(
                              child: CircularProgressIndicator(
                                color: theme.accentColor,
                              ),
                            )
                          : SingleChildScrollView(
                              child: Text(
                                _content,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Acceptance checkbox
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
                            value: _accepted,
                            onChanged: (v) =>
                                setState(() => _accepted = v ?? false),
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
                            'I have read and agree to the updated Privacy Policy',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: isSmall ? 14 : 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Continue button
                  GestureDetector(
                    onTap: _accepted ? _accept : null,
                    child: Opacity(
                      opacity: _accepted ? 1 : 0.4,
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.primaryColor, theme.accentColor],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Continue',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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
}
