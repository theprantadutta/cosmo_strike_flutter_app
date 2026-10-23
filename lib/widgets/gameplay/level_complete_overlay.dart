import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:flutter/material.dart';

import '../../data/database/app_database.dart';
import '../../game/cosmo_strike_game.dart';
import '../../models/level_run_result.dart';
import '../../utils/campaign_catalog.dart';
import 'run_stat_tiles.dart';

/// The per-level debrief shown when a campaign level is cleared (mid-run).
/// Same family as the game-over debrief, but celebratory (mint wash):
///   LEFT  — mint mono "LEVEL 03 COMPLETE", the level name headline, earned
///           stars + level score with NEW BEST / NEW STARS / NO-HIT badges, a
///           4×2 RUN-SO-FAR grid, then CONTINUE TO LEVEL N · QUIT.
///   RIGHT — the three star objectives, this level's bests and the next
///           level teaser (prism name).
/// Advancing is CONTINUE-only — the run never auto-advances. Coins/XP are
/// intentionally withheld here; they tally on the final run debrief.
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

  static const _wash = CsWash(CsColors.mint, .2, .3, rx: .4, ry: .7, alpha: .12);
  static const _scrim = Color(0xF20A0A0D);

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
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
    final gainedStars = outcome != null && outcome!.starsAfter > outcome!.starsBefore;

    final priorScore = priorBest?.bestScore ?? 0;
    final priorTime = priorBest?.bestTimeSeconds ?? 0;
    final newBestScore = lvl.score > priorScore;
    final firstNoHit = lvl.noHit && !(priorBest?.clearedNoHit ?? false);

    final parTime = CampaignCatalog.parTimeSeconds(level);
    final parScore = CampaignCatalog.parScore(level);
    final beatPar = (lvl.timeSeconds > 0 && lvl.timeSeconds <= parTime) || lvl.score >= parScore;

    final bestScore = lvl.score > priorScore ? lvl.score : priorScore;
    final bestTime = priorTime == 0
        ? lvl.timeSeconds
        : (lvl.timeSeconds > 0 && lvl.timeSeconds < priorTime ? lvl.timeSeconds : priorTime);

    final hasNext = level < CampaignCatalog.totalLevels;
    final lv = level.toString().padLeft(2, '0');

    final badges = <Widget>[
      if (newBestScore) const CsChip('New best', kind: CsChipKind.gold, icon: Symbols.star_rounded, size: 10),
      if (gainedStars) const CsChip('New stars', kind: CsChipKind.gold, size: 10),
      if (lvl.noHit)
        CsChip(
          firstNoHit ? 'First no-hit clear' : 'No-hit clear',
          kind: CsChipKind.mint,
          icon: Symbols.verified_rounded,
          size: 10,
        ),
    ];

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: CsFitColumn(
            children: [
              CsLabel('Level $lv clear · ${game.mode.name}', color: CsColors.mint),
              SizedBox(height: cs(8)),
              // Title case like every other headline; scales down rather
              // than truncating long names ("Shattered Light").
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _titleCase(CampaignCatalog.levelNameFor(level)),
                  maxLines: 1,
                  style: t.display(52, em: -0.04, height: 1),
                ),
              ),
              SizedBox(height: cs(14)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CsStars(stars, size: 30),
                  SizedBox(width: cs(18)),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          CsCountUp(value: lvl.score, style: t.display(36, em: -0.03, height: 1)),
                          SizedBox(width: cs(8)),
                          Text('PTS', style: t.mono(11, color: CsColors.ink55)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (badges.isNotEmpty) ...[
                SizedBox(height: cs(12)),
                Wrap(spacing: cs(8), runSpacing: cs(8), children: badges),
              ],
              SizedBox(height: cs(18)),
              const CsLabel('Run so far'),
              SizedBox(height: cs(8)),
              CsStatGrid(
                columns: 4,
                valueSize: 20,
                labelSize: 9,
                cellPadding: 10,
                stats: [
                  CsStat('${run.levelsCleared}', 'Cleared'),
                  CsStat('${run.enemiesKilled}', 'Kills'),
                  CsStat('${run.bossesKilled}', 'Bosses'),
                  CsStat('×${run.maxCombo}', 'Max combo'),
                  CsStat('${run.grazeCount}', 'Grazes'),
                  CsStat('${run.missilesFired}', 'Missiles'),
                  CsStat(formatRunTime(run.durationSeconds), 'Run time'),
                  CsStat('${run.score}', 'Total score'),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: cs(16)),
        OverlayActions(
          children: [
            CsButton.primary(
              label: hasNext ? 'Continue to level ${level + 1}' : 'Continue',
              trailingIcon: Symbols.arrow_forward_rounded,
              onPressed: onContinue,
            ),
            CsButton.secondary(label: 'Quit', onPressed: onQuit),
          ],
        ),
      ],
    );

    final right = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: CsMotion.slow,
      curve: CsMotion.standard,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(cs(12) * (1 - v), 0), child: child),
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [
          const CsLabel('Star objectives'),
          SizedBox(height: cs(4)),
          _Objective(earned: true, text: 'Clear the level'),
          _Objective(
            earned: beatPar,
            text: 'Beat par — under ${formatRunTime(parTime)} or $parScore pts',
          ),
          _Objective(earned: lvl.noHit, text: 'Flawless — take no hits'),
          SizedBox(height: cs(20)),
          const CsLabel('This level'),
          SizedBox(height: cs(4)),
          _BestLine(label: 'Best score', value: '$bestScore'),
          _BestLine(label: 'Best time', value: bestTime > 0 ? formatRunTime(bestTime) : '—'),
          if (hasNext) ...[
            SizedBox(height: cs(20)),
            CsLabel('Next · Level ${(level + 1).toString().padLeft(2, '0')}'),
            SizedBox(height: cs(8)),
            CsPrismText(
              _titleCase(CampaignCatalog.levelNameFor(level + 1)),
              maxLines: 1,
              style: t.display(26, em: -0.03, height: 1.1),
            ),
          ],
        ],
      ),
    );

    return GameplayOverlayFrame(
      scrim: _scrim,
      washes: const [_wash],
      child: OverlaySplit(left: left, right: right),
    );
  }
}

/// A star objective row: mint check when earned, faint ring when not.
class _Objective extends StatelessWidget {
  const _Objective({required this.earned, required this.text});

  final bool earned;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: EdgeInsets.symmetric(vertical: cs(10)),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CsColors.hairline))),
      child: Row(
        children: [
          Icon(
            earned ? Symbols.check_circle_rounded : Symbols.radio_button_unchecked_rounded,
            size: cs(18),
            color: earned ? CsColors.mint : CsColors.ink30,
          ),
          SizedBox(width: cs(12)),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: cs.type.body.copyWith(color: earned ? CsColors.ink : CsColors.ink55),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mono label · Syne value line for this level's bests.
class _BestLine extends StatelessWidget {
  const _BestLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: EdgeInsets.symmetric(vertical: cs(10)),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CsColors.hairline))),
      child: Row(
        children: [
          Expanded(child: CsLabel(label)),
          Text(value, maxLines: 1, style: cs.type.display(16, weight: FontWeight.w700, em: 0)),
        ],
      ),
    );
  }
}

String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');
