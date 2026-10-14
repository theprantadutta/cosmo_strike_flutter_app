import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
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
  bool get _isLoading => !_appCache.isFullyLoaded;

  @override
  Widget build(BuildContext context) {
    // Subscribe to AppDataCache so a post-game refreshStatistics() call
    // rebuilds this screen with the updated high score / totals instead of
    // leaving the user staring at the snapshot captured at first paint.
    return ListenableBuilder(
      listenable: _appCache,
      builder: (context, _) => CsScaffold(
        title: 'Statistics',
        washes: const [CsWash.cyanLeft],
        trailing: [
          CsIconButton(
            icon: Symbols.refresh_rounded,
            tooltip: 'Refresh',
            size: 36,
            onPressed: _refreshStatistics,
          ),
        ],
        body: _isLoading
            ? const CsLoadingState(label: 'Loading statistics')
            : CsSplit(
                // Inline banner in the summary column (no full-width banners).
                leftFooter: ColumnBannerAd(maxHeight: context.cs.isTablet ? 100 : 60),
                left: _buildSummary(context),
                right: _buildSections(context),
              ),
      ),
    );
  }

  // ── LEFT ───────────────────────────────────────────────────────────────

  /// Hero high score + compact telemetry + the stacked actions. Rendered at
  /// natural size and scaled down so it never scrolls.
  Widget _buildSummary(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return CsFitColumn(
      alignment: Alignment.centerLeft,
      children: [
        const CsLabel('High score'),
        SizedBox(height: cs(8)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('${_displayStats['highScore'] ?? 0}', maxLines: 1, style: t.scoreGiant),
        ),
        SizedBox(height: cs(16)),
        const CsHairline(),
        _telemetryRow(context, 'Games played', '${_displayStats['totalGames'] ?? 0}'),
        const CsHairline(),
        _telemetryRow(context, 'Play time', '${_displayStats['totalPlayTime'] ?? '0s'}'),
        const CsHairline(),
        SizedBox(height: cs(22)),
        CsButton.primary(
          label: 'View achievements',
          icon: Symbols.emoji_events_rounded,
          expand: true,
          onPressed: () => context.push(AppRoutes.achievements),
        ),
        SizedBox(height: cs(10)),
        CsButton.secondary(
          label: 'Replays',
          icon: Symbols.movie_rounded,
          expand: true,
          onPressed: () => context.push(AppRoutes.replays),
        ),
        SizedBox(height: cs(6)),
        CsButton.text(
          label: 'Reset statistics',
          icon: Symbols.restart_alt_rounded,
          onPressed: _showResetDialog,
        ),
      ],
    );
  }

  Widget _telemetryRow(BuildContext context, String label, String value) {
    final cs = context.cs;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: cs(10)),
      child: Row(children: [
        Expanded(child: CsLabel(label)),
        Text(value, maxLines: 1, style: cs.type.mono(12, color: CsColors.ink, weight: FontWeight.w600)),
      ]),
    );
  }

  // ── RIGHT ──────────────────────────────────────────────────────────────

  Widget _buildSections(BuildContext context) {
    final cs = context.cs;
    final cols = cs.size.width < 700 ? 2 : 4;
    final recentScores = (_performanceTrends['recentScores'] as List<int>?) ?? [];
    final trend = _performanceTrends['trend'] as String? ?? 'stable';
    final dailyPlayTime = (_playPatterns['dailyPlayTime'] as Map<String, int>?) ?? {};

    return ListView(
      padding: EdgeInsets.only(bottom: cs(16)),
      children: [
        const _Section('Performance overview'),
        CsStatGrid(columns: cols, valueSize: 22, stats: [
          CsStat('${_displayStats['highScore'] ?? 0}', 'High score'),
          CsStat('${_displayStats['totalGames'] ?? 0}', 'Total games'),
          CsStat('${_displayStats['averageScore'] ?? 0}', 'Average score'),
          CsStat('${_displayStats['winStreak'] ?? 0}', 'Win streak'),
        ]),
        const _Section('Game activity'),
        CsStatGrid(columns: cols, valueSize: 22, stats: [
          CsStat('${_displayStats['totalPlayTime'] ?? '0s'}', 'Play time'),
          CsStat('${_displayStats['longestSurvival'] ?? '0s'}', 'Longest game'),
          CsStat('${_displayStats['highestStage'] ?? 0}', 'Highest stage'),
          CsStat('${_displayStats['highestWave'] ?? 0}', 'Furthest wave'),
        ]),
        const _Section('Combat record'),
        CsStatGrid(columns: cols, valueSize: 22, stats: [
          CsStat('${_displayStats['enemiesKilled'] ?? 0}', 'Enemies destroyed', color: CsColors.pink),
          CsStat('${_displayStats['bossesKilled'] ?? 0}', 'Bosses defeated'),
          CsStat('${_displayStats['stagesCleared'] ?? 0}', 'Stages cleared'),
          CsStat('${_displayStats['bestCombo'] ?? 0}', 'Best combo'),
          CsStat('${_displayStats['victories'] ?? 0}', 'Victories', color: CsColors.mint),
          CsStat('${_displayStats['noHitClears'] ?? 0}', 'No-hit clears'),
          CsStat('${_displayStats['survivalRate'] ?? '0%'}', 'Survival rate'),
          CsStat('${_displayStats['longestStreak'] ?? 0}', 'Best streak'),
        ]),
        _Section('Performance trends', trailing: _trendChip(trend)),
        CsStatGrid(columns: cols, valueSize: 22, stats: [
          CsStat(trend.toUpperCase(), 'Overall trend', color: _trendColor(trend)),
          CsStat('${_performanceTrends['averageRecentScore'] ?? 0}', 'Recent average'),
          CsStat('${_performanceTrends['bestRecentScore'] ?? 0}', 'Best recent'),
          CsStat(_calculateConsistencyRating(recentScores), 'Consistency'),
        ]),
        if (recentScores.isNotEmpty) ...[
          SizedBox(height: cs(16)),
          Row(children: [
            Expanded(child: CsLabel('Progress · last ${recentScores.length} games', size: 10)),
            _legend(context, 'Scores', CsColors.ink25),
            SizedBox(width: cs(14)),
            _legend(context, 'Trend', CsColors.cyan),
          ]),
          SizedBox(height: cs(12)),
          SizedBox(
            height: cs(cs.isTablet ? 120 : 90),
            child: _buildTrendChart(recentScores, trend),
          ),
          SizedBox(height: cs(16)),
          _buildInsights(context, recentScores, trend),
        ],
        const _Section('Play patterns · last 7 days'),
        CsStatGrid(columns: 2, valueSize: 22, stats: [
          CsStat(_formatPlayTime(_playPatterns['totalWeeklyTime'] ?? 0), 'Weekly time'),
          CsStat('${_playPatterns['mostActiveDay'] ?? 'None'}', 'Most active day'),
        ]),
        if (dailyPlayTime.isNotEmpty) ...[
          SizedBox(height: cs(16)),
          const CsLabel('Daily activity', size: 10),
          SizedBox(height: cs(12)),
          SizedBox(height: cs(70), child: _buildDailyActivityChart(context, dailyPlayTime)),
        ],
        const _Section('Achievement progress'),
        _buildAchievementProgress(context),
      ],
    );
  }

  Widget _trendChip(String trend) => switch (trend) {
        'improving' => CsChip(trend, kind: CsChipKind.mint, icon: Symbols.trending_up_rounded),
        'declining' => CsChip(trend, kind: CsChipKind.pink, icon: Symbols.trending_down_rounded),
        _ => CsChip(trend, icon: Symbols.trending_flat_rounded),
      };

  Color _trendColor(String trend) => switch (trend) {
        'improving' => CsColors.mint,
        'declining' => CsColors.pink,
        _ => CsColors.ink,
      };

  Widget _legend(BuildContext context, String label, Color color) {
    final cs = context.cs;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: cs(12), height: 2, color: color),
      SizedBox(width: cs(6)),
      Text(label.toUpperCase(), style: cs.type.micro),
    ]);
  }

  Widget _buildAchievementProgress(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    // The display value comes through as 'X%' (a string). Strip the percent
    // sign, parse, default to 0, THEN divide by 100 so the ring (0.0–1.0)
    // shows the right fill.
    final pct = ((double.tryParse(
                  _displayStats['achievementProgress']?.toString().replaceAll('%', '') ?? '0',
                ) ??
                0) /
            100)
        .clamp(0.0, 1.0);
    return Padding(
      padding: EdgeInsets.only(top: cs(4)),
      child: Row(children: [
        CsRingProgress(
          value: pct,
          size: cs(64),
          stroke: 2.5,
          child: Icon(Symbols.military_tech_rounded, size: cs(24), color: CsColors.gold),
        ),
        SizedBox(width: cs(16)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Achievement progress', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
            SizedBox(height: cs(4)),
            Text('${_displayStats['achievementProgress'] ?? '0%'} COMPLETE', style: t.label),
          ]),
        ),
        CsButton.text(
          label: 'View all',
          size: CsButtonSize.small,
          trailingIcon: Symbols.arrow_forward_rounded,
          onPressed: () => context.push(AppRoutes.achievements),
        ),
      ]),
    );
  }

  Widget _buildDailyActivityChart(BuildContext context, Map<String, int> dailyData) {
    final cs = context.cs;
    final maxTime = dailyData.values.isNotEmpty ? dailyData.values.reduce((a, b) => a > b ? a : b) : 0;

    return LayoutBuilder(builder: (context, c) {
      final labelH = cs(16);
      final barMax = (c.maxHeight - labelH - cs(6)).clamp(4.0, double.infinity);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: dailyData.entries.map((entry) {
          final time = entry.value;
          final h = maxTime > 0 ? max(2.0, (time / maxTime) * barMax) : 2.0;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: cs(6),
                  height: h,
                  color: time > 0 ? CsColors.cyan : CsColors.track,
                ),
                SizedBox(height: cs(6)),
                SizedBox(
                  height: labelH,
                  child: Text(entry.key.toUpperCase(), maxLines: 1, style: cs.type.micro),
                ),
              ],
            ),
          );
        }).toList(),
      );
    });
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
    showCsDialog<void>(
      context,
      builder: (ctx) {
        final cs = ctx.cs;
        final t = cs.type;
        Widget bullet(String text) => Padding(
              padding: EdgeInsets.only(bottom: cs(6)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: EdgeInsets.only(top: cs(2)),
                  child: Icon(Symbols.remove_rounded, size: cs(14), color: CsColors.pink),
                ),
                SizedBox(width: cs(8)),
                Expanded(child: Text(text, style: t.body)),
              ]),
            );
        return CsDialog(
          icon: Symbols.warning_rounded,
          iconColor: CsColors.pink,
          eyebrow: 'Danger zone',
          title: 'Reset everything?',
          maxWidth: 560,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('This permanently deletes, on this device and the server:', style: t.body),
              SizedBox(height: cs(10)),
              bullet('All play statistics — games, enemies, bosses, stages, '
                  'combos, survival and win streaks'),
              bullet('Your high score, total score and total games'),
              bullet('Every leaderboard score (global, weekly and daily)'),
              bullet('Achievement progress and unlocks'),
              bullet('Daily-challenge progress'),
              SizedBox(height: cs(10)),
              Text('THIS CANNOT BE UNDONE.', style: t.mono(11, color: CsColors.pink, weight: FontWeight.w600)),
            ],
          ),
          actions: [
            CsButton.text(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
            _DangerButton(
              label: 'Delete everything',
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _performReset();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _performReset() async {
    final ok = await _statisticsService.resetStatistics();
    if (ok) {
      await _refreshStatistics();
    }
    if (!mounted) return;
    showCsToast(
      context,
      ok
          ? 'Everything has been reset.'
          : 'Couldn\'t reach the server. Connect to the internet and try '
              'again — nothing was changed.',
      kind: ok ? CsToastKind.success : CsToastKind.error,
    );
  }

  String _calculateConsistencyRating(List<int> scores) {
    if (scores.length < 3) return 'N/A';

    final average = scores.reduce((a, b) => a + b) / scores.length;
    final variance =
        scores.map((score) => (score - average) * (score - average)).reduce((a, b) => a + b) / scores.length;
    final standardDeviation = sqrt(variance);
    final coefficient = average > 0 ? standardDeviation / average : 0;

    if (coefficient < 0.3) return 'Excellent';
    if (coefficient < 0.5) return 'Good';
    if (coefficient < 0.7) return 'Fair';
    return 'Poor';
  }

  Widget _buildTrendChart(List<int> scores, String trend) {
    final maxScore = scores.reduce((a, b) => a > b ? a : b);
    final minScore = scores.reduce((a, b) => a < b ? a : b);
    return CustomPaint(
      painter: TrendChartPainter(
        scores: scores,
        maxScore: maxScore,
        minScore: minScore,
        barColor: CsColors.ink25,
        trendColor: CsColors.cyan,
        trend: trend,
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _buildInsights(BuildContext context, List<int> scores, String trend) {
    final cs = context.cs;
    final insights = _generateInsights(scores, trend);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CsMeta('Performance insights', icon: Symbols.lightbulb_rounded, iconColor: CsColors.gold, size: 10),
        SizedBox(height: cs(10)),
        for (final insight in insights)
          Padding(
            padding: EdgeInsets.only(bottom: cs(6)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: EdgeInsets.only(top: cs(7), right: cs(10)),
                child: Container(width: cs(4), height: 1, color: CsColors.ink45),
              ),
              Expanded(child: Text(insight, style: cs.type.body)),
            ]),
          ),
      ],
    );
  }

  List<String> _generateInsights(List<int> scores, String trend) {
    final insights = <String>[];

    if (scores.isEmpty) return ['Play more games to get performance insights!'];

    final average = scores.reduce((a, b) => a + b) / scores.length;
    final recent = scores.length >= 3 ? scores.sublist(scores.length - 3) : scores;
    final recentAvg = recent.reduce((a, b) => a + b) / recent.length;

    if (trend == 'improving') {
      insights.add('Great job! Your performance is on an upward trend.');
      if (recentAvg > average * 1.2) {
        insights.add('Your recent games are significantly above your average.');
      }
    } else if (trend == 'declining') {
      insights.add('Your performance has declined recently. Consider practicing more.');
      insights.add('Try focusing on avoiding collisions and planning your moves ahead.');
    } else {
      insights.add('Your performance is stable. Challenge yourself to improve!');
    }

    final maxScore = scores.reduce((a, b) => a > b ? a : b);
    final minScore = scores.reduce((a, b) => a < b ? a : b);
    if (maxScore > minScore * 3) {
      insights.add('You have potential for high scores - work on consistency.');
    }

    if (scores.length >= 5) {
      final lastFive = scores.sublist(scores.length - 5);
      if (lastFive.every((score) => score > average * 0.8)) {
        insights.add('You\'re maintaining solid performance across recent games.');
      }
    }

    return insights;
  }
}

/// Mono section label preceded by a group gap (and an optional trailing chip).
class _Section extends StatelessWidget {
  const _Section(this.label, {this.trailing});
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: EdgeInsets.only(top: cs(22), bottom: cs(4)),
      child: Row(children: [
        Expanded(child: CsLabel(label)),
        ?trailing,
      ]),
    );
  }
}

