import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';

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
  }

  int get gamesStarted => _gamesStarted;
  bool get isFirstGame => _gamesStarted == 0;
  bool get isInOnboarding => _gamesStarted < onboardingGameCount;
  bool get hasCompletedOnboarding => !isInOnboarding;

  DateTime? get installedAt {
    final ms = _prefs?.getInt(_kInstalledAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Call once per run start.
  Future<void> recordGameStarted() async {
    _gamesStarted++;
    try {
      await (_prefs ??= await SharedPreferences.getInstance()).setInt(_kGamesStarted, _gamesStarted);
    } catch (_) {}
  }
}
