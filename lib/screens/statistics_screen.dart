import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final StatisticsService _statisticsService = StatisticsService();
  late final AppDataCache _appCache;

  @override
  void initState() {
    super.initState();
    _appCache = getIt<AppDataCache>();
    // Trigger background refresh for fresh data (non-blocking)
    _appCache.refreshInBackground();
  }

  // Convenience getters using cached data - instant display!
  Map<String, dynamic> get _displayStats => _appCache.statistics ?? {};
  Map<String, dynamic> get _performanceTrends => _appCache.performanceTrends ?? {};
  Map<String, dynamic> get _playPatterns => _appCache.playPatterns ?? {};
  // Data is already loaded - no loading state needed
  bool get _isLoading => !_appCache.isFullyLoaded;

  @override
  Widget build(BuildContext context) {
    // Subscribe to AppDataCache so a post-game refreshStatistics() call
    // rebuilds this screen with the updated high score / totals instead of
    // leaving the user staring at the snapshot captured at first paint.
    return ListenableBuilder(
      listenable: _appCache,
      builder: (context, _) => BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        final theme = state.currentTheme;

        return CommandScaffold(
          theme: theme,
          title: 'Statistics',
          bottomBar: const ShipBannerAd(),
          bodyPadding: EdgeInsets.zero,
          actions: [
            IconButton(
              onPressed: _refreshStatistics,
              icon: Icon(
                Icons.refresh,
                color: theme.accentColor.withValues(alpha: 0.8),
                size: 22,
              ),
            ),
          ],
          body: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          theme.accentColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading Statistics...',
                        style: TextStyle(
                          color: theme.textMuted,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              // Landscape command deck: LEFT = hero telemetry + actions,
              // RIGHT = the scrollable stat sections. Both float borderless
              // on the starfield per the clean design.
              : Padding(
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
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              _buildPerformanceOverview(theme),
                              const SizedBox(height: 20),
                              _buildGameActivity(theme),
                              const SizedBox(height: 20),
                              _buildConsumptionStats(theme),
                              const SizedBox(height: 20),
                              _buildPerformanceTrends(theme),
                              const SizedBox(height: 20),
                              _buildPlayPatterns(theme),
                              const SizedBox(height: 20),
                              _buildAchievementProgress(theme),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    ),
    );
  }

  Widget _buildPerformanceOverview(GameTheme theme) {
    return _buildStatSection(
      title: 'Performance Overview',
      icon: Icons.trending_up,
      theme: theme,
      // One wide row of four — the landscape viewport has the width for it.
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'High Score',
                '${_displayStats['highScore'] ?? 0}',
                Icons.emoji_events,
                Colors.amber,
                theme,
              ),
            ),
            Expanded(
              child: _buildStatCard(
                'Total Games',
                '${_displayStats['totalGames'] ?? 0}',
                Icons.games,
                theme.accentColor,
                theme,
              ),
            ),
            Expanded(
              child: _buildStatCard(
                'Average Score',
                '${_displayStats['averageScore'] ?? 0}',
                Icons.trending_up,
                Colors.green,
                theme,
              ),
            ),
            Expanded(
              child: _buildStatCard(
                'Win Streak',
                '${_displayStats['winStreak'] ?? 0}',
                Icons.local_fire_department,
                Colors.orange,
                theme,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameActivity(GameTheme theme) {
    return _buildStatSection(
      title: 'Game Activity',
      icon: Icons.schedule,
      theme: theme,
      // One wide row of four.
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Play Time',
                '${_displayStats['totalPlayTime'] ?? '0s'}',
                Icons.access_time,
                Colors.blue,
                theme,
              ),
            ),
            Expanded(
              child: _buildStatCard(
                'Longest Game',
                '${_displayStats['longestSurvival'] ?? '0s'}',
                Icons.timer,
                Colors.purple,
                theme,
              ),
            ),
            Expanded(
              child: _buildStatCard(
                'Highest Level',
                '${_displayStats['highestLevel'] ?? 1}',
                Icons.military_tech,
                Colors.indigo,
                theme,
              ),
            ),
            Expanded(
              child: _buildStatCard(
                'Perfect Games',
                '${_displayStats['perfectGames'] ?? 0}',
                Icons.star,
                Colors.pink,
                theme,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConsumptionStats(GameTheme theme) {
    final foodBreakdown =
        _displayStats['foodBreakdown'] as Map<String, int>? ?? {};
    final powerUpBreakdown =
        _displayStats['powerUpBreakdown'] as Map<String, int>? ?? {};

    return _buildStatSection(
      title: 'Kills & Power-Ups',
      icon: Icons.restaurant,
      theme: theme,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Enemies Destroyed',
                  '${_displayStats['totalFood'] ?? 0}',
                  Icons.apple,
                  Colors.red,
                  theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Power-ups Used',
                  '${_displayStats['totalPowerUps'] ?? 0}',
                  Icons.flash_on,
                  Colors.yellow,
                  theme,
                ),
              ),
            ],
          ),

          if (foodBreakdown.isNotEmpty || powerUpBreakdown.isNotEmpty) ...[
            const SizedBox(height: 16),

            Row(
              children: [
                if (foodBreakdown.isNotEmpty)
                  Expanded(
                    child: _buildBreakdownCard(
                      'Favorite Target',
                      '${_displayStats['favoriteFood'] ?? 'None'}',
                      foodBreakdown,
                      theme,
                    ),
                  ),

                if (foodBreakdown.isNotEmpty && powerUpBreakdown.isNotEmpty)
                  const SizedBox(width: 12),

                if (powerUpBreakdown.isNotEmpty)
                  Expanded(
                    child: _buildBreakdownCard(
                      'Favorite Power-up',
                      '${_displayStats['favoritePowerUp'] ?? 'None'}',
                      powerUpBreakdown,
                      theme,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPerformanceTrends(GameTheme theme) {
    final recentScores =
        (_performanceTrends['recentScores'] as List<int>?) ?? [];
    final trend = _performanceTrends['trend'] as String? ?? 'stable';

    return _buildStatSection(
      title: 'Performance Trends',
      icon: Icons.show_chart,
      theme: theme,
      child: Column(
        children: [
          // One wide row of four trend cells.
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildTrendCard(
                    'Overall Trend',
                    trend,
                    _getTrendIcon(trend),
                    _getTrendColor(trend),
                    theme,
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    'Recent Average',
                    '${_performanceTrends['averageRecentScore'] ?? 0}',
                    Icons.analytics,
                    Colors.cyan,
                    theme,
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    'Best Recent',
                    '${_performanceTrends['bestRecentScore'] ?? 0}',
                    Icons.star_outline,
                    Colors.amber,
                    theme,
                  ),
                ),
                Expanded(
                  child: _buildStatCard(
                    'Consistency',
                    _calculateConsistencyRating(recentScores),
                    Icons.equalizer,
                    Colors.purple,
                    theme,
                  ),
                ),
              ],
            ),
          ),

          if (recentScores.isNotEmpty) ...[
            const SizedBox(height: 16),

            // Enhanced Chart Container
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress (Last ${recentScores.length} Games)',
                        style: TextStyle(
                          color: theme.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getTrendColor(trend).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          trend.toUpperCase(),
                          style: TextStyle(
                            color: _getTrendColor(trend),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Enhanced Chart with Trend Line
                  SizedBox(
                    height: 80,
                    child: _buildEnhancedTrendChart(recentScores, theme, trend),
                  ),

                  const SizedBox(height: 8),

                  // Chart Legend
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegendItem('Scores', theme.accentColor, theme),
                      const SizedBox(width: 16),
                      _buildLegendItem(
                        'Trend Line',
                        _getTrendColor(trend),
                        theme,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Performance Insights
            _buildPerformanceInsights(recentScores, trend, theme),
          ],
        ],
      ),
    );
  }

  Widget _buildPlayPatterns(GameTheme theme) {
    final dailyPlayTime =
        (_playPatterns['dailyPlayTime'] as Map<String, int>?) ?? {};

    return _buildStatSection(
      title: 'Play Patterns (Last 7 Days)',
      icon: Icons.calendar_today,
      theme: theme,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Weekly Time',
                  _formatPlayTime(_playPatterns['totalWeeklyTime'] ?? 0),
                  Icons.schedule,
                  Colors.green,
                  theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Most Active Day',
                  '${_playPatterns['mostActiveDay'] ?? 'None'}',
                  Icons.star,
                  Colors.orange,
                  theme,
                ),
              ),
            ],
          ),

          if (dailyPlayTime.isNotEmpty) ...[
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Activity',
                    style: TextStyle(
                      color: theme.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    height: 60,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical, // or horizontal if needed
                      child: _buildDailyActivityChart(dailyPlayTime, theme),
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

  Widget _buildAchievementProgress(GameTheme theme) {
    return _buildStatSection(
      title: 'Achievement Progress',
      icon: Icons.emoji_events,
      theme: theme,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Center(
                    child: CircularProgressIndicator(
                      // The display value comes through as 'X%' (a string).
                      // Strip the percent sign, parse, default to 0, THEN
                      // divide by 100 so the indicator (which expects 0.0–1.0)
                      // shows the right fill. The previous expression
                      // missed parentheses and ended up passing the raw
                      // 0–100 number, which the indicator clamps to 1.0 —
                      // a full ring at any non-zero progress.
                      value:
                          ((double.tryParse(
                                    _displayStats['achievementProgress']
                                            ?.toString()
                                            .replaceAll('%', '') ??
                                        '0',
                                  ) ??
                                  0) /
                              100)
                              .clamp(0.0, 1.0),
                      strokeWidth: 4,
                      backgroundColor: Colors.amber.withValues(alpha: 0.3),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.amber,
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      Icons.military_tech,
                      color: Colors.amber,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Achievement Progress',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: theme.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    '${_displayStats['achievementProgress'] ?? '0%'} Complete',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textMuted,
                    ),
                  ),

                  const SizedBox(height: 8),

                  GestureDetector(
                    onTap: () => context.push(AppRoutes.achievements),
                    child: Text(
                      'View All Achievements →',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// LEFT panel: hero high-score readout + compact telemetry rows + the
  /// stacked action buttons. Rendered at natural size inside a
  /// FittedBox(scaleDown) so it never scrolls in the short viewport.
  Widget _buildLeftPanel(GameTheme theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            'HIGH SCORE',
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            '${_displayStats['highScore'] ?? 0}',
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildTelemetryRow(
          theme,
          Icons.games,
          'Games Played',
          '${_displayStats['totalGames'] ?? 0}',
        ),
        const SizedBox(height: 6),
        _buildTelemetryRow(
          theme,
          Icons.access_time,
          'Play Time',
          '${_displayStats['totalPlayTime'] ?? '0s'}',
        ),
        const SizedBox(height: 16),
        NeonButton(
          onPressed: () => context.push(AppRoutes.achievements),
          label: 'View Achievements',
          icon: Icons.emoji_events,
          theme: theme,
          expand: true,
        ),
        const SizedBox(height: 8),
        NeonButton(
          onPressed: () => context.push(AppRoutes.replays),
          label: 'Replays',
          icon: Icons.video_library,
          theme: theme,
          variant: NeonButtonVariant.outline,
          expand: true,
        ),
        const SizedBox(height: 8),
        NeonButton(
          onPressed: _showResetDialog,
          label: 'Reset Statistics',
          icon: Icons.refresh,
          theme: theme,
          variant: NeonButtonVariant.ghost,
          expand: true,
        ),
      ],
    ).gameEntrance();
  }

  Widget _buildTelemetryRow(
    GameTheme theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: theme.textMuted),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildStatSection({
    required String title,
    required IconData icon,
    required GameTheme theme,
    required Widget child,
  }) {
    // Borderless section: uppercase HUD label floating straight on the
    // starfield — no glass panel, no outlines.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: theme.accentColor, size: 15),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                  color: theme.accentColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        child,
      ],
    ).gameZoomIn();
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
    GameTheme theme,
  ) {
    // Fully transparent per the clean design — the coloured icon + value
    // carry the cell, no fill.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 26),

          const SizedBox(height: 8),

          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 4),

          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.textMuted,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendCard(
    String label,
    String trend,
    IconData icon,
    Color color,
    GameTheme theme,
  ) {
    // Fully transparent per the clean design.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),

          const SizedBox(height: 8),

          Text(
            trend.toUpperCase(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard(
    String title,
    String favorite,
    Map<String, int> breakdown,
    GameTheme theme,
  ) {
    // Fully transparent per the clean design.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.textMuted,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            favorite,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: theme.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          ...breakdown.entries
              .take(3)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textMuted,
                        ),
                      ),
                      Text(
                        '${entry.value}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.textPrimary,
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

  Widget _buildDailyActivityChart(Map<String, int> dailyData, GameTheme theme) {
    final maxTime = dailyData.values.isNotEmpty
        ? dailyData.values.reduce((a, b) => a > b ? a : b)
        : 0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: dailyData.entries.map((entry) {
        final day = entry.key;
        final time = entry.value;
        final height = maxTime > 0 ? (time / maxTime) * 40 : 8.0;

        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 20,
              height: height + 8,
              decoration: BoxDecoration(
                color: time > 0
                    ? theme.accentColor.withValues(alpha: 0.7)
                    : theme.accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              day,
              style: TextStyle(
                fontSize: 10,
                color: theme.textMuted,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  IconData _getTrendIcon(String trend) {
    switch (trend) {
      case 'improving':
        return Icons.trending_up;
      case 'declining':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  Color _getTrendColor(String trend) {
    switch (trend) {
      case 'improving':
        return Colors.green;
      case 'declining':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatPlayTime(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      return '${(seconds / 60).round()}m';
    } else {
      return '${(seconds / 3600).round()}h';
    }
  }

  Future<void> _refreshStatistics() async {
    await _appCache.refreshStatistics();
    if (mounted) setState(() {});
  }

  void _showResetDialog() {
    final theme = context.read<ThemeCubit>().state.currentTheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Reset Statistics?',
          style: TextStyle(color: theme.accentColor),
        ),
        content: Text(
          'This will permanently delete all your game statistics. This action cannot be undone.',
          style: TextStyle(color: theme.accentColor.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: theme.accentColor.withValues(alpha: 0.7)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _statisticsService.resetStatistics();
              await _refreshStatistics();
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _calculateConsistencyRating(List<int> scores) {
    if (scores.length < 3) return 'N/A';

    final average = scores.reduce((a, b) => a + b) / scores.length;
    final variance =
        scores
            .map((score) => (score - average) * (score - average))
            .reduce((a, b) => a + b) /
        scores.length;
    final standardDeviation = sqrt(variance);
    final coefficient = average > 0 ? standardDeviation / average : 0;

    if (coefficient < 0.3) return 'Excellent';
    if (coefficient < 0.5) return 'Good';
    if (coefficient < 0.7) return 'Fair';
    return 'Poor';
  }

  Widget _buildEnhancedTrendChart(
    List<int> scores,
    GameTheme theme,
    String trend,
  ) {
    if (scores.isEmpty) return const Center(child: Text('No data'));

    final maxScore = scores.reduce((a, b) => a > b ? a : b);
    final minScore = scores.reduce((a, b) => a < b ? a : b);

    return CustomPaint(
      painter: TrendChartPainter(
        scores: scores,
        maxScore: maxScore,
        minScore: minScore,
        barColor: theme.accentColor,
        trendColor: _getTrendColor(trend),
        trend: trend,
      ),
      child: Container(),
    );
  }

  Widget _buildLegendItem(String label, Color color, GameTheme theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: theme.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildPerformanceInsights(
    List<int> scores,
    String trend,
    GameTheme theme,
  ) {
    final insights = _generateInsights(scores, trend);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: theme.primaryColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Performance Insights',
                style: TextStyle(
                  color: theme.primaryColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...insights.map(
            (insight) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 6, right: 8),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      insight,
                      style: TextStyle(
                        color: theme.textMuted,
                        fontSize: 12,
                      ),
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

  List<String> _generateInsights(List<int> scores, String trend) {
    final insights = <String>[];

    if (scores.isEmpty) return ['Play more games to get performance insights!'];

    final average = scores.reduce((a, b) => a + b) / scores.length;
    final recent = scores.length >= 3
        ? scores.sublist(scores.length - 3)
        : scores;
    final recentAvg = recent.reduce((a, b) => a + b) / recent.length;

    if (trend == 'improving') {
      insights.add('Great job! Your performance is on an upward trend.');
      if (recentAvg > average * 1.2) {
        insights.add('Your recent games are significantly above your average.');
      }
    } else if (trend == 'declining') {
      insights.add(
        'Your performance has declined recently. Consider practicing more.',
      );
      insights.add(
        'Try focusing on avoiding collisions and planning your moves ahead.',
      );
    } else {
      insights.add(
        'Your performance is stable. Challenge yourself to improve!',
      );
    }

    final maxScore = scores.reduce((a, b) => a > b ? a : b);
    final minScore = scores.reduce((a, b) => a < b ? a : b);
    if (maxScore > minScore * 3) {
      insights.add('You have potential for high scores - work on consistency.');
    }

    if (scores.length >= 5) {
      final lastFive = scores.sublist(scores.length - 5);
      if (lastFive.every((score) => score > average * 0.8)) {
        insights.add(
          'You\'re maintaining solid performance across recent games.',
        );
      }
    }

    return insights;
  }
}

class TrendChartPainter extends CustomPainter {
  final List<int> scores;
  final int maxScore;
  final int minScore;
  final Color barColor;
  final Color trendColor;
  final String trend;

  TrendChartPainter({
    required this.scores,
    required this.maxScore,
    required this.minScore,
    required this.barColor,
    required this.trendColor,
    required this.trend,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;

    final barPaint = Paint()
      ..color = barColor.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final trendPaint = Paint()
      ..color = trendColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final barWidth = size.width / scores.length;
    final range = maxScore > minScore ? maxScore - minScore : 1;

    // Draw bars
    for (int i = 0; i < scores.length; i++) {
      final score = scores[i];
      final normalizedHeight =
          ((score - minScore) / range) * (size.height - 10) + 5;
      final barHeight = normalizedHeight;

      final rect = Rect.fromLTWH(
        i * barWidth + barWidth * 0.1,
        size.height - barHeight,
        barWidth * 0.8,
        barHeight,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        barPaint,
      );
    }

    // Draw trend line
    if (scores.length > 1) {
      final path = Path();
      for (int i = 0; i < scores.length; i++) {
        final score = scores[i];
        final x = i * barWidth + barWidth * 0.5;
        final normalizedHeight =
            ((score - minScore) / range) * (size.height - 10) + 5;
        final y = size.height - normalizedHeight;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, trendPaint);

      // Draw trend line points
      final pointPaint = Paint()
        ..color = trendColor
        ..style = PaintingStyle.fill;

      for (int i = 0; i < scores.length; i++) {
        final score = scores[i];
        final x = i * barWidth + barWidth * 0.5;
        final normalizedHeight =
            ((score - minScore) / range) * (size.height - 10) + 5;
        final y = size.height - normalizedHeight;

        canvas.drawCircle(Offset(x, y), 3, pointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
