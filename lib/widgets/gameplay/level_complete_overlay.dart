import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import '../../utils/title_case.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database/app_database.dart';
import '../../game/cosmo_strike_game.dart';
import '../../models/level_run_result.dart';
import '../../utils/campaign_catalog.dart';
import 'results_motion.dart';
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
///
/// Entrance is one [CsBeatSheet] (see [LevelCompleteOverlay.beats]): header
/// drops in → score rolls up → stars pop one by one → badges pop → run grid
/// and objectives fade up → actions arrive (~2 s). A tap after 1 s skips to
/// the end state; reduce motion shows it at once.
class LevelCompleteOverlay extends StatefulWidget {
  const LevelCompleteOverlay({
    super.key,
    required this.game,
    required this.outcome,
    required this.priorBest,
    this.runLabel,
    required this.onContinue,
    required this.onQuit,
    this.reduceMotion,
  });

  final CosmoStrikeGame game;

  /// Merge outcome for this level (firstClear / star delta / next unlock).
  final StageClearOutcome? outcome;

  /// This level's persisted best BEFORE this run merged in — drives the
  /// accurate NEW BEST / FASTEST / FIRST NO-HIT badges.
  final StageProgressRow? priorBest;

  /// The run's name ("Daily Run" / "Sector Cup" / mode); null falls back to
  /// the mode name.
  final String? runLabel;

  final VoidCallback onContinue;
  final VoidCallback onQuit;

  /// Overrides [CsReduceMotion.of] (tests).
  final bool? reduceMotion;

  static const _wash = CsWash(CsColors.mint, .2, .3, rx: .4, ry: .7, alpha: .12);

  /// Fully opaque so nothing on the frozen battlefield ghosts through.
  static const _scrim = CsColors.bg;

  /// Beat timings, ms from mount.
  static const int starAt = 600;
  static const int starStep = 120;
  static const int tilesAt = 1200;
  static const int objectivesAt = 1250;

  /// The level-clear timeline; [onStar] is each star's landing cue.
  static Map<String, CsBeat> beats({required void Function(int star) onStar}) => {
        'header': const CsBeat(at: 0, duration: 400, curve: CsMotion.dropIn),
        'title': const CsBeat(at: 80, duration: 400, curve: CsMotion.dropIn),
        'scoreRow': const CsBeat(at: 160, duration: 400),
        'score': const CsBeat(at: 250, duration: 380),
        for (var i = 0; i < 3; i++)
          'star$i': CsBeat(
            at: starAt + starStep * i,
            duration: 450,
            curve: CsMotion.springPop,
            onStart: () => onStar(i),
          ),
        'badges': const CsBeat(at: 1060, duration: 450, curve: CsMotion.springPop),
        'runLabel': const CsBeat(at: 1150, duration: 400),
        for (var i = 0; i < 8; i++) 'tile$i': CsBeat(at: tilesAt + 55 * i, duration: 400),
        for (var i = 0; i < 3; i++) 'obj$i': CsBeat(at: objectivesAt + 55 * i, duration: 400),
        'bests': const CsBeat(at: 1450, duration: 400),
        'next': const CsBeat(at: 1550, duration: 400),
        'actions': const CsBeat(at: 1700, duration: 320),
      };

  @override
  State<LevelCompleteOverlay> createState() => _LevelCompleteOverlayState();
}

class _LevelCompleteOverlayState extends State<LevelCompleteOverlay> with SingleTickerProviderStateMixin {
  late final ResultsBeats _beats = ResultsBeats(
    vsync: this,
    beats: LevelCompleteOverlay.beats(onStar: _onStar),
  );

  /// Earned stars, refreshed every build (read by the star cues).
  int _earned = 0;

  void _onStar(int i) {
    if (i >= _earned) return;
    // A light tick per star landing, the success pattern on the last one.
    (i == _earned - 1 ? CsHaptic.success : CsHaptic.light).play();
    playResultsCue('pickup');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _beats.start(reduceMotion: CsReduceMotion.of(context, override: widget.reduceMotion, listen: false));
  }

