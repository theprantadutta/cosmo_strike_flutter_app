import 'dart:async';

import 'package:flutter/widgets.dart';

import 'analytics_facade.dart';

/// A [NavigatorObserver] that automatically tracks screen views
/// via [AnalyticsFacade] on push, pop, and replace events.
class AnalyticsRouteObserver extends NavigatorObserver {
  final AnalyticsFacade _analytics;

  AnalyticsRouteObserver(this._analytics);

  String? _screenName(Route<dynamic>? route) {
    return route?.settings.name;
  }

  void _track(String? screenName) {
    if (screenName != null && screenName.isNotEmpty) {
      unawaited(_analytics.trackScreenView(screenName));
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(_screenName(route));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _track(_screenName(previousRoute));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _track(_screenName(newRoute));
  }
}
