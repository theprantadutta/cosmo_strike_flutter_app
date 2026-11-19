import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/number_format.dart';
import 'package:material_ui/material_ui.dart';

import '../../game/run_upgrades.dart';
import 'upgrade_draft_overlay.dart' show upgradeIcon;

import '../../game/cosmo_strike_game.dart';
import '../../services/achievement_service.dart';
import 'challenge_panel.dart';
import 'results_motion.dart';
import 'run_stat_tiles.dart';

/// The end-of-run debrief: a two-region landscape layout that never scrolls
/// on the left.
///
///   LEFT  — pink mono "GAME OVER · L03 / W04" (mint VICTORY on a full
///           campaign clear), the score rolling up at 84px + BEST / NEW
///           RECORD, a 4×2 stat grid, +COINS (gold) · +XP (violet), unlock /
///           bonus notes, then RETRY · HOME/CAMPAIGN · 2× COINS.
///   RIGHT — today's directives with CLAIM pills + the prism CLAIM ALL chip,
///           then this run's achievement unlocks (the only scrollable).
///
/// Coins / XP / challenge progress / achievements all land async after
/// `_submitRun` and rebuild reactively.
///
/// Entrance is one [CsBeatSheet] (see [GameOverOverlay.beats]): header →
/// score rolls up → NEW RECORD pops (records only) → stat tiles stagger in →
/// +CR / +XP roll up → actions arrive (~2.1 s). A tap after 1 s skips to the
/// end state; reduce motion shows it at once.
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({
    super.key,
    required this.result,
    this.runLabel,
    required this.victory,
    required this.previousBest,
    required this.unlockedLevel,
    required this.runCoinsEarned,
    required this.runXpEarned,
    required this.coinsDoubled,
    required this.canDoubleCoins,
    required this.onDoubleCoins,
    required this.onRetry,
    required this.onExit,
    required this.challengeRunStart,
    this.reduceMotion,
    this.directives,
  });

  final GameResult result;

  /// The run's name ("Daily Run" / "Sector Cup" / mode), shared with the
  /// intro, pause and level-clear headers. Null omits it.
  final String? runLabel;

  final bool victory;

  /// High score BEFORE this run was submitted (drives NEW RECORD).
  final int previousBest;

  /// Highest newly-unlocked level this run, 0 = none.
  final int unlockedLevel;

  /// Coin payout from _submitRun (0 until it lands).
  final int runCoinsEarned;

  /// Battle-pass XP buffered by _submitRun (0 until it lands).
  final int runXpEarned;

  final bool coinsDoubled;
  final bool canDoubleCoins;
  final VoidCallback onDoubleCoins;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  /// Per-challenge progress snapshot from run start (id → progress).
  final Map<String, int> challengeRunStart;

  /// Overrides [CsReduceMotion.of] (tests).
  final bool? reduceMotion;

  /// Replaces the directive rows + commendations and drops the header's
  /// CLAIM ALL chip (tests, which have no directive service or achievement
  /// store).
  @visibleForTesting
  final Widget? directives;

  static const _victoryWash = CsWash(CsColors.mint, .2, .3, rx: .4, ry: .7, alpha: .12);

  /// Fully opaque: at 95% the frozen battlefield (and anything over it)
  /// ghosted through behind the header.
  static const _overScrim = CsColors.bg;

  /// Beat timings, ms from mount.
  static const int recordAt = 900;
  static const int tilesAt = 1100;
  static const int rewardsAt = 1600;

  /// When the directive rows start fading up (they run on their own
  /// CsFadeUps, finished before the skip window opens).
  static const Duration directivesDelay = Duration(milliseconds: 380);

  /// The game-over timeline; [onRecord] is the NEW RECORD cue.
  static Map<String, CsBeat> beats({required VoidCallback onRecord}) => {
        'header': const CsBeat(at: 0, duration: 400, curve: CsMotion.dropIn),
        'scoreRow': const CsBeat(at: 100, duration: 350),
        'score': const CsBeat(at: 200, duration: 600),
        'right': const CsBeat(at: 300, duration: 400),
        'record': CsBeat(at: recordAt, duration: 450, curve: CsMotion.springPop, onStart: onRecord),
        'soClose': const CsBeat(at: 1000, duration: 400),
        for (var i = 0; i < 8; i++) 'tile$i': CsBeat(at: tilesAt + 55 * i, duration: 400),
        'build': const CsBeat(at: 1450, duration: 400),
        'rewards': const CsBeat(at: rewardsAt, duration: 400),
        'notes': const CsBeat(at: 1750, duration: 400),
        'actions': const CsBeat(at: 1800, duration: 320),
      };

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay> with SingleTickerProviderStateMixin {
  late final ResultsBeats _beats = ResultsBeats(
    vsync: this,
    beats: GameOverOverlay.beats(onRecord: _onRecord),
  );

  bool get _newRecord => widget.result.score > widget.previousBest;

  void _onRecord() {
    if (!_newRecord) return;
    CsHaptic.success.play();
    playResultsCue('high_score');
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
    final result = widget.result;
    final previousBest = widget.previousBest;
    final victory = widget.victory;
    final newRecord = _newRecord;
    final accent = victory ? CsColors.mint : CsColors.pink;
    final lv = result.stageReached.toString().padLeft(2, '0');
    final wv = result.waveReached.toString().padLeft(2, '0');
    final showDouble = !widget.coinsDoubled && widget.canDoubleCoins;

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
                child: CsLabel(
                  [
                    victory ? 'Mission complete' : 'Ship lost',
                    ?widget.runLabel,
                    'L$lv / W$wv',
                  ].join(' · '),
                  color: accent,
                ),
              ),
              SizedBox(height: cs(10)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: BeatFade(
                      beats: b,
                      name: 'scoreRow',
                      rise: 0,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: BeatGate(
                          beats: b,
                          name: 'score',
                          builder: (_, reached, settled) => CsOdometer(
                            value: reached ? result.score : 0,
                            style: t.scoreGiant,
                            duration: CsMotion.countUp,
                            reduceMotion: settled ? true : null,
                            semanticsLabel: '${result.score} points',
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: cs(18)),
                  if (newRecord)
                    BeatPop(
                      beats: b,
                      name: 'record',
                      from: 0.4,
                      fade: true,
                      alignment: Alignment.centerLeft,
                      child: const CsChip('New record', kind: CsChipKind.gold, icon: Symbols.star_rounded, size: 10),
                    )
                  else
                    BeatFade(
                      beats: b,
                      name: 'record',
                      rise: 0,
                      child: Text(
                        'BEST ${formatThousands(previousBest)}',
                        maxLines: 1,
                        style: t.mono(12, em: 0.12, color: CsColors.ink55),
                      ),
                    ),
                ],
              ),
              // Near miss: "so close" pulls the player straight into Retry.
              if (!newRecord && !victory && previousBest > 0 && result.score >= previousBest * 0.7) ...[
                SizedBox(height: cs(10)),
                BeatFade(
                  beats: b,
                  name: 'soClose',
                  child: BeatGate(
                    beats: b,
                    name: 'soClose',
                    builder: (_, reached, _) => _SoClose(
                      gap: previousBest - result.score,
                      ratio: reached ? result.score / previousBest : 0,
                    ),
                  ),
                ),
              ],
              SizedBox(height: cs(14)),
              RunStatGrid(
                cell: (i, tile) => BeatFade(beats: b, name: 'tile${i.clamp(0, 7)}', child: tile),
                stats: [
                  CsStat('${result.enemiesKilled}', 'Kills'),
                  CsStat('${result.bossesKilled}', 'Bosses'),
                  CsStat('×${result.maxCombo}', 'Max combo'),
                  CsStat('${result.grazeCount}', 'Grazes'),
                  CsStat('${result.missilesFired}', 'Missiles'),
                  CsStat(formatRunTime(result.durationSeconds), 'Time'),
                  CsStat('${result.levelsCleared}', 'Cleared'),
                  CsStat('L${result.stageReached}·W${result.waveReached}', 'Stage'),
                ],
              ),
              if (result.upgrades.isNotEmpty) ...[
                SizedBox(height: cs(12)),
                BeatFade(beats: b, name: 'build', child: _RunBuild(picks: result.upgrades)),
              ],
              SizedBox(height: cs(14)),
              BeatFade(
                beats: b,
                name: 'rewards',
                child: BeatGate(
                  beats: b,
                  name: 'rewards',
                  builder: (_, reached, settled) => _Rewards(
                    coins: widget.runCoinsEarned,
                    xp: widget.runXpEarned,
                    revealed: reached,
                    instant: settled,
                  ),
                ),
              ),
              if (widget.unlockedLevel > 0 || widget.coinsDoubled) ...[
                SizedBox(height: cs(12)),
                BeatFade(
                  beats: b,
                  name: 'notes',
                  child: Wrap(
                    spacing: cs(8),
                    runSpacing: cs(8),
                    children: [
                      if (widget.unlockedLevel > 0)
                        CsChip(
                          'Level ${widget.unlockedLevel} unlocked',
                          kind: CsChipKind.mint,
                          icon: Symbols.lock_open_rounded,
                          size: 10,
                        ),
                      if (widget.coinsDoubled)
                        CsChip(
                          '+${widget.runCoinsEarned} bonus credits claimed',
                          kind: CsChipKind.outline,
                          icon: Symbols.check_rounded,
                          size: 10,
                        ),
                    ],
                  ),
                ),
              ],
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
                label: 'Retry',
                icon: Symbols.replay_rounded,
                onPressed: widget.onRetry,
              ),
              CsButton.secondary(
                label: victory ? 'Campaign' : 'Home',
                onPressed: widget.onExit,
              ),
              // "Watch ad → 2× coins": gating decided by the host screen; the
              // tap handles an ad that isn't loaded yet.
              if (showDouble)
                CsButton.premium(
                  label: 'Watch ad · 2× credits',
                  icon: Symbols.play_arrow_rounded,
                  trailing: Text(
                    '+${widget.runCoinsEarned}',
                    style: t.mono(12, em: 0.06, color: CsColors.onLight, weight: FontWeight.w600),
                  ),
                  onPressed: widget.onDoubleCoins,
                ),
            ],
          ),
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BeatFade(
          beats: b,
          name: 'right',
          rise: 0,
          slideX: 12,
          child: Row(
            children: [
              const Expanded(child: CsLabel('Daily Directives')),
              SizedBox(width: cs(10)),
              if (widget.directives == null) const ChallengeClaimAllButton(),
            ],
          ),
        ),
        SizedBox(height: cs(8)),
        Expanded(
          // Bottom fade while more rows sit below the fold.
          child: ScrollEdgeFade(
            fadeColor: GameOverOverlay._overScrim,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child:
                  widget.directives ??
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChallengePanel(
                        showClaimAll: false,
                        showRunDelta: true,
                        runStartProgress: widget.challengeRunStart,
                        entranceDelay: GameOverOverlay.directivesDelay,
                        reduceMotion: widget.reduceMotion,
                      ),
                      const _AchievementUnlocks(),
                    ],
                  ),
            ),
          ),
        ),
      ],
    );

    return ResultsTapToSkip(
      beats: b,
      child: GameplayOverlayFrame(
        scrim: GameOverOverlay._overScrim,
        washes: [victory ? GameOverOverlay._victoryWash : CsWash.pinkTopLeft],
        child: OverlaySplit(left: left, right: right),
      ),
    );
  }
}

