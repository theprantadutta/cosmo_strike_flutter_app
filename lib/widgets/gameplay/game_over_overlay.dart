import 'package:flutter/material.dart';

import '../../game/cosmo_palette.dart';
import '../../game/cosmo_strike_game.dart';
import '../../services/achievement_service.dart';
import '../../ui/design.dart';
import '../../utils/constants.dart';
import 'challenge_panel.dart';
import 'run_stat_tiles.dart';

/// The end-of-run debrief, designed for the wide-short landscape viewport as a
/// fixed three-band layout that NEVER scrolls:
///
///   ┌─────────────────────────────────────────────┐
///   │ VERDICT · SCORE                +COINS · +XP  │  headline (full width)
///   ├──────────────────────┬──────────────────────┤
///   │ TELEMETRY            │ DAILY DIRECTIVES      │  body (50 / 50)
///   │ (8-stat grid)        │ (challenges + unlocks)│
///   ├──────────────────────┴──────────────────────┤
///   │ 2× COINS  ·  RETRY  ·  HOME                  │  actions (full width)
///   └─────────────────────────────────────────────┘
///
/// Each body half fills its space at natural size; a `FittedBox(scaleDown)`
/// only kicks in on unusually small screens so nothing ever scrolls or
/// overflows. Coins / XP / challenge progress / achievements all land async
/// after `_submitRun` and rebuild reactively.
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

  static const Color _gold = Color(0xFFFFD37B);

  Color get _accent => victory ? _gold : CosmoPalette.hostile;

  String get _time {
    final m = result.durationSeconds ~/ 60;
    final s = (result.durationSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final newRecord = result.score > previousBest;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Container(
              color: const Color(0xFF05060F).withValues(alpha: 0.84),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GameTokens.space20,
              vertical: 10,
            ),
            child: Column(
              children: [
                _headline(newRecord),
                const SizedBox(height: 12),
                // 50 / 50 content split. Each half fills its space; nothing
                // scrolls.
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _telemetry()),
                      const SizedBox(width: GameTokens.space24),
                      Expanded(child: _directives()),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _footer(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Full-width headline: verdict + score on the left, this run's payout (and
  /// unlock / claimed flourish) on the right. Compact so the body gets the
  /// height it needs.
  Widget _headline(bool newRecord) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                victory ? 'VICTORY' : 'GAME OVER',
                style: TextStyle(
                  color: _accent,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  shadows: [
                    Shadow(color: _accent.withValues(alpha: 0.7), blurRadius: 16),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${result.score}',
                    style: const TextStyle(
                      color: CosmoPalette.highlight,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (newRecord)
                    _NewRecordBadge()
                  else
                    Text(
                      'BEST $previousBest',
                      style: TextStyle(
                        color: CosmoPalette.hull.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: GameTokens.space16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _RewardsRow(coins: runCoinsEarned, xp: runXpEarned),
            if (unlockedLevel > 0) ...[
              const SizedBox(height: 5),
              Text(
                'LEVEL $unlockedLevel UNLOCKED',
                style: TextStyle(
                  color: _gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  shadows: [
                    Shadow(color: _gold.withValues(alpha: 0.7), blurRadius: 12),
                  ],
                ),
              ),
            ],
            if (coinsDoubled) ...[
              const SizedBox(height: 5),
              Text(
                '✦ +$runCoinsEarned BONUS COINS CLAIMED',
                style: const TextStyle(
                  color: _gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// LEFT half — telemetry: the 8 run stats in a responsive 3-column grid
  /// (columns sized to the width, so tiles never get cramped).
  Widget _telemetry() {
    return _Region(
      header: 'TELEMETRY',
      builder: (w) {
        const spacing = GameTokens.space12;
        final tileW = (w - spacing * 2) / 3;
        return Wrap(
          spacing: spacing,
          runSpacing: 14,
          children: [
            RunStatTile(
                width: tileW,
                icon: Icons.flag,
                value: 'L${result.stageReached}·W${result.waveReached}',
                label: 'STAGE'),
            RunStatTile(
                width: tileW,
                icon: Icons.gps_fixed,
                value: '${result.enemiesKilled}',
                label: 'KILLS'),
            RunStatTile(
                width: tileW,
                icon: Icons.adjust,
                value: '${result.bossesKilled}',
                label: 'BOSSES'),
            RunStatTile(
                width: tileW,
                icon: Icons.bolt,
                value: '×${result.maxCombo}',
                label: 'COMBO'),
            RunStatTile(
                width: tileW,
                icon: Icons.shield_moon,
                value: '${result.grazeCount}',
                label: 'GRAZES'),
            RunStatTile(
                width: tileW,
                icon: Icons.rocket,
                value: '${result.missilesFired}',
                label: 'MISSILES'),
            RunStatTile(
                width: tileW, icon: Icons.timer, value: _time, label: 'TIME'),
            RunStatTile(
                width: tileW,
                icon: Icons.military_tech,
                value: '${result.levelsCleared}',
                label: 'CLEARED'),
          ],
        );
      },
    );
  }

  /// RIGHT half — today's directives + this run's achievement unlocks.
  Widget _directives() {
    return _Region(
      header: 'DAILY DIRECTIVES',
      builder: (w) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ChallengePanel(
            showRunDelta: true,
            runStartProgress: challengeRunStart,
          ),
          ListenableBuilder(
            listenable: AchievementService(),
            builder: (context, _) {
              final unlocks = AchievementService().lastGameUnlocks;
              if (unlocks.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: GameTokens.space8),
                  const SectionHeader('ACHIEVEMENTS UNLOCKED'),
                  const SizedBox(height: GameTokens.space12),
                  for (final a in unlocks)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: GameTokens.space12),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: a.rarityColor.withValues(alpha: 0.14),
                              boxShadow:
                                  softGlow(a.rarityColor, intensity: 0.6),
                            ),
                            child:
                                Icon(a.icon, size: 17, color: a.rarityColor),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: CosmoPalette.highlight,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  a.rarityName.toUpperCase(),
                                  style: TextStyle(
                                    color: a.rarityColor,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Full-width action bar: the gold "2× coins" rewarded offer (widest, so it's
  /// the most visible CTA) beside the large RETRY / HOME actions.
  Widget _footer() {
    final showDouble = !coinsDoubled && canDoubleCoins;
    return Row(
      children: [
        if (showDouble) ...[
          Expanded(
            flex: 4,
            child:
                _DoubleCoinsButton(amount: runCoinsEarned, onTap: onDoubleCoins),
          ),
          const SizedBox(width: GameTokens.space12),
        ],
        Expanded(
          flex: 3,
          child: NeonButton(
            label: 'RETRY',
            icon: Icons.refresh,
            onPressed: onRetry,
            theme: GameTheme.classic,
            height: 52,
            expand: true,
          ),
        ),
        const SizedBox(width: GameTokens.space12),
        Expanded(
          flex: 3,
          child: NeonButton(
            label: victory ? 'CAMPAIGN' : 'HOME',
            icon: victory ? Icons.grid_view : Icons.home,
            onPressed: onExit,
            theme: GameTheme.classic,
            variant: NeonButtonVariant.outline,
            height: 52,
            expand: true,
          ),
        ),
      ],
    );
  }
}

/// A debrief body half: an uppercase header over content that FILLS the
/// region's width at natural size. A [FittedBox] only scales the content down
/// on unusually small screens — it never scrolls. The [builder] gets the
/// region width so grids can size their columns to it (responsive).
class _Region extends StatelessWidget {
  const _Region({required this.header, required this.builder});

  final String header;
  final Widget Function(double width) builder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(header),
        const SizedBox(height: 10),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SizedBox(width: w, child: builder(w)),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Pulsing gold NEW RECORD badge.
class _NewRecordBadge extends StatefulWidget {
  @override
  State<_NewRecordBadge> createState() => _NewRecordBadgeState();
}

class _NewRecordBadgeState extends State<_NewRecordBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gold = GameOverOverlay._gold;
    return FadeTransition(
      opacity: Tween(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Text(
        '★ NEW RECORD',
        style: TextStyle(
          color: gold,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.8,
          shadows: [
            Shadow(color: gold.withValues(alpha: 0.8), blurRadius: 12),
          ],
        ),
      ),
    );
  }
}

/// "+N COINS · +M XP" payout line; shows a tallying state until _submitRun's
/// async write lands and the parent setStates the totals.
class _RewardsRow extends StatelessWidget {
  const _RewardsRow({required this.coins, required this.xp});

  final int coins;
  final int xp;

  @override
  Widget build(BuildContext context) {
    if (coins <= 0 && xp <= 0) {
      return Text(
        'TALLYING REWARDS…',
        style: TextStyle(
          color: CosmoPalette.hull.withValues(alpha: 0.55),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.monetization_on, size: 18, color: GameOverOverlay._gold),
        const SizedBox(width: 5),
        Text(
          '+$coins COINS',
          style: const TextStyle(
            color: GameOverOverlay._gold,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 14),
        const Icon(Icons.auto_awesome, size: 16, color: CosmoPalette.energy),
        const SizedBox(width: 5),
        Text(
          '+$xp XP',
          style: const TextStyle(
            color: CosmoPalette.energy,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// The gold "watch ad → 2× coins" offer: a full-width, pulsing, glowing bar so
/// it's the most eye-catching button on the debrief. Gating ([canDoubleCoins])
/// is decided by the host screen; the tap handles an ad that isn't loaded yet.
class _DoubleCoinsButton extends StatefulWidget {
  const _DoubleCoinsButton({required this.amount, required this.onTap});

  final int amount;
  final VoidCallback onTap;

  @override
  State<_DoubleCoinsButton> createState() => _DoubleCoinsButtonState();
}

class _DoubleCoinsButtonState extends State<_DoubleCoinsButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gold = GameOverOverlay._gold;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final g = _c.value;
          return Container(
            height: 52,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: gold.withValues(alpha: 0.16 + 0.07 * g),
              borderRadius: GameTokens.brMd,
              boxShadow: softGlow(gold, intensity: 0.35 + 0.5 * g),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.monetization_on, color: gold, size: 22),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    'WATCH AD · 2× COINS (+${widget.amount})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: gold,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
