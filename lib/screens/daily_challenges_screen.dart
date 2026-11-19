import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/providers/providers.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/services/daily_challenge_service.dart';
import 'package:cosmo_strike_flutter_app/services/weekly_quest_service.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/directives_board.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/launch_sortie.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/weekly_ops_strip.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives_empty_state.dart';
import 'package:cosmo_strike_flutter_app/widgets/list_entrance.dart';
import 'package:cosmo_strike_flutter_app/widgets/reward_toast.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';

/// The Daily tab of the challenges hub (ChallengesHubScreen owns the
/// CsScaffold + tab chrome; this renders only the two-region body):
/// LEFT = progress ring + headline + CLAIM ALL + rules, RIGHT = the
/// DirectivesBoard (one card per directive filling the column, then the
/// all-clear bonus and Weekly Ops strips).
class DailyChallengesBody extends ConsumerStatefulWidget {
  const DailyChallengesBody({super.key, this.onOpenWeekly});

  /// Switches the hub to the Weekly Ops tab (the Weekly Ops strip's tap).
  final VoidCallback? onOpenWeekly;

  @override
  ConsumerState<DailyChallengesBody> createState() =>
      _DailyChallengesBodyState();
}

class _DailyChallengesBodyState extends ConsumerState<DailyChallengesBody> {
  /// Coins from the last CLAIM ALL that can still be doubled via a rewarded
  /// ad. Null = no offer. Single use.
  int? _doubleOfferCoins;

  /// Rows stagger in on first open only.
  final _entrance = ListEntrance();

  Future<void> _refreshChallenges() async {
    await ref.read(dailyChallengesProvider.notifier).refresh();
  }

  Future<void> _claimReward(DailyChallenge challenge) async {
    final success = await ref
        .read(dailyChallengesProvider.notifier)
        .claimReward(challenge.id);
    if (success) {
      getIt<AnalyticsFacade>().trackDailyChallengeRewardClaimed();
      // Coins + BP XP are credited inside DailyChallengeService.claimReward
      // — crediting here again was paying the reward twice. The toast
      // brings its own sound + haptic.
      RewardToast.show(
        title: 'DIRECTIVE COMPLETE',
        amount: '+${challenge.coinReward} CR · +${challenge.xpReward} XP',
      );
    }
  }

  Future<void> _claimAllRewards() async {
    final totalClaimed = await ref
        .read(dailyChallengesProvider.notifier)
        .claimAllRewards();
    if (totalClaimed > 0) {
      // Coins are credited inside DailyChallengeService.claimAllRewards —
      // crediting here again was paying the reward twice. The toast brings
      // its own sound + haptic.
      RewardToast.show(
        title: 'ALL DIRECTIVES CLAIMED',
        amount: '+$totalClaimed CR',
      );
      if (!mounted) return;
      // The toast is non-interactive, so the rewarded "2×" entry point is
      // offered inline in the summary column when an ad is available.
      final ads = getIt.isRegistered<AdService>() ? getIt<AdService>() : null;
      final canDouble = ads != null && ads.adsEnabled && ads.isRewardedReady;
      if (canDouble) setState(() => _doubleOfferCoins = totalClaimed);
    }
  }