/// "Only 120 from your best": a prism progress line toward the record.
class _SoClose extends StatelessWidget {
  const _SoClose({required this.gap, required this.ratio});
  final int gap;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('SO CLOSE · ONLY $gap FROM YOUR BEST',
            maxLines: 1, style: cs.type.mono(11, em: 0.12, color: CsColors.gold)),
        SizedBox(height: cs(6)),
        CsProgressLine(value: ratio, width: cs(260), height: 3, gradient: CsGradients.prism),
      ],
    );
  }
}

/// The run's build: one chip per drafted upgrade (stacked count).
class _RunBuild extends StatelessWidget {
  const _RunBuild({required this.picks});
  final List<UpgradeId> picks;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final counts = <UpgradeId, int>{};
    for (final id in picks) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return Wrap(
      spacing: cs(6),
      runSpacing: cs(6),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        CsLabel('Build', size: 9),
        for (final e in counts.entries)
          CsChip(
            e.value > 1 ? '${UpgradeCatalog.byId(e.key).name} ×${e.value}' : UpgradeCatalog.byId(e.key).name,
            icon: upgradeIcon(e.key),
          ),
      ],
    );
  }
}

/// "◉ +41 CR   +70 XP" payout line; a tallying state until _submitRun's
/// async write lands and the parent setStates the totals. Once [revealed]
/// (its beat) the amounts roll up from 0, and roll again if they change
/// (2× credits); [instant] shows them without rolling.
class _Rewards extends StatelessWidget {
  const _Rewards({required this.coins, required this.xp, required this.revealed, required this.instant});

