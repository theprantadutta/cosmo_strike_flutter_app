import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/tournament_service.dart';
import 'package:cosmo_strike_flutter_app/services/auth_service.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/screens/gameplay_screen.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/widgets/gradient_button.dart';
import 'package:cosmo_strike_flutter_app/widgets/themed_loading.dart';

class TournamentDetailScreen extends StatefulWidget {
  /// The tournament ID for deep link support.
  final String tournamentId;

  /// Optional tournament object (for instant display when navigating with object).
  final Tournament? tournament;

  const TournamentDetailScreen({
    super.key,
    required this.tournamentId,
    this.tournament,
  });

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen>
    with SingleTickerProviderStateMixin {
  final TournamentService _tournamentService = TournamentService();

  late TabController _tabController;
  Tournament? _tournament;
  List<TournamentParticipant> _leaderboard = [];
  // Server-authoritative rank for the current user — set from the
  // leaderboard response's current_user_rank. Preferred over the
  // local Tournament.userRank computation, which only sees the 50-item
  // slice and is wrong for users outside the top 50.
  int? _serverUserRank;
  bool _isLoading = false;
  // Distinguishes "leaderboard load actually failed" from "load returned
  // empty list" so the UI can show a retry button instead of pretending
  // the tournament has no participants.
  bool _leaderboardLoadFailed = false;
  bool _isLoadingTournament = false;
  bool _isJoining = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _tournament = widget.tournament;
    _tabController = TabController(length: 3, vsync: this);

    if (_tournament != null) {
      // Tournament provided via navigation, load leaderboard
      _loadLeaderboard();
    } else {
      // Deep link: need to load tournament from service
      _loadTournamentFromId();
    }
  }