  void _watchToDouble() {
    final amount = _doubleOfferCoins;
    final ads = getIt.isRegistered<AdService>() ? getIt<AdService>() : null;
    if (amount == null || ads == null) return;
    final coins = context.read<CoinsCubit>();
    setState(() => _doubleOfferCoins = null);
    ads.showRewarded(
      onReward: () {
        coins.earnCoins(
          CoinEarningSource.dailyChallenge,
          customAmount: amount,
          itemName: 'Daily Directives 2x',
          metadata: const {'doubled': true},
        );
        RewardToast.show(title: 'CREDITS DOUBLED', amount: '+$amount CR');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dailyChallengesProvider);

    final claimable = state.challenges.where((c) => c.canClaim);
    final claimCoins = claimable.fold<int>(0, (s, c) => s + c.coinReward);
    final claimXp = claimable.fold<int>(0, (s, c) => s + c.xpReward);

    Widget? action;
    if (state.hasUnclaimedRewards) {
      action = CsButton.primary(
        label: 'Claim all · $claimCoins CR + $claimXp XP',
        icon: Symbols.redeem_rounded,
        expand: true,
        onPressed: _claimAllRewards,
      );
    } else if (_doubleOfferCoins != null) {
      action = CsButton.secondary(
        label: 'Watch to 2× · $_doubleOfferCoins CR',
        icon: Symbols.play_circle_rounded,
        expand: true,
        onPressed: _watchToDouble,
      );
    }

    return CsSplit(
      // Inline banner in the summary column (no full-width banners).
      leftFooter: ColumnBannerAd(maxHeight: context.cs.isTablet ? 100 : 60),
      left: ChallengeSummary(
        completed: state.completedCount,
        total: state.totalCount,
        ringLabel: 'Today',
        action: action,
        rules: const [
          'New orders at 00:00',
          'Credits + XP per directive',
          'XP raises your Pilot Rank',
          'Clear all 3 for a bonus',
        ],
      ),
      right: RefreshIndicator(
        onRefresh: _refreshChallenges,
        color: CsColors.ink,
        backgroundColor: CsColors.raised,
        child: LayoutBuilder(
          builder: (context, c) {
            final challenges = state.challenges;
            Widget content;
            if (challenges.isEmpty) {
              content = state.isLoading
                  ? const CsLoadingState(label: 'Loading directives')
                  // One shared, truthful reason (offline vs not posted yet),
                  // identical to the pause / game-over directives panel.
                  : DirectivesEmptyState(onRetry: _refreshChallenges);
            } else {
              content = DirectivesBoard(
                challenges: challenges,
                entrance: _entrance,
                onClaim: _claimReward,
                onFly: () => launchNextSortie(context),
                bonusStrip: state.allCompleted
                    ? DirectivesBonusStrip(
                        bonusCoins: state.bonusCoins,
                        claimed: state.isBonusClaimed,
                      )
                    : null,
                weeklyStrip: ListenableBuilder(
                  listenable: WeeklyQuestService(),
                  builder: (context, _) {
                    final weekly = WeeklyQuestService();
                    return WeeklyOpsStrip(
                      completed: weekly.completedCount,
                      total: weekly.quests.length,
                      claimable: weekly.claimableCount,
                      isGuest: DailyChallengeService.isAccountlessPilot(),
                      onOpen: widget.onOpenWeekly,
                    );
                  },
                ),
              );
            }
            // One viewport-tall page so pull-to-refresh works while the
            // cards fill the column exactly (they never scroll).
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [SizedBox(height: c.maxHeight, child: content)],
            );
          },
        ),
      ),
    );
  }
}

/// Left summary column shared by the Daily and Weekly tabs: 120px prism
/// progress ring + big headline, an optional action, and a mono rules list.
/// Never scrolls (scales down on short screens).
class ChallengeSummary extends StatelessWidget {
  const ChallengeSummary({
    super.key,
    required this.completed,
    required this.total,
    required this.ringLabel,
    required this.rules,
    this.action,
    this.note,
  });

  final int completed;
  final int total;

  /// Caption inside the ring ("TODAY", "THIS WEEK").
  final String ringLabel;
  final List<String> rules;
  final Widget? action;

  /// Optional mono status line under the headline (e.g. "2 READY TO CLAIM").
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final progress = total > 0 ? completed / total : 0.0;
    final remaining = (total - completed).clamp(0, total);
    // With nothing issued the right-hand empty state explains why; the
    // summary stays quiet instead of repeating it.
    final String? headline = total == 0
        ? null
        : (remaining == 0 ? 'All done.' : '$remaining to go.');
    final ring = cs(120);

