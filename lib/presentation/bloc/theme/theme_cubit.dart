import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_state.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/preferences_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/theme_transition_system.dart';

import 'theme_state.dart';

export 'theme_state.dart';

/// Cubit for managing app theme state
class ThemeCubit extends Cubit<ThemeState> {
  final PreferencesService _preferencesService;
  final AnalyticsFacade _analytics;

  ThemeCubit(this._preferencesService, this._analytics)
      : super(ThemeState.initial());

  /// Initialize the theme cubit by loading saved preferences
  Future<void> initialize() async {
    if (state.status == ThemeStatus.ready) return;

    emit(state.copyWith(status: ThemeStatus.loading));

    try {
      await _preferencesService.initialize();

      final savedTheme = _preferencesService.selectedTheme;
      final trailEnabled = _preferencesService.trailSystemEnabled;

      emit(
        state.copyWith(
          status: ThemeStatus.ready,
          currentTheme: savedTheme,
          trailSystemEnabled: trailEnabled,
        ),
      );
    } catch (e) {
      // On error, use defaults and mark as ready
      emit(state.copyWith(status: ThemeStatus.ready));
    }
  }

  /// Set the current theme
  Future<void> setTheme(GameTheme theme) async {
    if (state.currentTheme == theme) return;

    emit(state.copyWith(currentTheme: theme));
    await _preferencesService.setTheme(theme);
    _analytics.trackThemeSelected(theme.name);

    // Push the choice to the backend so it survives reinstall/device-switch.
    // Premium themes are the typical case worth syncing, but we sync all
    // applied themes (including free ones) for simplicity — the value is
    // tiny and the API call is fire-and-forget.
    unawaited(ApiService().setEquippedCosmetics(themeId: theme.name));
  }

  /// Apply a theme from the backend ONLY if the local choice is still the
  /// default (classic). Called by PremiumCubit during sync to restore
  /// the equipped theme after reinstall/device-switch without overriding
  /// a deliberate local pick. No backend push — the value came FROM there.
  Future<void> applyEquippedThemeFromBackend(String themeName) async {
    if (state.currentTheme != GameTheme.classic) return;
    final target = GameTheme.values.where((t) => t.name == themeName).firstOrNull;
    if (target == null || target == GameTheme.classic) return;
    emit(state.copyWith(currentTheme: target));
    await _preferencesService.setTheme(target);
  }

  /// Drop back to Classic if the currently-applied premium theme is no
  /// longer in the user's owned set (refund / chargeback / sub lapse).
  /// Pro subscribers get all premium themes implicitly, so this only
  /// fires for free-tier users with a previously-purchased theme that
  /// got revoked.
  Future<void> applyFallbackIfThemeRevoked(PremiumState premiumState) async {
    final current = state.currentTheme;
    if (!PremiumContent.isPremiumTheme(current)) return;
    if (premiumState.isThemeUnlocked(current)) return;
    emit(state.copyWith(currentTheme: GameTheme.classic));
    await _preferencesService.setTheme(GameTheme.classic);
  }

  /// Cycle to the next theme (only free themes; premium themes require explicit selection)
  void cycleTheme() {
    final themes = GameTheme.values
        .where((t) => !PremiumContent.isPremiumTheme(t))
        .toList();
    if (themes.isEmpty) return;
    final currentIndex = themes.indexOf(state.currentTheme);
    final nextIndex = currentIndex == -1 ? 0 : (currentIndex + 1) % themes.length;
    setTheme(themes[nextIndex]);
  }

  /// Get the preferred transition type for a theme
  TransitionType getPreferredTransition(GameTheme theme) {
    return ThemeTransitionPresets.getPreferredTransition(theme);
  }

  /// Set trail system enabled/disabled
  Future<void> setTrailSystemEnabled(bool enabled) async {
    if (state.trailSystemEnabled == enabled) return;

    emit(state.copyWith(trailSystemEnabled: enabled));
    await _preferencesService.setTrailSystemEnabled(enabled);
  }

  /// Toggle trail system
  Future<void> toggleTrailSystem() async {
    await setTrailSystemEnabled(!state.trailSystemEnabled);
  }
}
