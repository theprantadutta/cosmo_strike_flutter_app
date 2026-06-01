import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/router/app_router.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import '../utils/logger.dart';

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  /// Get the root navigator context from GoRouter
  BuildContext? get _routerContext {
    return appRouter.routerDelegate.navigatorKey.currentContext;
  }

  /// Navigate to a screen based on route from notification
  Future<void> navigateFromNotification({
    required String route,
    Map<String, dynamic>? params,
    bool clearStack = false,
  }) async {
    try {
      AppLogger.info('Navigating from notification: $route');

      String routePath;

      switch (route.toLowerCase()) {
        case 'home':
          routePath = AppRoutes.home;
          break;

        case 'achievements':
          routePath = AppRoutes.achievements;
          break;

        case 'tournament_detail':
          // If we have a tournament ID, navigate to the detail page
          final tournamentId = params?['tournament_id'] as String?;
          if (tournamentId != null) {
            routePath = AppRoutes.tournamentDetailPath(tournamentId);
          } else {
            routePath = AppRoutes.tournaments;
          }
          break;

        case 'tournaments':
          routePath = AppRoutes.tournaments;
          break;

        case 'friends_screen':
        case 'social':
          routePath = AppRoutes.friends;
          break;

        case 'leaderboard':
          routePath = AppRoutes.leaderboard;
          break;

        case 'profile':
          routePath = AppRoutes.profile;
          break;

        case 'settings':
          routePath = AppRoutes.settings;
          break;

        default:
          AppLogger.warning(
            'Unknown navigation route: $route, falling back to home',
          );
          routePath = AppRoutes.home;
      }

      if (clearStack) {
        // Replace entire navigation stack (like pushAndRemoveUntil)
        appRouter.go(routePath);
      } else {
        // Push new screen on top of stack
        appRouter.push(routePath);
      }

      AppLogger.info('Navigation completed: $route');
    } catch (e) {
      AppLogger.error('Failed to navigate from notification', e);

      // Fallback to home screen
      appRouter.go(AppRoutes.home);
    }
  }

  /// Navigate to achievement detail with achievement ID
  Future<void> navigateToAchievement(String achievementId) async {
    await navigateFromNotification(
      route: 'achievements',
      params: {'achievement_id': achievementId},
    );
  }

  /// Navigate to tournament detail
  Future<void> navigateToTournament(String tournamentId) async {
    appRouter.push(AppRoutes.tournamentDetailPath(tournamentId));
  }

  /// Navigate to user profile or friends screen
  Future<void> navigateToSocial({String? userId}) async {
    await navigateFromNotification(
      route: 'friends_screen',
      params: userId != null ? {'user_id': userId} : null,
    );
  }

  /// Navigate to leaderboard with specific filters
  Future<void> navigateToLeaderboard({String? filter}) async {
    await navigateFromNotification(
      route: 'leaderboard',
      params: filter != null ? {'filter': filter} : null,
    );
  }

  /// Navigate to home screen (clear stack)
  Future<void> navigateToHome() async {
    appRouter.go(AppRoutes.home);
  }

  /// Pop current screen if possible
  void goBack() {
    if (appRouter.canPop()) {
      appRouter.pop();
    }
  }

  /// Check if we can go back
  bool canGoBack() {
    return appRouter.canPop();
  }

  /// Get current route name if available
  String? getCurrentRouteName() {
    return appRouter.routerDelegate.currentConfiguration.last.matchedLocation;
  }

  /// Show a snackbar message
  void showSnackBar(String message, {bool isError = false}) {
    final context = _routerContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : null,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Show a dialog
  Future<void> showAppDialog({
    required String title,
    required String message,
    List<Widget>? actions,
  }) async {
    final context = _routerContext;
    if (context != null && context.mounted) {
      await showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: Text(message),
            actions:
                actions ??
                [
                  TextButton(
                    child: const Text('OK'),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
          );
        },
      );
    }
  }
}