  final int coins;
  final int xp;
  final bool revealed;
  final bool instant;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    if (coins <= 0 && xp <= 0) {
      return Text('TALLYING PAYOUT…', style: cs.type.mono(12, em: 0.1, color: CsColors.ink45));
    }
    final coinStyle = cs.type.mono(12, color: CsColors.gold, em: 0.1);
    final xpStyle = cs.type.mono(12, em: 0.1, color: CsColors.violet);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CsCoinGlyph(size: 12 * 1.45),
        SizedBox(width: cs(6)),
        if (revealed)
          RollUpNumber(value: coins, instant: instant, style: coinStyle, format: (v) => '+$v CR')
        else
          Text('+0 CR', style: coinStyle),
        SizedBox(width: cs(18)),
        if (revealed)
          RollUpNumber(value: xp, instant: instant, style: xpStyle, format: (v) => '+$v XP')
        else
          Text('+0 XP', style: xpStyle),
      ],
    );
  }
}

/// This run's achievement unlocks, under the directives.
class _AchievementUnlocks extends StatelessWidget {
  const _AchievementUnlocks();

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ListenableBuilder(
      listenable: AchievementService(),
      builder: (context, _) {
        final unlocks = AchievementService().lastGameUnlocks;
        if (unlocks.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: cs(18)),
            const CsLabel('Commendations earned'),
            SizedBox(height: cs(4)),
            for (final (i, a) in unlocks.indexed)
              CsFadeUp(
                index: i,
                child: CsListRow(
                  title: a.title,
                  leading: CsIconDisc(a.icon, size: 32),
                  titleTrailing: CsChip(a.rarityName, size: 8),
                ),
              ),
          ],
        );
      },
    );
  }
}
