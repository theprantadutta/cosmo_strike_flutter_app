import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
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
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _progressController;

  String _currentTask = 'Initializing Cosmo Strike...';
  String _subTask = '';
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
    'Cosmo Strike Pro unlocks bigger arenas and removes all ads.',
    'Time Attack rewards speed — and you can watch an ad for +30 seconds.',
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
      _subTask = subMessage;
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
      _subTask = '';
    });

    await _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;

        return Scaffold(
          // Same animated deep-space scene as the home screen (nebulae, sun,
          // planets, drifting starfield) — replaces the old bespoke gradient
          // + particle painter so the first screen matches the app.
          body: AppBackground(
            theme: theme,
            child: SafeArea(
              child: _hasError
                  ? _buildErrorView(theme)
                  : _buildLoadingView(theme),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingView(GameTheme theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Landscape phones report a short height — treat < 600 as "compact"
        // (smaller logo/text) so nothing clips.
        final isSmallScreen = constraints.maxHeight < 600;

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Column(
            children: [
              // Landscape body: branding on the left, live loading status
              // (spinner + progress + tip) on the right. Each side centers and
              // can scroll on tiny screens so content never overflows.
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: SingleChildScrollView(
                          primary: false,
                          child: _buildGameHeader(theme, isSmallScreen),
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 6,
                      child: Center(
                        child: SingleChildScrollView(
                          primary: false,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildEnhancedLoadingArea(theme, isSmallScreen),
                              const SizedBox(height: 14),
                              _buildProgressSection(theme, isSmallScreen),
                              const SizedBox(height: 12),
                              _buildTipCard(theme, isSmallScreen),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              _buildBrandedFooter(theme, isSmallScreen),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGameHeader(GameTheme theme, [bool isSmallScreen = false]) {
    final logoSize = isSmallScreen ? 88.0 : 110.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Glowing logo with the same shimmer treatment as the home brand.
        Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: theme.accentColor.withValues(alpha: 0.3),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/cosmo_strike_transparent.png',
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.rocket_launch,
              size: logoSize * 0.7,
              color: theme.accentColor,
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(
                duration: 2500.ms,
                color: theme.accentColor.withValues(alpha: 0.25),
              ),
        ),

        SizedBox(height: isSmallScreen ? 12 : 16),

        // Gradient wordmark — matches the home top-bar brand.
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [theme.primaryColor, theme.accentColor],
          ).createShader(bounds),
          child: Text(
            'COSMO STRIKE',
            style: TextStyle(
              fontSize: isSmallScreen ? 24 : 28,
              fontWeight: FontWeight.w900,
              color: Colors.white, // base for ShaderMask
              letterSpacing: 3,
            ),
          ),
        ),

        SizedBox(height: isSmallScreen ? 6 : 8),

        Text(
          'PREMIUM SPACE SHOOTER EXPERIENCE',
          style: TextStyle(
            fontSize: isSmallScreen ? 9 : 11,
            fontWeight: FontWeight.w600,
            color: theme.textMuted,
            letterSpacing: 1.5,
          ),
        ).gameEntrance(delay: 200.ms),
      ],
    );
  }

  Widget _buildEnhancedLoadingArea(
    GameTheme theme, [
    bool isSmallScreen = false,
  ]) {
    // Borderless per the clean design: the status floats straight on the
    // starfield. Fixed heights prevent layout shifts as messages change.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Current task with pulsing beacon — fixed height area.
          SizedBox(
            height: isSmallScreen ? 28 : 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.accentColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.accentColor.withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .scale(
                      begin: const Offset(0.8, 0.8),
                      end: const Offset(1.2, 1.2),
                    )
                    .then(delay: 200.ms)
                    .scale(
                      begin: const Offset(1.2, 1.2),
                      end: const Offset(0.8, 0.8),
                    ),

                const SizedBox(width: 12),

                Flexible(
                  child: Text(
                    _currentTask,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      fontWeight: FontWeight.w700,
                      color: theme.textPrimary,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Subtask area — fixed height whether content exists or not.
          SizedBox(
            height: isSmallScreen ? 16 : 20,
            child: _subTask.isNotEmpty
                ? Text(
                    _subTask,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 11 : 13,
                      color: theme.textMuted,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : const SizedBox(),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(GameTheme theme, [bool isSmallScreen = false]) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          // Slim neon progress bar — borderless track per the clean design.
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [

                  // Progress fill with animation
                  AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, child) {
                      return FractionallySizedBox(
                        widthFactor: _progress,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.accentColor,
                                theme.foodColor,
                                theme.accentColor,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // Shimmer effect
                  AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_progressController.value * 200 - 50, 0),
                        child: Container(
                          width: 50,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withValues(alpha: 0.0),
                                Colors.white.withValues(alpha: 0.4),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: isSmallScreen ? 12 : 16),

          // Progress percentage with enhanced styling
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LOADING',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.textMuted,
                  letterSpacing: 1.5,
                ),
              ),

              // Plain percentage — no chip box, clean design.
              Text(
                '${(_progress * 100).toInt()}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: theme.accentColor,
                ),
              ),
            ],
          ),
        ],
      ),
    ).gameZoomIn(delay: 300.ms);
  }

  Widget _buildTipCard(GameTheme theme, [bool isSmallScreen = false]) {
    // Borderless per the clean design — the tip floats on the starfield.
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 48 : 52,
        vertical: isSmallScreen ? 8 : 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: glowing bulb + label
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lightbulb_rounded,
                size: isSmallScreen ? 14 : 16,
                color: theme.foodColor,
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 900.ms)
                  .then()
                  .fade(begin: 1.0, end: 0.5, duration: 900.ms),
              const SizedBox(width: 8),
              Text(
                'DID YOU KNOW?',
                style: TextStyle(
                  fontSize: isSmallScreen ? 10 : 11,
                  fontWeight: FontWeight.w700,
                  color: theme.accentColor.withValues(alpha: 0.8),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),

          SizedBox(height: isSmallScreen ? 8 : 10),

          // Rotating tip text with a smooth fade/slide between tips. Fixed
          // height keeps the layout from jumping as tip lengths change.
          SizedBox(
            height: isSmallScreen ? 46 : 54,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  _tips[_tipIndex],
                  key: ValueKey<int>(_tipIndex),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 13.5,
                    height: 1.3,
                    color: theme.primaryColor.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).gameZoomIn(delay: 400.ms);
  }

  Widget _buildBrandedFooter(GameTheme theme, [bool isSmallScreen = false]) {
    // One slim muted line — borderless, no pill, per the clean design.
    return Text(
      'DEVELOPED BY PRANTA DUTTA',
      style: TextStyle(
        fontSize: isSmallScreen ? 9 : 10,
        fontWeight: FontWeight.w600,
        color: theme.textMuted,
        letterSpacing: 2,
      ),
      textAlign: TextAlign.center,
    ).gameEntrance(delay: 700.ms);
  }

  Widget _buildErrorView(GameTheme theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Error icon with animation
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.red.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: const Icon(Icons.error_outline, size: 64, color: Colors.red),
        ).animate().scale(delay: 200.ms).shake(),

        const SizedBox(height: 32),

        Text(
          'INITIALIZATION FAILED',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.primaryColor,
            letterSpacing: 1,
          ),
        ),

        const SizedBox(height: 16),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Text(
            _errorMessage,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            textAlign: TextAlign.center,
          ),
        ),

        if (_showRetryButton) ...[
          const SizedBox(height: 32),

          ElevatedButton(
                onPressed: _retryInitialization,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh),
                    const SizedBox(width: 8),
                    const Text(
                      'RETRY',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
              .gameZoomIn(delay: 300.ms),
        ],
      ],
    );
  }
}