  @override
  void dispose() {
    _beats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final b = _beats;
    final game = widget.game;
    final outcome = widget.outcome;
    final priorBest = widget.priorBest;
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
    _earned = stars.clamp(0, 3);
    final gainedStars = outcome != null && outcome.starsAfter > outcome.starsBefore;

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

    final scoreStyle = t.display(36, em: -0.03, height: 1);

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: CsFitColumn(
            children: [
              BeatFade(
                beats: b,
                name: 'header',
                rise: -12,
                child: CsLabel('Level $lv clear · ${widget.runLabel ?? game.mode.name}', color: CsColors.mint),
              ),
              SizedBox(height: cs(8)),
              // Title case like every other headline; scales down rather
              // than truncating long names ("Shattered Light").
              BeatFade(
                beats: b,
                name: 'title',
                rise: -14,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    titleCaseName(CampaignCatalog.levelNameFor(level)),
                    maxLines: 1,
                    style: t.display(52, em: -0.04, height: 1),
                  ),
                ),
              ),
              SizedBox(height: cs(14)),
              BeatFade(
                beats: b,
                name: 'scoreRow',
                rise: 0,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _PoppingStars(beats: b, earned: _earned, size: 30),
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
                            BeatGate(
                              beats: b,
                              name: 'score',
                              builder: (_, reached, settled) => CsOdometer(
                                value: reached ? lvl.score : 0,
                                style: scoreStyle,
                                reduceMotion: settled ? true : null,
                                semanticsLabel: '${lvl.score} points',
                              ),
                            ),
                            SizedBox(width: cs(8)),
                            Text('PTS', style: t.mono(11, color: CsColors.ink55)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (badges.isNotEmpty) ...[
                SizedBox(height: cs(12)),
                Wrap(
                  spacing: cs(8),
                  runSpacing: cs(8),
                  children: [
                    for (final chip in badges) BeatPop(beats: b, name: 'badges', from: 0.6, fade: true, child: chip),
                  ],
                ),
              ],
              SizedBox(height: cs(18)),
              BeatFade(beats: b, name: 'runLabel', child: const CsLabel('Run so far')),
              SizedBox(height: cs(8)),
              RunStatGrid(
                cell: (i, tile) => BeatFade(beats: b, name: 'tile${i.clamp(0, 7)}', child: tile),
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
        // Interactive from the first frame regardless of the fade.
        BeatFade(
          beats: b,
          name: 'actions',
          rise: 8,
          child: OverlayActions(
            children: [
              CsButton.primary(
                label: hasNext ? 'Continue to level ${level + 1}' : 'Continue',
                trailingIcon: Symbols.arrow_forward_rounded,
                onPressed: widget.onContinue,
              ),
              CsButton.secondary(label: 'Quit', onPressed: widget.onQuit),
            ],
          ),
        ),
      ],
    );

    final objectives = [
      (true, 'Clear the level'),
      (beatPar, 'Beat par — under ${formatRunTime(parTime)} or $parScore pts'),
      (lvl.noHit, 'Flawless — take no hits'),
    ];

    final right = ScrollEdgeFade(
      fadeColor: LevelCompleteOverlay._scrim,
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const ClampingScrollPhysics(),
        children: [
          BeatFade(beats: b, name: 'obj0', rise: 0, slideX: 12, child: const CsLabel('Star objectives')),
          SizedBox(height: cs(4)),
          for (final (i, (earned, text)) in objectives.indexed)
            BeatFade(
              beats: b,
              name: 'obj$i',
              rise: 0,
              slideX: 12,
              child: _Objective(earned: earned, text: text),
            ),
          SizedBox(height: cs(20)),
          BeatFade(
            beats: b,
            name: 'bests',
            rise: 0,
            slideX: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const CsLabel('This level'),
                SizedBox(height: cs(4)),
                BeatGate(
                  beats: b,
                  name: 'bests',
                  builder: (_, reached, settled) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BestLine(label: 'Best score', value: reached ? bestScore : 0, instant: settled),
                      _BestLine(
                        label: 'Best time',
                        value: reached ? bestTime : 0,
                        instant: settled,
                        format: bestTime > 0 ? formatRunTime : (_) => '—',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasNext) ...[
            SizedBox(height: cs(20)),
            BeatFade(
              beats: b,
              name: 'next',
              rise: 0,
              slideX: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CsLabel('Next · Level ${(level + 1).toString().padLeft(2, '0')}'),
                  SizedBox(height: cs(8)),
                  CsPrismText(
                    titleCaseName(CampaignCatalog.levelNameFor(level + 1)),
                    maxLines: 1,
                    style: t.display(26, em: -0.03, height: 1.1),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    return ResultsTapToSkip(
      beats: b,
      child: GameplayOverlayFrame(
        scrim: LevelCompleteOverlay._scrim,
        washes: const [LevelCompleteOverlay._wash],
        child: OverlaySplit(left: left, right: right),
      ),
    );
  }
}

/// Three star slots: faint outlines from the start, each earned star popping
/// in over its slot on its own beat (`star0..2`, springPop).
class _PoppingStars extends StatelessWidget {
  const _PoppingStars({required this.beats, required this.earned, required this.size});

  final ResultsBeats beats;
  final int earned;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = context.cs(size);
    final outline = Icon(Symbols.star_rounded, size: d, fill: 0, color: CsColors.gold.withValues(alpha: .7));
    return Semantics(
      label: '$earned of 3 stars',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            if (i < earned)
              Stack(
                alignment: Alignment.center,
                children: [
                  outline,
                  BeatPop(
                    key: ValueKey('star$i'),
                    beats: beats,
                    name: 'star$i',
                    child: Icon(Symbols.star_rounded, size: d, fill: 1, color: CsColors.gold),
                  ),
                ],
              )
            else
              outline,
        ],
      ),
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

/// Mono label · Syne value line for this level's bests; the value rolls up
/// on the `bests` beat.
class _BestLine extends StatelessWidget {
  const _BestLine({required this.label, required this.value, required this.instant, this.format});

  final String label;
  final int value;
  final bool instant;
  final String Function(int value)? format;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: EdgeInsets.symmetric(vertical: cs(10)),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CsColors.hairline))),
      child: Row(
        children: [
          Expanded(child: CsLabel(label)),
          CsOdometer(
            value: value,
            format: format ?? (v) => '$v',
            reduceMotion: instant ? true : null,
            style: cs.type.display(16, weight: FontWeight.w700, em: 0),
          ),
        ],
      ),
    );
  }
}
