import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/cosmo_palette.dart';
import '../../models/daily_challenge.dart';
import '../../providers/daily_challenges_provider.dart';
import '../../ui/design.dart';
import '../../utils/constants.dart';
import '../reward_toast.dart';
import 'run_stat_tiles.dart';

/// Today's daily challenges ("directives") for the pause / game-over
/// overlays: live progress bars, optional "+N THIS RUN" deltas and inline
/// CLAIM buttons. Renders as a shrink-wrapped column so the caller embeds
/// it in whichever scrollable owns the right-hand region.
///
/// Watches [dailyChallengesProvider], so claims and the post-run progress
/// feed (which lands async from `_submitRun`) rebuild the rows live.
class ChallengePanel extends ConsumerWidget {
  const ChallengePanel({
    super.key,
    this.showRunDelta = false,
    this.runStartProgress,
    this.showClaimAll = true,
  });

  /// Show a gold "+N THIS RUN" tag per challenge this run advanced.
  final bool showRunDelta;

  /// Render the in-panel "CLAIM ALL" button. Off when the caller hoists it into
  /// a header instead (see [ChallengeClaimAllButton]).
  final bool showClaimAll;

  /// Per-challenge progress snapshot taken at run start (id → progress);
  /// the delta tags render against this.
  final Map<String, int>? runStartProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dailyChallengesProvider);

    if (state.isLoading && state.challenges.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(CosmoPalette.hull),
            ),
          ),
        ),
      );
    }

    if (state.challenges.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              Icons.satellite_alt,
              size: 26,
              color: CosmoPalette.hull.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'NO ACTIVE DIRECTIVES\nRECONNECT TO SYNC',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CosmoPalette.hull.withValues(alpha: 0.55),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    final claimable = state.challenges.where((c) => c.canClaim).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showClaimAll && claimable > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: GameTokens.space12),
            child: NeonButton(
              label: 'CLAIM ALL ($claimable)',
              onPressed: () async {
                final total = await ref
                    .read(dailyChallengesProvider.notifier)
                    .claimAllRewards();
                if (total > 0) {
                  RewardToast.show(
                    title: 'ALL DIRECTIVES CLAIMED',
                    amount: '+$total COINS',
                  );
                }
              },
              theme: GameTheme.classic,
              height: 30,
              width: 168,
            ),
          ),
        for (final c in state.challenges)
          Padding(
            padding: const EdgeInsets.only(bottom: GameTokens.space8),
            child: _ChallengeRow(
              challenge: c,
              runDelta: showRunDelta
                  ? (c.currentProgress - (runStartProgress?[c.id] ?? c.currentProgress))
                      .clamp(0, c.currentProgress)
                  : 0,
              onClaim: () async {
                final ok = await ref
                    .read(dailyChallengesProvider.notifier)
                    .claimReward(c.id);
                if (ok) {
                  RewardToast.show(
                    title: 'DIRECTIVE COMPLETE',
                    amount: '+${c.coinReward} COINS · +${c.xpReward} XP',
                  );
                }
              },
            ),
          ),
      ],
    );
  }
}

/// Compact "CLAIM ALL (n)" action made to sit inline in a section header
/// (paired with `ChallengePanel(showClaimAll: false)`). Renders nothing when
/// there's nothing to claim, and watches the provider so it appears/disappears
/// live as directives complete and get claimed.
class ChallengeClaimAllButton extends ConsumerWidget {
  const ChallengeClaimAllButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dailyChallengesProvider);
    final claimable = state.challenges.where((c) => c.canClaim).length;
    if (claimable == 0) return const SizedBox.shrink();
    return NeonButton(
      label: 'CLAIM ALL ($claimable)',
      onPressed: () async {
        final total =
            await ref.read(dailyChallengesProvider.notifier).claimAllRewards();
        if (total > 0) {
          RewardToast.show(
            title: 'ALL DIRECTIVES CLAIMED',
            amount: '+$total COINS',
          );
        }
      },
      theme: GameTheme.classic,
      height: 28,
      width: 150,
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({
    required this.challenge,
    required this.runDelta,
    required this.onClaim,
  });

  final DailyChallenge challenge;
  final int runDelta;
  final VoidCallback onClaim;

  static const Color _gold = Color(0xFFFFD37B);

  Color get _accent => switch (challenge.difficulty) {
        ChallengeDifficulty.easy => CosmoPalette.boon,
        ChallengeDifficulty.medium => _gold,
        ChallengeDifficulty.hard => CosmoPalette.hostile,
      };

  @override
  Widget build(BuildContext context) {
    final claimed = challenge.claimedReward;
    final muted = claimed ? 0.45 : 1.0;

    final count = '${challenge.currentProgress.clamp(0, challenge.targetValue)}'
        ' / ${challenge.targetValue}';

    // Single compact LINE per directive — the directives half is wide but
    // vertically tight, so a one-line row (title · bar · count · action) lets
    // all of the day's directives fit without scrolling.
    return Opacity(
      opacity: muted,
      child: Row(
        children: [
          // Difficulty dot — the row's only "chrome".
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent,
              boxShadow: softGlow(_accent, intensity: 0.6),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              challenge.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CosmoPalette.highlight,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: SlimBar(
              value: challenge.progressPercentage,
              color: challenge.isCompleted ? CosmoPalette.boon : _accent,
            ),
          ),
          const SizedBox(width: 8),
          // Count, with this run's gain folded inline as a compact gold "+N"
          // so it costs no extra row width.
          Text.rich(
            TextSpan(
              text: count,
              style: TextStyle(
                color: CosmoPalette.hull.withValues(alpha: 0.8),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
              children: runDelta > 0
                  ? [
                      const TextSpan(
                        text: '  +',
                        style: TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: '$runDelta',
                        style: const TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          // Trailing action (natural width so the title absorbs the slack):
          // CLAIM when ready, a claimed tick once taken, or the prize while
          // still in progress.
          _trailing(claimed),
        ],
      ),
    );
  }

  Widget _trailing(bool claimed) {
    if (challenge.canClaim) {
      return _ClaimChip(onTap: onClaim);
    }
    if (claimed) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 14, color: CosmoPalette.boon),
          SizedBox(width: 4),
          Text(
            'CLAIMED',
            style: TextStyle(
              color: CosmoPalette.boon,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        ],
      );
    }
    return Text(
      '+${challenge.coinReward}c·${challenge.xpReward}xp',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: TextStyle(
        color: _gold.withValues(alpha: 0.9),
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    );
  }
}

/// Compact inline CLAIM pill for a one-line directive row. A full [NeonButton]
/// is too chunky here — its fixed padding truncates the label at this size — so
/// this is a small natural-width gradient chip that fits "CLAIM" cleanly.
class _ClaimChip extends StatelessWidget {
  const _ClaimChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = GameTheme.classic;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.neonPrimary, theme.neonSecondary],
          ),
          borderRadius: BorderRadius.circular(7),
          boxShadow: softGlow(theme.neonPrimary, intensity: 0.4),
        ),
        child: const Text(
          'CLAIM',
          style: TextStyle(
            color: Color(0xFF03040A),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}
