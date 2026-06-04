import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/models/user_profile.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/services/social_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';

class FriendsLeaderboardScreen extends StatefulWidget {
  const FriendsLeaderboardScreen({super.key});

  @override
  State<FriendsLeaderboardScreen> createState() =>
      _FriendsLeaderboardScreenState();
}

class _FriendsLeaderboardScreenState extends State<FriendsLeaderboardScreen>
    with SingleTickerProviderStateMixin {
  final SocialService _socialService = SocialService();
  final AppDataCache _appCache = AppDataCache();
  List<UserProfile> _leaderboard = [];
  bool _isLoading = true;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _initializeLeaderboard();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _initializeLeaderboard() {
    // Check cache first - use preloaded friends list sorted by high score
    if (_appCache.isFullyLoaded && _appCache.friendsList != null && _appCache.friendsList!.isNotEmpty) {
      // Sort friends by high score for leaderboard display
      final sortedFriends = List<UserProfile>.from(_appCache.friendsList!);
      sortedFriends.sort((a, b) => b.highScore.compareTo(a.highScore));

      setState(() {
        _leaderboard = sortedFriends;
        _isLoading = false;
      });
      _animationController.forward();

      // Refresh in background for latest data
      _refreshInBackground();
    } else {
      // No cache - load normally
      _loadLeaderboard();
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      final leaderboard = await _socialService.getFriendsLeaderboard();
      if (mounted) {
        setState(() {
          _leaderboard = leaderboard;
        });
      }
    } catch (_) {
      // Ignore errors in background refresh
    }
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _isLoading = true);

    try {
      final leaderboard = await _socialService.getFriendsLeaderboard();
      if (mounted) {
        setState(() {
          _leaderboard = leaderboard;
          _isLoading = false;
        });
        _animationController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        final theme = state.currentTheme;
        final authState = context.watch<AuthCubit>().state;
        final currentUid = authState.isSignedIn ? authState.userId : null;

        return CommandScaffold(
          theme: theme,
          title: 'Friends Leaderboard',
          bottomBar: const ShipBannerAd(),
          bodyPadding: EdgeInsets.zero,
          actions: [
            IconButton(
              onPressed: _loadLeaderboard,
              icon: Icon(
                Icons.refresh,
                color: theme.accentColor.withValues(alpha: 0.7),
                size: 24,
              ),
            ),
          ],
          body: Column(
            children: [
              _buildSubtitle(theme),
              Expanded(
                child: _isLoading
                    ? _buildLoadingIndicator(theme)
                    : _buildLeaderboard(theme, currentUid),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSubtitle(GameTheme theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.center,
        child: HudChip(
          label: 'Compete with your friends',
          icon: Icons.people,
          theme: theme,
        ),
      ),
    );
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
            'Loading leaderboard...',
            style: TextStyle(
              color: theme.accentColor.withValues(alpha: 0.8),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard(GameTheme theme, String? currentUid) {
    if (_leaderboard.isEmpty) {
      return _buildEmptyState(theme);
    }

    return Column(
      children: [
        // Top 3 podium
        if (_leaderboard.length >= 2) _buildPodium(theme, currentUid),

        // Rest of the leaderboard
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _leaderboard.length > 3 ? _leaderboard.length - 3 : 0,
            itemBuilder: (context, index) {
              final actualIndex = index + 3; // Skip top 3
              final user = _leaderboard[actualIndex];
              final rank = actualIndex + 1;

              return _buildLeaderboardCard(
                user: user,
                rank: rank,
                theme: theme,
                delay: (actualIndex * 100).ms,
                isCurrentUser:
                    currentUid != null && user.uid == currentUid,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPodium(GameTheme theme, String? currentUid) {
    return Container(
      height: 200,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2nd place
          if (_leaderboard.length >= 2)
            Expanded(
              child: _buildPodiumPlace(
                user: _leaderboard[1],
                rank: 2,
                height: 120,
                theme: theme,
                delay: 200.ms,
                isCurrentUser:
                    currentUid != null && _leaderboard[1].uid == currentUid,
              ),
            ),

          // 1st place
          Expanded(
            child: _buildPodiumPlace(
              user: _leaderboard[0],
              rank: 1,
              height: 160,
              theme: theme,
              delay: 100.ms,
              isCurrentUser:
                  currentUid != null && _leaderboard[0].uid == currentUid,
            ),
          ),

          // 3rd place
          if (_leaderboard.length >= 3)
            Expanded(
              child: _buildPodiumPlace(
                user: _leaderboard[2],
                rank: 3,
                height: 80,
                theme: theme,
                delay: 300.ms,
                isCurrentUser:
                    currentUid != null && _leaderboard[2].uid == currentUid,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPodiumPlace({
    required UserProfile user,
    required int rank,
    required double height,
    required GameTheme theme,
    required Duration delay,
    required bool isCurrentUser,
  }) {
    final colors = {
      1: [Colors.amber, Colors.yellow],
      2: [Colors.grey.shade400, Colors.grey.shade300],
      3: [Colors.brown.shade400, Colors.brown.shade300],
    };

    final rankColors = colors[rank] ?? [Colors.grey, Colors.grey];

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // User avatar — gets a glowing accent-color ring when this is the
        // signed-in player, so they spot themselves on the podium instantly.
        Container(
          padding: isCurrentUser ? const EdgeInsets.all(3) : EdgeInsets.zero,
          decoration: isCurrentUser
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      theme.accentColor,
                      theme.accentColor.withValues(alpha: 0.6),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.accentColor.withValues(alpha: 0.55),
                      blurRadius: 10,
                    ),
                  ],
                )
              : null,
          child: CircleAvatar(
            radius: rank == 1 ? 32 : 24,
            backgroundColor: theme.accentColor.withValues(alpha: 0.2),
            backgroundImage: user.photoUrl != null
                ? NetworkImage(user.photoUrl!)
                : null,
            onBackgroundImageError: user.photoUrl != null ? (e, s) {} : null,
            child: user.photoUrl == null
                ? Text(
                    user.publicLabel.isNotEmpty
                        ? user.publicLabel[0].toUpperCase()
                        : 'U',
                    style: TextStyle(
                      color: theme.accentColor,
                      fontSize: rank == 1 ? 24 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
        ).gamePop(delay: delay),

        const SizedBox(height: 8),

        // Rank crown/medal
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: rankColors[0],
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: rankColors[0].withValues(alpha: 0.3),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            rank == 1 ? Icons.emoji_events : Icons.military_tech,
            color: Colors.white,
            size: rank == 1 ? 20 : 16,
          ),
        ).gamePop(delay: delay + 100.ms),

        const SizedBox(height: 4),

        // User name — "YOU" chip below when the current user owns this slot.
        Text(
          user.publicLabel,
          style: TextStyle(
            color: isCurrentUser ? theme.accentColor : theme.accentColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ).gameEntrance(delay: delay + 200.ms),
        if (isCurrentUser) ...[
          const SizedBox(height: 2),
          _buildYouChip(theme).gameEntrance(delay: delay + 250.ms),
        ],

        // Score — thousands-separated
        Text(
          _formatThousands(user.highScore),
          style: TextStyle(
            color: rankColors[0],
            fontSize: rank == 1 ? 16 : 14,
            fontWeight: FontWeight.bold,
          ),
        ).gameEntrance(delay: delay + 300.ms),

        const SizedBox(height: 8),

        // Podium base
        Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: rankColors,
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            boxShadow: [
              BoxShadow(
                color: rankColors[0].withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              '#$rank',
              style: TextStyle(
                color: Colors.white,
                fontSize: rank == 1 ? 24 : 18,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ).gameZoomIn(delay: delay),
      ],
    );
  }

  Widget _buildLeaderboardCard({
    required UserProfile user,
    required int rank,
    required GameTheme theme,
    required Duration delay,
    required bool isCurrentUser,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: isCurrentUser
            ? LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  theme.accentColor.withValues(alpha: 0.32),
                  theme.accentColor.withValues(alpha: 0.16),
                  theme.primaryColor.withValues(alpha: 0.18),
                ],
              )
            : null,
        color: isCurrentUser ? null : theme.surfaceGlass,
        borderRadius: GameTokens.brMd,
        border: Border.all(
          color: isCurrentUser ? theme.accentColor : theme.stroke,
          width: isCurrentUser ? 1.5 : 1.0,
        ),
        boxShadow: isCurrentUser
            ? [
                BoxShadow(
                  color: theme.accentColor.withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Rank number
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.accentColor.withValues(alpha: 0.3),
                ),
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: theme.accentColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            // User avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.accentColor.withValues(alpha: 0.2),
              backgroundImage: user.photoUrl != null
                  ? NetworkImage(user.photoUrl!)
                  : null,
              onBackgroundImageError: user.photoUrl != null ? (e, s) {} : null,
              child: user.photoUrl == null
                  ? Text(
                      user.publicLabel.isNotEmpty
                          ? user.publicLabel[0].toUpperCase()
                          : 'U',
                      style: TextStyle(
                        color: theme.accentColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),

            const SizedBox(width: 16),

            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.publicLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: theme.accentColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 8),
                        _buildYouChip(theme),
                      ],
                      const SizedBox(width: 6),
                      Text(
                        user.status.emoji,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.games,
                        size: 14,
                        color: theme.accentColor.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatGamesPlayed(user.totalGamesPlayed),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.accentColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Score — thousands-separated.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_events, size: 16, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(
                      _formatThousands(user.highScore),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: theme.accentColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                Text(
                  'High Score',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.accentColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).gameListItem(0);
  }

  // ---------------------------------------------------------------------------
  // Shared helpers — mirror the global leaderboard treatment so YOU chip,
  // game-count pluralization, and number formatting stay consistent across
  // both screens.
  // ---------------------------------------------------------------------------

  Widget _buildYouChip(GameTheme theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.accentColor,
            theme.accentColor.withValues(alpha: 0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: theme.accentColor.withValues(alpha: 0.55),
            blurRadius: 6,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.person_pin,
            color: theme.backgroundColor,
            size: 11,
          ),
          const SizedBox(width: 3),
          Text(
            'YOU',
            style: TextStyle(
              color: theme.backgroundColor,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  String _formatGamesPlayed(int count) {
    final formatted = _formatThousands(count);
    return count == 1 ? '$formatted game' : '$formatted games';
  }

  String _formatThousands(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  Widget _buildEmptyState(GameTheme theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: theme.accentColor.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Friends Yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.accentColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add friends to see your private leaderboard!',
            style: TextStyle(
              fontSize: 14,
              color: theme.accentColor.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          NeonButton(
            onPressed: () => context.push(AppRoutes.friends),
            label: 'Add Friends',
            icon: Icons.person_add,
            theme: theme,
          ),
        ],
      ),
    );
  }
}
