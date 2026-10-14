import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/cs.dart';
import '../utils/privacy_policy.dart';

/// Read-only Privacy Policy (bundled PRIVACY.md). Reached from the Home
/// notice strip and Settings → Help; no accept step — acceptance is
/// recorded when the player first taps Play.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  String _content = '';

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('PRIVACY.md').then((c) {
      if (mounted) setState(() => _content = c);
    }).catchError((_) {
      if (mounted) setState(() => _content = 'The Privacy Policy could not be loaded.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return CsScaffold(
      title: 'Privacy policy',
      body: CsSplit(
        leftWidth: cs.isTablet ? 340 : 300,
        left: CsFitColumn(
          alignment: Alignment.centerLeft,
          children: [
            CsLabel('Version ${PrivacyPolicy.currentPrivacyPolicyVersion}'),
            SizedBox(height: cs(10)),
            CsHeadline(const ['Your data, ', 'plainly.'], prismIndex: 1, maxLines: 3, style: t.title),
            SizedBox(height: cs(14)),
            Text(
              'What Cosmo Strike collects, why, and the choices you have. '
              'Questions: prantadutta1997@gmail.com',
              style: t.body,
            ),
          ],
        ),
        right: _content.isEmpty
            ? const CsLoadingState(label: 'Loading policy')
            : Scrollbar(
                child: SingleChildScrollView(
                  primary: true,
                  padding: EdgeInsets.only(right: cs(12), bottom: cs(24)),
                  child: CsMarkdown(_content),
                ),
              ),
      ),
    );
  }
}
