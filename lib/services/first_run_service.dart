import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'analytics/analytics_facade.dart';

/// First-run / onboarding window, the gate for every deferred ask (sign-in,
/// notification soft-ask, game-mode picker, home prompt queue).
///
/// Device-only on purpose: SharedPreferences, not Drift, so a first-sign-in
/// cloud restore can't mark a fresh device as "onboarded". Counts runs
/// STARTED (a quit still counts) — mirrors Snake Classic's FirstRunService.
class FirstRunService {
  FirstRunService._();
  static final FirstRunService instance = FirstRunService._();

  /// Runs before the player counts as onboarded.
  static const int onboardingGameCount = 3;

  static const _kGamesStarted = 'first_run_games_started';
  static const _kInstalledAt = 'first_run_installed_at_ms';
  static const _kMigrated = 'first_run_migration_version';
  static const _kFirstGameAt = 'first_run_first_game_at_ms';

  SharedPreferences? _prefs;
  int _gamesStarted = onboardingGameCount; // fail safe: "onboarded"

  /// Loads the counters. [hasPriorPlay] marks installs from before this
  /// service existed (local stats show past runs) as already onboarded so
  /// veterans never see first-run asks.
  Future<void> initialize({required bool hasPriorPlay}) async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      prefs.getInt(_kInstalledAt) ?? await prefs.setInt(_kInstalledAt, DateTime.now().millisecondsSinceEpoch);
      if (prefs.getInt(_kMigrated) == null) {
        if (hasPriorPlay && (prefs.getInt(_kGamesStarted) ?? 0) < onboardingGameCount) {
          await prefs.setInt(_kGamesStarted, onboardingGameCount);
        }
        await prefs.setInt(_kMigrated, 1);
      }
      _gamesStarted = prefs.getInt(_kGamesStarted) ?? 0;
    } catch (e) {
      AppLogger.error('FirstRunService init failed', e);
    }
    _applyUserProperties();
  }

  /// Install cohort user properties: `install_week` (ISO year-week of
  /// [installedAt]) and `onboarding_done`, so every GA4 report can be
  /// split by install cohort.
  void _applyUserProperties() {
    final installed = installedAt;
    if (!GetIt.I.isRegistered<AnalyticsFacade>()) return;
    final analytics = GetIt.I<AnalyticsFacade>();
    if (installed != null) unawaited(analytics.setInstallWeek(installed));
    unawaited(analytics.setOnboardingDone(hasCompletedOnboarding));
  }

  int get gamesStarted => _gamesStarted;
  bool get isFirstGame => _gamesStarted == 0;
  bool get isInOnboarding => _gamesStarted < onboardingGameCount;
  bool get hasCompletedOnboarding => !isInOnboarding;

  DateTime? get installedAt {
    final ms = _prefs?.getInt(_kInstalledAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  DateTime? get firstGameAt {
    final ms = _prefs?.getInt(_kFirstGameAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Whole seconds from install to [now] (null before initialize).
  int? secondsSinceInstall([DateTime? now]) => _secondsSince(installedAt, now);

  /// Whole seconds from the first run's start to [now] (null if unknown).
  int? secondsSinceFirstGame([DateTime? now]) => _secondsSince(firstGameAt, now);

  static int? _secondsSince(DateTime? from, DateTime? now) {
    if (from == null) return null;
    final s = (now ?? DateTime.now()).difference(from).inSeconds;
    return s < 0 ? 0 : s;
  }

  /// Call once per run start. The counter bumps synchronously, so
  /// [gamesStarted] already includes this run when it returns; the first
  /// run also stamps [firstGameAt] (funnel analytics).
  Future<void> recordGameStarted() async {
    _gamesStarted++;
    final isFirst = _gamesStarted == 1;
    if (_gamesStarted == onboardingGameCount) _applyUserProperties();
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      if (isFirst && prefs.getInt(_kFirstGameAt) == null) {
        await prefs.setInt(_kFirstGameAt, DateTime.now().millisecondsSinceEpoch);
      }
      await prefs.setInt(_kGamesStarted, _gamesStarted);
    } catch (_) {}
  }
}
