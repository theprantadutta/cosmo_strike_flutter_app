import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/privacy_policy.dart';

/// Re-consent gate shown to EXISTING (already-onboarded) users when the
/// privacy policy version has changed since they last accepted it. New users
/// accept the policy inside [FirstTimeAuthScreen]; this screen handles the
/// "policy updated, please review again" case for returning users and then
/// sends them home. Back navigation is blocked so acceptance can't be skipped.
///
/// Layout: brand + headline on the left; on the right the scrollable policy
/// in a subtle bordered panel with the consent checkbox + CONTINUE under it.
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
    final cs = context.cs;
    final t = cs.type;

    final left = CsFitColumn(
      alignment: Alignment.centerLeft,
      children: [
        const CsLogoMark(size: 40),
        SizedBox(height: cs(26)),
        CsLabel('Privacy · v${PrivacyPolicy.currentPrivacyPolicyVersion}'),
        SizedBox(height: cs(10)),
        CsHeadline(const ['Policy ', 'updated.'], prismIndex: 1, maxLines: 3, style: t.title),
        SizedBox(height: cs(14)),
        Text(
          'Please review the updated Privacy Policy and accept it to continue.',
          style: t.body,
        ),
      ],
    );

    final policy = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(CsRadius.card),
        border: Border.all(color: CsColors.lineSubtle),
      ),
      child: _content.isEmpty
          ? const CsLoadingState(label: 'Loading policy')
          : ClipRRect(
              borderRadius: BorderRadius.circular(CsRadius.card),
              child: Scrollbar(
                child: SingleChildScrollView(
                  primary: true,
                  padding: EdgeInsets.all(cs(22)),
                  child: CsMarkdown(_content),
                ),
              ),
            ),
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: policy),
        SizedBox(height: cs(14)),
        Row(
          children: [
            Expanded(
              child: _ConsentCheck(
                value: _accepted,
                label: 'I have read and agree to the updated Privacy Policy',
                onChanged: (v) => setState(() => _accepted = v),
              ),
            ),
            SizedBox(width: cs(16)),
            CsButton.primary(
              label: 'Continue',
              icon: Symbols.check_circle_rounded,
              onPressed: _accepted ? _accept : null,
            ),
          ],
        ),
      ],
    );

    return PopScope(
      // Block back-out — the user must accept the updated policy to proceed.
      canPop: false,
      child: CsScaffold(
        showTopBar: false,
        washes: const [CsWash.cyanLeft],
        body: CsSplit(
          leftWidth: cs.isTablet ? 340 : 300,
          left: left,
          right: right,
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
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
              ),
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
