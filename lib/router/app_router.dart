import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/models/game_replay.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/screens/achievements_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/battle_pass_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/challenges_hub_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/email_auth_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/first_time_auth_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/privacy_consent_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/username_setup_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/friends_leaderboard_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/friends_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/gameplay_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/home_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/instructions_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/leaderboard_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/level_select_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/loading_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/pre_game_loading_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/premium_benefits_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/profile_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/replay_viewer_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/replays_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/settings_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/statistics_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/store_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/tournament_detail_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/tournaments_screen.dart';

/// Zoom-in page transition (default for most routes)
CustomTransitionPage<void> _zoomPage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );
    },
  );
}

/// Scale page transition (dramatic reveal for game screen)
CustomTransitionPage<void> _scalePage(GoRouterState state, Widget child) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return ScaleTransition(
        scale: Tween<double>(begin: 0.85, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        ),
        child: FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
          child: child,
        ),
      );
    },
  );
}

/// Late-initialized global GoRouter instance.
late final GoRouter appRouter;

/// Global key on the root Navigator. SyncEngine uses it to insert the
/// first-sign-in OverlayEntry above whatever route the user is on when
/// sign-in fires (could be FirstTimeAuthScreen, LoadingScreen, or
/// ProfileScreen's "Save your progress" upgrade — anywhere).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'rootNavigator',
);

