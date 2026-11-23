import 'dart:async';

import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/daily_challenge.dart';
import '../../models/ship_coins.dart';
import '../../presentation/bloc/coins/coins_cubit.dart';
import '../../providers/daily_challenges_provider.dart';
import '../../services/daily_challenge_service.dart';

/// Tomorrow's (or today's still unopened) Supply Drop from the 7-day ladder.
class SupplyDropPreview {
  const SupplyDropPreview({
    required this.day,
    required this.coins,
    this.bonusItem,
    required this.readyToday,
  });

  final int day;
  final int coins;
  final String? bonusItem;

  /// Today's drop hasn't been opened yet (shown instead of tomorrow's).
  final bool readyToday;

  String get line {
    final reward = bonusItem == null ? '+$coins CR' : '+$coins CR + $bonusItem';
    return readyToday
        ? 'Supply Drop ready · Day $day · $reward'
        : 'Tomorrow · Day $day · $reward';
  }
}

/// Pure content rules for the game over's NEXT UP strip (from run 2 on):
/// the closest-to-done directive, the directive streak and the next Supply
/// Drop. Each is a reason to fly again today or come back tomorrow.
abstract final class NextUp {
  /// From the second run on (run 1's debrief stays about the run itself).
  static bool showsFor({required int runsStarted}) => runsStarted >= 2;

  /// The unfinished directive closest to done: highest progress share,
  /// then fewest steps left, then list order. Null when none is left.
  static DailyChallenge? pickFocus(List<DailyChallenge> challenges) {
    DailyChallenge? best;
    for (final c in challenges) {
      if (c.isCompleted || c.claimedReward || c.targetValue <= 0) continue;
      if (best == null) {
        best = c;
        continue;
      }
      final share = c.progressPercentage;
      final bestShare = best.progressPercentage;
      if (share > bestShare ||
          (share == bestShare &&
              c.targetValue - c.currentProgress <
                  best.targetValue - best.currentProgress)) {
        best = c;
      }
    }
    return best;
  }

  /// The streak line: secured today, at risk, or not started.
  static String streakLine({required int days, required bool securedToday}) {
    if (securedToday) {
      return days >= 2 ? '$days-day streak secured' : 'Streak started · day 1 secured';
    }
    return days >= 1
        ? 'Clear 1 directive to keep your $days-day streak'
        : 'Clear 1 directive to start a streak';
  }

  /// The Supply Drop to point at. Claimed today → tomorrow's rung (the
  /// streak counts today's claim, so tomorrow is `streak % 7 + 1`); not
  /// claimed yet → today's rung, still waiting on Home.
  static SupplyDropPreview? supplyDrop({
    required bool claimedToday,
    required int currentStreak,
    required int nextClaimDay,
    List<DailyLoginBonus>? ladder,
  }) {
    final rungs = ladder ?? DailyLoginBonus.getWeeklyBonuses();
    if (rungs.isEmpty) return null;
    final day = claimedToday ? (currentStreak % rungs.length) + 1 : nextClaimDay;
    if (day < 1 || day > rungs.length) return null;
    final rung = rungs[day - 1];
    return SupplyDropPreview(
      day: day,
      coins: rung.coins,
      bonusItem: rung.bonusItem,
      readyToday: !claimedToday,
    );
  }
}

/// The NEXT UP strip, fed plain values (laid out and tested without the
/// services): the focus directive (tap → Directives), the streak line and
/// the Supply Drop line. Compact enough for a 640×360 phone's right column.
class NextUpView extends StatelessWidget {
  const NextUpView({
    super.key,
    required this.focus,
    required this.streakDays,
    required this.streakSecuredToday,
    required this.drop,
    this.runDelta = 0,
    this.onOpenDirectives,
  });

  final DailyChallenge? focus;
  final int streakDays;
  final bool streakSecuredToday;
  final SupplyDropPreview? drop;

