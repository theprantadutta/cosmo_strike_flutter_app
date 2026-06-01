import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/models/snake_coins.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/providers/daily_challenges_provider.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';

class DailyChallengesScreen extends ConsumerStatefulWidget {
  const DailyChallengesScreen({super.key});

  @override
  ConsumerState<DailyChallengesScreen> createState() => _DailyChallengesScreenState();
}

class _DailyChallengesScreenState extends ConsumerState<DailyChallengesScreen> {
  final AudioService _audioService = AudioService();

  Future<void> _refreshChallenges() async {
    await ref.read(dailyChallengesProvider.notifier).refresh();
  }

  Future<void> _claimReward(DailyChallenge challenge) async {
    final success = await ref.read(dailyChallengesProvider.notifier).claimReward(challenge.id);
    if (success) {
      getIt<AnalyticsFacade>().trackDailyChallengeRewardClaimed();
      // Actually earn the coins via CoinsCubit
      if (mounted) {
        context.read<CoinsCubit>().earnCoins(
          CoinEarningSource.dailyChallenge,
          customAmount: challenge.coinReward,
          itemName: challenge.title,
          metadata: {
            'challengeId': challenge.id,
            'xpReward': challenge.xpReward,
            'difficulty': challenge.difficulty.name,
          },
        );
      }

      HapticFeedback.mediumImpact();
      _audioService.playSound('coin_collect');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.monetization_on, color: Colors.amber),
                const SizedBox(width: 8),
                Text(
                  'Claimed ${challenge.coinReward} coins and ${challenge.xpReward} XP!',
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _claimAllRewards() async {
    final totalClaimed = await ref.read(dailyChallengesProvider.notifier).claimAllRewards();
    if (totalClaimed > 0) {
      // Actually earn the coins via CoinsCubit
      if (mounted) {
        context.read<CoinsCubit>().earnCoins(
          CoinEarningSource.dailyChallenge,
          customAmount: totalClaimed,
          itemName: 'All Daily Challenges',
          metadata: {'bulkClaim': true},
        );
      }

      HapticFeedback.heavyImpact();
      _audioService.playSound('coin_collect');
      if (mounted) {
        // Offer a rewarded "2×" on the claimed total when an ad is available.
        final ads = getIt.isRegistered<AdService>() ? getIt<AdService>() : null;
        final canDouble = ads != null && ads.adsEnabled && ads.isRewardedReady;
        final coins = context.read<CoinsCubit>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.celebration, color: Colors.amber),
                const SizedBox(width: 8),
                Text('Claimed $totalClaimed coins!'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: Duration(seconds: canDouble ? 6 : 2),
            action: canDouble
                ? SnackBarAction(
                    label: 'WATCH TO 2×',
                    textColor: Colors.amber,
                    onPressed: () => ads.showRewarded(
                      onReward: () => coins.earnCoins(
                        CoinEarningSource.dailyChallenge,
                        customAmount: totalClaimed,
                        itemName: 'Daily Challenges 2x',
                        metadata: const {'doubled': true},
                      ),
                    ),
                  )
                : null,
          ),
        );
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

  Widget _buildContent(BuildContext context, GameTheme theme, DailyChallengesState challengesState) {
    final isRefreshing = challengesState.isLoading;
    final challenges = challengesState.challenges;
    final hasUnclaimedRewards = challengesState.hasUnclaimedRewards;
    final allCompleted = challengesState.allCompleted;

    return Scaffold(
      bottomNavigationBar: const SnakeBannerAd(),
      appBar: AppBar(
        title: const Text(
          'Daily Challenges',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.primaryColor),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (hasUnclaimedRewards)
            TextButton.icon(
              onPressed: _claimAllRewards,
              icon: Icon(Icons.redeem, color: Colors.amber),
              label: Text('Claim All', style: TextStyle(color: Colors.amber)),
            ),
          IconButton(
            icon: isRefreshing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(theme.accentColor),
                      strokeWidth: 2,
                    ),
                  )
                : Icon(Icons.refresh, color: theme.accentColor),
            onPressed: isRefreshing ? null : _refreshChallenges,
          ),
        ],
      ),
      body: AppBackground(
        theme: theme,
        child: RefreshIndicator(
          onRefresh: _refreshChallenges,
          color: theme.accentColor,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Progress summary card
                _buildProgressSummary(theme, challengesState),
                const SizedBox(height: 20),

                // Challenges list
                if (isRefreshing && challenges.isEmpty)
                  _buildLoadingState(theme)
                else if (challenges.isEmpty)
                  _buildEmptyState(theme)
                else
                  ...challenges.asMap().entries.map(
                    (e) => _buildChallengeCard(e.value, e.key, theme),
                  ),

                // All complete bonus
                if (allCompleted)
                  _buildAllCompleteBonusCard(theme, challengesState),

                const SizedBox(height: 20),

                // Info section
                _buildInfoSection(theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSummary(GameTheme theme, DailyChallengesState challengesState) {
    final completed = challengesState.completedCount;
    final total = challengesState.totalCount;
    final progress = total > 0 ? completed / total : 0.0;
    final allCompleted = challengesState.allCompleted;

    return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.primaryColor.withValues(alpha: 0.3),
                theme.accentColor.withValues(alpha: 0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.primaryColor.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    color: theme.accentColor,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Today's Progress",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '$completed of $total challenges completed',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          backgroundColor: theme.primaryColor.withValues(
                            alpha: 0.2,
                          ),
                          valueColor: AlwaysStoppedAnimation(
                            allCompleted
                                ? Colors.green
                                : theme.accentColor,
                          ),
                          strokeWidth: 6,
                        ),
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(
                    allCompleted
                        ? Colors.green
                        : theme.accentColor,
                  ),
                  minHeight: 8,
                ),
              ),
            ],
          ),
        )
        .gameZoomIn();
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

