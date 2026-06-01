import 'package:flutter/material.dart';

/// Available transition types for page navigation.
/// Only scale-based transitions — no slides.
enum AppTransitionType {
  /// Zoom in with fade - default for most screens
  zoomIn,

  /// Scale up with fade - for dramatic reveals (game screen)
  scale,

  /// No animation - instant transition
  none,
}

/// Custom page route with predefined transitions
class AppPageRoute<T> extends PageRouteBuilder<T> {
  /// The page widget to navigate to
  final Widget page;

  /// The type of transition animation
  final AppTransitionType transitionType;

  /// Optional custom duration (overrides default)
  final Duration? customDuration;

  AppPageRoute({
    required this.page,
    this.transitionType = AppTransitionType.zoomIn,
    this.customDuration,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration:
              customDuration ?? _getDuration(transitionType),
          reverseTransitionDuration:
              customDuration ?? _getDuration(transitionType),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return _buildTransition(
              transitionType,
              animation,
              secondaryAnimation,
              child,
            );
          },
        );

  /// Get default duration for each transition type
  static Duration _getDuration(AppTransitionType type) {
    switch (type) {
      case AppTransitionType.zoomIn:
        return const Duration(milliseconds: 300);
      case AppTransitionType.scale:
        return const Duration(milliseconds: 320);
      case AppTransitionType.none:
        return Duration.zero;
    }
  }

  /// Build the transition animation widget
  static Widget _buildTransition(
    AppTransitionType type,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    switch (type) {
      case AppTransitionType.zoomIn:
        return _ZoomInTransition(animation: animation, child: child);

      case AppTransitionType.scale:
        return _ScaleTransition(animation: animation, child: child);

      case AppTransitionType.none:
        return child;
    }
  }
}

/// Zoom in with fade transition - default for most screens
class _ZoomInTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _ZoomInTransition({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: 0.92,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ),
        child: child,
      ),
    );
  }
}

/// Scale up with fade transition - for dramatic reveals
class _ScaleTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _ScaleTransition({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: 0.85,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      )),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeIn,
        ),
        child: child,
      ),
    );
  }
}

/// Extension on NavigatorState for convenient transition navigation
extension NavigatorTransitionExtensions on NavigatorState {
  /// Push a page with specified transition type
  Future<T?> pushWithTransition<T extends Object?>(
    Widget page, {
    AppTransitionType type = AppTransitionType.zoomIn,
    RouteSettings? settings,
  }) {
    return push(AppPageRoute<T>(
      page: page,
      transitionType: type,
      settings: settings,
    ));
  }

  /// Push replacement with specified transition type
  Future<T?> pushReplacementWithTransition<T extends Object?, TO extends Object?>(
    Widget page, {
    AppTransitionType type = AppTransitionType.zoomIn,
    TO? result,
    RouteSettings? settings,
  }) {
    return pushReplacement(
      AppPageRoute<T>(
        page: page,
        transitionType: type,
        settings: settings,
      ),
      result: result,
    );
  }

  /// Push and remove until with specified transition type
  Future<T?> pushAndRemoveUntilWithTransition<T extends Object?>(
    Widget page,
    RoutePredicate predicate, {
    AppTransitionType type = AppTransitionType.zoomIn,
    RouteSettings? settings,
  }) {
    return pushAndRemoveUntil(
      AppPageRoute<T>(
        page: page,
        transitionType: type,
        settings: settings,
      ),
      predicate,
    );
  }
}

/// Helper function to create an AppPageRoute
/// Usage: Navigator.of(context).push(appRoute(MyScreen(), type: AppTransitionType.zoomIn))
Route<T> appRoute<T>(
  Widget page, {
  AppTransitionType type = AppTransitionType.zoomIn,
  RouteSettings? settings,
}) {
  return AppPageRoute<T>(
    page: page,
    transitionType: type,
    settings: settings,
  );
}