  /// How much this run advanced [focus].
  final int runDelta;
  final VoidCallback? onOpenDirectives;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final f = focus;
    final drop = this.drop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (f != null)
          CsPressable(
            onTap: onOpenDirectives,
            haptic: CsHaptic.selection,
            semanticLabel: 'Open Daily Directives',
            child: Container(
              padding: EdgeInsets.symmetric(vertical: cs(10)),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: CsColors.hairline),
                  bottom: BorderSide(color: CsColors.hairline),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(f.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
                        SizedBox(height: cs(7)),
                        CsProgressLine(value: f.progressPercentage),
                        SizedBox(height: cs(6)),
                        Text.rich(
                          TextSpan(
                            text: '${f.currentProgress.clamp(0, f.targetValue)} / ${f.targetValue}',
                            children: [
                              if (runDelta > 0)
                                TextSpan(
                                  text: '  +$runDelta THIS RUN',
                                  style: const TextStyle(color: CsColors.gold),
                                ),
                              TextSpan(
                                text: '  ·  +${f.coinReward} CR',
                                style: const TextStyle(color: CsColors.gold),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.mono(10, em: 0.1, color: CsColors.ink45),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: cs(10)),
                  Icon(Symbols.chevron_right_rounded, size: cs(18), color: CsColors.ink45),
                ],
              ),
            ),
          ),
        SizedBox(height: cs(10)),
        _InfoLine(
          icon: Symbols.local_fire_department_rounded,
          color: streakSecuredToday ? CsColors.mint : CsColors.gold,
          text: NextUp.streakLine(days: streakDays, securedToday: streakSecuredToday),
        ),
        if (drop != null) ...[
          SizedBox(height: cs(6)),
          _InfoLine(
            icon: Symbols.redeem_rounded,
            color: CsColors.gold,
            text: drop.line,
          ),
        ],
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Row(
      children: [
        Icon(icon, size: cs(14), color: color),
        SizedBox(width: cs(8)),
        Expanded(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: cs.type.mono(10, em: 0.1, color: color),
          ),
        ),
      ],
    );
  }
}

/// [NextUpView] wired to the live sources: today's directives
/// ([dailyChallengesProvider], updated as the run's progress lands), the
/// streak ([DailyChallengeService]) and the Supply Drop ladder
/// ([CoinsCubit]). All local (Drift-backed), never a network wait.
class GameOverNextUp extends ConsumerStatefulWidget {
  const GameOverNextUp({
    super.key,
    required this.runStartProgress,
    this.onOpenDirectives,
  });

  /// Per-directive progress at run start (id → progress), for "+N THIS RUN".
  final Map<String, int> runStartProgress;
  final VoidCallback? onOpenDirectives;

  @override
  ConsumerState<GameOverNextUp> createState() => _GameOverNextUpState();
}

class _GameOverNextUpState extends ConsumerState<GameOverNextUp> {
  final DailyChallengeService _service = DailyChallengeService();

  @override
  void initState() {
    super.initState();
    unawaited(_service.refreshStreak());
  }

  @override
  Widget build(BuildContext context) {
    final challenges = ref.watch(dailyChallengesProvider).challenges;
    final focus = NextUp.pickFocus(challenges);
    final runDelta = focus == null
        ? 0
        : (focus.currentProgress - (widget.runStartProgress[focus.id] ?? focus.currentProgress))
            .clamp(0, focus.currentProgress);
    final coins = GetIt.I.isRegistered<CoinsCubit>() ? GetIt.I<CoinsCubit>() : null;

    Widget view(SupplyDropPreview? drop) => ListenableBuilder(
          listenable: _service,
          builder: (context, _) => NextUpView(
            focus: focus,
            runDelta: runDelta,
            streakDays: _service.streakDays,
            streakSecuredToday: _service.streakSecuredToday,
            drop: drop,
            onOpenDirectives: widget.onOpenDirectives,
          ),
        );

    if (coins == null) return view(null);
    return BlocBuilder<CoinsCubit, CoinsState>(
      bloc: coins,
      buildWhen: (a, b) =>
          a.dailyBonusLastClaimUtcMs != b.dailyBonusLastClaimUtcMs ||
          a.dailyBonusCurrentStreak != b.dailyBonusCurrentStreak,
      builder: (context, s) => view(
        NextUp.supplyDrop(
          claimedToday: s.wasDailyBonusClaimedToday,
          currentStreak: s.dailyBonusCurrentStreak,
          nextClaimDay: s.nextClaimDay,
        ),
      ),
    );
  }
}