    return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isCompleted
                ? Colors.green.withValues(alpha: 0.15)
                : theme.primaryColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: canClaim
                  ? Colors.amber.withValues(alpha: 0.8)
                  : isCompleted
                  ? Colors.green.withValues(alpha: 0.5)
                  : theme.primaryColor.withValues(alpha: 0.3),
              width: canClaim ? 2 : 1,
            ),
          ),
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
                        // Challenge type icon
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? Colors.green.withValues(alpha: 0.2)
                                : theme.primaryColor.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isCompleted
                                  ? Colors.green
                                  : theme.primaryColor,
                              width: 2,
                            ),
                          ),
                          child: isCompleted
                              ? Icon(Icons.check, color: Colors.green, size: 28)
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
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        decoration: challenge.claimedReward
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: difficultyColor.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: difficultyColor,
                                      ),
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
                              const SizedBox(height: 4),
                              Text(
                                challenge.description,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Progress bar
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: challenge.progressPercentage,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.1,
                              ),
                              valueColor: AlwaysStoppedAnimation(
                                isCompleted ? Colors.green : theme.accentColor,
                              ),
                              minHeight: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${challenge.currentProgress}/${challenge.targetValue}',
                          style: TextStyle(
                            color: isCompleted
                                ? Colors.green
                                : Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
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
                          ElevatedButton(
                            onPressed: () => _claimReward(challenge),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.redeem, size: 18),
                                const SizedBox(width: 4),
                                Text('Claim'),
                              ],
                            ),
                          ),
                        if (challenge.claimedReward)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green),
                            ),
                            child: Row(
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
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
        .gameListItem(index);
  }

  Widget _buildAllCompleteBonusCard(GameTheme theme, DailyChallengesState challengesState) {
    return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.amber.withValues(alpha: 0.3),
                Colors.orange.withValues(alpha: 0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.celebration, color: Colors.amber, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All Challenges Complete!',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      challengesState.isBonusClaimed
                          ? 'Bonus reward claimed'
                          : 'Bonus reward pending — claim any challenge',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      challengesState.isBonusClaimed
                          ? Icons.check_circle
                          : Icons.monetization_on,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '+${challengesState.bonusCoins}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'About Daily Challenges',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoItem(
            Icons.schedule,
            'New challenges every day at midnight',
          ),
          _buildInfoItem(
            Icons.monetization_on,
            'Complete challenges to earn coins',
          ),
          _buildInfoItem(Icons.star, 'Gain XP to level up your profile'),
          _buildInfoItem(
            Icons.celebration,
            'Complete all 3 for a bonus reward!',
          ),
        ],
      ),
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
        iconData = Icons.restaurant;
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
    return Icon(iconData, color: theme.primaryColor, size: 28);
  }
}