    return CsFitColumn(
      alignment: Alignment.centerLeft,
      children: [
        Row(
          children: [
            CsRingProgress(
              value: progress,
              size: ring,
              stroke: cs(3).clamp(2.0, 4.0),
              child: Padding(
                padding: EdgeInsets.all(cs(14)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        total == 0 ? '—' : '$completed/$total',
                        maxLines: 1,
                        style: t.number(36, em: -0.04, height: 1),
                      ),
                    ),
                    SizedBox(height: cs(4)),
                    Text(
                      ringLabel.toUpperCase(),
                      maxLines: 1,
                      style: t.mono(9, color: CsColors.ink45, em: 0.2),
                    ),
                  ],
                ),
              ),
            ),
            if (headline != null) ...[
            SizedBox(width: cs(22)),
            Expanded(
              // Break at the first space ("All / done.") and scale down rather
              // than wrapping mid-word in a narrow column.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  headline.replaceFirst(' ', '\n'),
                  maxLines: 2,
                  style: t.display(36, em: -0.04, height: 0.95),
                ),
              ),
            ),
            ],
          ],
        ),
        if (note != null) ...[SizedBox(height: cs(16)), note!],
        if (action != null) ...[
          SizedBox(height: cs(24)),
          SizedBox(width: double.infinity, child: action!),
        ],
        SizedBox(height: cs(22)),
        for (final r in rules)
          Padding(
            padding: EdgeInsets.symmetric(vertical: cs(3)),
            child: Text(
              '—  $r',
              maxLines: 2,
              style: t.mono(11, color: CsColors.ink45, em: 0.06, height: 1.4),
            ),
          ),
      ],
    );
  }
}

/// One challenge / quest row: completion check, title + difficulty chip,
/// description, progress line + value, gold reward + CLAIM. Tapping the
/// row also claims when claimable.
class ChallengeRow extends StatelessWidget {
  const ChallengeRow({
    super.key,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.currentProgress,
    required this.targetValue,
    required this.progress,
    required this.isCompleted,
    required this.claimed,
    required this.canClaim,
    required this.coinReward,
    required this.xpReward,
    required this.onClaim,
    this.xpUnit = 'XP',
  });

  final String title;
  final String description;
  final ChallengeDifficulty difficulty;
  final int currentProgress;
  final int targetValue;
  final double progress;
  final bool isCompleted;
  final bool claimed;
  final bool canClaim;
  final int coinReward;
  final int xpReward;
  final String xpUnit;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;

    final Widget? action = canClaim
        ? CsButton.primary(
            label: 'Claim',
            size: CsButtonSize.small,
            onPressed: onClaim,
          )
        : (claimed
            ? const CsChip('Claimed', kind: CsChipKind.mint, icon: Symbols.check_rounded)
            : null);

    final row = Container(
      padding: EdgeInsets.symmetric(vertical: cs(16)),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CsColors.hairline)),
      ),
      child: Row(
        children: [
          CsPop(
            trigger: isCompleted || claimed,
            peak: 1.2,
            child: Icon(
              Symbols.check_circle_rounded,
              size: cs(26),
              fill: isCompleted ? 1 : 0,
              color: isCompleted ? CsColors.mint : CsColors.ink25,
            ),
          ),
          SizedBox(width: cs(18)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      // Shrink long op titles ("Weekly Skirmisher") instead
                      // of cutting them off next to the chip.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          maxLines: 1,
                          style: t.display(
                            19,
                            weight: FontWeight.w700,
                            em: -0.01,
                            height: 1.2,
                            color: claimed ? CsColors.ink45 : CsColors.ink,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: cs(10)),
                    CsChip(difficulty.displayName),
                  ],
                ),
                SizedBox(height: cs(4)),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.body,
                ),
                SizedBox(height: cs(10)),
                Row(
                  children: [
                    Expanded(child: CsGoalLine(value: progress)),
                    SizedBox(width: cs(12)),
                    Text(
                      '$currentProgress/$targetValue',
                      maxLines: 1,
                      style: t.mono(
                        10.5,
                        weight: FontWeight.w600,
                        em: 0.04,
                        color: isCompleted ? CsColors.mint : CsColors.ink60,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: cs(22)),
          // Pops when the reward is claimed (the RewardToast brings the
          // success haptic, so none is added here).
          CsPop(
            trigger: claimed,
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: cs(84)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '+$coinReward CR · $xpReward$xpUnit',
                  maxLines: 1,
                  style: t.mono(11, weight: FontWeight.w600, em: 0.06, color: CsColors.gold),
                ),
                if (action != null) ...[SizedBox(height: cs(10)), action],
              ],
            ),
          ),
          ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canClaim ? onClaim : null,
      child: row,
    );
  }
}
