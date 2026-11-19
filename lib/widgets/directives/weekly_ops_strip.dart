import 'package:material_ui/material_ui.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/account_upgrade_sheet.dart';

/// Height of the compact strips under the directive cards (Weekly Ops,
/// all-clear bonus). Keeps a >=40 px touch target on every device.
double directivesStripHeight(BuildContext context) =>
    context.cs(44).clamp(40.0, 56.0);

/// "1d 4h" / "5h" / "12m" for a reset countdown.
String formatResetsIn(Duration d) {
  if (d.isNegative) d = Duration.zero;
  if (d.inDays >= 1) {
    final h = d.inHours % 24;
    return h == 0 ? '${d.inDays}d' : '${d.inDays}d ${h}h';
  }
  if (d.inHours >= 1) return '${d.inHours}h';
  return '${d.inMinutes.clamp(1, 59)}m';
}

/// Time until the next Weekly Ops set (local Monday 00:00), matching the
/// hub's countdown.
Duration weeklyOpsResetsIn([DateTime? now]) {
  final n = now ?? DateTime.now();
  final daysToMonday = (DateTime.monday - n.weekday) % 7;
  final next = DateTime(n.year, n.month, n.day + (daysToMonday == 0 ? 7 : daysToMonday));
  return next.difference(n);
}

/// Shared frame: a 1px hairline box, glyph, label, body, trailing.
class _StripFrame extends StatelessWidget {
  const _StripFrame({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.child,
    this.trailing,
    this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final body = SizedBox(
      height: directivesStripHeight(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(cs(CsRadius.tile)),
          border: Border.all(color: CsColors.hairline),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: cs(16), right: cs(onTap != null ? 8 : 12)),
          child: Row(
            children: [
              Icon(icon, size: cs(18), color: iconColor),
              SizedBox(width: cs(10)),
              Text(
                label.toUpperCase(),
                maxLines: 1,
                style: t.mono(10, weight: FontWeight.w600, color: CsColors.ink, em: 0.14),
              ),
              SizedBox(width: cs(14)),
              Expanded(child: child),
              if (trailing != null) ...[SizedBox(width: cs(10)), trailing!],
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return body;
    return CsPressable(
      onTap: onTap,
      scale: 0.99,
      haptic: CsHaptic.selection,
      semanticLabel: semanticLabel,
      child: body,
    );
  }
}

/// A compact strip under the Daily Directives showing this week's Weekly Ops
/// progress ("2 of 5 · resets in 3d") with a small progress line; tapping it
/// (or the chevron) switches to the Weekly Ops tab via [onOpen].
///
/// Accountless pilots get the compact "Sign in for Weekly Ops" CTA instead
/// (the ops come from the backend), opening [showAccountUpgradeSheet].
class WeeklyOpsStrip extends StatelessWidget {
  const WeeklyOpsStrip({
    super.key,
    required this.completed,
    required this.total,
    this.claimable = 0,
    this.resetsIn,
    this.isGuest = false,
    this.onOpen,
  });

  final int completed;
  final int total;

  /// Ops finished but not yet claimed (shown in mint).
  final int claimable;

  /// Defaults to [weeklyOpsResetsIn].
  final Duration? resetsIn;

  /// No account: show the sign-in CTA instead of progress.
  final bool isGuest;

  /// Switches to the Weekly Ops tab.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;

    if (isGuest) {
      return _StripFrame(
        icon: Symbols.event_repeat_rounded,
        iconColor: CsColors.ink45,
        label: 'Weekly Ops',
        trailing: CsButton.secondary(
          label: 'Sign in',
          icon: Symbols.person_add_rounded,
          size: CsButtonSize.small,
          onPressed: () => showAccountUpgradeSheet(
            context,
            reason: AccountUpgradeReason.saveProgress,
          ),
        ),
        child: Text(
          'Sign in for Weekly Ops',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.body,
        ),
      );
    }

    final reset = formatResetsIn(resetsIn ?? weeklyOpsResetsIn());
    final String status = total == 0
        ? 'Not posted yet · resets in $reset'
        : '$completed of $total · resets in $reset';
    final progress = total > 0 ? completed / total : 0.0;

    return _StripFrame(
      icon: Symbols.event_repeat_rounded,
      iconColor: claimable > 0 ? CsColors.mint : CsColors.ink60,
      label: 'Weekly Ops',
      onTap: onOpen,
      semanticLabel: 'Weekly Ops, $status',
      trailing: onOpen == null
          ? null
          : Icon(Symbols.chevron_right_rounded, size: cs(22), color: CsColors.ink60),
      child: Row(
        children: [
          Flexible(
            child: Text(
              claimable > 0 ? '$status · $claimable to claim' : status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.mono(10, color: claimable > 0 ? CsColors.mint : CsColors.ink55, em: 0.08),
            ),
          ),
          SizedBox(width: cs(14)),
          SizedBox(
            width: cs(72),
            child: CsProgressLine(
              value: progress,
              height: cs(3).clamp(2.0, 4.0),
              gradient: progress >= 1
                  ? CsGradients.complete
                  : const LinearGradient(colors: [CsColors.ink60, CsColors.ink60]),
            ),
          ),
        ],
      ),
    );
  }
}

/// The all-clear bonus as a compact strip ("All directives complete" +
/// bonus Credits, then a mint "Claimed" chip once paid).
class DirectivesBonusStrip extends StatelessWidget {
  const DirectivesBonusStrip({
    super.key,
    required this.bonusCoins,
    required this.claimed,
  });

  final int bonusCoins;
  final bool claimed;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return _StripFrame(
      icon: Symbols.redeem_rounded,
      iconColor: CsColors.gold,
      label: 'All clear',
      trailing: claimed
          ? const CsChip('Claimed', kind: CsChipKind.mint, icon: Symbols.check_rounded)
          : CsCoins(bonusCoins, prefix: '+', size: 11),
      child: Text(
        claimed ? 'Bonus reward claimed' : 'Bonus pending. Claim a directive.',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.body,
      ),
    );
  }
}
