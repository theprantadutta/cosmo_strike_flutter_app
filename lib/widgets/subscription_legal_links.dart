import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

/// Apple's standard licensed application EULA — the Terms of Use for
/// auto-renewing subscriptions (App Store guideline 3.1.2).
const String _termsOfUseUrl =
    'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

/// "Auto-renews until cancelled · Terms of Use · Privacy Policy" line shown
/// under every subscription offer. App Review rejects subscription screens
/// without functional links to both.
///
/// [compact] drops the renewal note and shortens the labels to fit on one
/// line beside other footer text that already says the plan auto-renews.
class SubscriptionLegalLinks extends StatelessWidget {
  const SubscriptionLegalLinks({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final quiet = context.cs.type.mono(10, em: 0.04, color: CsColors.ink45);
    final link = quiet.copyWith(
      color: CsColors.ink70,
      decoration: TextDecoration.underline,
      decorationColor: CsColors.ink30,
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!compact) Text('Auto-renews until cancelled  ·  ', style: quiet),
        _Link(
          label: compact ? 'Terms' : 'Terms of Use',
          style: link,
          onTap: () => launchUrl(
            Uri.parse(_termsOfUseUrl),
            mode: LaunchMode.externalApplication,
          ),
        ),
        Text('  ·  ', style: quiet),
        _Link(
          label: compact ? 'Privacy' : 'Privacy Policy',
          style: link,
          onTap: () => context.push(AppRoutes.privacyPolicy),
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.style, required this.onTap});
  final String label;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CsPressable(
      onTap: onTap,
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Center(widthFactor: 1, child: Text(label, style: style)),
      ),
    );
  }
}
