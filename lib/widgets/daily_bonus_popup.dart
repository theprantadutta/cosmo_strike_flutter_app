import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// Data class for daily bonus reward
class DailyBonusReward {
  final int day;
  final int coins;
  final String? bonusItem;
  final bool claimed;

  const DailyBonusReward({
    required this.day,
    required this.coins,
    this.bonusItem,
    this.claimed = false,
  });

  factory DailyBonusReward.fromJson(Map<String, dynamic> json) {
    return DailyBonusReward(
      day: json['day'],
      coins: json['coins'],
      bonusItem: json['bonus_item'],
      claimed: json['claimed'] ?? false,
    );
  }
}

/// Daily bonus status from API
class DailyBonusStatus {
  final bool canClaim;
  final int currentStreak;
  final DateTime? lastClaimDate;
  final DailyBonusReward? todayReward;
  final List<DailyBonusReward> weekRewards;

  const DailyBonusStatus({
    required this.canClaim,
    required this.currentStreak,
    this.lastClaimDate,
    this.todayReward,
    required this.weekRewards,
  });

  factory DailyBonusStatus.fromJson(Map<String, dynamic> json) {
    return DailyBonusStatus(
      canClaim: json['can_claim'] ?? false,
      currentStreak: json['current_streak'] ?? 0,
      lastClaimDate: json['last_claim_date'] != null
          ? DateTime.parse(json['last_claim_date'])
          : null,
      todayReward: json['today_reward'] != null
          ? DailyBonusReward.fromJson(json['today_reward'])
          : null,
      weekRewards:
          (json['week_rewards'] as List?)
              ?.map((r) => DailyBonusReward.fromJson(r))
              .toList() ??
          [],
    );
  }

  /// Create a default/fallback status for offline mode
  factory DailyBonusStatus.offline() {
    return DailyBonusStatus(
      canClaim: false,
      currentStreak: 0,
      weekRewards: _defaultWeekRewards,
    );
  }

  static const List<DailyBonusReward> _defaultWeekRewards = [
    DailyBonusReward(day: 1, coins: 10),
    DailyBonusReward(day: 2, coins: 15),
    DailyBonusReward(day: 3, coins: 20, bonusItem: 'Speed Boost'),
    DailyBonusReward(day: 4, coins: 25),
    DailyBonusReward(day: 5, coins: 30, bonusItem: '2x XP Boost'),
    DailyBonusReward(day: 6, coins: 40),
    DailyBonusReward(day: 7, coins: 50, bonusItem: 'Premium Theme'),
  ];
}

/// The daily login bonus dialog (Prism Noir CsDialog): a 7-day streak row of
/// tiles (claimed = mint check, today = prism ring, upcoming = faint), today's
/// reward in gold mono, CLAIM (white) + optional CLAIM 2× via rewarded ad.
class DailyBonusPopup extends StatefulWidget {
  /// Kept for API compatibility; the dialog is always Prism Noir styled.
  final GameTheme theme;
  final DailyBonusStatus status;
  final Future<void> Function() onClaim;
  final VoidCallback onClose;
  final bool isLoading;

  /// Optional "claim + watch ad to double" action. When non-null a secondary
  /// button is shown. The caller (home) only supplies this when ads are
  /// available and the user isn't Pro, so the popup stays ad-agnostic.
  final Future<void> Function()? onClaimDoubled;

  const DailyBonusPopup({
    super.key,
    required this.theme,
    required this.status,
    required this.onClaim,
    required this.onClose,
    this.isLoading = false,
    this.onClaimDoubled,
  });

  /// Show the daily bonus popup as a dialog
  /// [onClaim] is called when the user taps claim - it should handle the reward immediately
  /// and queue any API calls for background sync (offline-first approach)
  static Future<void> show({
    required BuildContext context,
    required GameTheme theme,
    required DailyBonusStatus status,
    required Future<bool> Function() onClaim,
    Future<void> Function()? onClaimDoubled,
  }) async {
    await showCsDialog<void>(
      context,
      barrierDismissible: false,
      builder: (dialogContext) {
        void close() {
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        }

        return DailyBonusPopup(
          theme: theme,
          status: status,
          isLoading: false, // Never show loading - instant feedback
          onClaim: () async {
            // Await the claim BEFORE dismissing the dialog so the
            // Drift write + sync-outbox enqueue lands before the dialog
            // future resolves. Previously the popup closed first and the
            // claim ran in the background — a fast remount of home in that
            // window could re-trigger the popup because the Drift gate
            // hadn't been flipped yet.
            await onClaim();
            close();
          },
          onClaimDoubled: onClaimDoubled == null
              ? null
              : () async {
                  await onClaimDoubled();
                  close();
                },
          onClose: close,
        );
      },
    );
  }

  @override
  State<DailyBonusPopup> createState() => _DailyBonusPopupState();
}

class _DailyBonusPopupState extends State<DailyBonusPopup> {
  // Guards against a fast double-tap firing the claim (and crediting the
  // reward) twice before the dialog pops. We deliberately don't flip to a
  // loading spinner here — the popup is meant to feel instant — we just
  // make the button inert while the claim is in flight.
  bool _isClaiming = false;

