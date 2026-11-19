import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/daily_challenge_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

/// Left column of the Daily Directives tab: the day's goal (clear all 3 for
/// the bonus), the pilot's daily streak and the countdown to new orders.
///
/// Self-contained: it listens to [DailyChallengeService] (Drift-backed,
/// offline-first) and claims through its bonus path, so it takes no
/// arguments. Drop it into the screen's split in place of the old summary:
///
/// ```dart
/// left: const DirectivesGoalPanel(),
/// ```
///
/// Never scrolls (a [CsFitColumn] scales it down on short phones).
class DirectivesGoalPanel extends StatefulWidget {
  const DirectivesGoalPanel({super.key});

  @override
  State<DirectivesGoalPanel> createState() => _DirectivesGoalPanelState();
}

class _DirectivesGoalPanelState extends State<DirectivesGoalPanel> {
  final DailyChallengeService _service = DailyChallengeService();
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    // One indexed Drift query; the panel renders straight away with the
    // last known value and updates when it lands.
    unawaited(_service.refreshStreak());
  }

  Future<void> _claimBonus() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      final claimed = await _service.claimAllCompleteBonus();
      if (claimed) CsHaptic.success.play();
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  /// Local midnight passed while the panel was open: roll the day over.
  /// All offline-safe — [DailyChallengeService.initialize] re-hydrates from
  /// Drift (and seeds a guest's new set); the backend refresh is fire-and-
  /// forget and the panel never waits on it.
  void _onNewDay() {
    unawaited(() async {
      await _service.initialize();
      unawaited(_service.refreshChallenges());
    }());
  }

  @override
  Widget build(BuildContext context) {
    final coins = GetIt.I.isRegistered<CoinsCubit>() ? GetIt.I<CoinsCubit>() : null;
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) => DirectivesGoalView(
        completed: _service.completedCount,
        total: _service.totalCount,
        bonusCoins: DailyChallengeService.allCompleteBonusCoins,
        bonusXp: DailyChallengeService.allCompleteBonusXp,
        bonusClaimed: _service.isBonusClaimed,
        unclaimedDirectives: _service.unclaimedRewardsCount,
        streakDays: _service.streakDays,
        streakSecuredToday: _service.streakSecuredToday,
        claiming: _claiming,
        onClaimBonus: _claimBonus,
        onNewDay: _onNewDay,
        balance: coins == null
            ? null
            : BlocBuilder<CoinsCubit, CoinsState>(
                bloc: coins,
                buildWhen: (a, b) => a.balance.total != b.balance.total,
                builder: (context, s) => CsCoins(s.balance.total, size: 11),
              ),
      ),
    );
  }
}

/// Where today's goal stands.
enum DirectivesGoalPhase {
  /// Some directives still to clear (or none issued yet).
  inProgress,

  /// Every directive cleared, bonus not collected yet.
  claimable,

  /// Bonus collected.
  claimed,
}

/// The stateless-ish view behind [DirectivesGoalPanel], fed plain values so
/// it can be laid out and tested without the service or Drift.
class DirectivesGoalView extends StatelessWidget {
  const DirectivesGoalView({
    super.key,
    required this.completed,
    required this.total,
    required this.bonusCoins,
    required this.bonusXp,
    required this.bonusClaimed,
    required this.streakDays,
    required this.streakSecuredToday,
    this.unclaimedDirectives = 0,
    this.claiming = false,
    this.onClaimBonus,
    this.onNewDay,
    this.balance,
    this.clock = DateTime.now,
  });

  final int completed;
  final int total;
  final int bonusCoins;
  final int bonusXp;
  final bool bonusClaimed;
  final int streakDays;
  final bool streakSecuredToday;

  /// Completed directives whose own reward isn't claimed yet; the claim
  /// button collects them together with the bonus.
  final int unclaimedDirectives;
  final bool claiming;
  final VoidCallback? onClaimBonus;

  /// Fired once when the countdown passes local midnight.
  final VoidCallback? onNewDay;

  /// Optional Credits balance (rolls when the claim lands).
  final Widget? balance;

  /// Time source for the countdown (tests).
  final DateTime Function() clock;

