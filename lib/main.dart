import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'package:provider/provider.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/debug/demo_mode.dart';
import 'package:cosmo_strike_flutter_app/debug/perf_monitor.dart';
import 'package:cosmo_strike_flutter_app/core/startup/startup_guard.dart';
import 'package:cosmo_strike_flutter_app/core/startup/startup_reporter.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_tuning.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_settings_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/power_up/power_up_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/tournament/tournament_context_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/battle_pass_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/app_router.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_gate.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_route_observer.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/test_device.dart';
import 'package:cosmo_strike_flutter_app/services/telemetry/telemetry_service.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/auth_service.dart';
import 'package:cosmo_strike_flutter_app/services/connectivity_service.dart';
import 'package:cosmo_strike_flutter_app/services/data_sync_service.dart';
import 'package:cosmo_strike_flutter_app/services/haptic_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/notification_service.dart';
import 'package:cosmo_strike_flutter_app/services/preferences_service.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/services/sync/sync_engine.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/ui/design/immersive.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';
import 'package:cosmo_strike_flutter_app/services/walkthrough_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
// import 'package:cosmo_strike_flutter_app/utils/performance_monitor.dart'; // temporarily disabled

import 'firebase_options.dart';

// ─── Startup safety net ────────────────────────────────────────────────────
//
// EVERY path out of main() must reach runApp() with the native splash gone.
// FlutterNativeSplash.preserve() holds the launch image until something
// removes it, so a startup that throws or hangs before LoadingScreen mounts
// used to leave the player on the splash with no error, no retry and nothing
// reported. Now:
//  * the whole bootstrap is bounded by [_bootstrapBudget];
//  * a failure shows [_StartupRecoveryApp] (splash removed first) whose
//    "Try again" re-runs the bootstrap in-process through [_bootstrapFlight];
//  * errors raised before Crashlytics exists are buffered by
//    [StartupReporter] and flushed once it does, together with the phase
//    timings / failed phase as custom keys;
//  * after runApp, the 15 s splash safety net below and LoadingScreen's 18 s
//    watchdog bound the rest.

/// Hard ceiling on the pre-runApp bootstrap. Individual steps have their own
/// timeouts; this catches the step that hangs without throwing (a platform
/// channel that never answers, a socket that never resets). Generous on
/// purpose — a slow cold start on a cheap phone must still finish normally.
const Duration _bootstrapBudget = Duration(seconds: 25);

/// After runApp, lift the splash even if LoadingScreen never routes. Shorter
/// than LoadingScreen's watchdog (18 s), so the watchdog always routes from a
/// visible screen (the splash mirror) rather than from under the splash.
const Duration _splashSafetyNet = Duration(seconds: 15);

/// Non-critical bootstrap steps give up waiting after this long.
const Duration _stepTimeout = Duration(seconds: 5);

/// Whether Firebase.initializeApp completed — the gate for touching any
/// Firebase.instance.
bool _firebaseReady = false;

/// Whether DI is configured. get_it throws on re-registering a singleton, so
/// a retry must not run [configureDependencies] twice.
bool _dependenciesReady = false;

/// Whether [appRouter] (late final) has been assigned. The real app cannot
/// build before this, and the assignment cannot repeat on a retry.
bool _routerReady = false;

/// AdTuning.init is started once per process.
bool _adTuningStarted = false;

/// Captured init failure (shown small on the recovery screen).
String? _initError;

/// Running count of bootstrap attempts (initial + retries).
int _bootstrapAttempt = 0;

/// Phase timings of the current bootstrap run.
StartupPhaseTracker _phases = StartupPhaseTracker();

/// The bootstrap that is in flight or already succeeded: a retry joins a run
/// that is still going (the budget timeout abandons the wait, not the work)
/// instead of racing a second one into configureDependencies.
final SingleFlight<void> _bootstrapFlight = SingleFlight<void>();

/// Firebase.initializeApp, shared by the bootstrap and the failure-report
/// path so the two can never both call it ([core/duplicate-app]).
final SingleFlight<void> _firebaseFlight = SingleFlight<void>();

/// Thrown when [_bootstrapBudget] runs out — a distinct type so it is never
/// confused with a TimeoutException thrown by a step inside the bootstrap.
class _BootstrapBudgetExceeded implements Exception {
  const _BootstrapBudgetExceeded(this.phase);
  final String? phase;

