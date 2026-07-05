import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../data/database/app_database.dart';
import '../../game/cosmo_palette.dart';
import '../../game/cosmo_strike_game.dart';
import '../../models/level_run_result.dart';
import '../../services/ads/ad_tuning.dart';
import '../../ui/design.dart';
import '../../utils/campaign_catalog.dart';
import '../../utils/game_animations.dart';
import '../ads/banner_ad_widget.dart';
import 'run_stat_tiles.dart';

/// The per-level debrief shown when a campaign level is cleared (mid-run).
/// A rich, two-region landscape summary in the same Command-HUD language as
/// the end-of-run [GameOverOverlay]: LEFT = this level's result (stars, score,
/// new-best badges) + a RUN-SO-FAR telemetry grid; RIGHT = the three star
/// objectives, this level's bests, and a next-level teaser. Advancing is
/// CONTINUE-only — the run never auto-advances. Coins/XP are intentionally
/// withheld here; they tally on the final run debrief.
class LevelCompleteOverlay extends StatelessWidget {
  const LevelCompleteOverlay({
    super.key,
    required this.game,
    required this.outcome,
    required this.priorBest,
    required this.onContinue,
    required this.onQuit,
  });

  final CosmoStrikeGame game;

  /// Merge outcome for this level (firstClear / star delta / next unlock).
  final StageClearOutcome? outcome;

  /// This level's persisted best BEFORE this run merged in — drives the
  /// accurate NEW BEST / FASTEST / FIRST NO-HIT badges.
  final StageProgressRow? priorBest;

  final VoidCallback onContinue;
  final VoidCallback onQuit;

  static const Color _gold = Color(0xFFFFD37B);

