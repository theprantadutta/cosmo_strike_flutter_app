import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart' show ChallengeDifficulty;
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/models/weekly_quest.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/weekly_quest_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';

class WeeklyQuestsScreen extends StatefulWidget {
  const WeeklyQuestsScreen({super.key});

  @override
  State<WeeklyQuestsScreen> createState() => _WeeklyQuestsScreenState();
}

class _WeeklyQuestsScreenState extends State<WeeklyQuestsScreen> {
  final WeeklyQuestService _service = WeeklyQuestService();
  final AudioService _audioService = AudioService();

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

    HapticFeedback.mediumImpact();
    _audioService.playSound('coin_collect');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Row(
          children: [
            const Icon(Icons.monetization_on, color: Colors.amber),
            const SizedBox(width: 8),
            Text('+${quest.coinReward} coins, +${quest.battlePassXpReward} BP XP'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;
        return ListenableBuilder(
          listenable: _service,
          builder: (context, _) {
            return Scaffold(
              bottomNavigationBar: const ShipBannerAd(),
              body: AppBackground(
                theme: theme,
                child: SafeArea(
                  child: Column(
                    children: [
                      _Header(theme: theme),
                      _SummaryStrip(theme: theme, service: _service),
                      Expanded(
                        child: _service.isLoading && _service.quests.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : RefreshIndicator(
                                onRefresh: _service.refresh,
                                child: _service.quests.isEmpty
                                    ? Center(
                                        child: Text(
                                          "No weekly quests yet — check back Monday",
                                          style: TextStyle(
                                              color: theme.accentColor
                                                  .withValues(alpha: 0.7)),
                                        ),
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        itemCount: _service.quests.length,
                                        itemBuilder: (context, i) {
                                          final quest = _service.quests[i];
                                          return _QuestCard(
                                            quest: quest,
                                            theme: theme,
                                            onClaim: () => _claimReward(quest),
                                          );
                                        },
                                      ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final GameTheme theme;
  const _Header({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: theme.accentColor, size: 20),
          ),
          const SizedBox(width: 4),
          Text(
            'Weekly Quests',
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Icon(Icons.calendar_view_week, color: theme.accentColor),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final GameTheme theme;
  final WeeklyQuestService service;
  const _SummaryStrip({required this.theme, required this.service});

  @override
  Widget build(BuildContext context) {
    final claimable = service.claimableCount;
    final completed = service.completedCount;
    final total = service.quests.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.08),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_rounded, color: theme.accentColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$completed / $total complete'
              '${claimable > 0 ? '   •   $claimable claimable' : ''}',
              style: TextStyle(
                color: theme.accentColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestCard extends StatelessWidget {
  final WeeklyQuest quest;
  final GameTheme theme;
  final VoidCallback onClaim;
  const _QuestCard(
      {required this.quest, required this.theme, required this.onClaim});

  Color _difficultyColor() {
    switch (quest.difficulty) {
      case ChallengeDifficulty.easy:
        return Colors.green;
      case ChallengeDifficulty.medium:
        return Colors.amber;
      case ChallengeDifficulty.hard:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = quest.progressPercentage;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _difficultyColor().withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _difficultyColor().withValues(alpha: 0.6)),
                ),
                child: Text(
                  quest.difficulty.displayName,
                  style: TextStyle(
                    color: _difficultyColor(),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  quest.title,
                  style: TextStyle(
                    color: theme.accentColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            quest.description,
            style: TextStyle(
              color: theme.accentColor.withValues(alpha: 0.75),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor:
                  theme.accentColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(_difficultyColor()),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${quest.currentProgress} / ${quest.targetValue}',
                style: TextStyle(
                  color: theme.accentColor.withValues(alpha: 0.85),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              const Icon(Icons.monetization_on,
                  color: Colors.amber, size: 14),
              const SizedBox(width: 4),
              Text(
                '${quest.coinReward}',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.star, color: Colors.blueAccent.shade100, size: 14),
              const SizedBox(width: 4),
              Text(
                '${quest.battlePassXpReward} XP',
                style: TextStyle(
                  color: Colors.blueAccent.shade100,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (quest.canClaim)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onClaim,
                  icon: const Icon(Icons.card_giftcard, size: 16),
                  label: const Text('Claim Reward'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            )
          else if (quest.claimedReward)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Colors.green, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Claimed',
                    style: TextStyle(
                      color: Colors.green.shade300,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