  @override
  String toString() => 'Startup exceeded ${_bootstrapBudget.inSeconds}s '
      '(stuck in phase: ${phase ?? 'unknown'})';
}

/// Global error handlers — installed FIRST in main(), before anything can
/// throw. Until Crashlytics is up, [StartupReporter] buffers what they catch
/// and flushes it on [StartupReporter.markCrashlyticsReady]; release builds
/// only (debug surfaces errors locally).
///
/// PlatformDispatcher.onError + FlutterError.onError is the FlutterFire-
/// recommended pair; a runZonedGuarded wrapper is deliberately NOT used — the
/// binding is initialized in the root zone, and running the app in another
/// zone trips Flutter's zone-mismatch check.
void _installGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    AppLogger.error('Flutter Error', details.exception, details.stack);
    if (kDebugMode) {
      FlutterError.presentError(details);
    } else {
      StartupReporter.recordFlutterError(details);
    }
  };

  // Uncaught async errors outside the Flutter framework (e.g. in Futures /
  // event handlers). Returning true marks them handled.
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Uncaught async error', error, stack);
    StartupReporter.recordError(
      error,
      stack,
      reason: 'Uncaught async error',
      fatal: true,
    );
    return true;
  };
}

void main() async {
  // Ensure Flutter is initialized and preserve splash screen
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  if (DemoMode.perfLog) PerfMonitor.instance.start();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Before any init step: errors from here on are buffered for Crashlytics.
  _installGlobalErrorHandlers();

  AppLogger.lifecycle('Cosmo Strike starting up...');

  if (await _runBootstrap(isRetry: false)) {
    _startApp();
  } else {
    // Drop the native splash FIRST — otherwise the recovery screen renders
    // underneath it and the app still looks frozen.
    FlutterNativeSplash.remove();
    runApp(const _StartupRecoveryApp());
  }
}

/// Starts the real app. The splash is normally lifted by LoadingScreen as it
/// routes; [_splashSafetyNet] lifts it anyway if that screen never mounts.
void _startApp() {
  Future.delayed(_splashSafetyNet, FlutterNativeSplash.remove);
  runApp(const riverpod.ProviderScope(child: CosmoStrikeApp()));
}

/// Runs (or joins) the bootstrap under [_bootstrapBudget]. Returns whether the
/// real app can start. Never throws.
Future<bool> _runBootstrap({required bool isRetry}) async {
  _bootstrapAttempt++;
  StartupReporter.setKey('startup_attempt', _bootstrapAttempt);
  try {
    await _bootstrapFlight.run(_bootstrap).timeout(
          _bootstrapBudget,
          onTimeout: () =>
              throw _BootstrapBudgetExceeded(_phases.currentPhase),
        );
    StartupReporter.publishPhases(
      _phases,
      outcome: isRetry ? 'retry_ok' : 'ok',
    );
    AppLogger.success('Cosmo Strike ready to launch!');
    return true;
  } on _BootstrapBudgetExceeded catch (error, stackTrace) {
    // Launch anyway if the router exists: everything after it is optional at
    // launch and keeps running in the background. Without the router the
    // first build would throw LateInitializationError, so show recovery.
    final launchable = _routerReady;
    _initError = '$error';
    AppLogger.error('Startup budget exceeded', error, stackTrace);
    StartupReporter.publishPhases(
      _phases,
      outcome: launchable ? 'timeout_degraded' : 'timeout_failed',
    );
    await _reportStartupFailure(
      error,
      stackTrace,
      reason: '$error',
      // Fatal only when it cost the player the app, and only once per
      // session — a stuck player tapping Try again must not bury the
      // crash-free rate.
      fatal: !launchable && !isRetry,
    );
    return launchable;
  } catch (error, stackTrace) {
    _initError = '$error';
    AppLogger.error('Failed to initialize Cosmo Strike', error, stackTrace);
    StartupReporter.publishPhases(_phases, outcome: 'failed');
    StartupReporter.setKey('startup_failed_phase', _phases.currentPhase ?? '');
    await _reportStartupFailure(
      error,
      stackTrace,
      reason: isRetry
          ? 'Startup retry failed in ${_phases.currentPhase}'
          : 'App initialization failed in ${_phases.currentPhase}',
      fatal: !isRetry,
    );
    return false;
  }
}