  Future<void> _loadTournamentFromId() async {
    setState(() {
      _isLoadingTournament = true;
      _loadError = null;
    });

    try {
      final tournament = await _tournamentService.getTournament(
        widget.tournamentId,
      );
      if (mounted) {
        if (tournament != null) {
          setState(() {
            _tournament = tournament;
            _isLoadingTournament = false;
          });
          _loadLeaderboard();
        } else {
          setState(() {
            _loadError = 'Tournament not found';
            _isLoadingTournament = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = 'Failed to load tournament';
          _isLoadingTournament = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLeaderboard() async {
    if (_tournament == null) return;

    setState(() {
      _isLoading = true;
      _leaderboardLoadFailed = false;
    });

    try {
      final result = await _tournamentService.getTournamentLeaderboard(
        _tournament!.id,
      );
      // Detect "real failure" vs "actually empty": if the tournament
      // says it has participants but we got an empty list back, the
      // fetch must have failed silently in the service layer.
      final isLegitimatelyEmpty = result.entries.isEmpty &&
          _tournament!.currentParticipants == 0;
      setState(() {
        _leaderboard = result.entries;
        _serverUserRank = result.userRank;
        _isLoading = false;
        _leaderboardLoadFailed =
            result.entries.isEmpty && !isLegitimatelyEmpty;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _leaderboardLoadFailed = true;
      });
    }
  }

  Future<void> _refreshTournament() async {
    final tournamentId = _tournament?.id ?? widget.tournamentId;
    final updatedTournament = await _tournamentService.getTournament(
      tournamentId,
    );
    if (updatedTournament != null && mounted) {
      setState(() {
        _tournament = updatedTournament;
      });
      _loadLeaderboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;

        return Scaffold(
          bottomNavigationBar: const SnakeBannerAd(),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.backgroundColor,
                  theme.backgroundColor.withValues(alpha: 0.8),
                  theme.accentColor.withValues(alpha: 0.1),
                ],
              ),
            ),
            child: SafeArea(
              child: _buildContent(theme),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(GameTheme theme) {
    // Show loading state when fetching tournament from deep link
    if (_isLoadingTournament) {
      return ThemedLoading(theme: theme, label: 'Loading tournament...');
    }

    // Show error state
    if (_loadError != null || _tournament == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.accentColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _loadError ?? 'Tournament not found',
              style: TextStyle(
                color: theme.accentColor.withValues(alpha: 0.8),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accentColor,
              ),
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
    }

    final tournament = _tournament!;
    return Column(
      children: [
        _buildHeader(theme),
        _buildTournamentInfo(theme),
        _buildTabBar(theme),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(theme),
              _buildLeaderboardTab(theme),
              _buildRulesTab(theme),
            ],
          ),
        ),
        if (tournament.status.canJoin || tournament.status.canSubmitScore)
          _buildActionButtons(theme),
      ],
    );
  }

  Widget _buildHeader(GameTheme theme) {
    final tournament = _tournament!;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_back, color: theme.accentColor, size: 24),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tournament.name,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.accentColor,
                  ),
                ),
                Text(
                  tournament.type.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    color: _getTournamentTypeColor(tournament.type),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _refreshTournament,
            icon: Icon(
              Icons.refresh,
              color: theme.accentColor.withValues(alpha: 0.7),
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTournamentInfo(GameTheme theme) {
    final tournament = _tournament!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getTournamentStatusColor(
            tournament.status,
          ).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getTournamentTypeColor(
                    tournament.type,
                  ).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tournament.type.emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
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
                              fontSize: 12,
                              color: _getTournamentStatusColor(
                                tournament.status,
                              ),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
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
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 16,
                          color: theme.accentColor.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          tournament.timeRemainingFormatted,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.accentColor.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.people,
                          size: 16,
                          color: theme.accentColor.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${tournament.currentParticipants}/${tournament.maxParticipants} players',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.accentColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (tournament.hasJoined) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You\'re participating!',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        if (tournament.userBestScore != null &&
                            tournament.userAttempts != null)
                          Text(
                            'Best Score: ${tournament.userBestScore} • Attempts: ${tournament.userAttempts}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.withValues(alpha: 0.8),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Prefer the server-authoritative rank when we have it;
                  // fall back to the local heuristic only as a degraded
                  // mode (e.g. leaderboard wasn't loaded yet).
                  if ((_serverUserRank ?? 0) > 0 || tournament.userRank > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Rank #${_serverUserRank ?? tournament.userRank}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar(GameTheme theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TabBar(
        controller: _tabController,
        indicatorColor: theme.accentColor,
        labelColor: theme.accentColor,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Leaderboard'),
          Tab(text: 'Rules'),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(GameTheme theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDescriptionCard(theme),
          const SizedBox(height: 16),
          _buildRewardsCard(theme),
          const SizedBox(height: 16),
          _buildGameModeCard(theme),
        ],
      ),
    );
  }

  Widget _buildLeaderboardTab(GameTheme theme) {
    if (_isLoading) {
      return ThemedLoading(theme: theme, label: 'Loading leaderboard...');
    }

    // Explicit load-failure state. Distinguishes "fetch crashed" from
    // "genuinely empty tournament" so the user sees a retry button
    // instead of a misleading "no participants" screen.
    if (_leaderboardLoadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.cloud_off,
                size: 64,
                color: theme.accentColor.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                "Couldn't load the leaderboard",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.accentColor.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Check your connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.accentColor.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadLeaderboard,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: theme.backgroundColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_leaderboard.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.leaderboard,
              size: 80,
              color: theme.accentColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No participants yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.accentColor.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to join!',
              style: TextStyle(
                fontSize: 14,
                color: theme.accentColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _leaderboard.length,
      itemBuilder: (context, index) {
        final participant = _leaderboard[index];
        final rank = index + 1;

        return _buildLeaderboardItem(
          participant,
          rank,
          theme,
        ).gameListItem(index);
      },
    );
  }

  Widget _buildRulesTab(GameTheme theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRulesCard(theme),
          const SizedBox(height: 16),
          _buildScoringCard(theme),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard(GameTheme theme) {
    final tournament = _tournament!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Description',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: theme.accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            tournament.description,
            style: TextStyle(
              fontSize: 14,
              color: theme.accentColor.withValues(alpha: 0.8),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: theme.accentColor.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Text(
                tournament.formattedDateRange,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.accentColor.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRewardsCard(GameTheme theme) {
    final tournament = _tournament!;
    if (tournament.rewards.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                'Rewards',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...tournament.rewards.entries.map((entry) {
            final rank = entry.key;
            final reward = entry.value;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _getRankColor(rank).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '#$rank',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getRankColor(rank),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reward.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: theme.accentColor,
                          ),
                        ),
                        if (reward.coins > 0)
                          Text(
                            '+${reward.coins} coins',
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
            );
          }),
        ],
      ),
    );
  }

  Widget _buildGameModeCard(GameTheme theme) {
    final tournament = _tournament!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                tournament.gameMode.emoji,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Text(
                tournament.gameMode.displayName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tournament.gameMode.description,
            style: TextStyle(
              fontSize: 14,
              color: theme.accentColor.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardItem(
    TournamentParticipant participant,
    int rank,
    GameTheme theme,
  ) {
    // AuthService is a singleton (factory pattern in auth_service.dart),
    // NOT a registered Provider. The previous context.read<AuthService>()
    // threw ProviderNotFoundException because nothing in the widget tree
    // exposes it. Call the singleton factory directly.
    final authService = AuthService();
    final isCurrentUser = participant.userId == authService.currentUser?.uid;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? theme.accentColor.withValues(alpha: 0.1)
            : theme.backgroundColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentUser
              ? theme.accentColor.withValues(alpha: 0.3)
              : theme.accentColor.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _getRankColor(rank).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _getRankColor(rank),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 16,
            backgroundColor: theme.accentColor.withValues(alpha: 0.2),
            backgroundImage: participant.photoUrl != null
                ? NetworkImage(participant.photoUrl!)
                : null,
            onBackgroundImageError: participant.photoUrl != null ? (e, s) {} : null,
            child: participant.photoUrl == null
                ? Text(
                    participant.displayName.isNotEmpty
                        ? participant.displayName[0].toUpperCase()
                        : 'U',
                    style: TextStyle(
                      color: theme.accentColor,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.accentColor,
                  ),
                ),
                Text(
                  '${participant.attempts} attempts',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.accentColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${participant.highScore}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.amber,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRulesCard(GameTheme theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rule, color: theme.accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Tournament Rules',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: theme.accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._getTournamentRules().map(
            (rule) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 8, right: 8),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      rule,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.accentColor.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoringCard(GameTheme theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                'Scoring System',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Your highest score during the tournament period will count towards the final ranking. You can play multiple times to improve your score.',
            style: TextStyle(
              fontSize: 14,
              color: theme.accentColor.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(GameTheme theme) {
    final tournament = _tournament!;
    // Bottom CTA bar — anchored full-width with a subtle top divider so
    // it reads as a sticky action bar rather than a centered chip
    // floating under the tab view. Previously the Container had no width
    // constraint, so its child Column shrank to the GradientButton's
    // default 160px and the "JOIN TOURNAMENT" label got clipped.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(
            color: theme.accentColor.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!tournament.hasJoined && tournament.status.canJoin)
            GradientButton(
              onPressed: _isJoining ? null : () => _joinTournament(),
              text: _isJoining ? 'JOINING…' : 'JOIN TOURNAMENT',
              primaryColor: Colors.blue,
              secondaryColor: Colors.cyan,
              icon: Icons.person_add,
              width: double.infinity,
              height: 56,
            )
          else if (tournament.status.canSubmitScore)
            GradientButton(
              onPressed: _playTournament,
              text: 'PLAY NOW',
              primaryColor: theme.accentColor,
              secondaryColor: theme.foodColor,
              icon: Icons.play_arrow,
              width: double.infinity,
              height: 56,
            ),

          if (tournament.requiresEntry) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final premiumCubit = context.read<PremiumCubit>();
                if (premiumCubit.state.hasPremium) {
                  return _buildEntryStatusChip(
                    icon: Icons.diamond,
                    label: 'Pro · Unlimited entries',
                    color: Colors.amber,
                  );
                }
                final tier = _getTournamentTier(tournament.type);
                final count = premiumCubit.state.getTournamentEntryCount(tier);
                return _buildEntryStatusChip(
                  icon: count > 0
                      ? Icons.confirmation_number
                      : Icons.error_outline,
                  label: count > 0
                      ? 'Entries remaining: $count'
                      : 'No entries — tap JOIN to buy',
                  color: count > 0 ? Colors.green : Colors.redAccent,
                );
              },
            ),
          ],

          if (tournament.status == TournamentStatus.upcoming) ...[
            const SizedBox(height: 10),
            _buildEntryStatusChip(
              icon: Icons.schedule,
              label: 'Starts ${tournament.timeRemainingFormatted}',
              color: theme.accentColor,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEntryStatusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  List<String> _getTournamentRules() {
    final tournament = _tournament!;
    final baseRules = [
      'Play during the tournament period to have your scores counted',
      'You can play multiple times - only your highest score counts',
      'Must be signed in to participate',
      'Final rankings are determined at tournament end',
    ];

    // Add game mode specific rules
    switch (tournament.gameMode) {
      case TournamentGameMode.speedRun:
        baseRules.add('Game speed increases rapidly every 10 points');
        break;
      case TournamentGameMode.survival:
        baseRules.add('Score is based on survival time, not food consumed');
        break;
      case TournamentGameMode.noWalls:
        baseRules.add(
          'Snake wraps around screen edges instead of hitting walls',
        );
        break;
      case TournamentGameMode.powerUpMadness:
        baseRules.add('Power-ups spawn every 5 seconds');
        break;
      case TournamentGameMode.perfectGame:
        baseRules.add('Any collision immediately ends the game');
        break;
      case TournamentGameMode.classic:
        baseRules.add('Standard Snake rules apply');
        break;
    }

    return baseRules;
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

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return Colors.amber;
      case 2:
        return Colors.grey;
      case 3:
        return Colors.brown;
      default:
        return Colors.blue;
    }
  }

  String _getTournamentTier(TournamentType type) {
    switch (type) {
      case TournamentType.daily:
        return 'bronze';
      case TournamentType.weekly:
        return 'silver';
      case TournamentType.special:
        return 'gold';
    }
  }

  Future<void> _joinTournament() async {
    final tournament = _tournament!;
    final tier = _getTournamentTier(tournament.type);
    final entryCost = tournament.entryCost.clamp(1, 99);

    // Check entry requirement
    if (tournament.requiresEntry) {
      final premiumCubit = context.read<PremiumCubit>();

      // Premium users bypass entry requirement
      if (!premiumCubit.state.hasPremium) {
        final availableEntries =
            premiumCubit.state.getTournamentEntryCount(tier);
        if (availableEntries < entryCost) {
          _showNoEntryDialog(tier);
          return;
        }
      }
    }

    setState(() => _isJoining = true);

    try {
      final success = await _tournamentService.joinTournament(
        tournament.id,
        entryTier: tier,
      );

      if (success && mounted) {
        // Optimistically mark the local tournament as joined so the
        // CTA button flips from JOIN → PLAY NOW immediately, before
        // the network refresh below completes. The backend's
        // TournamentDto.IsJoined will confirm it on the next fetch.
        setState(() {
          _tournament = _tournament!.copyWith(isJoinedServer: true);
        });

        // Consume entries AFTER backend confirms the join succeeded
        if (tournament.requiresEntry) {
          final premiumCubit = context.read<PremiumCubit>();
          if (!premiumCubit.state.hasPremium) {
            await premiumCubit.useTournamentEntry(tier, count: entryCost);
          }
        }

        getIt<AnalyticsFacade>().trackTournamentEntered(
          tournamentId: tournament.id,
          tier: tier,
        );

        // TournamentService.onTournamentJoined broadcast (subscribed by
        // TournamentsNotifier in its constructor) handles the list
        // refresh — no more brittle ProviderScope.containerOf dance.

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Successfully joined tournament!')),
        );
        await _refreshTournament();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to join tournament')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error joining tournament')),
        );
      }
    }

    if (mounted) {
      setState(() => _isJoining = false);
    }
  }

  void _showNoEntryDialog(String tier) {
    final theme = context.read<ThemeCubit>().state.currentTheme;
    final premiumCubit = context.read<PremiumCubit>();
    final entryCount = premiumCubit.state.getTournamentEntryCount(tier);

    String productId;
    switch (tier) {
      case 'bronze':
        productId = ProductIds.tournamentBronze;
        break;
      case 'silver':
        productId = ProductIds.tournamentSilver;
        break;
      case 'gold':
        productId = ProductIds.tournamentGold;
        break;
      default:
        return;
    }

    final tierName = '${tier[0].toUpperCase()}${tier.substring(1)}';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.confirmation_num, color: Colors.amber, size: 24),
              const SizedBox(width: 8),
              Text(
                'Entry Required',
                style: TextStyle(
                  color: theme.accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You need a $tierName tournament entry to join this tournament.',
                style: TextStyle(
                  color: theme.accentColor.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Current $tierName entries: $entryCount',
                style: TextStyle(
                  color: entryCount > 0 ? Colors.green : Colors.red,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Pro subscribers get unlimited tournament access.',
                style: TextStyle(
                  color: theme.accentColor.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: theme.accentColor.withValues(alpha: 0.6)),
              ),
            ),
            // Free Bronze entry via rewarded ad (free users only, bronze tier
            // only — never devalue the paid Silver/Gold entries).
            if (tier == 'bronze' &&
                getIt.isRegistered<AdService>() &&
                getIt<AdService>().adsEnabled &&
                getIt<AdService>().isRewardedReady)
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  getIt<AdService>().showRewarded(
                    onReward: () => premiumCubit.addTournamentEntry('bronze'),
                  );
                },
                icon: const Icon(Icons.play_circle_fill,
                    color: Colors.amber, size: 18),
                label: Text('Free entry (ad)',
                    style: TextStyle(color: theme.accentColor)),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                final purchaseService = PurchaseService();
                final product = purchaseService.getProduct(productId);
                if (product != null) {
                  purchaseService.buyProduct(product);
                }
              },
              child: Text('Buy $tierName Entry - ${PurchaseService().getStorePrice(productId) ?? _getDefaultPrice(tier)}'),
            ),
          ],
        );
      },
    );
  }

  String _getDefaultPrice(String tier) {
    switch (tier) {
      case 'bronze':
        return '\$0.99';
      case 'silver':
        return '\$1.99';
      case 'gold':
        return '\$4.99';
      default:
        return '\$0.99';
    }
  }

  void _playTournament() {
    final tournament = _tournament!;
    final gameCubit = context.read<GameCubit>();

    // Set tournament mode in game cubit
    gameCubit.setTournamentMode(tournament.id, tournament.gameMode);

    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => const GameplayScreen()))
        .then((_) {
          // Refresh tournament data when returning from game
          _refreshTournament();
        });
  }
}