/// Creates a [GoRouter] with optional [NavigatorObserver]s for analytics.
GoRouter createAppRouter({List<NavigatorObserver>? observers}) => GoRouter(
  initialLocation: AppRoutes.loading,
  navigatorKey: rootNavigatorKey,
  debugLogDiagnostics: true,
  observers: observers ?? [],
  routes: [
    // Core routes
    GoRoute(
      path: AppRoutes.loading,
      name: 'loading',
      builder: (context, state) => const LoadingScreen(),
    ),
    GoRoute(
      path: AppRoutes.firstTimeAuth,
      name: 'firstTimeAuth',
      pageBuilder: (context, state) =>
          _zoomPage(state, const FirstTimeAuthScreen()),
    ),
    GoRoute(
      path: AppRoutes.privacyConsent,
      name: 'privacyConsent',
      pageBuilder: (context, state) =>
          _zoomPage(state, const PrivacyConsentScreen()),
    ),
    GoRoute(
      path: AppRoutes.emailAuth,
      name: 'emailAuth',
      pageBuilder: (context, state) {
        // `link` query flag distinguishes the upgrade-from-anonymous flow
        // from a fresh sign-in. Set when launching from the purchase-gate
        // bottom sheet.
        final isLink = state.uri.queryParameters['link'] == '1';
        return _zoomPage(state, EmailAuthScreen(linkFromAnonymous: isLink));
      },
    ),
    GoRoute(
      path: AppRoutes.usernameSetup,
      name: 'usernameSetup',
      pageBuilder: (context, state) =>
          _zoomPage(state, const UsernameSetupScreen()),
    ),
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      pageBuilder: (context, state) => _zoomPage(state, const HomeScreen()),
    ),

    // Game flow
    GoRoute(
      path: AppRoutes.levelSelect,
      name: 'levelSelect',
      pageBuilder: (context, state) =>
          _zoomPage(state, const LevelSelectScreen()),
    ),
    GoRoute(
      path: AppRoutes.playLoading,
      name: 'playLoading',
      // `extra` carries the 1-based campaign start level from level select
      // (per-run transient — route extra, not a cubit; null-safe for deep
      // links, defaulting to level 1).
      pageBuilder: (context, state) => _zoomPage(
        state,
        PreGameLoadingScreen(startLevel: state.extra as int? ?? 1),
      ),
    ),
    GoRoute(
      path: AppRoutes.game,
      name: 'game',
      pageBuilder: (context, state) => _scalePage(
        state,
        GameplayScreen(startLevel: state.extra as int? ?? 1),
      ),
    ),
    // /game-over removed: the Flame GameplayScreen shows its own game-over
    // overlay and routes home, so the ship GameOverScreen is no longer used.

    // Profile & Stats
    GoRoute(
      path: AppRoutes.profile,
      name: 'profile',
      pageBuilder: (context, state) => _zoomPage(state, const ProfileScreen()),
    ),
    GoRoute(
      path: AppRoutes.settings,
      name: 'settings',
      pageBuilder: (context, state) => _zoomPage(state, const SettingsScreen()),
    ),
    GoRoute(
      path: AppRoutes.statistics,
      name: 'statistics',
      pageBuilder: (context, state) =>
          _zoomPage(state, const StatisticsScreen()),
    ),
    GoRoute(
      path: AppRoutes.achievements,
      name: 'achievements',
      pageBuilder: (context, state) =>
          _zoomPage(state, const AchievementsScreen()),
    ),

    // Social & Competitive
    GoRoute(
      path: AppRoutes.leaderboard,
      name: 'leaderboard',
      pageBuilder: (context, state) =>
          _zoomPage(state, const LeaderboardScreen()),
    ),
    GoRoute(
      path: AppRoutes.friendsLeaderboard,
      name: 'friendsLeaderboard',
      pageBuilder: (context, state) =>
          _zoomPage(state, const FriendsLeaderboardScreen()),
    ),
    GoRoute(
      path: AppRoutes.friends,
      name: 'friends',
      pageBuilder: (context, state) => _zoomPage(state, const FriendsScreen()),
    ),
    GoRoute(
      path: AppRoutes.tournaments,
      name: 'tournaments',
      pageBuilder: (context, state) =>
          _zoomPage(state, const TournamentsScreen()),
    ),
    GoRoute(
      path: AppRoutes.tournamentDetail,
      name: 'tournamentDetail',
      pageBuilder: (context, state) {
        // Get tournament ID from path parameter
        final tournamentId = state.pathParameters['id'] ?? '';
        // Get tournament object from extra if available (for instant display)
        final tournament = state.extra as Tournament?;

        return _zoomPage(
          state,
          TournamentDetailScreen(
            tournamentId: tournamentId,
            tournament: tournament,
          ),
        );
      },
    ),

    // Monetization
    GoRoute(
      path: AppRoutes.store,
      name: 'store',
      pageBuilder: (context, state) {
        // Get initial tab from query parameter
        final tabString = state.uri.queryParameters['tab'];
        final initialTab = tabString != null ? int.tryParse(tabString) ?? 0 : 0;
        return _zoomPage(state, StoreScreen(initialTab: initialTab));
      },
    ),
    GoRoute(
      path: AppRoutes.premiumBenefits,
      name: 'premiumBenefits',
      pageBuilder: (context, state) =>
          _zoomPage(state, const PremiumBenefitsScreen()),
    ),
    // Cosmetics route is preserved as a redirect to the store's Skins tab.
    // The standalone CosmeticsScreen was removed when the store screen
    // inlined its content. Deep links from older builds (or in-game prompts)
    // still resolve cleanly through this redirect.
    GoRoute(
      path: AppRoutes.cosmetics,
      name: 'cosmetics',
      redirect: (context, state) => '${AppRoutes.store}?tab=3',
    ),
    GoRoute(
      path: AppRoutes.battlePass,
      name: 'battlePass',
      pageBuilder: (context, state) =>
          _zoomPage(state, const BattlePassScreen()),
    ),

    // Other features — both quest routes land on the same hub, opened on
    // the matching tab (Daily | Weekly).
    GoRoute(
      path: AppRoutes.dailyChallenges,
      name: 'dailyChallenges',
      pageBuilder: (context, state) =>
          _zoomPage(state, const ChallengesHubScreen(initialTab: 0)),
    ),
    GoRoute(
      path: AppRoutes.weeklyQuests,
      name: 'weeklyQuests',
      pageBuilder: (context, state) =>
          _zoomPage(state, const ChallengesHubScreen(initialTab: 1)),
    ),
    GoRoute(
      path: AppRoutes.instructions,
      name: 'instructions',
      pageBuilder: (context, state) =>
          _zoomPage(state, const InstructionsScreen()),
    ),
    GoRoute(
      path: AppRoutes.replays,
      name: 'replays',
      pageBuilder: (context, state) => _zoomPage(state, const ReplaysScreen()),
    ),
    GoRoute(
      path: AppRoutes.replayViewer,
      name: 'replayViewer',
      pageBuilder: (context, state) {
        // Get replay ID from path parameter
        final replayId = state.pathParameters['id'] ?? '';
        // Get replay object from extra if available (for instant display)
        final replay = state.extra as GameReplay?;

        return _zoomPage(
          state,
          ReplayViewerScreen(replayId: replayId, replay: replay),
        );
      },
    ),
  ],
);
