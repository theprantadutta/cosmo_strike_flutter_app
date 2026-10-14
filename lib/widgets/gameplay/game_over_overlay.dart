import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:flutter/material.dart';

import '../../game/run_upgrades.dart';
import 'upgrade_draft_overlay.dart' show upgradeIcon;

import '../../game/cosmo_strike_game.dart';
import '../../services/achievement_service.dart';
import 'challenge_panel.dart';
import 'run_stat_tiles.dart';

/// The end-of-run debrief: a two-region landscape layout that never scrolls
/// on the left.
///
///   LEFT  — pink mono "GAME OVER · L03 / W04" (mint VICTORY on a full
///           campaign clear), the score counting up at 84px + BEST / NEW
///           RECORD, a 4×2 stat grid, +COINS (gold) · +XP (violet), unlock /
///           bonus notes, then RETRY · HOME/CAMPAIGN · 2× COINS.
///   RIGHT — today's directives with CLAIM pills + the prism CLAIM ALL chip,
///           then this run's achievement unlocks (the only scrollable).
///
/// Coins / XP / challenge progress / achievements all land async after
/// `_submitRun` and rebuild reactively.
class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({
    super.key,
    required this.result,
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
  });

  final GameResult result;
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

  static const _victoryWash = CsWash(CsColors.mint, .2, .3, rx: .4, ry: .7, alpha: .12);
  static const _overScrim = Color(0xF20A0A0D);

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final newRecord = result.score > previousBest;
    final accent = victory ? CsColors.mint : CsColors.pink;
    final lv = result.stageReached.toString().padLeft(2, '0');
    final wv = result.waveReached.toString().padLeft(2, '0');
    final showDouble = !coinsDoubled && canDoubleCoins;

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: CsFitColumn(
            children: [
              CsLabel('${victory ? 'Victory' : 'Game over'} · L$lv / W$wv', color: accent),
              SizedBox(height: cs(10)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: CsCountUp(value: result.score, style: t.scoreGiant),
                    ),
                  ),
                  SizedBox(width: cs(18)),
                  if (newRecord)
                    const CsChip('New record', kind: CsChipKind.gold, icon: Symbols.star_rounded, size: 10)
                  else
                    Text(
                      'BEST $previousBest',
                      maxLines: 1,
                      style: t.mono(12, em: 0.12, color: CsColors.ink55),
                    ),
                ],
              ),
              // Near miss: "so close" pulls the player straight into Retry.
              if (!newRecord && !victory && previousBest > 0 && result.score >= previousBest * 0.7) ...[
                SizedBox(height: cs(10)),
                _SoClose(gap: previousBest - result.score, ratio: result.score / previousBest),
              ],
              SizedBox(height: cs(14)),
              CsStatGrid(
                columns: 4,
                valueSize: 20,
                labelSize: 9,
                cellPadding: 10,
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
                _RunBuild(picks: result.upgrades),
              ],
              SizedBox(height: cs(14)),
              _Rewards(coins: runCoinsEarned, xp: runXpEarned),
              if (unlockedLevel > 0 || coinsDoubled) ...[
                SizedBox(height: cs(12)),
                Wrap(
                  spacing: cs(8),
                  runSpacing: cs(8),
                  children: [
                    if (unlockedLevel > 0)
                      CsChip(
                        'Level $unlockedLevel unlocked',
                        kind: CsChipKind.mint,
                        icon: Symbols.lock_open_rounded,
                        size: 10,
                      ),
                    if (coinsDoubled)
                      CsChip(
                        '+$runCoinsEarned bonus coins claimed',
                        kind: CsChipKind.outline,
                        icon: Symbols.check_rounded,
                        size: 10,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: cs(16)),
        OverlayActions(
          children: [
            CsButton.primary(
              label: 'Retry',
              icon: Symbols.replay_rounded,
              onPressed: onRetry,
            ),
            CsButton.secondary(
              label: victory ? 'Campaign' : 'Home',
              onPressed: onExit,
            ),
            // "Watch ad → 2× coins": gating decided by the host screen; the
            // tap handles an ad that isn't loaded yet.
            if (showDouble)
              CsButton.premium(
                label: 'Watch ad · 2× coins',
                icon: Symbols.play_arrow_rounded,
                trailing: Text(
                  '+$runCoinsEarned',
                  style: t.mono(12, em: 0.06, color: CsColors.onLight, weight: FontWeight.w600),
                ),
                onPressed: onDoubleCoins,
              ),
          ],
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: CsLabel('Daily directives')),
            SizedBox(width: cs(10)),
            const ChallengeClaimAllButton(),
          ],
        ),
        SizedBox(height: cs(8)),
        Expanded(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ChallengePanel(
                  showClaimAll: false,
                  showRunDelta: true,
                  runStartProgress: challengeRunStart,
                ),
                const _AchievementUnlocks(),
              ],
            ),
          ),
        ),
      ],
    );

    return GameplayOverlayFrame(
      scrim: _overScrim,
      washes: [victory ? _victoryWash : CsWash.pinkTopLeft],
      child: OverlaySplit(left: left, right: right),
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

/// "◉ +41 COINS   +70 XP" payout line; a tallying state until _submitRun's
/// async write lands and the parent setStates the totals.
class _Rewards extends StatelessWidget {
  const _Rewards({required this.coins, required this.xp});

  final int coins;
  final int xp;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    if (coins <= 0 && xp <= 0) {
      return Text('TALLYING REWARDS…', style: cs.type.mono(12, em: 0.1, color: CsColors.ink45));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CsCoins(coins, prefix: '+', suffix: ' COINS', size: 12),
        SizedBox(width: cs(18)),
        Text('+$xp XP', style: cs.type.mono(12, em: 0.1, color: CsColors.violet)),
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
            const CsLabel('Achievements unlocked'),
            SizedBox(height: cs(4)),
            for (final a in unlocks)
              CsListRow(
                title: a.title,
                leading: CsIconDisc(a.icon, size: 32),
                titleTrailing: CsChip(a.rarityName, size: 8),
              ),
          ],
        );
      },
    );
  }
}