  String _time(int s) {
    final m = s ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final level = game.levelIndex;
    final run = game.buildPartialResult();
    final lvl = run.levelResults.lastWhere(
      (lr) => lr.stageId == level,
      orElse: () => LevelRunResult(
        stageId: level,
        cleared: true,
        score: 0,
        timeSeconds: 0,
        waveReached: 1,
        noHit: false,
      ),
    );

    final stars =
        outcome?.starsAfter ??
        CampaignCatalog.starsFor(
          stageId: level,
          cleared: true,
          noHit: lvl.noHit,
          bestTimeSeconds: lvl.timeSeconds,
          bestScore: lvl.score,
        );
    final gainedStars =
        outcome != null && outcome!.starsAfter > outcome!.starsBefore;

    final priorScore = priorBest?.bestScore ?? 0;
    final priorTime = priorBest?.bestTimeSeconds ?? 0;
    final newBestScore = lvl.score > priorScore;
    final firstNoHit = lvl.noHit && !(priorBest?.clearedNoHit ?? false);

    final parTime = CampaignCatalog.parTimeSeconds(level);
    final parScore = CampaignCatalog.parScore(level);
    final beatPar =
        (lvl.timeSeconds > 0 && lvl.timeSeconds <= parTime) ||
        lvl.score >= parScore;

    final bestScore = lvl.score > priorScore ? lvl.score : priorScore;
    final bestTime = priorTime == 0
        ? lvl.timeSeconds
        : (lvl.timeSeconds > 0 && lvl.timeSeconds < priorTime
              ? lvl.timeSeconds
              : priorTime);

    final hasNext = level < CampaignCatalog.totalLevels;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Container(
              color: const Color(0xFF05060F).withValues(alpha: 0.88),
            ),
          ),
        ),
        // Banner strip at the top; debrief content adapts below it (see
        // PauseOverlay for the full rationale + remote kill switch).
        Column(
          children: [
            if (AdTuning.overlayBannersEnabled) const ShipBannerAd(top: true),
            Expanded(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: GameTokens.space24,
                    vertical: GameTokens.space16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // LEFT — hero result + run telemetry. Scales down, never scrolls.
                      Expanded(
                        flex: 11,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: 430,
                                  child: _heroColumn(
                                    level: level,
                                    lvl: lvl,
                                    run: run,
                                    stars: stars,
                                    gainedStars: gainedStars,
                                    newBestScore: newBestScore,
                                    firstNoHit: firstNoHit,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: GameTokens.space12),
                            Row(
                              children: [
                                Expanded(
                                  child: OverlayActionButton(
                                    label: hasNext
                                        ? 'CONTINUE TO LEVEL ${level + 1}'
                                        : 'CONTINUE',
                                    onTap: onContinue,
                                  ),
                                ),
                                const SizedBox(width: GameTokens.space8),
                                Expanded(
                                  child: OverlayActionButton(
                                    label: 'QUIT',
                                    onTap: onQuit,
                                    variant: NeonButtonVariant.outline,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: GameTokens.space24),
                      // RIGHT — objectives + bests + next teaser.
                      Expanded(
                        flex: 9,
                        child: ListView(
                          children: [
                            const SectionHeader('STAR OBJECTIVES'),
                            const SizedBox(height: GameTokens.space12),
                            _objective(true, 'Clear the level'),
                            _objective(
                              beatPar,
                              'Beat par — under ${_time(parTime)} or $parScore pts',
                            ),
                            _objective(lvl.noHit, 'Flawless — take no hits'),
                            const SizedBox(height: GameTokens.space20),
                            const SectionHeader('THIS LEVEL'),
                            const SizedBox(height: GameTokens.space12),
                            _bestLine('BEST SCORE', '$bestScore'),
                            _bestLine(
                              'BEST TIME',
                              bestTime > 0 ? _time(bestTime) : '—',
                            ),
                            if (hasNext) ...[
                              const SizedBox(height: GameTokens.space20),
                              const SectionHeader('NEXT'),
                              const SizedBox(height: GameTokens.space12),
                              Text(
                                'LEVEL ${level + 1}',
                                style: const TextStyle(
                                  color: CosmoPalette.highlight,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                CampaignCatalog.levelNameFor(level + 1),
                                style: TextStyle(
                                  color: CosmoPalette.hull.withValues(
                                    alpha: 0.7,
                                  ),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ).gameEntrance(delay: 220.ms),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _heroColumn({
    required int level,
    required LevelRunResult lvl,
    required GameResult run,
    required int stars,
    required bool gainedStars,
    required bool newBestScore,
    required bool firstNoHit,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LEVEL $level COMPLETE',
          style: TextStyle(
            color: _gold,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
            shadows: [
              Shadow(color: _gold.withValues(alpha: 0.7), blurRadius: 18),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          CampaignCatalog.levelNameFor(level).toUpperCase(),
          style: TextStyle(
            color: CosmoPalette.hull.withValues(alpha: 0.8),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: GameTokens.space12),
        // Stars — staggered pop-in.
        Row(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 42,
                  color: i < stars
                      ? _gold
                      : CosmoPalette.hull.withValues(alpha: 0.3),
                  shadows: i < stars
                      ? [
                          Shadow(
                            color: _gold.withValues(alpha: 0.7),
                            blurRadius: 14,
                          ),
                        ]
                      : null,
                ).gamePop(delay: Duration(milliseconds: 180 + i * 130)),
              ),
            if (gainedStars) ...[
              const SizedBox(width: 8),
              _badge('NEW STARS', _gold),
            ],
          ],
        ),
        const SizedBox(height: GameTokens.space16),
        // This level's score + badges.
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${lvl.score}',
              style: const TextStyle(
                color: CosmoPalette.highlight,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'PTS',
              style: TextStyle(
                color: CosmoPalette.hull.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(width: 12),
            if (newBestScore) _badge('★ NEW BEST', _gold),
          ],
        ),
        if (lvl.noHit) ...[
          const SizedBox(height: GameTokens.space8),
          _badge(
            firstNoHit ? 'FIRST NO-HIT CLEAR' : 'NO-HIT CLEAR',
            CosmoPalette.energy,
          ),
        ],
        const SizedBox(height: GameTokens.space20),
        const SectionHeader('RUN SO FAR'),
        const SizedBox(height: GameTokens.space12),
        Wrap(
          spacing: GameTokens.space16,
          runSpacing: GameTokens.space12,
          children: [
            RunStatTile(
              icon: Icons.military_tech,
              value: '${run.levelsCleared}',
              label: 'LEVELS CLEARED',
            ),
            RunStatTile(
              icon: Icons.gps_fixed,
              value: '${run.enemiesKilled}',
              label: 'KILLS',
            ),
            RunStatTile(
              icon: Icons.adjust,
              value: '${run.bossesKilled}',
              label: 'BOSSES',
            ),
            RunStatTile(
              icon: Icons.bolt,
              value: '×${run.maxCombo}',
              label: 'MAX COMBO',
            ),
            RunStatTile(
              icon: Icons.shield_moon,
              value: '${run.grazeCount}',
              label: 'GRAZES',
            ),
            RunStatTile(
              icon: Icons.rocket,
              value: '${run.missilesFired}',
              label: 'MISSILES',
            ),
            RunStatTile(
              icon: Icons.timer,
              value: _time(run.durationSeconds),
              label: 'RUN TIME',
            ),
            RunStatTile(
              icon: Icons.stars,
              value: '${run.score}',
              label: 'TOTAL SCORE',
            ),
          ],
        ),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(GameTokens.radiusPill),
        boxShadow: softGlow(color, intensity: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
    ).gameEntrance(delay: 360.ms);
  }

  Widget _objective(bool earned, String text) {
    final color = earned ? CosmoPalette.energy : CosmoPalette.hull;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: earned ? 0.14 : 0.06),
              boxShadow: earned ? softGlow(color, intensity: 0.5) : null,
            ),
            child: Icon(
              earned ? Icons.check_rounded : Icons.circle_outlined,
              size: 15,
              color: earned ? color : CosmoPalette.hull.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: earned
                    ? CosmoPalette.highlight
                    : CosmoPalette.hull.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bestLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: CosmoPalette.hull.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: CosmoPalette.highlight,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
