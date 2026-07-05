import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/providers/daily_challenges_provider.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/widgets/reward_toast.dart';

/// The Daily tab of the challenges hub (ChallengesHubScreen owns the
/// CommandScaffold + tab chrome; this renders only the two-region body).
class DailyChallengesBody extends ConsumerStatefulWidget {
  const DailyChallengesBody({super.key});

  @override
  ConsumerState<DailyChallengesBody> createState() =>
      _DailyChallengesBodyState();
}

class _DailyChallengesBodyState extends ConsumerState<DailyChallengesBody> {
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
        amount: '+${challenge.coinReward} COINS · +${challenge.xpReward} XP',
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
        amount: '+$totalClaimed COINS',
      );
      if (mounted) {
        // The toast is non-interactive, so the rewarded "2×" entry point
        // stays on a slim SnackBar action when an ad is available.
        final ads = getIt.isRegistered<AdService>() ? getIt<AdService>() : null;
        final canDouble = ads != null && ads.adsEnabled && ads.isRewardedReady;
        if (canDouble) {
          final coins = context.read<CoinsCubit>();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Double your $totalClaimed coins?'),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'WATCH TO 2×',
                textColor: Colors.amber,
                onPressed: () => ads.showRewarded(
                  onReward: () {
                    coins.earnCoins(
                      CoinEarningSource.dailyChallenge,
                      customAmount: totalClaimed,
                      itemName: 'Daily Challenges 2x',
                      metadata: const {'doubled': true},
                    );
                    RewardToast.show(
                      title: 'COINS DOUBLED',
                      amount: '+$totalClaimed COINS',
                    );
                  },
                ),
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the daily challenges state from Riverpod
    final challengesState = ref.watch(dailyChallengesProvider);

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;
        return _buildContent(context, theme, challengesState);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    GameTheme theme,
    DailyChallengesState challengesState,
  ) {
    final isRefreshing = challengesState.isLoading;
    final challenges = challengesState.challenges;
    final allCompleted = challengesState.allCompleted;

    // Landscape command deck: LEFT = today's telemetry (completion ring +
    // claim-all + hints), RIGHT = the scrollable challenge list. Both float
    // borderless on the starfield per the clean design.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            // Never scrolls: the telemetry column renders at its natural
            // size and FittedBox scales it down to exactly fit the
            // available height, so it always uses the column responsively.
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 270,
                  child: _buildProgressSummary(theme, challengesState),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 6,
            child: RefreshIndicator(
              onRefresh: _refreshChallenges,
              color: theme.accentColor,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (isRefreshing && challenges.isEmpty)
                    _buildLoadingState(theme)
                  else if (challenges.isEmpty)
                    _buildEmptyState(theme)
                  else ...[
                    ...challenges.asMap().entries.map(
                      (e) => _buildChallengeCard(e.value, e.key, theme),
                    ),
                    if (allCompleted)
                      _buildAllCompleteBonusCard(theme, challengesState),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSummary(
    GameTheme theme,
    DailyChallengesState challengesState,
  ) {
    final completed = challengesState.completedCount;
    final total = challengesState.totalCount;
    final progress = total > 0 ? completed / total : 0.0;
    final allCompleted = challengesState.allCompleted;
    final hasUnclaimedRewards = challengesState.hasUnclaimedRewards;
    final ringColor = allCompleted ? Colors.green : theme.neonPrimary;

    // Borderless telemetry column — the big completion ring floats straight
    // on the starfield, with claim-all and the hints beneath it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(ringColor),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    '$completed of $total',
                    style: TextStyle(color: theme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "TODAY'S PROGRESS",
          style: TextStyle(
            color: theme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        if (hasUnclaimedRewards) ...[
          NeonButton(
            onPressed: _claimAllRewards,
            label: 'Claim All',
            icon: Icons.redeem,
            theme: theme,
            height: 44,
          ),
          const SizedBox(height: 16),
        ],
        _buildInfoSection(theme),
      ],
    ).gameZoomIn();
  }

  Widget _buildChallengeCard(
    DailyChallenge challenge,
    int index,
    GameTheme theme,
  ) {
    final isCompleted = challenge.isCompleted;
    final canClaim = challenge.canClaim;

    Color difficultyColor;
    switch (challenge.difficulty) {
      case ChallengeDifficulty.easy:
        difficultyColor = Colors.green;
        break;
      case ChallengeDifficulty.medium:
        difficultyColor = Colors.orange;
        break;
      case ChallengeDifficulty.hard:
        difficultyColor = Colors.red;
        break;
    }

    final accent = isCompleted ? Colors.green : theme.neonPrimary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      // Fully transparent per the clean design — the rows float straight
      // on the starfield; the icon disc, bars, and Claim button carry the
      // structure.
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: canClaim ? () => _claimReward(challenge) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Challenge type disc — borderless neon tint + glow.
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.25),
                            blurRadius: 10,
                            spreadRadius: -3,
                          ),
                        ],
                      ),
                      child: isCompleted
                          ? Icon(Icons.check, color: Colors.green, size: 24)
                          : _getChallengeTypeIcon(challenge.type, theme),
                    ),
                    const SizedBox(width: 12),

                    // Title and description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  challenge.title,
                                  style: TextStyle(
                                    color: theme.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    decoration: challenge.claimedReward
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              // Difficulty pill — borderless tint.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: difficultyColor.withValues(
                                    alpha: 0.16,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  challenge.difficulty.displayName,
                                  style: TextStyle(
                                    color: difficultyColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            challenge.description,
                            style: TextStyle(
                              color: theme.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Slim neon progress bar.
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: challenge.progressPercentage,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(accent),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${challenge.currentProgress}/${challenge.targetValue}',
                      style: TextStyle(
                        color: isCompleted ? Colors.green : theme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Rewards row
                Row(
                  children: [
                    // Coin reward
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.monetization_on,
                            color: Colors.amber,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${challenge.coinReward}',
                            style: TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // XP reward
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, color: Colors.purple, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '${challenge.xpReward} XP',
                            style: TextStyle(
                              color: Colors.purple.shade200,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),

                    // Claim button
                    if (canClaim)
                      NeonButton(
                        onPressed: () => _claimReward(challenge),
                        label: 'Claim',
                        icon: Icons.redeem,
                        theme: theme,
                        height: 40,
                      ),
                    // Claimed — plain green check + label, no boxed badge.
                    if (challenge.claimedReward)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Claimed',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).gameListItem(index);
  }

  Widget _buildAllCompleteBonusCard(
    GameTheme theme,
    DailyChallengesState challengesState,
  ) {
    // Borderless amber glow — the celebratory highlight at the end of the list.
    return Container(
          margin: const EdgeInsets.only(top: 4, bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.celebration, color: Colors.amber, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All Challenges Complete!',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      challengesState.isBonusClaimed
                          ? 'Bonus reward claimed'
                          : 'Bonus reward pending — claim any challenge',
                      style: TextStyle(color: theme.textMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    challengesState.isBonusClaimed
                        ? Icons.check_circle
                        : Icons.monetization_on,
                    color: Colors.amber,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '+${challengesState.bonusCoins}',
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        )
        .gamePop(delay: 300.ms)
        .animate()
        .shimmer(duration: 2000.ms, delay: 500.ms);
  }

  Widget _buildLoadingState(GameTheme theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(theme.accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading challenges...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(GameTheme theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.calendar_today,
              color: theme.primaryColor.withValues(alpha: 0.5),
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'No challenges available',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check back later for new daily challenges!',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(GameTheme theme) {
    // Compact borderless hints under the telemetry ring — no panel chrome.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoItem(Icons.schedule, 'New challenges every day at midnight'),
        _buildInfoItem(
          Icons.monetization_on,
          'Complete challenges to earn coins',
        ),
        _buildInfoItem(Icons.star, 'Gain XP to level up your profile'),
        _buildInfoItem(Icons.celebration, 'Complete all 3 for a bonus reward!'),
      ],
    ).gameEntrance(delay: 300.ms);
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.5), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _getChallengeTypeIcon(ChallengeType type, GameTheme theme) {
    IconData iconData;
    switch (type) {
      case ChallengeType.score:
        iconData = Icons.stars;
        break;
      case ChallengeType.foodEaten:
        // Energy pickups — flare reads space-y for the shooter.
        iconData = Icons.flare;
        break;
      case ChallengeType.gameMode:
        iconData = Icons.games;
        break;
      case ChallengeType.survival:
        iconData = Icons.timer;
        break;
      case ChallengeType.gamesPlayed:
        iconData = Icons.play_circle_outline;
        break;
    }
    return Icon(iconData, color: theme.neonPrimary, size: 22);
  }
}