/// Reports a startup failure, bringing Crashlytics up first if the failure
/// happened before it existed (e.g. `.env` failed to load). Skipped when
/// Firebase itself is what failed or hung — retrying it here would only hold
/// the player on the splash longer. Bounded; never throws.
Future<void> _reportStartupFailure(
  Object error,
  StackTrace stackTrace, {
  required String reason,
  required bool fatal,
}) async {
  if (kDebugMode) return;
  try {
    if (!StartupReporter.isReady && _phases.currentPhase != 'firebase') {
      await _firebaseFlight.run(_initFirebase).timeout(_stepTimeout);
      await _enableCrashReporting();
    }
  } catch (_) {
    // Firebase unreachable: the error stays buffered for the retry path.
  }
  await StartupReporter.recordErrorNow(
    error,
    stackTrace,
    reason: reason,
    fatal: fatal,
  );
}

Future<void> _initFirebase() async {
  // Guarded on Firebase.apps: a repeat initializeApp throws
  // [core/duplicate-app], which would make every retry fail.
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  _firebaseReady = true;
}

/// Turns Crashlytics collection on (release only, as before) and flushes the
/// early-error buffer. A collection toggle that stalls doesn't stop reporting.
Future<void> _enableCrashReporting() async {
  if (!_firebaseReady || StartupReporter.isReady) return;
  await withStepTimeout<void>(
    FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode),
    _stepTimeout,
    label: 'crashlytics_collection',
    orElse: () {},
    onTimedOut: _logStepTimeout,
  );
  StartupReporter.markCrashlyticsReady();
}

void _logStepTimeout(String label, Duration timeout) {
  AppLogger.warning(
    'Startup step "$label" timed out after ${timeout.inSeconds}s — continuing',
  );
  StartupReporter.log('startup step timeout: $label');
  StartupReporter.setKey('startup_timeout_$label', true);
}

/// Runs a non-critical step: bounded by [timeout], and a throw is reported
/// (non-fatal) instead of failing the whole startup.
Future<void> _optionalStep(
  String label,
  Future<void> Function() step, {
  Duration timeout = _stepTimeout,
}) async {
  try {
    await withStepTimeout<void>(
      step(),
      timeout,
      label: label,
      orElse: () {},
      onTimedOut: _logStepTimeout,
    );
  } catch (error, stackTrace) {
    AppLogger.error('Startup step "$label" failed — continuing', error,
        stackTrace);
    StartupReporter.recordError(
      error,
      stackTrace,
      reason: 'Startup step failed: $label',
    );
  }
}

