import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/providers/tournaments_provider.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';

class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await ref.read(tournamentsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the tournaments state from Riverpod
    final tournamentsState = ref.watch(tournamentsProvider);

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;

        return CommandScaffold(
          theme: theme,
          title: 'Tournaments',
          bottomBar: const ShipBannerAd(),
          bodyPadding: EdgeInsets.zero,
          actions: [
            IconButton(
              onPressed: _loadData,
              icon: Icon(
                Icons.refresh,
                color: theme.accentColor.withValues(alpha: 0.7),
                size: 24,
              ),
            ),
          ],
          body: Column(
            children: [
              _buildTabBar(theme),
              // "Updated X ago" chip — surfaces Drift cache
              // freshness for the currently-active tab so the user
              // can tell if they're looking at stale offline data.
              AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) =>
                    _buildStalenessChip(theme, tournamentsState),
              ),
              Expanded(
                child: tournamentsState.isLoading
                    ? _buildLoadingIndicator(theme)
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildActiveTournaments(theme, tournamentsState.activeTournaments),
                          _buildTournamentHistory(theme, tournamentsState.historyTournaments),
                          _buildUserStats(theme, tournamentsState.userStats),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabBar(GameTheme theme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: theme.surfaceGlass,
        borderRadius: GameTokens.brMd,
        border: Border.all(color: theme.stroke),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: theme.neonPrimary.withValues(alpha: 0.85),
          borderRadius: GameTokens.brMd,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: const Color(0xFF03040A),
        unselectedLabelColor: theme.textMuted,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold),
        tabs: const [
          Tab(text: 'Active'),
          Tab(text: 'History'),
          Tab(text: 'My Stats'),
        ],
      ),
    );
  }

  /// Inline chip showing how stale the Drift cache for the active tab
  /// is. Tap triggers a forced refresh. The My Stats tab has no cache
  /// of its own — fall back to whichever list was most recently
  /// touched so the user still gets a signal.
  Widget _buildStalenessChip(
    GameTheme theme,
    TournamentsState state,
  ) {
    final tabIndex = _tabController.index;
    DateTime? ts;
    switch (tabIndex) {
      case 0:
        ts = state.activeLastRefreshedAt;
        break;
      case 1:
        ts = state.historyLastRefreshedAt;
        break;
      default:
        ts = state.activeLastRefreshedAt ?? state.historyLastRefreshedAt;
    }

    final label = ts == null ? 'No cache yet' : 'Updated ${_relativeAge(ts)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => ref.read(tournamentsProvider.notifier).refresh(),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.refresh_rounded,
                  color: theme.accentColor.withValues(alpha: 0.7),
                  size: 12,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: theme.accentColor.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _relativeAge(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildLoadingIndicator(GameTheme theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(theme.accentColor),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading tournaments...',
            style: TextStyle(
              color: theme.accentColor.withValues(alpha: 0.8),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTournaments(GameTheme theme, List<Tournament> activeTournaments) {
    if (activeTournaments.isEmpty) {
      return _buildEmptyState(
        icon: Icons.emoji_events,
        title: 'No Active Tournaments',
        subtitle: 'Check back later for new tournaments!',
        theme: theme,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: activeTournaments.length,
      itemBuilder: (context, index) {
        final tournament = activeTournaments[index];
        return _buildTournamentCard(
          tournament: tournament,
          theme: theme,
          onTap: () => _openTournamentDetail(tournament),
        ).gameListItem(index);
      },
    );
  }

  Widget _buildTournamentHistory(GameTheme theme, List<Tournament> historyTournaments) {
    if (historyTournaments.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history,
        title: 'No Tournament History',
        subtitle: 'Participate in tournaments to see your history!',
        theme: theme,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: historyTournaments.length,
      itemBuilder: (context, index) {
        final tournament = historyTournaments[index];
        return _buildTournamentCard(
          tournament: tournament,
          theme: theme,
          showResults: true,
          onTap: () => _openTournamentDetail(tournament),
        ).gameListItem(index);
      },
    );
  }

  Widget _buildUserStats(GameTheme theme, Map<String, dynamic> userStats) {
    if (userStats.isEmpty) {
      return _buildEmptyState(
        icon: Icons.bar_chart,
        title: 'No Tournament Stats',
        subtitle: 'Join tournaments to track your progress!',
        theme: theme,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildStatsOverview(theme, userStats),
          const SizedBox(height: 24),
          _buildStatsDetails(theme, userStats),
        ],
      ),
    );
  }

  Widget _buildTournamentCard({
    required Tournament tournament,
    required GameTheme theme,
    bool showResults = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        theme: theme,
        onTap: onTap,
        borderColor: _getTournamentStatusColor(
          tournament.status,
        ).withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getTournamentTypeColor(
                        tournament.type,
                      ).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tournament.type.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tournament.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.accentColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tournament.type.displayName,
                          style: TextStyle(
                            fontSize: 12,
                            color: _getTournamentTypeColor(tournament.type),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getTournamentStatusColor(
                        tournament.status,
                      ).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tournament.status.displayName,
                      style: TextStyle(
                        fontSize: 10,
                        color: _getTournamentStatusColor(tournament.status),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Description
              Text(
                tournament.description,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.accentColor.withValues(alpha: 0.8),
                ),
              ),

              const SizedBox(height: 12),

              // Game mode and time info
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tournament.gameMode.emoji,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          tournament.gameMode.displayName,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color: theme.accentColor.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tournament.timeRemainingFormatted,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.accentColor.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Participation info
              Row(
                children: [
                  Icon(
                    Icons.people,
                    size: 16,
                    color: theme.accentColor.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${tournament.currentParticipants}/${tournament.maxParticipants} players',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.accentColor.withValues(alpha: 0.6),
                    ),
                  ),
                  const Spacer(),
                  if (tournament.hasJoined) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Joined',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (tournament.userBestScore != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        'Best: ${tournament.userBestScore}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ],
              ),

              // Show rewards for active tournaments or results for history
              if (showResults && tournament.userReward != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.emoji_events, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rank #${tournament.userRank} - ${tournament.userReward!.name}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                            if (tournament.userReward!.coins > 0)
                              Text(
                                '+${tournament.userReward!.coins} coins',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.amber.withValues(alpha: 0.8),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (!showResults && tournament.rewards.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.accentColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.card_giftcard,
                        color: theme.accentColor,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${tournament.rewards.length} reward${tournament.rewards.length > 1 ? 's' : ''} available',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        'View Details →',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.accentColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
  }

  Widget _buildStatsOverview(GameTheme theme, Map<String, dynamic> userStats) {
    return GlassPanel(
      theme: theme,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tournament Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.accentColor,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Tournaments',
                  '${userStats['totalTournaments'] ?? 0}',
                  Icons.emoji_events,
                  Colors.blue,
                  theme,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Wins',
                  '${userStats['wins'] ?? 0}',
                  Icons.emoji_events,
                  Colors.amber,
                  theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Top 3 Finishes',
                  '${userStats['topThreeFinishes'] ?? 0}',
                  Icons.military_tech,
                  Colors.orange,
                  theme,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Best Score',
                  '${userStats['bestScore'] ?? 0}',
                  Icons.star,
                  Colors.purple,
                  theme,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsDetails(GameTheme theme, Map<String, dynamic> userStats) {
    return GlassPanel(
      theme: theme,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detailed Statistics',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.accentColor,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow(
            'Total Attempts',
            '${userStats['totalAttempts'] ?? 0}',
            theme,
          ),
          _buildDetailRow('Win Rate', '${userStats['winRate'] ?? 0}%', theme),
          _buildDetailRow(
            'Average Performance',
            'Top ${100 - (userStats['winRate'] ?? 0)}%',
            theme,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
    GameTheme theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.accentColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: theme.accentColor.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, GameTheme theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: theme.accentColor.withValues(alpha: 0.8),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required GameTheme theme,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: theme.accentColor.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.accentColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: theme.accentColor.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getTournamentStatusColor(TournamentStatus status) {
    switch (status) {
      case TournamentStatus.active:
        return Colors.green;
      case TournamentStatus.upcoming:
        return Colors.blue;
      case TournamentStatus.ended:
        return Colors.grey;
    }
  }

  Color _getTournamentTypeColor(TournamentType type) {
    switch (type) {
      case TournamentType.daily:
        return Colors.blue;
      case TournamentType.weekly:
        return Colors.orange;
      case TournamentType.special:
        return Colors.pink;
    }
  }

  void _openTournamentDetail(Tournament tournament) {
    context.push(AppRoutes.tournamentDetailPath(tournament.id), extra: tournament);
  }
}
