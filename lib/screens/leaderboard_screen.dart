import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/providers/leaderboard_provider.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    // Calculate user rank once data is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateUserRank();
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final type = _tabController.index == 0 ? 'global' : 'weekly';
    getIt<AnalyticsFacade>().trackLeaderboardViewed(type);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _calculateUserRank() {
    final authState = context.read<AuthCubit>().state;
    if (!authState.isSignedIn || authState.userId == null) return;
    ref.read(combinedLeaderboardProvider.notifier).calculateUserRankFor(authState.userId);
  }

  Future<void> _loadGlobalLeaderboard() async {
    await ref.read(combinedLeaderboardProvider.notifier).refresh();
    _calculateUserRank();
  }

  Future<void> _loadWeeklyLeaderboard() async {
    await ref.read(combinedLeaderboardProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the leaderboard state from Riverpod
    final leaderboardState = ref.watch(combinedLeaderboardProvider);
    final themeState = context.watch<ThemeCubit>().state;
    final authState = context.watch<AuthCubit>().state;
    final theme = themeState.currentTheme;

    // Update user rank when global leaderboard loads
    ref.listen<CombinedLeaderboardState>(combinedLeaderboardProvider, (prev, next) {
      if (prev?.isLoadingGlobal == true && next.isLoadingGlobal == false) {
        _calculateUserRank();
      }
    });

    return CommandScaffold(
      theme: theme,
      title: 'Leaderboards',
      bottomBar: const ShipBannerAd(),
      bodyPadding: EdgeInsets.zero,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // LEFT — section rail + board telemetry (subtitle, cache
            // freshness, the signed-in player's rank). Never scrolls:
            // rendered at natural size and scaled down.
            Expanded(
              flex: 3,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 230,
                    child: _buildLeftPanel(theme, authState, leaderboardState),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            // RIGHT — the selected board's entries (swipeable).
            Expanded(
              flex: 7,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGlobalLeaderboard(theme, authState, leaderboardState),
                  _buildWeeklyLeaderboard(theme, authState, leaderboardState),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Themed loading state matching the other data screens — a centered
  /// spinner over a 'Loading…' label so users perceive the network fetch
  /// as work-in-progress rather than an empty/broken screen.
  Widget _buildLoadingState(GameTheme theme, String label) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(theme.accentColor),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  /// Vertical, borderless section rail + board telemetry for the left
  /// region. Driven by the existing [_tabController] so taps and
  /// TabBarView swipes stay in sync.
  Widget _buildLeftPanel(
    GameTheme theme,
    AuthState authState,
    CombinedLeaderboardState leaderboardState,
  ) {
    const items = [
      (Icons.public, 'Global'),
      (Icons.calendar_today, 'Weekly'),
    ];

    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final userRank = leaderboardState.userRank;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++)
              _buildNavItem(theme, i, items[i].$1, items[i].$2),
            const SizedBox(height: 6),

            // Subtitle explaining what the active board ranks by — without
            // this, "Global vs Weekly" doesn't tell players whether the
            // metric is score / coins / XP / something else.
            _buildSubtitle(theme),
            const SizedBox(height: 8),

            // Cache freshness chip — surfaces when the Drift cache for
            // the active board was last refreshed from the server so
            // the user knows if they're looking at stale data (offline,
            // or a recent disconnect).
            _buildStalenessChip(theme, leaderboardState),

            // The signed-in player's own standing on the board.
            if (authState.isSignedIn && userRank != null) ...[
              const SizedBox(height: 12),
              _buildUserRankCard(authState, theme, userRank),
            ],
          ],
        );
      },
    );
  }

  Widget _buildNavItem(GameTheme theme, int i, IconData icon, String label) {
    final selected = _tabController.index == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tabController.animateTo(i),
      // No background at all — selection reads purely through the neon icon,
      // brighter text, and a small glowing indicator dot.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? theme.neonPrimary : theme.textMuted,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? theme.textPrimary : theme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (selected)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.neonPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.neonPrimary.withValues(alpha: 0.7),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Tells the player exactly what metric the active tab is ranking on,
  /// so "Global vs Weekly" isn't ambiguous between high score / coins / XP.
  /// Mirrors what the backend handlers do: GetGlobalLeaderboardQueryHandler
  /// orders by aggregated max(Score.ScoreValue) lifetime; the weekly one
  /// scopes scores to `CreatedAt >= startOfWeek` (Sunday).
  Widget _buildSubtitle(GameTheme theme) {
    final isWeekly = _tabController.index == 1;
    final icon = isWeekly ? Icons.calendar_today : Icons.public;
    final text = isWeekly
        ? 'Ranked by your best single-game score this week (resets Sunday)'
        : 'Ranked by your highest single-game score ever';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, color: theme.textMuted, size: 12),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  /// Tiny inline chip reading "Updated 3m ago · tap to refresh" for the
  /// active board. The Drift cache survives offline launches, so this
  /// is the user's signal for "is what I'm looking at stale?". Tap
  /// triggers a forced refresh.
  Widget _buildStalenessChip(
    GameTheme theme,
    CombinedLeaderboardState state,
  ) {
    final isWeekly = _tabController.index == 1;
    final ts =
        isWeekly ? state.weeklyLastRefreshedAt : state.globalLastRefreshedAt;
    final hasData = isWeekly
        ? state.weeklyEntries.isNotEmpty
        : state.globalEntries.isNotEmpty;
    // No chip until the cache has at least once been populated. A
    // brand-new install hitting an offline state would just look
    // confusing with a "Never updated" label.
    if (ts == null && !hasData) return const SizedBox.shrink();

    final label = ts == null ? 'No cache yet' : 'Updated ${_relativeAge(ts)}';
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ref.read(combinedLeaderboardProvider.notifier).refresh(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
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

  /// The signed-in player's own standing — borderless, no card chrome:
  /// a section label, the big "#n" rank value, then muted detail rows.
  Widget _buildUserRankCard(AuthState authState, GameTheme theme, Map<String, dynamic> userRank) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'YOUR RANK',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
              color: theme.accentColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundImage: authState.photoURL != null
                    ? NetworkImage(authState.photoURL!)
                    : null,
                onBackgroundImageError: authState.photoURL != null
                    ? (e, s) {}
                    : null,
                backgroundColor: theme.primaryColor,
                child: authState.photoURL == null
                    ? Icon(Icons.person, color: theme.backgroundColor, size: 18)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${userRank['rank']}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: theme.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      authState.publicLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Score: ${authState.highScore}',
            style: TextStyle(
              fontSize: 12,
              color: theme.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Top ${userRank['percentile']}%',
            style: TextStyle(
              fontSize: 12,
              color: theme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalLeaderboard(GameTheme theme, AuthState authState, CombinedLeaderboardState leaderboardState) {
    if (leaderboardState.isLoadingGlobal) {
      return _buildLoadingState(theme, 'Loading global leaderboard...');
    }

    if (leaderboardState.globalError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.accentColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              leaderboardState.globalError!,
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            NeonButton(
              onPressed: _loadGlobalLeaderboard,
              label: 'Retry',
              icon: Icons.refresh,
              theme: theme,
            ),
          ],
        ),
      );
    }

    if (leaderboardState.globalEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 64,
              color: theme.accentColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No scores yet',
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to set a high score!',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGlobalLeaderboard,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: leaderboardState.globalEntries.length,
        itemBuilder: (context, index) {
          final player = leaderboardState.globalEntries[index];
          final isCurrentUser =
              authState.isSignedIn &&
              authState.userId != null &&
              player['uid'] == authState.userId;

          return _buildLeaderboardItem(index + 1, player, theme, isCurrentUser)
              .gameListItem(index);
        },
      ),
    );
  }

  Widget _buildWeeklyLeaderboard(GameTheme theme, AuthState authState, CombinedLeaderboardState leaderboardState) {
    if (leaderboardState.isLoadingWeekly) {
      return _buildLoadingState(theme, 'Loading weekly leaderboard...');
    }

    if (leaderboardState.weeklyError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.accentColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              leaderboardState.weeklyError!,
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            NeonButton(
              onPressed: _loadWeeklyLeaderboard,
              label: 'Retry',
              icon: Icons.refresh,
              theme: theme,
            ),
          ],
        ),
      );
    }

    if (leaderboardState.weeklyEntries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 64,
              color: theme.accentColor.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No weekly scores yet',
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Play this week to appear here!',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadWeeklyLeaderboard,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: leaderboardState.weeklyEntries.length,
        itemBuilder: (context, index) {
          final player = leaderboardState.weeklyEntries[index];
          final isCurrentUser =
              authState.isSignedIn &&
              authState.userId != null &&
              player['uid'] == authState.userId;

          return _buildLeaderboardItem(index + 1, player, theme, isCurrentUser)
              .gameListItem(index);
        },
      ),
    );
  }

  Widget _buildLeaderboardItem(
    int rank,
    Map<String, dynamic> player,
    GameTheme theme,
    bool isCurrentUser,
  ) {
    // Top-3 podium styling lives on the small rank disc (gold / silver /
    // bronze gradient + glow) — rows themselves float transparently on
    // the starfield. Only the signed-in player's row keeps a single faint
    // accent tint so they always know which row is theirs.
    final podium = _podiumStyle(rank);
    final isPodium = podium != null;

    final score = (player['highScore'] ?? 0) as int;
    final gamesPlayed = (player['totalGamesPlayed'] ?? 0) as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: isCurrentUser
          ? BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            )
          : null,
      child: Row(
        children: [
          // Rank chip — medal for top 3, pill with "#N" for the rest.
          _buildRankWidget(rank, podium, theme),

          const SizedBox(width: 10),

          // Avatar with subtle metallic ring for podium positions.
          Container(
            padding: isPodium ? const EdgeInsets.all(2) : EdgeInsets.zero,
            decoration: isPodium
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        podium.color,
                        podium.color.withValues(alpha: 0.5),
                      ],
                    ),
                  )
                : null,
            child: CircleAvatar(
              radius: 20,
              backgroundImage: player['photoURL'] != null
                  ? NetworkImage(player['photoURL']!)
                  : null,
              onBackgroundImageError: player['photoURL'] != null
                  ? (e, s) {}
                  : null,
              backgroundColor: theme.primaryColor,
              child: player['photoURL'] == null
                  ? Icon(Icons.person, color: theme.backgroundColor, size: 20)
                  : null,
            ),
          ),

          const SizedBox(width: 12),

          // Name and details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      // Prefer the stable username (now backfilled for
                      // every user post-Phase-1) over the display name,
                      // which can be null/missing for anonymous users
                      // and changes when the user updates their Google
                      // profile.
                      player['username'] ??
                          player['displayName'] ??
                          'Anonymous',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isCurrentUser
                            ? theme.accentColor
                            : theme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (player['isAnonymous'] == true) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'GUEST',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    if (isCurrentUser) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accentColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_pin,
                              color: theme.accentColor,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'YOU',
                              style: TextStyle(
                                color: theme.accentColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  _formatGamesPlayed(gamesPlayed),
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textMuted,
                  ),
                ),
              ],
            ),
          ),

          // Score — right-aligned, thousands-separated. Podium uses a
          // gradient text effect via ShaderMask for a "scoreboard" feel.
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildScoreText(score, podium, isCurrentUser, theme),
              const SizedBox(height: 2),
              Text(
                'pts',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: theme.textMuted,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Leaderboard row helpers
  // ---------------------------------------------------------------------------

  /// Returns gold / silver / bronze styling for the top 3, or null for the rest.
  _PodiumStyle? _podiumStyle(int rank) {
    switch (rank) {
      case 1:
        return const _PodiumStyle(
          color: Color(0xFFFFD54F), // gold
          icon: Icons.emoji_events,
        );
      case 2:
        return _PodiumStyle(
          color: Colors.grey.shade400, // silver
          icon: Icons.workspace_premium,
        );
      case 3:
        return _PodiumStyle(
          color: const Color(0xFFCD7F32), // bronze
          icon: Icons.workspace_premium,
        );
      default:
        return null;
    }
  }

  /// Rank widget — medal disc for top 3, pill chip with "#N" for the rest.
  Widget _buildRankWidget(int rank, _PodiumStyle? podium, GameTheme theme) {
    if (podium != null) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [podium.color, podium.color.withValues(alpha: 0.6)],
          ),
          boxShadow: [
            BoxShadow(
              color: podium.color.withValues(alpha: 0.55),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(podium.icon, color: Colors.white, size: 20),
      );
    }
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.primaryColor.withValues(alpha: 0.16),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: theme.accentColor,
        ),
      ),
    );
  }

  /// Score text with thousands separator. Podium positions get a gradient
  /// ShaderMask in their medal color; the current user gets the accent
  /// color; everyone else is plain white.
  Widget _buildScoreText(
    int score,
    _PodiumStyle? podium,
    bool isCurrentUser,
    GameTheme theme,
  ) {
    final formatted = _formatThousands(score);
    if (podium != null && !isCurrentUser) {
      return ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: [Colors.white, podium.color],
        ).createShader(bounds),
        child: Text(
          formatted,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
      );
    }
    return Text(
      formatted,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: isCurrentUser ? theme.accentColor : theme.textPrimary,
        letterSpacing: -0.5,
      ),
    );
  }

  /// "1 game played" / "12 games played" / "1,234 games played". The
  /// thousand-separator handles backend-aggregated counts that can get big.
  String _formatGamesPlayed(int count) {
    final formatted = _formatThousands(count);
    return count == 1 ? '$formatted game played' : '$formatted games played';
  }

  String _formatThousands(int n) {
    // Manual thousand-separator — saves pulling in `intl` just for this.
    final s = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

class _PodiumStyle {
  final Color color;
  final IconData icon;
  const _PodiumStyle({required this.color, required this.icon});
}