/// Pink outlined pill for irreversible actions inside dialogs.
class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return CsPressable(
      onTap: onPressed,
      semanticLabel: label,
      child: Container(
        constraints: BoxConstraints(minHeight: cs(48).clamp(44.0, 64.0)),
        padding: EdgeInsets.symmetric(horizontal: cs(24)),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: CsColors.pink.withValues(alpha: .12),
          shape: const StadiumBorder(side: BorderSide(color: CsColors.pink)),
        ),
        child: Text(label.toUpperCase(), maxLines: 1, style: cs.type.button.copyWith(color: CsColors.pink)),
      ),
    );
  }
}

/// Thin-line score chart: 2px score ticks on the ink25 track + a 1.5px
/// trend polyline with small dots. No fills under the curve.
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

    // Baseline hairline.
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = CsColors.hairline
        ..strokeWidth = 1,
    );

    final slot = size.width / scores.length;
    final range = maxScore > minScore ? maxScore - minScore : 1;
    double yFor(int score) => size.height - (((score - minScore) / range) * (size.height - 10) + 5);

    // Score ticks (2px columns).
    final barPaint = Paint()..color = barColor;
    final barW = min(2.0, slot * 0.5);
    for (int i = 0; i < scores.length; i++) {
      final x = i * slot + slot * 0.5;
      canvas.drawRect(Rect.fromLTRB(x - barW / 2, yFor(scores[i]), x + barW / 2, size.height), barPaint);
    }

    if (scores.length > 1) {
      final path = Path();
      for (int i = 0; i < scores.length; i++) {
        final x = i * slot + slot * 0.5;
        final y = yFor(scores[i]);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = trendColor
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final dot = Paint()..color = trendColor;
    final bg = Paint()..color = CsColors.bg;
    for (int i = 0; i < scores.length; i++) {
      final c = Offset(i * slot + slot * 0.5, yFor(scores[i]));
      canvas.drawCircle(c, 3, bg);
      canvas.drawCircle(c, 2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant TrendChartPainter old) =>
      old.scores != scores || old.barColor != barColor || old.trendColor != trendColor;
}
