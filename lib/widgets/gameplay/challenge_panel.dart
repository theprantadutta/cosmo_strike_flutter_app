import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/daily_challenge.dart';
import '../../providers/daily_challenges_provider.dart';
import '../reward_toast.dart';

/// Today's daily challenges ("directives") for the pause / game-over
/// overlays: hairline-separated rows with a 2px progress line (mint when
/// complete), optional "+N THIS RUN" deltas and inline CLAIM pills. Renders
/// as a shrink-wrapped column so the caller embeds it in whichever
/// scrollable owns the right-hand region.
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
    final cs = context.cs;
    final state = ref.watch(dailyChallengesProvider);

    if (state.isLoading && state.challenges.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: cs(28)),
        child: const CsLoadingState(label: 'Loading directives'),
      );
    }

    if (state.challenges.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: cs(20)),
        child: const CsEmptyState(
          compact: true,
          icon: Symbols.satellite_alt_rounded,
          title: 'No active directives',
          message: 'Reconnect to sync today\'s directives.',
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
            padding: EdgeInsets.only(bottom: cs(12)),
            child: const ChallengeClaimAllButton(),
          ),
        for (final c in state.challenges)
          _ChallengeRow(
            challenge: c,
            runDelta: showRunDelta
                ? (c.currentProgress - (runStartProgress?[c.id] ?? c.currentProgress))
                    .clamp(0, c.currentProgress)
                : 0,
            onClaim: () async {
              final ok = await ref.read(dailyChallengesProvider.notifier).claimReward(c.id);
              if (ok) {
                RewardToast.show(
                  title: 'DIRECTIVE COMPLETE',
                  amount: '+${c.coinReward} COINS · +${c.xpReward} XP',
                );
              }
            },
          ),
      ],
    );
  }
}

/// Prism-outlined "CLAIM ALL · n" chip made to sit inline in a section header
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
    return CsButton.prism(
      label: 'Claim all · $claimable',
      onPressed: () async {
        HapticFeedback.lightImpact();
        final total = await ref.read(dailyChallengesProvider.notifier).claimAllRewards();
        if (total > 0) {
          RewardToast.show(
            title: 'ALL DIRECTIVES CLAIMED',
            amount: '+$total COINS',
          );
        }
      },
    );
  }
}

/// One directive: title + difficulty chip + gold reward on top, a 2px progress
/// line, then the mono count (mint "· COMPLETE" when done, gold "+N THIS RUN"
/// when this run advanced it). CLAIM pill on the right when claimable;
/// claimed rows dim to 45%.
class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({
    required this.challenge,
    required this.runDelta,
    required this.onClaim,
  });

  final DailyChallenge challenge;
  final int runDelta;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final c = challenge;
    final claimed = c.claimedReward;
    final done = c.isCompleted;
    final count = '${c.currentProgress.clamp(0, c.targetValue)} / ${c.targetValue}';

    final status = Text.rich(
      TextSpan(
        text: count,
        children: [
          if (claimed)
            const TextSpan(text: '  ·  CLAIMED')
          else if (done)
            const TextSpan(text: '  ·  COMPLETE'),
          if (runDelta > 0)
            TextSpan(
              text: '  +$runDelta THIS RUN',
              style: const TextStyle(color: CsColors.gold),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.mono(10, em: 0.1, color: done ? CsColors.mint : CsColors.ink45),
    );

    final reward = Text(
      '+${c.coinReward}C · ${c.xpReward}XP',
      maxLines: 1,
      style: t.mono(11, em: 0.06, color: CsColors.gold),
    );

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.rowTitle,
                    ),
                  ),
                  SizedBox(width: cs(8)),
                  CsChip(c.difficulty.name, size: 8),
                ],
              ),
            ),
            // Claimable rows show the reward under the CLAIM pill instead,
            // so the title isn't squeezed to "Casu…" on phones.
            if (!c.canClaim) ...[
              SizedBox(width: cs(10)),
              reward,
            ],
          ],
        ),
        SizedBox(height: cs(8)),
        CsGoalLine(value: c.progressPercentage),
        SizedBox(height: cs(7)),
        status,
      ],
    );

    return Opacity(
      opacity: claimed ? 0.45 : 1,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: cs(11)),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CsColors.hairline)),
        ),
        child: Row(
          children: [
            Expanded(child: body),
            if (c.canClaim) ...[
              SizedBox(width: cs(14)),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                CsButton.primary(
                  label: 'Claim',
                  size: CsButtonSize.small,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onClaim();
                  },
                ),
                SizedBox(height: cs(6)),
                reward,
              ]),
            ] else if (claimed) ...[
              SizedBox(width: cs(14)),
              Icon(Symbols.check_circle_rounded, size: cs(18), color: CsColors.mint),
            ],
          ],
        ),
      ),
    );
  }
}
