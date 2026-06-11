import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../data/database/app_database.dart';
import '../presentation/bloc/theme/theme_cubit.dart';
import '../router/routes.dart';
import '../services/audio_service.dart';
import '../ui/design.dart';
import '../widgets/ads/banner_ad_widget.dart';
import '../utils/campaign_catalog.dart';
import '../utils/constants.dart';

/// Campaign level select. Landscape two-region layout in the clean
/// borderless style: LEFT = campaign telemetry (cleared ring, total stars,
/// selected-level detail, LAUNCH pill) on a no-scroll FittedBox rail;
/// RIGHT = the scrollable level grid grouped by biome.
///
/// Data: a single Drift watch on StageProgressDao — offline-first, always
/// live (a finished run updates the tiles the moment it persists).
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  int? _selected;
  bool _autoSelected = false;

  void _launch(int level) {
    AudioService().playSound('button_click');
    context.push(AppRoutes.playLoading, extra: level);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;
        return CommandScaffold(
          theme: theme,
          title: 'Campaign',
          bottomBar: const ShipBannerAd(),
          bodyPadding: EdgeInsets.zero,
          body: StreamBuilder<List<StageProgressRow>>(
            stream: GetIt.I<AppDatabase>().stageProgressDao.watchAll(),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const <StageProgressRow>[];
              final byStage = {for (final r in rows) r.stageId: r};

              // Furthest unlocked level — the default selection, so LAUNCH
              // is "continue" out of the box.
              var furthest = 1;
              for (final r in rows) {
                if (r.unlocked && r.stageId > furthest) furthest = r.stageId;
              }
              if (!_autoSelected && rows.isNotEmpty) {
                _autoSelected = true;
                _selected = furthest;
              }
              final selected = (_selected ?? 1)
                  .clamp(1, CampaignCatalog.totalLevels);

              final clearedCount = rows.where((r) => r.cleared).length;
              final totalStars =
                  rows.fold<int>(0, (sum, r) => sum + r.stars);

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 4,
                      // Never scrolls: natural size, scaled down to fit.
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: 280,
                            child: _CampaignRail(
                              theme: theme,
                              clearedCount: clearedCount,
                              totalStars: totalStars,
                              selected: selected,
                              row: byStage[selected],
                              furthest: furthest,
                              onLaunch: () => _launch(selected),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 6,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (var b = 0;
                              b < CampaignCatalog.biomeIds.length;
                              b++)
                            _BiomeSection(
                              theme: theme,
                              biomeIndex: b,
                              byStage: byStage,
                              selected: selected,
                              furthest: furthest,
                              onSelect: (level) =>
                                  setState(() => _selected = level),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// LEFT rail: cleared ring + star total + selected-level detail + LAUNCH.
class _CampaignRail extends StatelessWidget {
  const _CampaignRail({
    required this.theme,
    required this.clearedCount,
    required this.totalStars,
    required this.selected,
    required this.row,
    required this.furthest,
    required this.onLaunch,
  });

  final GameTheme theme;
  final int clearedCount;
  final int totalStars;
  final int selected;
  final StageProgressRow? row;
  final int furthest;
  final VoidCallback onLaunch;

  @override
  Widget build(BuildContext context) {
    final unlocked = row?.unlocked ?? (selected == 1);
    final cleared = row?.cleared ?? false;
    final stars = row?.stars ?? 0;
    final progress = clearedCount / CampaignCatalog.totalLevels;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cleared ring.
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
                  valueColor: AlwaysStoppedAnimation(
                      progress >= 1 ? Colors.green : theme.neonPrimary),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$clearedCount/${CampaignCatalog.totalLevels}',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  Text(
                    'CLEARED',
                    style: TextStyle(
                      color: theme.textMuted,
                      fontSize: 9,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.star_rounded,
                size: 16, color: Color(0xFFFFD54F)),
            const SizedBox(width: 4),
            Text(
              '$totalStars / ${CampaignCatalog.totalStars}',
              style: TextStyle(
                color: theme.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Selected level detail.
        Text(
          CampaignCatalog.biomeNameFor(selected),
          style: TextStyle(
            color: theme.neonSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'LEVEL $selected',
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          CampaignCatalog.levelNameFor(selected),
          style: TextStyle(
            color: theme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        // Star pips for the selected level.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final earned = i < stars;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                earned ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 22,
                color: earned
                    ? const Color(0xFFFFD54F)
                    : theme.textMuted.withValues(alpha: 0.5),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        if (unlocked) ...[
          _bestLine(
            'BEST SCORE',
            (row?.bestScore ?? 0) > 0 ? '${row!.bestScore}' : '—',
          ),
          _bestLine(
            'BEST TIME',
            (row?.bestTimeSeconds ?? 0) > 0 ? '${row!.bestTimeSeconds}s' : '—',
          ),
          if (row?.clearedNoHit ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'NO-HIT CLEAR',
                style: TextStyle(
                  color: Colors.green.shade400,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'CLEAR LEVEL ${selected - 1} TO UNLOCK',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
          ),
        const SizedBox(height: 20),
        SizedBox(
          width: 220,
          child: NeonButton(
            label: !unlocked
                ? 'LOCKED'
                : (selected == furthest && !cleared ? 'CONTINUE' : 'LAUNCH'),
            onPressed: unlocked ? onLaunch : null,
            theme: theme,
          ),
        ),
      ],
    );
  }

  Widget _bestLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$label  ',
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// RIGHT side: one biome header + its three level tiles.
class _BiomeSection extends StatelessWidget {
  const _BiomeSection({
    required this.theme,
    required this.biomeIndex,
    required this.byStage,
    required this.selected,
    required this.furthest,
    required this.onSelect,
  });

  final GameTheme theme;
  final int biomeIndex;
  final Map<int, StageProgressRow> byStage;
  final int selected;
  final int furthest;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final biomeId = CampaignCatalog.biomeIds[biomeIndex];
    final firstLevel = biomeIndex * CampaignCatalog.levelsPerBiome + 1;
    final levels = [
      for (var i = 0; i < CampaignCatalog.levelsPerBiome; i++) firstLevel + i,
    ];
    final biomeStars = levels.fold<int>(
        0, (sum, l) => sum + (byStage[l]?.stars ?? 0));

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                Text(
                  CampaignCatalog.biomeNames[biomeId]!,
                  style: TextStyle(
                    color: theme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.star_rounded,
                    size: 13, color: Color(0xFFFFD54F)),
                const SizedBox(width: 3),
                Text(
                  '$biomeStars/${CampaignCatalog.levelsPerBiome * 3}',
                  style: TextStyle(
                    color: theme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              for (final level in levels) ...[
                Expanded(
                  child: _LevelTile(
                    theme: theme,
                    level: level,
                    row: byStage[level],
                    isSelected: level == selected,
                    isFurthest: level == furthest,
                    onTap: () => onSelect(level),
                  ),
                ),
                if (level != levels.last) const SizedBox(width: 12),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One level tile: neon number disc (glow when selected — never an
/// outline), star pips, lock state, NEW dot, CONTINUE chip.
class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.theme,
    required this.level,
    required this.row,
    required this.isSelected,
    required this.isFurthest,
    required this.onTap,
  });

  final GameTheme theme;
  final int level;
  final StageProgressRow? row;
  final bool isSelected;
  final bool isFurthest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unlocked = row?.unlocked ?? (level == 1);
    final cleared = row?.cleared ?? false;
    final stars = row?.stars ?? 0;
    final isNew = unlocked && !cleared && level > 1;

    final discColor = !unlocked
        ? theme.textMuted.withValues(alpha: 0.25)
        : (cleared ? theme.neonPrimary : theme.neonSecondary);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: discColor.withValues(alpha: unlocked ? 0.16 : 0.08),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: theme.glow.withValues(alpha: 0.55),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: unlocked
                      ? Text(
                          '$level',
                          style: TextStyle(
                            color: isSelected
                                ? theme.textPrimary
                                : discColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : Icon(
                          Icons.lock_rounded,
                          size: 20,
                          color: theme.textMuted.withValues(alpha: 0.4),
                        ),
                ),
                if (isNew)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.neonSecondary,
                        boxShadow: [
                          BoxShadow(
                            color: theme.neonSecondary.withValues(alpha: 0.7),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Star pips.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final earned = i < stars;
                return Icon(
                  Icons.star_rounded,
                  size: 11,
                  color: earned
                      ? const Color(0xFFFFD54F)
                      : theme.textMuted.withValues(alpha: 0.25),
                );
              }),
            ),
            if (isFurthest && unlocked && !cleared) ...[
              const SizedBox(height: 4),
              Text(
                'CONTINUE',
                style: TextStyle(
                  color: theme.neonPrimary,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