  DirectivesGoalPhase get phase {
    if (bonusClaimed) return DirectivesGoalPhase.claimed;
    if (total > 0 && completed >= total) return DirectivesGoalPhase.claimable;
    return DirectivesGoalPhase.inProgress;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return CsFitColumn(
      alignment: Alignment.centerLeft,
      children: [
        CsFadeUp(
          index: 0,
          child: _GoalBlock(
            phase: phase,
            completed: completed,
            total: total,
            bonusCoins: bonusCoins,
            bonusXp: bonusXp,
            unclaimedDirectives: unclaimedDirectives,
            claiming: claiming,
            onClaimBonus: onClaimBonus,
            balance: balance,
          ),
        ),
        SizedBox(height: cs(18)),
        CsFadeUp(
          index: 1,
          child: _StreakBlock(days: streakDays, securedToday: streakSecuredToday),
        ),
        SizedBox(height: cs(18)),
        CsFadeUp(
          index: 2,
          child: _ResetBlock(clock: clock, onNewDay: onNewDay),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Goal: clear all 3
// ─────────────────────────────────────────────────────────────────────────────

class _GoalBlock extends StatelessWidget {
  const _GoalBlock({
    required this.phase,
    required this.completed,
    required this.total,
    required this.bonusCoins,
    required this.bonusXp,
    required this.unclaimedDirectives,
    required this.claiming,
    required this.onClaimBonus,
    required this.balance,
  });

  final DirectivesGoalPhase phase;
  final int completed;
  final int total;
  final int bonusCoins;
  final int bonusXp;
  final int unclaimedDirectives;
  final bool claiming;
  final VoidCallback? onClaimBonus;
  final Widget? balance;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final pips = total > 0 ? total : 3;
    final cleared = completed.clamp(0, pips);
    final claimable = phase == DirectivesGoalPhase.claimable;
    final claimed = phase == DirectivesGoalPhase.claimed;

    final Widget status = switch (phase) {
      DirectivesGoalPhase.claimed => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.check_circle_rounded, size: cs(14), fill: 1, color: CsColors.mint),
          SizedBox(width: cs(5)),
          Text('Bonus collected',
              maxLines: 1, style: t.mono(10, weight: FontWeight.w600, color: CsColors.mint, em: 0.08)),
        ]),
      DirectivesGoalPhase.claimable => Text('Bonus ready',
          maxLines: 1, style: t.mono(10, weight: FontWeight.w600, color: CsColors.gold, em: 0.08)),
      DirectivesGoalPhase.inProgress => Text(
          total == 0 ? 'Awaiting orders' : '$cleared of $total cleared',
          maxLines: 1,
          style: t.mono(10, weight: FontWeight.w600, color: CsColors.ink60, em: 0.08),
        ),
    };

    final ringIcon = claimed
        ? Icon(Symbols.check_rounded, size: cs(30), color: CsColors.mint)
        : Icon(
            Symbols.redeem_rounded,
            size: cs(28),
            fill: claimable ? 1 : 0,
            color: claimable ? CsColors.gold : CsColors.ink45,
          );

    final reward = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CsCoinGlyph(size: 17),
        SizedBox(width: cs(6)),
        Text('+$bonusCoins CR', maxLines: 1, style: t.number(16, color: CsColors.gold)),
        SizedBox(width: cs(12)),
        Text('+$bonusXp XP', maxLines: 1, style: t.number(16, color: CsColors.violet)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("TODAY'S GOAL", maxLines: 1, style: t.mono(9, color: CsColors.ink45, em: 0.2)),
        SizedBox(height: cs(10)),
        Row(
          children: [
            CsRingProgress(
              value: total > 0 ? completed / total : 0,
              size: cs(76),
              stroke: cs(3).clamp(2.0, 4.0),
              popOnComplete: true,
              child: Center(
                child: CsPop(trigger: phase, peak: 1.2, child: ringIcon),
              ),
            ),
            SizedBox(width: cs(16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Clear all ${total > 0 ? total : 3}',
                      maxLines: 1,
                      style: t.display(26, em: -0.03, height: 1),
                    ),
                  ),
                  SizedBox(height: cs(9)),
                  Row(
                    children: [
                      for (var i = 0; i < pips; i++) ...[
                        if (i > 0) SizedBox(width: cs(6)),
                        _Pip(filled: i < cleared),
                      ],
                    ],
                  ),
                  SizedBox(height: cs(8)),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: status),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: cs(14)),
        // Pops when the bonus becomes claimable (and again as it's
        // collected); also on open if it's already waiting.
        CsPop(
          trigger: phase,
          playOnMount: claimable,
          delay: const Duration(milliseconds: 420),
          alignment: Alignment.centerLeft,
          child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: reward),
        ),
        if (claimable) ...[
          SizedBox(height: cs(14)),
          SizedBox(
            width: double.infinity,
            child: CsButton.premium(
              label: unclaimedDirectives > 0 ? 'Claim all + bonus' : 'Claim bonus',
              icon: Symbols.redeem_rounded,
              expand: true,
              loading: claiming,
              onPressed: claiming ? null : onClaimBonus,
            ),
          ),
        ],
        if (balance != null && phase != DirectivesGoalPhase.inProgress) ...[
          SizedBox(height: cs(10)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('BALANCE', maxLines: 1, style: t.mono(9, color: CsColors.ink45, em: 0.2)),
              SizedBox(width: cs(8)),
              balance!,
            ],
          ),
        ],
      ],
    );
  }
}

