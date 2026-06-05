import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/models/achievement.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/achievement_service.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AchievementService _achievementService = AchievementService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _achievementService.addListener(_onAchievementsChanged);
  }

  @override
  void dispose() {
    _achievementService.removeListener(_onAchievementsChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onAchievementsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;
        return _buildContent(context, theme);
      },
    );
  }

  Widget _buildContent(BuildContext context, GameTheme theme) {
    return CommandScaffold(
      theme: theme,
      title: 'Achievements',
      bottomBar: const ShipBannerAd(),
      bodyPadding: EdgeInsets.zero,
      // Landscape command deck: LEFT = completion ring + section rail,
      // RIGHT = the achievement lists. Both float borderless on the
      // starfield per the clean design.
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 230,
                    child: _buildLeftPanel(theme),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 7,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAchievementsList(
                    _achievementService.achievements,
                    theme,
                  ),
                  _buildAchievementsList(
                    _achievementService.getUnlockedAchievements(),
                    theme,
                  ),
                  _buildAchievementsList(
                    _achievementService.getLockedAchievements(),
                    theme,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// LEFT panel: gold completion ring + claimed/pending readout + the
  /// All/Unlocked/Locked rail (no-background, glowing-dot selection).
  /// Stat counts use the same logic as the dashboard's AchievementsGrid.
  Widget _buildLeftPanel(GameTheme theme) {
    final all = _achievementService.achievements;
    final total = all.length;
    final unlocked = all.where((a) => a.isUnlocked).length;
    final claimed = all.where((a) => a.rewardClaimed).length;
    final pending = all.where((a) => !a.isUnlocked).length;
    final completionPercentage = _achievementService.completionPercentage;
    final completionPct = (completionPercentage * 100).round();

    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: CircularProgressIndicator(
                      value: completionPercentage,
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation(Colors.amber),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$completionPct%',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                      Text(
                        '$unlocked of $total',
                        style:
                            TextStyle(color: theme.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'COMPLETION',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '$claimed claimed · $pending pending',
              style: TextStyle(color: theme.textMuted, fontSize: 11),
            ),
          ),
          const SizedBox(height: 14),
          _buildNavItem(theme, 0, Icons.apps, 'All', total),
          _buildNavItem(theme, 1, Icons.emoji_events, 'Unlocked', unlocked),
          _buildNavItem(theme, 2, Icons.lock_outline, 'Locked', pending),
        ],
      ),
    ).gameEntrance();
  }

  Widget _buildNavItem(
    GameTheme theme,
    int i,
    IconData icon,
    String label,
    int count,
  ) {
    final selected = _tabController.index == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tabController.animateTo(i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? theme.neonPrimary : theme.textMuted,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? theme.textPrimary : theme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: theme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.neonPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.neonPrimary.withValues(alpha: 0.7),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementsList(
    List<Achievement> achievements,
    GameTheme theme,
  ) {
    if (achievements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.workspace_premium_outlined,
              size: 64,
              color: theme.primaryColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No achievements here',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: achievements.length,
      itemBuilder: (context, index) {
        final achievement = achievements[index];

        return _buildAchievementCard(achievement, theme)
            .gameListItem(index);
      },
    );
  }

  Widget _buildAchievementCard(Achievement achievement, GameTheme theme) {
    final isUnlocked = achievement.isUnlocked;
    final progress = achievement.progressPercentage;

    // Fully transparent row per the clean design — the rarity-coloured icon
    // disc, badges, and reward pills carry the card.
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Achievement Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUnlocked
                        ? achievement.rarityColor
                        : Colors.grey.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: isUnlocked
                        ? [
                            BoxShadow(
                              color: achievement.rarityColor
                                  .withValues(alpha: 0.35),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    achievement.icon,
                    color: isUnlocked ? Colors.white : theme.textMuted,
                    size: 24,
                  ),
                ),

                const SizedBox(width: 16),

                // Achievement Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              achievement.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isUnlocked
                                    ? theme.textPrimary
                                    : theme.textMuted,
                              ),
                            ),
                          ),

                          // Rarity Badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: achievement.rarityColor.withValues(
                                alpha: 0.2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              achievement.rarityName.toUpperCase(),
                              style: TextStyle(
                                color: achievement.rarityColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      Text(
                        achievement.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.textMuted,
                        ),
                      ),

                      if (!isUnlocked && progress > 0) ...[
                        const SizedBox(height: 8),

                        // Progress Bar
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: theme.accentColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 8),

                            Text(
                              '${achievement.currentProgress}/${achievement.targetValue}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Rewards and Status
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isUnlocked) ...[
                      Icon(
                        achievement.rewardClaimed
                            ? Icons.check_circle
                            : Icons.hourglass_top,
                        color: achievement.rewardClaimed
                            ? Colors.green
                            : Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                    ],

                    // XP badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.lightBlueAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+${achievement.xpReward} XP',
                        style: const TextStyle(
                          color: Colors.lightBlueAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Coin badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+${achievement.coinReward} coins',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Unlock Date
            if (isUnlocked && achievement.unlockedAt != null) ...[
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.green.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 8),

                    Text(
                      'Unlocked ${_formatDate(achievement.unlockedAt!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }
}
