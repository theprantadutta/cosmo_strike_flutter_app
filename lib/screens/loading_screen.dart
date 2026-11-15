import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/utils/privacy_policy.dart';
import 'package:cosmo_strike_flutter_app/services/achievement_service.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/connectivity_service.dart';
import 'package:cosmo_strike_flutter_app/services/data_sync_service.dart';
import 'package:cosmo_strike_flutter_app/services/preferences_service.dart';
import 'package:cosmo_strike_flutter_app/services/first_run_service.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/services/hangar_service.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/core/startup/startup_guard.dart';
import 'package:cosmo_strike_flutter_app/core/startup/startup_reporter.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  bool _hasError = false;
  String _errorMessage = '';
  bool _showRetryButton = false;

  /// Backstop for a stalled init. Every step below is try/caught and bounded,
  /// but a call that neither completes nor throws (now or in a future edit)
  /// would leave the player under the splash forever. If we haven't routed by
  /// then, lift the splash and go Home. Longer than main's 15 s splash safety
  /// net, so by the time it fires the splash mirror is already showing.
  static const Duration _initWatchdog = Duration(seconds: 18);

  /// How long the error view stays before carrying the player Home anyway.
  /// Reaching it means main()'s bootstrap succeeded, so Home works.
  static const Duration _errorFallback = Duration(seconds: 5);

  /// Per-step budgets for the non-critical init steps (local work / network
  /// with offline fallbacks). A step that runs over is abandoned, not failed.
  static const Duration _localStepTimeout = Duration(seconds: 5);
  static const Duration _networkStepTimeout = Duration(seconds: 8);

  Timer? _watchdogTimer;

  /// Guards against a double navigation when the watchdog fires at the same
  /// moment init finishes. First caller of [_leaveLoadingScreen] wins.
  bool _navigated = false;

  /// Whether the init path already started FirstRunService (so the watchdog
  /// doesn't start it a second time).
  bool _firstRunStarted = false;

  final Stopwatch _sinceMount = Stopwatch()..start();

  @override
  void initState() {
    super.initState();

    // The NATIVE splash stays up for the whole startup (preserved in main);
    // it is lifted in [_leaveLoadingScreen] right as we route.
    //
    // Arm the watchdog BEFORE init starts, so a step that hangs on its very
    // first await is still covered.
    _armWatchdog();

    // Start the initialization process
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    super.dispose();
  }

  void _armWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(_initWatchdog, _onWatchdog);
  }

  /// Init exceeded [_initWatchdog]. Route anyway, respecting the routing
  /// rules as far as a quick, bounded check allows: a returning player on an
  /// older policy still gets re-consent; everyone else goes Home (where both
  /// new and returning players are headed). A first-launch marker the stuck
  /// path never reached is written fire-and-forget.
  Future<void> _onWatchdog() async {
    if (_navigated || !mounted) return;
    AppLogger.warning(
      'Loading watchdog fired after ${_initWatchdog.inSeconds}s — routing anyway',
    );
    StartupReporter.recordError(
      StateError('Loading screen init exceeded ${_initWatchdog.inSeconds}s'),
      StackTrace.current,
      reason: 'Loading screen watchdog',
    );

    final authCubit = context.read<AuthCubit>();
    final isFirstTime = authCubit.state.isFirstTimeUser;
    if (!_firstRunStarted) {
      _firstRunStarted = true;
      unawaited(FirstRunService.instance.initialize(hasPriorPlay: !isFirstTime));
    }
    if (isFirstTime) {
      unawaited(authCubit.markFirstTimeSetupComplete().catchError((Object _) {}));
    }

    final reconsent = await _boundedStep(
      'reconsent_check_watchdog',
      PrivacyPolicy.needsReconsent(),
      const Duration(seconds: 1),
      orElse: () => false,
    );
    _leaveLoadingScreen(
      reconsent ? AppRoutes.privacyConsent : AppRoutes.home,
      reason: 'watchdog',
    );
  }

  /// Single exit point from this screen: lifts the splash and routes.
  void _leaveLoadingScreen(String route, {required String reason}) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _watchdogTimer?.cancel();
    final ms = _sinceMount.elapsedMilliseconds;
    AppLogger.lifecycle('Leaving loading screen → $route ($reason, ${ms}ms)');
    StartupReporter.setKey('startup_route_reason', reason);
    StartupReporter.setKey('startup_loading_ms', ms);
    StartupReporter.log('loading screen → $route ($reason, ${ms}ms)');
    _liftSplash();
    context.go(route);
  }

  /// Bounds a non-critical step; on timeout logs and resolves to [orElse].
  Future<T> _boundedStep<T>(
    String label,
    Future<T> future,
    Duration timeout, {
    required T Function() orElse,
  }) {
    return withStepTimeout<T>(
      future,
      timeout,
      label: label,
      orElse: orElse,
      onTimedOut: (label, timeout) {
        AppLogger.warning(
          'Loading step "$label" timed out after ${timeout.inSeconds}s — continuing',
        );
        StartupReporter.log('loading step timeout: $label');
        StartupReporter.setKey('loading_timeout_$label', true);
      },
    );
  }

  Future<void> _initializeApp() async {
    try {
      // Step 1: Initialize Core Services
      await _updateProgress(
        0.1,
        'Powering up flight systems…',
        'Opening the uplink',
      );
      await _boundedStep<void>(
        'core_services',
        _initializeCoreServices(),
        _localStepTimeout,
        orElse: () {},
      );

      // Step 2: Initialize User System
      await _updateProgress(
        0.25,
        'Preparing your Pilot File…',
        'Assigning a call sign',
      );
      await _boundedStep<void>(
        'user_system',
        _initializeUserSystem(),
        _networkStepTimeout,
        orElse: () {},
      );

      // Step 3: Load User Preferences
      await _updateProgress(
        0.4,
        'Loading cockpit settings…',
        'Controls, audio, Sectors',
      );
      await _boundedStep<void>(
        'preferences',
        _initializePreferences(),
        _localStepTimeout,
        orElse: () {},
      );

      // Step 4a: Bootstrap DataSyncService — fast local op, needed before
      // preload because preload paths call into the sync service.
      await _updateProgress(
        0.50,
        'Syncing flight data…',
        'Checking the uplink',
      );
      await _boundedStep<void>(
        'data_sync_init',
        _initializeDataSyncService(),
        _localStepTimeout,
        orElse: () {},
      );

      // Step 4b + 5: Drain the outgoing sync queue AND fetch fresh data
      // concurrently. Previously the drain ran sequentially before the
      // preload, adding its full duration to the loading screen even
      // though the two operations don't depend on each other (drain is
      // POST-to-server, preload is GET-from-server).
      await _updateProgress(0.60, 'Loading mission data…', 'Campaign, Cups, Directives');
      await Future.wait([
        _boundedStep<void>(
          'preload',
          _preloadAllDataConcurrently(),
          _networkStepTimeout,
          orElse: () {},
        ),
        _boundedStep<void>(
          'sync_drain',
          _drainSyncQueue(),
          _networkStepTimeout,
          orElse: () {},
        ),
      ]);

      // Step 6: Initialize Audio System
      await _updateProgress(
        0.90,
        'Arming audio…',
        'Loading weapons and engine sounds',
      );
      await _initializeAudio();

      // Step 8: Check for first-time user
      await _updateProgress(0.98, 'Pre-flight checks…', 'Nearly cleared');

      if (mounted) {
        final authCubit = context.read<AuthCubit>();

        // Wait for local init only (fast, no network) with 2-second timeout
        // This uses the Completer instead of polling - more reliable and efficient
        try {
          await authCubit.waitForLocalInit().timeout(
            const Duration(seconds: 2),
          );
          AppLogger.info(
            'AuthCubit local init complete. isFirstTimeUser: ${authCubit.state.isFirstTimeUser}',
          );
        } catch (e) {
          // Timeout - fall back to checking SharedPreferences directly
          AppLogger.warning(
            'AuthCubit local init timeout, checking prefs directly',
          );
          try {
            final prefs = await SharedPreferences.getInstance();
            final isFirstTimeFromPrefs =
                !(prefs.getBool('first_time_setup_complete') ?? false);
            // Update state if needed (though authCubit should have it by now)
            if (authCubit.state.isFirstTimeUser != isFirstTimeFromPrefs) {
              AppLogger.info(
                'Using direct prefs check: isFirstTime=$isFirstTimeFromPrefs',
              );
            }
          } catch (_) {
            // Ignore - use whatever authCubit has
          }
        }

        final isFirstTime = authCubit.state.isFirstTimeUser;
        if (!_firstRunStarted) {
          _firstRunStarted = true;
          await _boundedStep<void>(
            'first_run',
            FirstRunService.instance.initialize(
              hasPriorPlay: !isFirstTime ||
                  StatisticsService().statistics.totalGamesPlayed > 0,
            ),
            const Duration(seconds: 3),
            orElse: () {},
          );
        }

        if (isFirstTime) {
          // No gates on first launch: the local guest created by
          // UnifiedUserService is already active, so straight to Home.
          // Privacy is a notice strip on Home (accepted on first Play);
          // sign-in and notifications are asked later — see FirstRunService.
          await _boundedStep<void>(
            'first_time_setup',
            authCubit.markFirstTimeSetupComplete(),
            const Duration(seconds: 3),
            orElse: () {},
          );
        }
      }

      // Only players who accepted an EARLIER policy version are gated
      // through re-consent; new players get the notice strip on Home.
      final needsReconsent = await _boundedStep(
        'reconsent_check',
        PrivacyPolicy.needsReconsent(),
        const Duration(seconds: 3),
        orElse: () => false,
      );
      if (needsReconsent) {
        _leaveLoadingScreen(AppRoutes.privacyConsent, reason: 'reconsent');
        return;
      }

      // Step 9: Complete (for returning users)
      await _updateProgress(
        1.0,
        'Cleared for launch',
        'Welcome back, pilot',
      );
      await Future.delayed(
        const Duration(milliseconds: 50),
      ); // Reduced from 100ms

      // Navigation to Home Screen with smooth transition (returning users)
      _leaveLoadingScreen(AppRoutes.home, reason: 'init complete');
    } catch (error, stackTrace) {
      StartupReporter.recordError(
        error,
        stackTrace,
        reason: 'Loading screen init failed',
      );
      _handleError('Initialization failed: $error');
    }
  }

  Future<void> _initializeCoreServices() async {
    try {
      AppLogger.lifecycle('Initializing core services');

      // Initialize connectivity service early so sync indicator works
      final connectivityService = ConnectivityService();
      await connectivityService.initialize();
      AppLogger.success('ConnectivityService initialized');

      // Core services (Firebase, Audio, etc.) already initialized in main()
    } catch (e) {
      AppLogger.error('Core services initialization warning', e);
    }
  }

  Future<void> _initializeUserSystem() async {
    try {
      AppLogger.lifecycle('Starting user system initialization...');

      if (!mounted) return;
      final unifiedUserService = Provider.of<UnifiedUserService>(
        context,
        listen: false,
      );

      await unifiedUserService.initialize();
      AppLogger.success('UnifiedUserService initialized');

      // AuthCubit is already initialized via MultiBlocProvider in main.dart
      // PurchaseService is already initialized in main.dart
      AppLogger.info('PurchaseService ready');

      AppLogger.success('User system initialization complete');
    } catch (e) {
      AppLogger.error('User system initialization error', e);
    }
  }

  Future<void> _initializePreferences() async {
    try {
      if (!mounted) return;

      // Cache context before async operations
      final currentContext = context;
      final preferencesService = Provider.of<PreferencesService>(
        currentContext,
        listen: false,
      );

      await preferencesService.initialize();

      // ThemeCubit and PremiumCubit are already initialized via MultiBlocProvider in main.dart
      AppLogger.info('Preferences and Cubits initialized successfully');
    } catch (e) {
      AppLogger.prefs('Preferences initialization warning', e);
    }
  }

  /// Load ALL data concurrently for maximum speed
  Future<void> _preloadAllDataConcurrently() async {
    try {
      AppLogger.lifecycle('Preloading all data concurrently');

      // All these run IN PARALLEL - much faster!
      await Future.wait([
        // Core services initialization
        _initializeStatistics(),
        _initializeAchievements(),

        // Preload ALL cached data (stats, settings, leaderboards, etc.)
        _preloadAppDataCache(),
      ]);

      AppLogger.success('All data preloaded concurrently');
    } catch (e) {
      AppLogger.error('Concurrent preload warning', e);
    }
  }

  Future<void> _preloadAppDataCache() async {
    try {
      final appCache = getIt<AppDataCache>();
      await appCache.preloadAll();
      AppLogger.success('AppDataCache preloaded successfully');
    } catch (e) {
      AppLogger.error('AppDataCache preload warning', e);
    }
  }

  Future<void> _initializeStatistics() async {
    try {
      AppLogger.stats('Initializing statistics service');

      final statisticsService = StatisticsService();
      await statisticsService.initialize();

      AppLogger.success('Statistics service initialized');
    } catch (e) {
      AppLogger.stats('Statistics initialization warning', e);
    }
  }

  Future<void> _initializeAchievements() async {
    try {
      AppLogger.achievement('Initializing achievement system');

      final achievementService = AchievementService();
      await achievementService.initialize();

      AppLogger.success('Achievement system initialized');
    } catch (e) {
      AppLogger.achievement('Achievement system initialization warning', e);
    }
  }

  Future<void> _initializeAudio() async {
    try {
      AppLogger.audio('Verifying audio service');
      // Audio already initialized in main() with sounds pre-loaded
      // Just access the singleton to verify it exists
      AudioService();
      AppLogger.success('Audio service verified - sounds pre-loaded and ready');
    } catch (e) {
      AppLogger.audio('Audio system verification warning', e);
    }
  }

  /// Fast, local-only initialization of DataSyncService. Must run before
  /// _preloadAllDataConcurrently because preload paths call into the sync
  /// service for cloud reads. This is just Drift bootstrap + connectivity
  /// listener wiring — typically <100ms.
  Future<void> _initializeDataSyncService() async {
    try {
      if (!mounted) return;

      final unifiedUserService = Provider.of<UnifiedUserService>(
        context,
        listen: false,
      );
      final userId = unifiedUserService.currentUser?.uid ?? 'local_pending';

      final syncService = Provider.of<DataSyncService>(context, listen: false);

      await syncService.initialize(userId);
      AppLogger.success('DataSyncService initialized with userId: $userId');
    } catch (e) {
      AppLogger.sync('DataSyncService init warning', e);
    }
  }

  /// Slow, network-bearing drain of the pending sync queue. Independent of
  /// the data preload, so it runs in parallel with _preloadAllDataConcurrently.
  /// Skips entirely for placeholder / offline users.
  Future<void> _drainSyncQueue() async {
    try {
      if (!mounted) return;

      final unifiedUserService = Provider.of<UnifiedUserService>(
        context,
        listen: false,
      );
      final userId = unifiedUserService.currentUser?.uid ?? 'local_pending';
      final isPlaceholder =
          userId.startsWith('local_') || userId.startsWith('offline_');

      if (isPlaceholder || unifiedUserService.currentUser == null) {
        AppLogger.info(
          'Skipping force sync — placeholder user or offline session',
        );
        return;
      }

      final syncService = Provider.of<DataSyncService>(context, listen: false);
      await syncService.forceSyncNow();
      AppLogger.success('Force sync completed');
    } catch (e) {
      AppLogger.sync('Force sync warning', e);
    }
  }

  /// Lift the native splash just before the first real screen appears.
  /// Removal is idempotent (main's safety net may already have done it).
  void _liftSplash() {
    FlutterNativeSplash.remove();
    // Warm the Hangar loadout so the first run applies it.
    unawaited(HangarService.instance.load());
  }

  Future<void> _updateProgress(
    double progress,
    String message,
    String subMessage,
  ) async {
    // Startup runs under the native splash, so progress is only logged.
    AppLogger.lifecycle('Startup ${(progress * 100).round()}% — $message');
  }

  void _handleError(String error) {
    FlutterNativeSplash.remove();
    if (!mounted || _navigated) return;

    setState(() {
      _hasError = true;
      _errorMessage = error;
      _showRetryButton = true;
    });

    // Not a dead end: every step is individually guarded, so reaching here
    // means something unexpected broke AFTER main()'s bootstrap succeeded —
    // the app itself is up and Home works. Show the error with Retry, then
    // carry the player on shortly either way.
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(
      _errorFallback,
      () => _leaveLoadingScreen(AppRoutes.home, reason: 'error fallback'),
    );
  }

  Future<void> _retryInitialization() async {
    // A retry gets a fresh full-length watchdog, so it is bounded too.
    _armWatchdog();
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _showRetryButton = false;
    });

    await _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    // Normally hidden under the native splash. If the splash is lifted before
    // init finishes (main's safety net), this draws the same mark + wordmark
    // in the same place, so nothing visibly changes; a quiet loading line
    // fades in under it.
    return Scaffold(
      backgroundColor: CsColors.bg,
      body: _hasError
          ? SafeArea(child: _buildErrorView())
          : const _NativeSplashMirror(),
    );
  }

  Widget _buildErrorView() {
    final cs = context.cs;
    return CsEmptyState.error(
      key: const ValueKey('error'),
      title: "Couldn't start up",
      message: _errorMessage,
      action: _showRetryButton
          ? CsButton.primary(
              label: 'Retry',
              icon: Symbols.refresh_rounded,
              onPressed: _retryInitialization,
            )
          : SizedBox(height: cs(1)),
    );
  }
}

/// Pixel-matches flutter_native_splash's layout: the 256dp splash mark centred
/// on the screen and the 200x80dp branding centred at the bottom.
class _NativeSplashMirror extends StatelessWidget {
  const _NativeSplashMirror();

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Center(
          child: Image.asset(
            'assets/images/brand/splash-mark.png',
            width: 256,
            height: 256,
            gaplessPlayback: true,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 24 + bottom,
          child: Center(
            child: Image.asset(
              'assets/images/brand/splash-branding.png',
              width: 200,
              height: 80,
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, 0.42),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: const Interval(0.5, 1),
            builder: (_, v, child) => Opacity(opacity: v, child: child),
            child: const CsLoadingLine(width: 120),
          ),
        ),
      ],
    );
  }
}
