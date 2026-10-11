import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/models/weekly_quest.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/screens/daily_challenges_screen.dart'
    show ChallengeRow, ChallengeSummary;
import 'package:cosmo_strike_flutter_app/services/weekly_quest_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/reward_toast.dart';

/// The Weekly tab of the challenges hub (ChallengesHubScreen owns the
/// CsScaffold + tab chrome; this renders only the two-region body).
/// Mirrors DailyChallengesBody: LEFT = the week's progress ring + rules,
/// RIGHT = the hairline-separated quest list.
class WeeklyQuestsBody extends StatefulWidget {
  const WeeklyQuestsBody({super.key});

  @override
  State<WeeklyQuestsBody> createState() => _WeeklyQuestsBodyState();
}

class _WeeklyQuestsBodyState extends State<WeeklyQuestsBody> {
  final WeeklyQuestService _service = WeeklyQuestService();

  @override
  void initState() {
    super.initState();
    // initialize() no-ops if already loaded; refresh() is the explicit
    // user-pull-to-refresh path.
    WidgetsBinding.instance.addPostFrameCallback((_) => _service.initialize());
  }

  Future<void> _claimReward(WeeklyQuest quest) async {
    final success = await _service.claimReward(quest.id);
    if (!success || !mounted) return;

    // Mirror DailyChallenge: server credits coins/BP XP atomically, but we
    // also poke the CoinsCubit so the in-app balance reflects immediately
    // (next backend refresh will reconcile if the server amount differs).
    context.read<CoinsCubit>().earnCoins(
      CoinEarningSource.dailyChallenge, // closest existing source
      customAmount: quest.coinReward,
      itemName: quest.title,
      metadata: {
        'questId': quest.id,
        'battlePassXp': quest.battlePassXpReward,
        'difficulty': quest.difficulty.name,
      },
    );

    // The toast brings its own coin sound + haptic.
    RewardToast.show(
      title: 'QUEST COMPLETE',
      amount: '+${quest.coinReward} COINS · +${quest.battlePassXpReward} BP XP',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final cs = context.cs;
        final quests = _service.quests;
        final claimable = _service.claimableCount;

        return CsSplit(
          left: ChallengeSummary(
            completed: _service.completedCount,
            total: quests.length,
            ringLabel: 'This week',
            note: claimable > 0
                ? CsMeta(
                    '$claimable reward${claimable == 1 ? '' : 's'} ready to claim',
                    color: CsColors.mint,
                    icon: Symbols.redeem_rounded,
                  )
                : null,
            rules: const [
              'New quests every Monday',
              'Bigger goals, bigger coin rewards',
              'Quests grant Battle Pass XP too',
            ],
          ),
          right: _service.isLoading && quests.isEmpty
              ? const CsLoadingState(label: 'Loading quests')
              : RefreshIndicator(
                  onRefresh: _service.refresh,
                  color: CsColors.ink,
                  backgroundColor: CsColors.raised,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      if (quests.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: c.maxHeight,
                              child: const CsEmptyState(
                                icon: Symbols.event_repeat_rounded,
                                title: 'No weekly quests yet',
                                message: 'Check back Monday for a new set.',
                              ),
                            ),
                          ],
                        );
                      }
                      return ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(bottom: cs(12)),
                        itemCount: quests.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) return const CsHairline();
                          final quest = quests[i - 1];
                          return ChallengeRow(
                            title: quest.title,
                            description: quest.description,
                            difficulty: quest.difficulty,
                            currentProgress: quest.currentProgress,
                            targetValue: quest.targetValue,
                            progress: quest.progressPercentage,
                            isCompleted: quest.isCompleted,
                            claimed: quest.claimedReward,
                            canClaim: quest.canClaim,
                            coinReward: quest.coinReward,
                            xpReward: quest.battlePassXpReward,
                            xpUnit: ' BP XP',
                            onClaim: () => _claimReward(quest),
                          );
                        },
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}