/// One directive pip: mint dot when cleared, hairline ring when not.
class _Pip extends StatelessWidget {
  const _Pip({required this.filled});
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final d = context.cs(10);
    return CsPop(
      trigger: filled,
      peak: 1.35,
      child: Container(
        width: d,
        height: d,
        decoration: ShapeDecoration(
          color: filled ? CsColors.mint : null,
          shape: CircleBorder(
            side: filled ? BorderSide.none : const BorderSide(color: CsColors.lineStrong),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Streak
// ─────────────────────────────────────────────────────────────────────────────

class _StreakBlock extends StatefulWidget {
  const _StreakBlock({required this.days, required this.securedToday});
  final int days;
  final bool securedToday;

  @override
  State<_StreakBlock> createState() => _StreakBlockState();
}

class _StreakBlockState extends State<_StreakBlock> {
  /// When a streak starts while the panel is open, the counter mounts fresh;
  /// this makes its first build roll up from 0 instead of appearing static.
  int? _rollFrom;

  @override
  void didUpdateWidget(_StreakBlock old) {
    super.didUpdateWidget(old);
    if (old.days == 0 && widget.days > 0) _rollFrom = 0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final days = widget.days;
    final active = days > 0;

    final flame = Icon(
      Symbols.local_fire_department_rounded,
      size: cs(30),
      fill: active ? 1 : 0,
      color: active ? CsColors.gold : CsColors.ink30,
    );

    final Widget body;
    if (!active) {
      body = Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('Start a streak today',
                  maxLines: 1, style: t.display(17, weight: FontWeight.w700, em: -0.01, height: 1.15)),
            ),
            SizedBox(height: cs(4)),
            Text('CLEAR 1 DIRECTIVE TO LIGHT IT',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.mono(9, color: CsColors.ink45, em: 0.14)),
          ],
        ),
      );
    } else {
      body = Expanded(
        child: Row(
          children: [
            CsOdometer(
              value: days,
              from: _rollFrom,
              style: t.number(34, em: -0.04, height: 1),
              semanticsLabel: '$days-day streak',
            ),
            SizedBox(width: cs(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('DAY STREAK',
                      maxLines: 1, style: t.mono(10, weight: FontWeight.w600, color: CsColors.ink, em: 0.16)),
                  SizedBox(height: cs(4)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: widget.securedToday
                        ? Text('SECURED TODAY',
                            maxLines: 1, style: t.mono(9, color: CsColors.mint, em: 0.14))
                        : Text('CLEAR 1 TODAY TO KEEP IT',
                            maxLines: 1, style: t.mono(9, color: CsColors.pink, em: 0.14)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const CsHairline(),
        SizedBox(height: cs(16)),
        Row(
          children: [
            CsPop(trigger: active && widget.securedToday, peak: 1.2, child: flame),
            SizedBox(width: cs(10)),
            body,
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reset countdown
// ─────────────────────────────────────────────────────────────────────────────

class _ResetBlock extends StatelessWidget {
  const _ResetBlock({required this.clock, required this.onNewDay});
  final DateTime Function() clock;
  final VoidCallback? onNewDay;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const CsHairline(),
        SizedBox(height: cs(16)),
        Text('NEW ORDERS IN', maxLines: 1, style: t.mono(9, color: CsColors.ink45, em: 0.2)),
        SizedBox(height: cs(6)),
        DirectivesResetCountdown(
          clock: clock,
          onNewDay: onNewDay,
          style: t.number(32, em: -0.03, height: 1),
        ),
      ],
    );
  }
}

/// "07:12:40" to the next local midnight. Ticks once a second, aligned to
/// the wall-clock second, and only this Text rebuilds/repaints (it sits in
/// its own RepaintBoundary).
class DirectivesResetCountdown extends StatefulWidget {
  const DirectivesResetCountdown({
    super.key,
    required this.style,
    this.clock = DateTime.now,
    this.onNewDay,
  });

  final TextStyle style;
  final DateTime Function() clock;
  final VoidCallback? onNewDay;

  /// "hh:mm:ss" until the local midnight after [now].
  static String format(DateTime now) {
    final next = DateTime(now.year, now.month, now.day + 1);
    var left = next.difference(now);
    if (left.isNegative) left = Duration.zero;
    String two(int v) => v.toString().padLeft(2, '0');
    final secs = (left.inMilliseconds / 1000).ceil();
    return '${two(secs ~/ 3600)}:${two(secs % 3600 ~/ 60)}:${two(secs % 60)}';
  }

  @override
  State<DirectivesResetCountdown> createState() => _DirectivesResetCountdownState();
}

class _DirectivesResetCountdownState extends State<DirectivesResetCountdown> {
  Timer? _timer;
  late DateTime _now = widget.clock();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final ms = 1000 - _now.millisecond;
    _timer = Timer(Duration(milliseconds: ms <= 0 ? 1000 : ms), _tick);
  }

  void _tick() {
    if (!mounted) return;
    final next = widget.clock();
    final newDay = next.day != _now.day || next.month != _now.month || next.year != _now.year;
    setState(() => _now = next);
    if (newDay) widget.onNewDay?.call();
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = DirectivesResetCountdown.format(_now);
    return RepaintBoundary(
      child: Semantics(
        label: 'New orders in $text',
        excludeSemantics: true,
        child: Text(text, maxLines: 1, style: widget.style),
      ),
    );
  }
}
