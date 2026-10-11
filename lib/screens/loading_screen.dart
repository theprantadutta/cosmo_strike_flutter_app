import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
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
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:package_info_plus/package_info_plus.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _progressController;

  String _currentTask = 'Initializing Cosmo Strike...';
  double _progress = 0.0;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showRetryButton = false;

  final Random _random = Random();

  // Rotating "Did you know?" tips shown in the center while loading.
  Timer? _tipTimer;
  int _tipIndex = 0;
  static const List<String> _tips = [
    'Read the wave ahead — enemies telegraph where they\'ll strike next.',
    'Bonus Pickups are worth more points, but they disappear fast. Grab them quick!',
    'Destroyed? Watch a quick ad or spend coins to revive and keep your score.',
    'Chain kills without a break to build a combo multiplier.',
    'Pinned down? Slip to the screen edge to buy yourself a moment.',
    'Daily challenges and weekly quests stack up coins fast.',
    'Cosmo Strike Pro removes all ads and doubles your coin rewards.',
    'Time Attack: three minutes on the clock — score as fast as you can.',
    'Power-ups stack: arm a shield before charging a tight gap.',
    'Switch themes, skins, and engine trails anytime in the store for a fresh look.',
  ];

  @override
  void initState() {
    super.initState();

    // Hide the Splash Screen after initialization
    FlutterNativeSplash.remove();

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 200), // Faster progress updates
      vsync: this,
    );

    // Seed a random starting tip so it's not always the same on every launch,
    // then rotate through them with a gentle fade while loading.
    _tipIndex = _random.nextInt(_tips.length);
    _tipTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (!mounted) return;
      setState(() => _tipIndex = (_tipIndex + 1) % _tips.length);
    });

    // Start the initialization process
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      // Step 1: Initialize Core Services
      await _updateProgress(
        0.1,
        'Initializing core systems...',
        'Setting up Server connection',
      );
      await _initializeCoreServices();

      // Step 2: Initialize User System
      await _updateProgress(
        0.25,
        'Creating your player profile...',
        'Generating unique username',
      );
      await _initializeUserSystem();

      // Step 3: Load User Preferences
      await _updateProgress(
        0.4,
        'Loading your preferences...',
        'Syncing themes and settings',
      );
      await _initializePreferences();

      // Step 4a: Bootstrap DataSyncService — fast local op, needed before
      // preload because preload paths call into the sync service.
      await _updateProgress(
        0.50,
        'Syncing with cloud...',
        'Ensuring data is up to date',
      );
      await _initializeDataSyncService();

      // Step 4b + 5: Drain the outgoing sync queue AND fetch fresh data
      // concurrently. Previously the drain ran sequentially before the
      // preload, adding its full duration to the loading screen even
      // though the two operations don't depend on each other (drain is
      // POST-to-server, preload is GET-from-server).
      await _updateProgress(
        0.60,
        'Loading game data...',
        'Fetching Game Data',
      );
      await Future.wait([
        _preloadAllDataConcurrently(),
        _drainSyncQueue(),
      ]);

      // Step 6: Initialize Audio System
      await _updateProgress(
        0.90,
        'Configuring audio system...',
        'Loading sound effects',
      );
      await _initializeAudio();

      // Step 8: Check for first-time user
      await _updateProgress(0.98, 'Checking setup status...', 'Almost ready!');

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
          AppLogger.warning('AuthCubit local init timeout, checking prefs directly');
          try {
            final prefs = await SharedPreferences.getInstance();
            final isFirstTimeFromPrefs = !(prefs.getBool('first_time_setup_complete') ?? false);
            // Update state if needed (though authCubit should have it by now)
            if (authCubit.state.isFirstTimeUser != isFirstTimeFromPrefs) {
              AppLogger.info('Using direct prefs check: isFirstTime=$isFirstTimeFromPrefs');
            }
          } catch (_) {
            // Ignore - use whatever authCubit has
          }
        }

        final isFirstTime = authCubit.state.isFirstTimeUser;

        if (isFirstTime) {
          await _updateProgress(1.0, 'Welcome!', 'Choose how to continue');
          await Future.delayed(
            const Duration(milliseconds: 50),
          ); // Reduced from 100ms

          // Navigate to first-time auth screen
          if (!mounted) {
            return;
          }
          context.go(AppRoutes.firstTimeAuth);
          return;
        }
      }

      // Returning user: if the privacy policy has changed version since they
      // last accepted it, gate them through the re-consent screen first.
      final policyAccepted = await PrivacyPolicy.isCurrentVersionAccepted();
      if (!policyAccepted) {
        if (!mounted) return;
        context.go(AppRoutes.privacyConsent);
        return;
      }

      // Step 9: Complete (for returning users)
      await _updateProgress(
        1.0,
        'Ready to play!',
        'Welcome back to Cosmo Strike',
      );
      await Future.delayed(
        const Duration(milliseconds: 50),
      ); // Reduced from 100ms

      // Navigation to Home Screen with smooth transition (returning users)
      if (mounted) {
        context.go(AppRoutes.home);
      }
    } catch (error) {
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

      final syncService = Provider.of<DataSyncService>(
        context,
        listen: false,
      );

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

      final syncService = Provider.of<DataSyncService>(
        context,
        listen: false,
      );
      await syncService.forceSyncNow();
      AppLogger.success('Force sync completed');
    } catch (e) {
      AppLogger.sync('Force sync warning', e);
    }
  }

  Future<void> _updateProgress(
    double progress,
    String message,
    String subMessage,
  ) async {
    if (!mounted) return;

    setState(() {
      _progress = progress;
      _currentTask = message;
    });

    _progressController.reset();
    _progressController.forward();

    // Minimal delay for UI update (reduced from 50ms)
    await Future.delayed(const Duration(milliseconds: 16)); // ~1 frame
  }

  void _handleError(String error) {
    if (!mounted) return;

    setState(() {
      _hasError = true;
      _errorMessage = error;
      _showRetryButton = true;
    });
  }

  Future<void> _retryInitialization() async {
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _showRetryButton = false;
      _progress = 0.0;
      _currentTask = 'Retrying initialization...';
    });

    await _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    // Prism Noir splash: identical #0A0A0D ground to the native splash, so the
    // hand-off is invisible; then the mark scales in, the wordmark rises and
    // the prism line tracks real init progress.
    return Scaffold(
      backgroundColor: CsColors.bg,
      body: CsBackground(
        stars: true,
        washes: const [CsWash.violetCenter, CsWash.cyanBottomLeft, CsWash.pinkBottomRight],
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: CsMotion.slow,
            child: _hasError ? _buildErrorView() : _buildLoadingView(),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    final cs = context.cs;
    final t = cs.type;
    return Stack(
      key: const ValueKey('loading'),
      children: [
        Center(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 500),
                  curve: CsMotion.standard,
                  builder: (_, v, child) => Opacity(
                    opacity: v,
                    child: Transform.scale(scale: 0.92 + 0.08 * v, child: child),
                  ),
                  child: CsLogoMark(size: cs.isCompact ? 110 : 150),
                ),
                SizedBox(height: cs(22)),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 500),
                  curve: const Interval(0.3, 1, curve: CsMotion.standard),
                  builder: (_, v, child) => Opacity(
                    opacity: v,
                    child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child),
                  ),
                  child: const CsWordmark(size: 26, spacing: 0.2),
                ),
                SizedBox(height: cs(22)),
                CsProgressLine(value: _progress, width: cs(180), gradient: CsGradients.prism),
                SizedBox(height: cs(18)),
                AnimatedSwitcher(
                  duration: CsMotion.base,
                  child: Text(
                    _currentTask.replaceAll('...', '').replaceAll('…', '').toUpperCase(),
                    key: ValueKey(_currentTask),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.mono(10, em: 0.2, color: CsColors.ink55),
                  ),
                ),
                SizedBox(height: cs(14)),
                SizedBox(
                  width: cs(420),
                  height: cs(36),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Text(
                      _tips[_tipIndex],
                      key: ValueKey<int>(_tipIndex),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(color: CsColors.ink30),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: cs(18),
          child: FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) {
              final v = snap.data?.version;
              return Text(
                [if (v != null) 'v$v', 'Developed by Pranta Dutta'].join(' · ').toUpperCase(),
                textAlign: TextAlign.center,
                style: t.mono(10, color: CsColors.ink30),
              );
            },
          ),
        ),
      ],
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
