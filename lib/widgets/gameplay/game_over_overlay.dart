import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../game/cosmo_palette.dart';
import '../../game/cosmo_strike_game.dart';
import '../../presentation/bloc/premium/battle_pass_cubit.dart';
import '../../services/achievement_service.dart';
import '../../ui/design.dart';
import 'challenge_panel.dart';
import 'run_stat_tiles.dart';

/// The end-of-run debrief: full telemetry grid with best-score comparison,
/// coin/XP payout (+ the watch-ad 2× offer), battle-pass progress, and a
/// right-hand panel of daily directives (with this run's deltas + claims)
/// and any achievements unlocked this run.
///
/// Everything that lands async after `_submitRun` (coins, XP flush,
/// challenge progress, achievement unlocks) rebuilds reactively — the
/// parent setStates coins/XP, challenges ride the Riverpod provider, the
/// battle-pass bar a BlocBuilder, achievements a ListenableBuilder.
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
              color: const Color(0xFF05060F).withValues(alpha: 0.78),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GameTokens.space24,
              vertical: GameTokens.space16,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // LEFT — debrief telemetry. Scales down, never scrolls.
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
                            width: 400,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  victory ? 'VICTORY' : 'GAME OVER',
                                  style: TextStyle(
                                    color: _accent,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 4,
                                    shadows: [
                                      Shadow(
                                        color: _accent.withValues(alpha: 0.75),
                                        blurRadius: 18,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      '${result.score}',
                                      style: const TextStyle(
                                        color: CosmoPalette.highlight,
                                        fontSize: 34,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (newRecord)
                                      _NewRecordBadge()
                                    else
                                      Text(
                                        'BEST $previousBest',
                                        style: TextStyle(
                                          color: CosmoPalette.hull
                                              .withValues(alpha: 0.7),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.6,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: GameTokens.space16),
                                Wrap(
                                  spacing: GameTokens.space16,
                                  runSpacing: GameTokens.space12,
                                  children: [
                                    RunStatTile(
                                      icon: Icons.flag,
                                      value:
                                          'L${result.stageReached} · W${result.waveReached}',
                                      label: 'LEVEL · WAVE',
                                    ),
                                    RunStatTile(
                                      icon: Icons.gps_fixed,
                                      value: '${result.enemiesKilled}',
                                      label: 'KILLS',
                                    ),
                                    RunStatTile(
                                      icon: Icons.adjust,
                                      value: '${result.bossesKilled}',
                                      label: 'BOSSES',
                                    ),
                                    RunStatTile(
                                      icon: Icons.bolt,
                                      value: '×${result.maxCombo}',
                                      label: 'MAX COMBO',
                                    ),
                                    RunStatTile(
                                      icon: Icons.shield_moon,
                                      value: '${result.grazeCount}',
                                      label: 'GRAZES',
                                    ),
                                    RunStatTile(
                                      icon: Icons.rocket,
                                      value: '${result.missilesFired}',
                                      label: 'MISSILES',
                                    ),
                                    RunStatTile(
                                      icon: Icons.timer,
                                      value: _time,
                                      label: 'TIME',
                                    ),
                                    RunStatTile(
                                      icon: Icons.military_tech,
                                      value: '${result.levelsCleared}',
                                      label: 'LEVELS CLEARED',
                                    ),
                                  ],
                                ),
                                if (unlockedLevel > 0) ...[
                                  const SizedBox(height: GameTokens.space12),
                                  Text(
                                    'LEVEL $unlockedLevel UNLOCKED',
                                    style: TextStyle(
                                      color: _gold,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2,
                                      shadows: [
                                        Shadow(
                                          color: _gold.withValues(alpha: 0.7),
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: GameTokens.space16),
                                _RewardsRow(
                                  coins: runCoinsEarned,
                                  xp: runXpEarned,
                                ),
                                if (coinsDoubled) ...[
                                  const SizedBox(height: GameTokens.space8),
                                  Text(
                                    '+$runCoinsEarned BONUS COINS CLAIMED',
                                    style: const TextStyle(
                                      color: _gold,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                ] else if (canDoubleCoins) ...[
                                  const SizedBox(height: GameTokens.space12),
                                  OverlayActionButton(
                                    label:
                                        '▶ WATCH AD: 2× COINS (+$runCoinsEarned)',
                                    onTap: onDoubleCoins,
                                    variant: NeonButtonVariant.outline,
                                    expand: false,
                                  ),
                                ],
                                const SizedBox(height: GameTokens.space16),
                                _BattlePassStrip(runXpEarned: runXpEarned),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: GameTokens.space12),
                      Row(
                        children: [
                          Expanded(
                            child: OverlayActionButton(
                              label: 'RETRY',
                              onTap: onRetry,
                            ),
                          ),
                          const SizedBox(width: GameTokens.space8),
                          Expanded(
                            child: OverlayActionButton(
                              label: victory ? 'CAMPAIGN' : 'HOME',
                              onTap: onExit,
                              variant: NeonButtonVariant.outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: GameTokens.space24),
                // RIGHT — directives + unlocks (single scrollable).
                Expanded(
                  flex: 9,
                  child: ListView(
                    children: [
                      const SectionHeader('DAILY DIRECTIVES'),
                      const SizedBox(height: GameTokens.space12),
                      ChallengePanel(
                        showRunDelta: true,
                        runStartProgress: challengeRunStart,
                      ),
                      ListenableBuilder(
                        listenable: AchievementService(),
                        builder: (context, _) {
                          final unlocks = AchievementService().lastGameUnlocks;
                          if (unlocks.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: GameTokens.space12),
                              const SectionHeader('ACHIEVEMENTS UNLOCKED'),
                              const SizedBox(height: GameTokens.space12),
                              for (final a in unlocks)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: GameTokens.space12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 34,
                                        height: 34,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: a.rarityColor
                                              .withValues(alpha: 0.14),
                                          boxShadow: softGlow(a.rarityColor,
                                              intensity: 0.6),
                                        ),
                                        child: Icon(a.icon,
                                            size: 17, color: a.rarityColor),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                ),
              ],
            ),
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

/// "+N COINS · +M XP" payout line; shows a tallying state until
/// _submitRun's async write lands and the parent setStates the totals.
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
        const Icon(Icons.monetization_on,
            size: 16, color: GameOverOverlay._gold),
        const SizedBox(width: 5),
        Text(
          '+$coins COINS',
          style: const TextStyle(
            color: GameOverOverlay._gold,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 14),
        const Icon(Icons.auto_awesome, size: 15, color: CosmoPalette.energy),
        const SizedBox(width: 5),
        Text(
          '+$xp XP',
          style: const TextStyle(
            color: CosmoPalette.energy,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Battle-pass tier bar — rebuilds live when flushXP lands.
class _BattlePassStrip extends StatelessWidget {
  const _BattlePassStrip({required this.runXpEarned});

  final int runXpEarned;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BattlePassCubit, BattlePassState>(
      builder: (context, state) {
        if (!state.isActive) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SectionHeader('PASS TIER ${state.currentTier}'),
                const Spacer(),
                if (runXpEarned > 0)
                  Text(
                    '+$runXpEarned XP',
                    style: const TextStyle(
                      color: CosmoPalette.energy,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: state.tierProgress),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => SlimBar(value: v),
            ),
          ],
        );
      },
    );
  }
}