  Future<void> _handleClaim() async {
    if (_isClaiming) return;
    setState(() => _isClaiming = true);
    try {
      await widget.onClaim();
    } finally {
      // onClaim normally pops the dialog, so this State is usually gone by
      // now — only reset if we're somehow still mounted (claim failed).
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  Future<void> _handleClaimDoubled() async {
    if (_isClaiming || widget.onClaimDoubled == null) return;
    setState(() => _isClaiming = true);
    try {
      await widget.onClaimDoubled!();
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final status = widget.status;
    final todayReward = status.todayReward;
    final currentDay = status.currentStreak > 0 ? status.currentStreak : 1;
    final busy = widget.isLoading || _isClaiming;

    return CsDialog(
      maxWidth: 600,
      titleWidget: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('DAILY BONUS', style: t.mono(11, em: .16)),
                SizedBox(height: cs(6)),
                Text(
                  status.canClaim ? 'Claim your daily reward!' : 'Come back tomorrow!',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.display(24, em: -0.03, height: 1.05),
                ),
              ],
            ),
          ),
          if (status.currentStreak > 1) ...[
            SizedBox(width: cs(10)),
            Padding(
              padding: EdgeInsets.only(top: cs(12)),
              child: CsChip(
                '${status.currentStreak} day streak',
                kind: CsChipKind.pink,
                icon: Symbols.local_fire_department_rounded,
              ),
            ),
          ],
          SizedBox(width: cs(4)),
          CsIconButton(
            icon: Symbols.close_rounded,
            size: 34,
            bordered: false,
            color: CsColors.ink60,
            tooltip: 'Close',
            onPressed: widget.onClose,
          ),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _WeekRow(status: status, currentDay: currentDay),
          SizedBox(height: cs(16)),
          if (todayReward != null) _TodayReward(reward: todayReward),
          if (!status.canClaim) ...[
            SizedBox(height: cs(10)),
            const CsMeta('Already claimed today', icon: Symbols.schedule_rounded),
          ],
        ],
      ),
      actions: status.canClaim
          ? [
              if (widget.onClaimDoubled != null)
                CsButton.secondary(
                  label: 'Claim 2× · watch ad',
                  icon: Symbols.play_circle_rounded,
                  onPressed: busy ? null : _handleClaimDoubled,
                ),
              CsButton.primary(
                label: 'Claim reward',
                icon: Symbols.redeem_rounded,
                loading: widget.isLoading,
                onPressed: busy ? null : _handleClaim,
              ),
            ]
          : [CsButton.text(label: 'Close', onPressed: widget.onClose)],
    );
  }
}

/// The 7-day streak as a row of tiles: claimed = done + mint check, today =
/// prism ring, everything else = faint future tile.
class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.status, required this.currentDay});
  final DailyBonusStatus status;
  final int currentDay;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final tiles = <Widget>[];
    for (var index = 0; index < 7; index++) {
      final day = index + 1;
      final reward = status.weekRewards.length > index
          ? status.weekRewards[index]
          : DailyBonusReward(day: day, coins: 10 + (day * 5));
      final isClaimed = reward.claimed;
      final isToday = day == currentDay;

      final CsTileState state = isClaimed
          ? CsTileState.done
          : (isToday ? CsTileState.current : CsTileState.future);

      final Widget glyph = isClaimed
          ? Icon(Symbols.check_circle_rounded, size: cs(18), color: CsColors.mint)
          : (reward.bonusItem != null
              ? Icon(Symbols.redeem_rounded, size: cs(18), color: CsColors.gold)
              : Image.asset('assets/images/ui/coin.png', width: cs(18), height: cs(18)));

      tiles.add(Expanded(
        child: CsTile(
          state: state,
          rotateRing: isToday && status.canClaim,
          padding: EdgeInsets.symmetric(vertical: cs(9), horizontal: cs(2)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'D$day',
                maxLines: 1,
                style: t.mono(9, color: isToday ? CsColors.ink : CsColors.ink45, em: 0.12),
              ),
              SizedBox(height: cs(6)),
              glyph,
              SizedBox(height: cs(6)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${reward.coins}',
                  maxLines: 1,
                  style: t.mono(
                    10.5,
                    weight: FontWeight.w600,
                    em: 0.04,
                    color: isClaimed ? CsColors.ink45 : CsColors.gold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ));
      if (index < 6) tiles.add(SizedBox(width: cs(6)));
    }
    return Row(children: tiles);
  }
}

/// "TODAY'S REWARD" caption + gold coins (+ bonus item chip).
class _TodayReward extends StatelessWidget {
  const _TodayReward({required this.reward});
  final DailyBonusReward reward;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: cs(14),
      runSpacing: cs(8),
      children: [
        const CsLabel("Today's reward"),
        CsCoins(reward.coins, prefix: '+', size: 14),
        if (reward.bonusItem != null)
          CsChip(reward.bonusItem!, kind: CsChipKind.gold, icon: Symbols.redeem_rounded, size: 10),
      ],
    );
  }
}