/// Everything that must happen before the app can render. Retry-safe: each
/// one-shot step is guarded so a second run (after a failure) skips what
/// already succeeded.
Future<void> _bootstrap() async {
  _phases = StartupPhaseTracker();

  // Full-screen immersive app-wide from first launch: status + nav bars
  // hidden (immersiveSticky — swiping from an edge reveals them briefly).
  // The Immersive helper (ui/design/immersive.dart) re-applies this on
  // lifecycle resumes. The transparent overlay style below keeps the bars
  // unobtrusive during those brief reveals.
  _phases.begin('system_ui');
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Load environment variables
  _phases.begin('dotenv');
  AppLogger.info('Loading environment variables...');
  await dotenv.load(fileName: '.env');
  AppLogger.success('Environment variables loaded');

  // Initialize Firebase
  _phases.begin('firebase');
  AppLogger.firebase('Initializing Firebase...');
  await _firebaseFlight.run(_initFirebase);
  AppLogger.success('Firebase initialized successfully');

  // Remote-tunable ad cadence — non-blocking; ads run on in-code defaults
  // until (and unless) the fetch lands.
  if (!_adTuningStarted) {
    _adTuningStarted = true;
    unawaited(AdTuning.init());
  }

  // Crash reporting + performance + analytics collection. All gated to
  // release builds so local dev crashes/traces/auto-events never pollute
  // the production dashboards. (The Dart-side analytics client split in
  // injection.dart only covers explicit events — without this toggle,
  // debug builds still emitted native auto-events like first_open /
  // session_start into the prod property.) Crashlytics comes up first and
  // flushes everything buffered since main() started.
  _phases.begin('crash_reporting');
  await _enableCrashReporting();
  await _optionalStep(
    'performance_collection',
    () => FirebasePerformance.instance.setPerformanceCollectionEnabled(
      !kDebugMode,
    ),
  );
  // Off for debug, DemoMode (autopilot) builds and devices marked with the
  // hidden test-device switch (About & Credits → tap the version 7×).
  await _optionalStep(
    'analytics_collection',
    () async => FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      AnalyticsGate.collectionEnabled(
        testDevice: await TestDevice.instance.load(),
      ),
    ),
  );

  // Re-assert the handlers now Firebase is up, in case a plugin's init
  // replaced them. Idempotent.
  _installGlobalErrorHandlers();

  // Landscape-only: Cosmo Strike is a horizontal command-HUD experience
  // (side-scrolling shmup + wide UI). Lock both landscape orientations so
  // the device can flip between them but never rotates to portrait.
  AppLogger.ui('Setting device orientation...');
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Initialize dependency injection
  _phases.begin('dependencies');
  if (!_dependenciesReady) {
    AppLogger.info('Configuring dependencies...');
    try {
      await configureDependencies();
    } catch (_) {
      // A half-finished registration would make the retry's
      // configureDependencies throw "already registered" before reaching
      // the step that actually failed. Start the retry from empty.
      await _resetDependencies();
      rethrow;
    }
    _dependenciesReady = true;
    AppLogger.success('Dependencies configured');
  }

  // Initialize router with analytics observer (late final: exactly once).
  _phases.begin('router');
  if (!_routerReady) {
    appRouter = createAppRouter(
      observers: [AnalyticsRouteObserver(getIt<AnalyticsFacade>())],
    );
    _routerReady = true;

    // Track app open (fire-and-forget)
    unawaited(getIt<AnalyticsFacade>().trackAppOpened());
    // Backend retention telemetry: counts today's first session and sends
    // it (background, never blocks; no-op in DemoMode). Re-sends when
    // connectivity returns.
    unawaited(TelemetryService.instance.noteForeground());
    getIt<ConnectivityService>().onlineStatusStream.listen((online) {
      if (online) TelemetryService.instance.noteOnline();
    });
  }

  // From here on every step is optional at launch: bounded and non-fatal.
  //
  // Note: PurchaseService.initialize() is NOT called here because
  // PremiumCubit.initialize() already calls it. Calling it twice would
  // double-subscribe to the purchase stream.
  _phases.begin('services');
  AppLogger.info('Initializing services...');
  await _optionalStep(
    'audio',
    () => AudioService().initialize(),
    timeout: const Duration(seconds: 10),
  );
  AppLogger.success('Audio service initialized');

  // Start the background-music loop (no-op while the toggle is off).
  unawaited(AudioService().playBackgroundMusic());

  // Walkthrough flags (home tour / game tutorial / control choice) are
  // read SYNCHRONOUSLY at screen-build time — hydrate the prefs-backed
  // service up front so a launch into Play can never mis-read
  // "tutorial already done".
  await _optionalStep('walkthrough', () => WalkthroughService().initialize());

  // Hydrate the haptics master toggle from the Drift settings row
  // (synced setting; defaults to on). HapticService is an in-memory
  // singleton — without this, every launch would vibrate regardless
  // of the saved preference.
  await _optionalStep('haptics', () async {
    HapticService().setEnabled(
      await getIt<StorageService>().isHapticsEnabled(),
    );
  });

  // NotificationService.initialize() is no longer called here — it
  // requests the OS notification permission as a side effect, and
  // showing that dialog before the user has seen the app would feel
  // intrusive. The call has moved to home_screen.dart's initState,
  // so the request only fires once the user has actually landed on
  // home and signed in (if applicable).

  _phases.begin('wiring');
  // The Play in-app update check runs from Home after its first frame
  // (HomeScreen.initState), not here: see InAppUpdateService.

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

  _phases.end();
}

