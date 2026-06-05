import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
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

/// A popup dialog for daily login bonus
class DailyBonusPopup extends StatefulWidget {
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
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (dialogContext) {
        return DailyBonusPopup(
          theme: theme,
          status: status,
          isLoading: false, // Never show loading - instant feedback
          onClaim: () async {
            // Await the claim BEFORE dismissing the dialog so the
            // Drift write + sync-outbox enqueue lands before
            // showDialog resolves. Previously the popup closed first
            // and the claim ran in the background — a fast remount of
            // home in that window could re-trigger the popup because
            // the Drift gate hadn't been flipped yet.
            await onClaim();
            if (dialogContext.mounted) dialogContext.pop();
          },
          onClaimDoubled: onClaimDoubled == null
              ? null
              : () async {
                  await onClaimDoubled();
                  if (dialogContext.mounted) dialogContext.pop();
                },
          onClose: () => dialogContext.pop(),
        );
      },
    );
  }

  @override
  State<DailyBonusPopup> createState() => _DailyBonusPopupState();
}

class _DailyBonusPopupState extends State<DailyBonusPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

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
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todayReward = widget.status.todayReward;
    final currentDay = widget.status.currentStreak > 0
        ? widget.status.currentStreak
        : 1;

    return Dialog(
      backgroundColor: Colors.transparent,
      child:
          Container(
            constraints: const BoxConstraints(maxWidth: 520),
            // Borderless per the clean design — the skin's neon glow frames it.
            decoration: BoxDecoration(
              color: widget.theme.backgroundColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: widget.theme.glow.withValues(alpha: 0.35),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compact header (icon + title + streak on one row).
                _buildHeader(),

                // Week progress
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildWeekProgress(currentDay),
                ),

                const SizedBox(height: 8),

                // Today's reward
                if (todayReward != null) _buildTodayReward(todayReward),

                const SizedBox(height: 10),

                // Claim button
                _buildClaimButton(),

                // Close button (if can't claim)
                if (!widget.status.canClaim) _buildCloseButton(),

                const SizedBox(height: 10),
              ],
            ),
          ).animate().scale(
            begin: const Offset(0.8, 0.8),
            end: const Offset(1, 1),
            duration: 300.ms,
            curve: Curves.easeOutBack,
          ),
    );
  }

  Widget _buildHeader() {
    // Borderless, no banner fill — the gift disc and typography carry it.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 6),
      child: Row(
        children: [
          // Gift disc on the skin's neon ramp, with animation (compact).
          Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.theme.neonPrimary,
                      widget.theme.neonSecondary,
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.theme.glow.withValues(alpha: 0.5),
                      blurRadius: 16,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: const Text('🎁', style: TextStyle(fontSize: 26)),
              )
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.1, 1.1),
                duration: 1000.ms,
              ),

          const SizedBox(width: 12),

          // Title + subtitle.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Daily Bonus',
                  style: TextStyle(
                    color: widget.theme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.status.canClaim
                      ? 'Claim your daily reward!'
                      : 'Come back tomorrow!',
                  style: TextStyle(
                    color: widget.theme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          // Streak chip.
          if (widget.status.currentStreak > 1) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              // Borderless neon tint.
              decoration: BoxDecoration(
                color: widget.theme.neonSecondary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.status.currentStreak} day streak!',
                    style: TextStyle(
                      color: widget.theme.neonSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(width: 8),

          // Close button.
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: widget.theme.backgroundColor.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                color: widget.theme.accentColor.withValues(alpha: 0.7),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekProgress(int currentDay) {
    return Column(
      children: [
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(7, (index) {
            final day = index + 1;
            final reward = widget.status.weekRewards.length > index
                ? widget.status.weekRewards[index]
                : DailyBonusReward(day: day, coins: 10 + (day * 5));

            final isClaimed = reward.claimed;
            final isToday = day == currentDay;
            final isFuture = day > currentDay;

            return Expanded(
              child: _buildDayCircle(
                day: day,
                coins: reward.coins,
                hasBonus: reward.bonusItem != null,
                isClaimed: isClaimed,
                isToday: isToday,
                isFuture: isFuture,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildDayCircle({
    required int day,
    required int coins,
    required bool hasBonus,
    required bool isClaimed,
    required bool isToday,
    required bool isFuture,
  }) {
    // Borderless per the clean design — day state reads via tint + glow:
    // claimed = green (app-wide success colour) tint + check, today = the
    // skin's neon tint + glow + pulse, upcoming = faint glass tint.
    Color bgColor;
    Widget icon;

    if (isClaimed) {
      bgColor = Colors.green.withValues(alpha: 0.22);
      icon = const Icon(Icons.check, color: Colors.green, size: 16);
    } else if (isToday) {
      bgColor = widget.theme.neonPrimary.withValues(alpha: 0.22);
      icon = Text('🎁', style: TextStyle(fontSize: hasBonus ? 14 : 12));
    } else {
      bgColor = widget.theme.surfaceGlass;
      icon = Text(
        hasBonus ? '⭐' : '🪙',
        style: const TextStyle(fontSize: 12),
      );
    }

    Widget circle = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        boxShadow: isToday
            ? [
                BoxShadow(
                  color: widget.theme.glow.withValues(alpha: 0.5),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Center(child: icon),
    );

    if (isToday && widget.status.canClaim) {
      circle = circle
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.1, 1.1),
            duration: 800.ms,
          );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        const SizedBox(height: 4),
        Text(
          'D$day',
          style: TextStyle(
            color: isToday
                ? widget.theme.neonPrimary
                : widget.theme.textMuted
                    .withValues(alpha: isFuture ? 0.55 : 1.0),
            fontSize: 10,
            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildTodayReward(DailyBonusReward reward) {
    // Fully transparent — the reward pills alone carry the emphasis.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Today's Reward",
            style: TextStyle(
              color: widget.theme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                // Coins
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🪙', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(
                        '+${reward.coins}',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // Bonus item if any
                if (reward.bonusItem != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    // Borderless neon tint.
                    decoration: BoxDecoration(
                      color: widget.theme.neonSecondary
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🎁', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          reward.bonusItem!,
                          style: TextStyle(
                            color: widget.theme.neonSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildClaimButton() {
    if (!widget.status.canClaim) {
      // Borderless muted state chip on the skin's glass tint.
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: widget.theme.surfaceGlass,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.access_time,
              color: widget.theme.textMuted,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Already claimed today',
              style: TextStyle(
                color: widget.theme.textMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    final claimButton = GestureDetector(
      onTap: (widget.isLoading || _isClaiming) ? null : _handleClaim,
      // CTA pill on the skin's neon ramp — same language as the mode
      // picker's START PLAYING pill: glow only, dark lettering, no border.
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              widget.theme.neonPrimary,
              widget.theme.neonSecondary,
            ],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: widget.theme.neonPrimary.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: widget.isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Color(0xFF03040A),
                  strokeWidth: 2,
                ),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('🎉', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 8),
                  Text(
                    'CLAIM REWARD',
                    style: TextStyle(
                      color: Color(0xFF03040A),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
      ),
    );

    Widget animate(Widget w) =>
        w.animate(delay: 300.ms).fadeIn().scale(begin: const Offset(0.9, 0.9));

    // No ad option → just the normal claim button.
    if (widget.onClaimDoubled == null) return animate(claimButton);

    // Ad available → claim button + a "claim and double via ad" option.
    return animate(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          claimButton,
          const SizedBox(height: 8),
          GestureDetector(
            onTap: (widget.isLoading || _isClaiming)
                ? null
                : _handleClaimDoubled,
            // Borderless neon tint — the secondary action.
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
              decoration: BoxDecoration(
                color: widget.theme.neonPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_fill,
                      color: widget.theme.neonPrimary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'CLAIM 2× — WATCH AD',
                    style: TextStyle(
                      color: widget.theme.neonPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloseButton() {
    return TextButton(
      onPressed: widget.onClose,
      child: Text(
        'Close',
        style: TextStyle(
          color: widget.theme.textMuted,
          fontSize: 14,
        ),
      ),
    );
  }
}
