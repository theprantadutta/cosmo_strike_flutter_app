import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/models/achievement.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/player_progression.dart';
import 'package:cosmo_strike_flutter_app/widgets/themed_loading.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AppDataCache _appCache;

  @override
  void initState() {
    super.initState();
    _appCache = getIt<AppDataCache>();
    // Trigger background refresh for fresh data (non-blocking)
    _appCache.refreshInBackground();

    // Edge case: if the screen is opened while already unauthenticated
    // (token expired, race during nav), the BlocListener won't fire because
    // there's no state transition. Schedule a redirect for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authState = context.read<AuthCubit>().state;
      if (authState.status == AuthStatus.unauthenticated) {
        context.go(AppRoutes.firstTimeAuth);
      }
    });
  }

  // Convenience getters using cached data
  Map<String, dynamic> get _displayStats => _appCache.statistics ?? {};
  List<Achievement> get _recentAchievements => _appCache.recentAchievements ?? [];
  // Data is already loaded - no loading state needed
  bool get _isLoading => !_appCache.isFullyLoaded;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final theme = themeState.currentTheme;

    // BlocListener routes the user to the sign-in screen as soon as they
    // become unauthenticated (i.e. after a successful sign-out). This is the
    // sole place the redirect happens — the build path below is responsible
    // for the loader UI during the transition itself.
    return BlocListener<AuthCubit, AuthState>(
      listenWhen: (previous, current) =>
          current.status == AuthStatus.unauthenticated &&
          previous.status != AuthStatus.unauthenticated,
      listener: (context, state) {
        if (mounted) {
          // .go (not .push) so the back stack doesn't preserve the stale
          // profile screen behind the auth screen.
          context.go(AppRoutes.firstTimeAuth);
        }
      },
      // Subscribe to AppDataCache so a post-game refreshStatistics() call
      // rebuilds the stat row with the updated high score / totals. Without
      // this, the cached snapshot from app startup stays visible.
      child: ListenableBuilder(
        listenable: _appCache,
        builder: (context, _) => BlocBuilder<AuthCubit, AuthState>(
        builder: (context, authState) {
          return CommandScaffold(
            theme: theme,
            title: 'Profile',
            bottomBar: const ShipBannerAd(),
            bodyPadding: const EdgeInsets.symmetric(horizontal: 10.0),
            body: _buildBody(context, authState, themeState),
          );
        },
      ),
      ),
    );
  }

  /// Pick the right body view for the current auth state. Loading takes
  /// priority over content so we never render a half-rendered profile
  /// (with stale name/badge/sections) while sign-out is in flight.
  Widget _buildBody(
    BuildContext context,
    AuthState authState,
    ThemeState themeState,
  ) {
    if (authState.isLoading) {
      return _buildFullScreenLoader(themeState, message: 'Signing out...');
    }
    if (authState.isSignedIn) {
      return _buildProfileContent(context, authState, themeState);
    }
    // Unauthenticated and not loading — the BlocListener will navigate us
    // away on the next frame, but show a clean spinner so we don't flash
    // the inline sign-in content during the redirect.
    return _buildFullScreenLoader(themeState);
  }

  Widget _buildFullScreenLoader(ThemeState themeState, {String? message}) {
    final theme = themeState.currentTheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: theme.accentColor, strokeWidth: 3),
          if (message != null) ...[
            const SizedBox(height: 20),
            Text(
              message,
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileContent(
    BuildContext context,
    AuthState authState,
    ThemeState themeState,
  ) {
    final theme = themeState.currentTheme;

    // Landscape command deck: LEFT = identity + account actions, RIGHT = the
    // scrollable profile sections. Both float borderless on the starfield
    // per the clean design.
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 250,
                  child: _buildIdentityPanel(context, authState, theme),
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  // Lifetime player progression (level + XP)
                  PlayerProgressionCard(theme: theme),
                  const SizedBox(height: 20),
                  _buildQuickActionsSection(context, theme),
                  const SizedBox(height: 20),
                  _buildStatsSection(context, theme),
                  if (_recentAchievements.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _buildAchievementsSection(context, theme),
                  ],
                  const SizedBox(height: 20),
                  _buildReplaysSection(context, theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// LEFT panel: glowing avatar + public name + account badge + the primary
  /// account actions. Rendered at natural size inside a FittedBox(scaleDown)
  /// so it never scrolls in the short landscape viewport.
  Widget _buildIdentityPanel(
    BuildContext context,
    AuthState authState,
    GameTheme theme,
  ) {
    final hasPhoto = authState.photoURL != null;
    final statusColor = authState.isAnonymous ? Colors.orange : Colors.green;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Glowing avatar. A gradient ring frames a real network photo; the
        // fallback icon avatar sits on a plain tint disc instead.
        Center(
          child: Container(
            padding: hasPhoto ? const EdgeInsets.all(3) : EdgeInsets.zero,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasPhoto
                  ? LinearGradient(
                      colors: [theme.primaryColor, theme.accentColor],
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: theme.accentColor.withValues(alpha: 0.35),
                  blurRadius: 22,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: hasPhoto
                ? CircleAvatar(
                    radius: 44,
                    backgroundImage: NetworkImage(authState.photoURL!),
                    onBackgroundImageError: (e, s) {},
                    backgroundColor: theme.backgroundColor,
                  )
                : CircleAvatar(
                    radius: 44,
                    backgroundColor: theme.accentColor.withValues(alpha: 0.14),
                    child: Icon(
                      Icons.person_rounded,
                      size: 44,
                      color: theme.accentColor,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // Uses publicLabel so it matches the leaderboard rendering — your
        // profile shows the same name everyone else sees.
        Text(
          authState.publicLabel,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: theme.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        // Account status badge — clean tint pill, no gradient, no border.
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  authState.isAnonymous ? Icons.person : Icons.verified_user,
                  color: statusColor,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(
                  authState.isAnonymous ? 'Guest Player' : 'Verified Account',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Google Sign-In upgrade CTA (for guest users only).
        if (authState.isAnonymous && !authState.isGoogleUser) ...[
          Text(
            'Save your progress and sync across devices',
            style: TextStyle(fontSize: 12, color: theme.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          NeonButton(
            onPressed: () => _handleGoogleUpgrade(context, theme),
            label: 'Sign in with Google',
            icon: Icons.login_rounded,
            theme: theme,
            expand: true,
          ),
          const SizedBox(height: 8),
        ],

        if (!authState.isLoading)
          NeonButton(
            onPressed: () => _showSignOutDialog(context, theme),
            label: 'Sign Out',
            icon: Icons.logout_rounded,
            theme: theme,
            variant: NeonButtonVariant.outline,
            expand: true,
          ),
      ],
    );
  }

  /// Borderless section header: uppercase HUD label floating straight on the
  /// starfield — no glass panel, no outlines.
  Widget _buildSectionLabel(
    GameTheme theme,
    IconData icon,
    String title, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, color: theme.accentColor, size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
              color: theme.accentColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailing,
      ],
    );
  }

  /// Transparent "View All" link — whole area tappable via opaque hit test.
  Widget _buildViewAllLink(GameTheme theme, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          'View All →',
          style: TextStyle(
            color: theme.accentColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context, GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(theme, Icons.bolt, 'Quick Actions'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionButton(
                context,
                'Statistics',
                Icons.analytics_rounded,
                theme.accentColor,
                () => _navigateToStatistics(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionButton(
                context,
                'Replays',
                Icons.video_library_rounded,
                Colors.blue,
                () => _navigateToReplays(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionButton(
                context,
                'Achievements',
                Icons.emoji_events_rounded,
                Colors.amber,
                () => _navigateToAchievements(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsSection(BuildContext context, GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(
          theme,
          Icons.bar_chart_rounded,
          'Statistics',
          trailing: _isLoading
              ? null
              : _buildViewAllLink(theme, () => _navigateToStatistics(context)),
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ThemedLoading(theme: theme, label: 'Loading stats...'),
          )
        else ...[
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'High Score',
                    _displayStats['highScore']?.toString() ?? '0',
                    Icons.emoji_events,
                    Colors.amber,
                    theme,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Games Played',
                    _displayStats['totalGames']?.toString() ?? '0',
                    Icons.games,
                    theme.accentColor,
                    theme,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Play Time',
                    '${_displayStats['totalPlayTime'] ?? '0s'}',
                    Icons.access_time,
                    Colors.blue,
                    theme,
                  ),
                ),
              ],
            ),
          ),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Average Score',
                    _displayStats['averageScore']?.toString() ?? '0',
                    Icons.trending_up,
                    Colors.green,
                    theme,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Enemies Destroyed',
                    _displayStats['totalFood']?.toString() ?? '0',
                    Icons.fastfood,
                    Colors.red,
                    theme,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'Power-ups',
                    _displayStats['totalPowerUps']?.toString() ?? '0',
                    Icons.flash_on,
                    Colors.yellow,
                    theme,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAchievementsSection(BuildContext context, GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(
          theme,
          Icons.emoji_events_rounded,
          'Achievements',
          trailing: _buildViewAllLink(
            theme,
            () => _navigateToAchievements(context),
          ),
        ),
        const SizedBox(height: 12),
        ..._recentAchievements.map(
          (achievement) => _buildAchievementCard(achievement, theme),
        ),
      ],
    );
  }

  Widget _buildReplaysSection(BuildContext context, GameTheme theme) {
    final replayKeys = _appCache.replayKeys ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(
          theme,
          Icons.movie_rounded,
          'Replays',
          trailing: _buildViewAllLink(
            theme,
            () => _navigateToReplays(context),
          ),
        ),
        const SizedBox(height: 12),
        if (replayKeys.isEmpty)
          Text(
            'No replays yet. Play some games!',
            style: TextStyle(color: theme.textMuted, fontSize: 13),
          )
        else
          Row(
            children: [
              const Icon(
                Icons.video_library_rounded,
                color: Colors.purple,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                '${replayKeys.length} replays saved',
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
    GameTheme theme,
  ) {
    // Fully transparent per the clean design — the coloured icon + value
    // carry the cell, no fill.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 2),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: theme.textMuted),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    // Gradient CTA tile — deliberate fill, borderless per the clean design.
    return Container(
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.8), color.withValues(alpha: 0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getRarityColor(AchievementRarity rarity) {
    switch (rarity) {
      case AchievementRarity.common:
        return Colors.grey;
      case AchievementRarity.rare:
        return Colors.blue;
      case AchievementRarity.epic:
        return Colors.purple;
      case AchievementRarity.legendary:
        return Colors.amber;
      case AchievementRarity.diamond:
        return Colors.cyanAccent;
    }
  }

  String _getRarityDisplayName(AchievementRarity rarity) {
    switch (rarity) {
      case AchievementRarity.common:
        return 'Common';
      case AchievementRarity.rare:
        return 'Rare';
      case AchievementRarity.epic:
        return 'Epic';
      case AchievementRarity.legendary:
        return 'Legendary';
      case AchievementRarity.diamond:
        return 'Diamond';
    }
  }

  Widget _buildAchievementCard(Achievement achievement, GameTheme theme) {
    final rarityColor = _getRarityColor(achievement.rarity);

    // Transparent row — the rarity-coloured icon disc carries the emphasis:
    // solid rarity + soft glow when unlocked, a faint tint when locked.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: achievement.isUnlocked
                  ? rarityColor
                  : rarityColor.withValues(alpha: 0.16),
              boxShadow: achievement.isUnlocked
                  ? [
                      BoxShadow(
                        color: rarityColor.withValues(alpha: 0.45),
                        blurRadius: 12,
                        spreadRadius: -1,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              achievement.icon,
              color: achievement.isUnlocked ? Colors.white : rarityColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: theme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  style: TextStyle(fontSize: 12, color: theme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Rarity pill — clean tint, no gradient, no border.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: rarityColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _getRarityDisplayName(achievement.rarity),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: rarityColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToStatistics(BuildContext context) {
    context.push(AppRoutes.statistics);
  }

  void _navigateToAchievements(BuildContext context) {
    context.push(AppRoutes.achievements);
  }

  void _navigateToReplays(BuildContext context) {
    context.push(AppRoutes.replays);
  }

  void _showStyledSnackBar(
    BuildContext context,
    String message,
    Color color,
    GameTheme theme,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _handleGoogleUpgrade(
    BuildContext context,
    GameTheme theme,
  ) async {
    try {
      final authCubit = context.read<AuthCubit>();
      final success = await authCubit.signInWithGoogle();

      if (success && context.mounted) {
        _showStyledSnackBar(
          context,
          'Successfully upgraded to Google account! 🎉',
          Colors.green,
          theme,
        );
      } else if (context.mounted) {
        _showStyledSnackBar(
          context,
          'Failed to upgrade account. Please try again.',
          Colors.red,
          theme,
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showStyledSnackBar(
          context,
          'An error occurred during account upgrade.',
          Colors.red,
          theme,
        );
      }
    }
  }

  void _showSignOutDialog(BuildContext context, GameTheme theme) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Sign Out',
          style: TextStyle(
            color: theme.primaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to sign out?\n\nYour progress will be saved if you\'re signed in with Google.',
          style: TextStyle(color: theme.textMuted, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: theme.accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final authCubit = context.read<AuthCubit>();
              await authCubit.signOut();
              if (context.mounted) {
                _showStyledSnackBar(
                  context,
                  'Signed out successfully 👋',
                  Colors.blue,
                  theme,
                );
              }
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
