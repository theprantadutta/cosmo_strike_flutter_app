import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart'
    show ChallengeDifficulty;
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/models/weekly_quest.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/weekly_quest_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';

/// The Weekly tab of the challenges hub (ChallengesHubScreen owns the
/// CommandScaffold + tab chrome; this renders only the two-region body).
/// Mirrors DailyChallengesBody: LEFT = the week's telemetry ring + hints,
/// RIGHT = the scrollable quest list — all borderless on the starfield.
class WeeklyQuestsBody extends StatefulWidget {
  const WeeklyQuestsBody({super.key});

  @override
  State<WeeklyQuestsBody> createState() => _WeeklyQuestsBodyState();
}

class _WeeklyQuestsBodyState extends State<WeeklyQuestsBody> {
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
            Text(
              '+${quest.coinReward} coins, +${quest.battlePassXpReward} BP XP',
            ),
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
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 4,
                    // Never scrolls: the telemetry column renders at its
                    // natural size and FittedBox scales it down to exactly
                    // fit the available height.
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: 270,
                          child: _buildProgressSummary(theme),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 6,
                    child: _service.isLoading && _service.quests.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: _service.refresh,
                            color: theme.accentColor,
                            child: _service.quests.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    children: [
                                      const SizedBox(height: 60),
                                      Center(
                                        child: Text(
                                          'No weekly quests yet — check back Monday',
                                          style: TextStyle(
                                            color: theme.textMuted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    itemCount: _service.quests.length,
                                    itemBuilder: (context, i) {
                                      final quest = _service.quests[i];
                                      return _QuestCard(
                                        quest: quest,
                                        index: i,
                                        theme: theme,
                                        onClaim: () => _claimReward(quest),
                                      );
                                    },
                                  ),
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProgressSummary(GameTheme theme) {
    final completed = _service.completedCount;
    final claimable = _service.claimableCount;
    final total = _service.quests.length;
    final progress = total > 0 ? completed / total : 0.0;
    final allCompleted = total > 0 && completed >= total;
    final ringColor = allCompleted ? Colors.green : theme.neonPrimary;

    // Borderless telemetry column — mirrors the daily tab's completion ring.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(ringColor),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    '$completed of $total',
                    style: TextStyle(color: theme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "THIS WEEK'S PROGRESS",
          style: TextStyle(
            color: theme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        if (claimable > 0) ...[
          const SizedBox(height: 8),
          Text(
            '$claimable reward${claimable == 1 ? '' : 's'} ready to claim',
            style: TextStyle(
              color: theme.neonPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildInfoSection(theme),
      ],
    ).gameZoomIn();
  }

  Widget _buildInfoSection(GameTheme theme) {
    // Compact borderless hints under the telemetry ring — no panel chrome.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoItem(Icons.schedule, 'New quests every Monday'),
        _buildInfoItem(
          Icons.monetization_on,
          'Bigger goals, bigger coin rewards',
        ),
        _buildInfoItem(Icons.star, 'Quests grant Battle Pass XP too'),
      ],
    ).gameEntrance(delay: 300.ms);
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.5), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
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
  final int index;
  final GameTheme theme;
  final VoidCallback onClaim;
  const _QuestCard({
    required this.quest,
    required this.index,
    required this.theme,
    required this.onClaim,
  });

  Color _difficultyColor() {
    switch (quest.difficulty) {
      case ChallengeDifficulty.easy:
        return Colors.green;
      case ChallengeDifficulty.medium:
        return Colors.orange;
      case ChallengeDifficulty.hard:
        return Colors.redAccent;
    }
  }

  IconData _typeIcon() {
    switch (quest.type) {
      case WeeklyQuestType.score:
        return Icons.stars;
      case WeeklyQuestType.foodEaten:
        return Icons.flare;
      case WeeklyQuestType.gamesPlayed:
        return Icons.play_circle_outline;
      case WeeklyQuestType.survival:
        return Icons.timer;
      case WeeklyQuestType.gameMode:
        return Icons.games;
      case WeeklyQuestType.tournamentParticipation:
        return Icons.emoji_events;
      case WeeklyQuestType.dailyChallengesCompleted:
        return Icons.calendar_today;
      case WeeklyQuestType.battlePassTiersReached:
        return Icons.military_tech;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = quest.isCompleted;
    final canClaim = quest.canClaim;
    final difficultyColor = _difficultyColor();
    final accent = isCompleted ? Colors.green : theme.neonPrimary;

    // Fully transparent per the clean design — rows float straight on the
    // starfield; the icon disc, slim bar, and Claim button carry the
    // structure (styled to match the daily tab's cards).
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: canClaim ? onClaim : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Quest type disc — borderless neon tint + glow.
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.25),
                            blurRadius: 10,
                            spreadRadius: -3,
                          ),
                        ],
                      ),
                      child: isCompleted
                          ? const Icon(
                              Icons.check,
                              color: Colors.green,
                              size: 24,
                            )
                          : Icon(
                              _typeIcon(),
                              color: theme.neonPrimary,
                              size: 22,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  quest.title,
                                  style: TextStyle(
                                    color: theme.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    decoration: quest.claimedReward
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              // Difficulty pill — borderless tint.
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: difficultyColor.withValues(
                                    alpha: 0.16,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  quest.difficulty.displayName,
                                  style: TextStyle(
                                    color: difficultyColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            quest.description,
                            style: TextStyle(
                              color: theme.textMuted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Slim neon progress bar.
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: quest.progressPercentage,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation(accent),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${quest.currentProgress}/${quest.targetValue}',
                      style: TextStyle(
                        color: isCompleted ? Colors.green : theme.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Rewards row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.monetization_on,
                            color: Colors.amber,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${quest.coinReward}',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star,
                            color: Colors.purple,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${quest.battlePassXpReward} XP',
                            style: TextStyle(
                              color: Colors.purple.shade200,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (canClaim)
                      NeonButton(
                        onPressed: onClaim,
                        label: 'Claim',
                        icon: Icons.redeem,
                        theme: theme,
                        height: 40,
                      ),
                    if (quest.claimedReward)
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 18,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Claimed',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).gameListItem(index);
  }
}