/// Undoes a [configureDependencies] that threw partway, so the next attempt
/// can register everything again. The database is closed first: get_it has
/// no dispose hook for it, and the retry opens a fresh connection.
Future<void> _resetDependencies() async {
  try {
    if (getIt.isRegistered<AppDatabase>()) await getIt<AppDatabase>().close();
  } catch (_) {}
  try {
    await getIt.reset();
  } catch (_) {}
}

/// Prism Noir recovery screen for a failed startup.
///
/// Depends on nothing the bootstrap sets up — no DI, no router, no cubits —
/// only the theme tokens and stateless `cs` components. Most startup failures
/// are transient (a cold database file, a Firebase handshake on a flaky
/// network), so "Try again" re-runs the bootstrap in-process and, on success,
/// swaps in the real app: no restart, nothing local lost.
class _StartupRecoveryApp extends StatefulWidget {
  const _StartupRecoveryApp();

  @override
  State<_StartupRecoveryApp> createState() => _StartupRecoveryAppState();
}

class _StartupRecoveryAppState extends State<_StartupRecoveryApp> {
  bool _retrying = false;
  String? _detail = _initError;

  @override
  void initState() {
    super.initState();
    // The bootstrap may have failed before it locked orientation.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    if (await _runBootstrap(isRetry: true)) {
      AppLogger.success('Startup retry succeeded — starting the app');
      // runApp on a running binding replaces the root widget: a live
      // recovery, not a restart.
      _startApp();
      return;
    }
    if (mounted) {
      setState(() {
        _retrying = false;
        _detail = _initError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cosmo Strike',
      theme: buildCosmoTheme(),
      debugShowCheckedModeBanner: false,
      // The app is on package:material_ui; its own delegates are required or
      // the one screen that must never fail would throw on first build.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) {
          final cs = context.cs;
          return Scaffold(
            backgroundColor: CsColors.bg,
            body: SafeArea(
              child: Stack(
                children: [
                  CsEmptyState.error(
                    title: "Cosmo Strike couldn't launch",
                    message: 'This is usually temporary. Your progress is '
                        'saved on this device.',
                    action: CsButton.primary(
                      label: 'Try again',
                      icon: Symbols.refresh_rounded,
                      loading: _retrying,
                      onPressed: _retrying ? null : _retry,
                    ),
                  ),
                  if (_detail != null)
                    Positioned(
                      left: cs(24),
                      right: cs(24),
                      bottom: cs(12),
                      child: Text(
                        _detail!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.type.mono(
                          10,
                          color: CsColors.ink45,
                          em: 0.02,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
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
      // New telemetry session after 30+ min in the background.
      unawaited(TelemetryService.instance.noteForeground());
    }

    // Music pauses ONLY on a real background transition — `inactive`
    // fires on transient occlusions (permission dialogs, system sheets,
    // the gameplay screen's system-UI swaps) and pausing there would
    // stutter the track.
    if (state == AppLifecycleState.paused) {
      unawaited(AudioService().pauseBackgroundMusic());
      unawaited(TelemetryService.instance.noteBackground());
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
        // Game Settings
        BlocProvider<GameSettingsCubit>(
          create: (_) => getIt<GameSettingsCubit>()..initialize(),
        ),
        // Coins
        BlocProvider<CoinsCubit>(
          create: (_) => getIt<CoinsCubit>()..initialize(),
        ),
        // Tournament context for Flame runs (root-provided: the tournament
        // detail screen pushes gameplay via the root navigator)
        BlocProvider<TournamentContextCubit>(
          create: (_) => getIt<TournamentContextCubit>(),
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
              // The app is on package:material_ui (Flutter 3.50 split), so its
              // own Material/Cupertino localization delegates are required.
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              // Prism Noir: one look for every menu. Purchased color themes
              // (ThemeCubit) now tint gameplay only — see cosmo_palette.dart.
              theme: buildCosmoTheme(),
              darkTheme: buildCosmoTheme(),
              themeMode: ThemeMode.dark,
              // Landscape layouts are tuned to the type scale; allow a little
              // system font scaling for legibility but cap it so headlines
              // and HUD numbers never blow out of their rows.
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                // Bridges third-party packages still on
                // package:flutter/material.dart into the material_ui tree.
                // ignore: deprecated_member_use
                return MaterialUiCompatibilityBridge(
                  child: MediaQuery(
                    data: mq.copyWith(
                      textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.15),
                    ),
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
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
