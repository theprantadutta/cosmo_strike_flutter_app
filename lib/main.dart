import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'package:provider/provider.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/multiplayer/multiplayer_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/power_up/power_up_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/battle_pass_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/app_router.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_route_observer.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/auth_service.dart';
import 'package:cosmo_strike_flutter_app/services/data_sync_service.dart';
import 'package:cosmo_strike_flutter_app/services/haptic_service.dart';
import 'package:cosmo_strike_flutter_app/services/in_app_update_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/notification_service.dart';
import 'package:cosmo_strike_flutter_app/services/preferences_service.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/services/sync/sync_engine.dart';
import 'package:cosmo_strike_flutter_app/ui/design/immersive.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';
import 'package:cosmo_strike_flutter_app/services/walkthrough_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
import 'package:cosmo_strike_flutter_app/utils/typography.dart';
// import 'package:cosmo_strike_flutter_app/utils/performance_monitor.dart'; // temporarily disabled

import 'firebase_options.dart';

/// Whether critical init succeeded. If false, show an error screen.
bool _initSucceeded = false;

/// Captured init failure (shown on the error screen so a startup failure is
/// visible instead of an infinite splash).
String? _initError;

void main() async {
  // Ensure Flutter is initialized and preserve splash screen
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  AppLogger.lifecycle('Cosmo Strike starting up...');

  try {
    // Edge-to-edge mode for Android 15+ compliance. Content draws under the
    // (translucent) status + nav bars; SafeArea widgets on each screen handle
    // the inset padding. SystemUiMode.manual previously used here routed
    // through Flutter's deprecated setStatusBarColor / setNavigationBarColor
    // path which triggers Play Console's "deprecated APIs for edge-to-edge"
    // warning — see flutter/flutter#183372. The active game screen still
    // goes full-immersive via immersiveSticky (handled in GameScreen).
    // Full-screen game: hide the status/notification + nav bars app-wide from
    // first launch (immersiveSticky — swipe from an edge reveals them briefly).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ));

    // Load environment variables
    AppLogger.info('Loading environment variables...');
    await dotenv.load(fileName: '.env');
    AppLogger.success('Environment variables loaded');

    // Initialize Firebase
    AppLogger.firebase('Initializing Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AppLogger.success('Firebase initialized successfully');

    // Landscape-only: Cosmo Strike is a horizontal command-HUD experience
    // (side-scrolling shmup + wide UI). Lock both landscape orientations so
    // the device can flip between them but never rotates to portrait.
    AppLogger.ui('Setting device orientation...');
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Initialize dependency injection
    AppLogger.info('Configuring dependencies...');
    await configureDependencies();
    AppLogger.success('Dependencies configured');

    // Initialize router with analytics observer
    appRouter = createAppRouter(
      observers: [AnalyticsRouteObserver(getIt<AnalyticsFacade>())],
    );

    // Track app open (fire-and-forget)
    unawaited(getIt<AnalyticsFacade>().trackAppOpened());

    // Initialize independent services in parallel for faster startup
    // Note: PurchaseService.initialize() is NOT called here because
    // PremiumCubit.initialize() already calls it. Calling it twice would
    // double-subscribe to the purchase stream.
    AppLogger.info('Initializing services...');
    await AudioService().initialize().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        AppLogger.warning('Audio service init timed out — continuing without audio');
      },
    );
    AppLogger.success('Audio service initialized');

    // Start the background-music loop (no-op while the toggle is off).
    unawaited(AudioService().playBackgroundMusic());

    // Walkthrough flags (home tour / game tutorial / control choice) are
    // read SYNCHRONOUSLY at screen-build time — hydrate the prefs-backed
    // service up front so a launch into Play can never mis-read
    // "tutorial already done".
    await WalkthroughService().initialize();

    // Hydrate the haptics master toggle from the Drift settings row
    // (synced setting; defaults to on). HapticService is an in-memory
    // singleton — without this, every launch would vibrate regardless
    // of the saved preference.
    HapticService().setEnabled(await getIt<StorageService>().isHapticsEnabled());

    // NotificationService.initialize() is no longer called here — it
    // requests the OS notification permission as a side effect, and
    // showing that dialog before the user has seen the app would feel
    // intrusive. The call has moved to home_screen.dart's initState,
    // so the request only fires once the user has actually landed on
    // home and signed in (if applicable).

    InAppUpdateService().checkForUpdate().then((_) {
      AppLogger.success('In-app update check completed');
    });

    // Initialize ads (UMP consent + ATT + SDK). Fire-and-forget — the service
    // is mobile-only, Pro-gated, and self-disables on web/desktop or for Pro.
    unawaited(getIt<AdService>().initialize());

    AppLogger.success('All critical services initialized');

    // Wire up PurchaseService.setUserIdGetter so backend verification
    // includes the real user ID instead of 'anonymous_user'.
    PurchaseService().setUserIdGetter(() {
      return ApiService().currentUserId;
    });
    AppLogger.info('Purchase service user ID getter wired');

    // Wire ApiService.onUnauthorized to trigger re-authentication
    ApiService().onUnauthorized = () {
      AppLogger.warning('JWT expired — will re-authenticate on next API call');
      // AuthService.ensureBackendAuthentication() is called on app resume
      // and before critical API calls, so we just clear the token here.
    };

    // Boot the outbox drain engine. It owns the SyncQueue → backend
    // batch sync. Gated internally on auth + connectivity AND on the
    // first-sign-in restore having settled, so it's safe to fire
    // before sign-in completes — the drain stays asleep until
    // maybeRunFirstSignInPull arms it.
    unawaited(getIt<SyncEngine>().initialize(getIt<AppDatabase>()));

    // Hand the root navigator key to the engine so it can imperatively
    // insert the first-sign-in OverlayEntry above whatever route is
    // active when sign-in fires (could be a login screen, but could
    // also be ProfileScreen's "Save your progress" upgrade flow).
    getIt<SyncEngine>().attachNavigatorKey(rootNavigatorKey);

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    _initSucceeded = true;
    AppLogger.success('Cosmo Strike ready to launch!');
  } catch (error, stackTrace) {
    _initError = '$error';
    AppLogger.error('Failed to initialize Cosmo Strike', error, stackTrace);
  }

  // Setup global error handling — always, not just in debug mode
  FlutterError.onError = (details) {
    AppLogger.error('Flutter Error', details.exception, details.stack);
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };

  if (_initSucceeded) {
    // Safety net: the splash is normally lifted by LoadingScreen.initState.
    // If the first screen somehow never mounts, lift it anyway after a few
    // seconds so the app can never appear permanently frozen on the splash.
    Future.delayed(const Duration(seconds: 6), FlutterNativeSplash.remove);
    runApp(
      const riverpod.ProviderScope(
        child: CosmoStrikeApp(),
      ),
    );
  } else {
    // Critical init failed — remove the splash (otherwise it stays on top
    // forever, hiding this screen and making the app look frozen) and show a
    // minimal error screen with the actual cause instead of crashing.
    FlutterNativeSplash.remove();
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to start Cosmo Strike',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please restart the app. If this persists, try reinstalling.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  if (_initError != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _initError!,
                      style: TextStyle(color: Colors.red[300], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CosmoStrikeApp extends StatefulWidget {
  const CosmoStrikeApp({super.key});

  @override
  State<CosmoStrikeApp> createState() => _CosmoStrikeAppState();
}

class _CosmoStrikeAppState extends State<CosmoStrikeApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setImmersiveMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-apply immersive mode when app resumes
    if (state == AppLifecycleState.resumed) {
      _setImmersiveMode();
      // Trigger sync when app comes back to foreground
      DataSyncService().forceSyncNow();
      // Re-authenticate with backend if JWT expired and refresh premium state
      _refreshOnResume();
      unawaited(AudioService().resumeBackgroundMusic());
    }

    // Music pauses ONLY on a real background transition — `inactive`
    // fires on transient occlusions (permission dialogs, system sheets,
    // the gameplay screen's system-UI swaps) and pausing there would
    // stutter the track.
    if (state == AppLifecycleState.paused) {
      unawaited(AudioService().pauseBackgroundMusic());
    }

    // When app goes to background, attempt to sync pending data
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      DataSyncService().forceSyncNow();
    }
  }

  /// Ensure backend auth is fresh and sync premium/subscription status.
  Future<void> _refreshOnResume() async {
    try {
      // Network-independent first: if the locally-stored (server-authoritative)
      // subscription expiry has already passed, drop to free right now —
      // don't wait on connectivity or a successful backend round-trip.
      await getIt<PremiumCubit>().recheckLocalExpiry();
      await AuthService().ensureBackendAuthentication();
      // Retry any pending offline purchases
      await PurchaseService().retryPendingVerifications();
      // Sync premium entitlements (catches subscription renewals/cancellations)
      getIt<PremiumCubit>().syncWithBackend();
    } catch (e) {
      AppLogger.error('Error refreshing on resume', e);
    }
  }

  void _setImmersiveMode() {
    // Re-apply the edge-to-edge menu chrome on app resume — UNLESS a gameplay
    // screen is active, in which case it owns the full-screen immersiveSticky
    // mode and we must not override it (that's what made the status bar
    // reappear mid-game). See Immersive.inGameplay.
    if (Immersive.inGameplay) {
      Immersive.enterGame();
      return;
    }
    Immersive.enterMenu();
  }

  @override
  Widget build(BuildContext context) {
    // MultiBlocProvider for all Cubit-based state management
    return MultiBlocProvider(
      providers: [
        // Auth & User
        BlocProvider<AuthCubit>(
          create: (_) => getIt<AuthCubit>()..initialize(),
        ),
        // Theme
        BlocProvider<ThemeCubit>(
          create: (_) => getIt<ThemeCubit>()..initialize(),
        ),
        // Game Settings & Game
        BlocProvider<GameSettingsCubit>(
          create: (_) => getIt<GameSettingsCubit>()..initialize(),
        ),
        BlocProvider<GameCubit>(
          create: (_) => getIt<GameCubit>()..initialize(),
        ),
        // Coins
        BlocProvider<CoinsCubit>(
          create: (_) => getIt<CoinsCubit>()..initialize(),
        ),
        // Multiplayer
        BlocProvider<MultiplayerCubit>(
          create: (_) => getIt<MultiplayerCubit>(),
        ),
        // Premium & Battle Pass
        BlocProvider<PremiumCubit>.value(
          value: getIt<PremiumCubit>()..initialize(),
        ),
        BlocProvider<BattlePassCubit>.value(
          value: getIt<BattlePassCubit>()..initialize(),
        ),
        // Pre-game power-up inventory (coin-purchased, server-backed)
        BlocProvider<PowerUpCubit>.value(
          value: getIt<PowerUpCubit>()..loadInventory(),
        ),
      ],
      // MultiProvider for core services that are not Cubits
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => UnifiedUserService(),
            lazy: false,
          ),
          ChangeNotifierProvider(create: (_) => DataSyncService(), lazy: false),
          ChangeNotifierProvider(
            create: (_) => PreferencesService(),
            lazy: false,
          ),
        ],
        child: BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, themeState) {
            return MaterialApp.router(
              title: 'Cosmo Strike',
              debugShowCheckedModeBanner: false,
              routerConfig: appRouter,
              theme: ThemeData(
                brightness: Brightness.dark,
                scaffoldBackgroundColor:
                    themeState.currentTheme.backgroundColor,
                visualDensity: VisualDensity.adaptivePlatformDensity,
                useMaterial3: false,
                textTheme: GameTypography.createTextTheme(
                  color: themeState.currentTheme.accentColor,
                ),
              ),
              // The first-sign-in cloud-restore overlay is mounted on the
              // three screens the restore can possibly be active on
              // (LoadingScreen / FirstTimeAuthScreen / EmailAuthScreen),
              // not globally — once the user lands on home, restore is
              // already done and the home tree shouldn't carry the
              // subscription.
            );
          },
        ),
      ),
    );
  }
}
