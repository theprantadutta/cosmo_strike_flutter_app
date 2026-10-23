import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// "About / Credits" dialog for Cosmo Strike. Reached from the home top bar's
/// about tool (and the Settings screen).
///
/// Prism Noir [CsDialog]: brand lockup + version on the left, credits as
/// hairline rows on the right. [theme] is kept for API compatibility; menus
/// are always Prism Noir, so it no longer tints the dialog.
Future<void> showCreditsDialog(BuildContext context, GameTheme theme) async {
  final currentYear = DateTime.now().year;
  final packageInfo = await PackageInfo.fromPlatform();
  if (!context.mounted) return;

  await showCsDialog<void>(
    context,
    builder: (dialogContext) => CsDialog(
      maxWidth: 600,
      content: _CreditsBody(
        version: 'v${packageInfo.version} · build ${packageInfo.buildNumber}',
        year: currentYear,
      ),
      actions: [
        CsButton.secondary(
          label: 'Close',
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ],
    ),
  );
}

Future<void> _openSite() async {
  final url = Uri.parse('https://pranta.dev');
  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

class _CreditsBody extends StatelessWidget {
  const _CreditsBody({required this.version, required this.year});
  final String version;
  final int year;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;

    final brand = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CsLogoMark(size: 64),
        SizedBox(height: cs(14)),
        const CsWordmark(size: 18),
        SizedBox(height: cs(8)),
        Text('A 12-level space shooter campaign.', style: t.body),
        SizedBox(height: cs(14)),
        CsChip(version),
      ],
    );

    final credits = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CsLabel('Crafted by'),
        CsListRow(
          title: 'Pranta Dutta',
          subtitle: 'pranta.dev',
          leading: const CsIconDisc(Symbols.language_rounded, size: 34),
          trailing: Icon(Symbols.open_in_new_rounded, size: cs(18), color: CsColors.ink55),
          onTap: _openSite,
        ),
        SizedBox(height: cs(14)),
        const CsLabel('Powered by'),
        CsListRow(
          title: 'Flame Game Engine',
          subtitle: 'Flutter + Flame',
          leading: const CsIconDisc(Symbols.local_fire_department_rounded, size: 34, color: CsColors.gold),
        ),
        SizedBox(height: cs(14)),
        Text(
          '© $year Pranta Dutta · All rights reserved'.toUpperCase(),
          style: t.micro,
        ),
      ],
    );

    if (cs.isCompact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [brand, SizedBox(height: cs(18)), credits],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: brand),
          SizedBox(width: cs(20)),
          const CsHairline(vertical: true),
          SizedBox(width: cs(20)),
          Expanded(flex: 6, child: credits),
        ],
      ),
    );
  }
}
