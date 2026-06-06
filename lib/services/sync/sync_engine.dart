import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/data/daos/game_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/settings_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/store_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/sync_dao.dart';
import 'package:cosmo_strike_flutter_app/models/achievement.dart' as ach_model;
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/connectivity_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
import 'package:cosmo_strike_flutter_app/widgets/sync_restore_overlay.dart';

/// Result of a single backend dispatch.
enum _DispatchResult {
  /// Backend accepted the batch; drop the items from the outbox.
  success,

  /// Backend isn't ready yet (e.g., stub returned null) — leave the
  /// items pending without bumping the retry counter, so when the
  /// endpoint lands the engine just picks them up.
  notReady,

  /// Backend explicitly rejected the batch. Bump retry; if max
  /// retries exceeded the items get marked failed.
  failed,
}

/// Outcome of [SyncEngine.maybeRunFirstSignInPull]. The UI uses this
/// to drive the "restoring your data…" loading modal during sign-in.
enum FirstSignInResult {
  /// Device has previously completed first-sign-in. No-op.
  alreadyDone,

  /// User just registered on the backend (is_new_user = true).
  /// No cloud data to restore; flag set so future sign-ins are
  /// normal sessions.
  brandNew,

  /// Returning user; backend snapshot pulled and applied to local
  /// Drift. Flag set.
  restored,

  /// Returning user but the pull failed or returned null. Flag
  /// stays unset so next launch retries the whole flow. UI should
  /// show a non-blocking warning and proceed with whatever local
  /// data exists (likely empty defaults).
  pullFailed,
}

/// UI-facing state stream emitted by the SyncEngine during the
/// first-sign-in flow. The global overlay subscribes to this and
/// renders a modal whenever the state is anything other than
/// [idle] / [done]. `welcoming` covers the brand-new-user path so
/// the user still sees a setup modal during their first sign-in
/// (even when there's nothing to pull).
enum FirstSignInState { idle, welcoming, pulling, applying, restored, failed, done }

/// User-driven resolution of the failed-modal. Used by the engine to
/// distinguish "Try Again" (loop) from "Continue Anyway" (give up).
enum _ModalAction { retry, dismiss }

/// Drains the local outbox (the `SyncQueue` Drift table) to the
/// backend. Owns the periodic + reactive (Drift-stream-driven)
/// drain loop and the first-sign-in pull flow.
///
/// Architecture:
///   * Every synced DAO mutation writes an outbox row in the same
///     Drift transaction (see [GameDao], [StoreDao], [SettingsDao]).
///   * This engine watches the outbox stream and drains in batches,
///     grouped by dataType, hitting one batch endpoint per group.
///   * Gated on `apiService.isAuthenticated && connectivity.isOnline`.
///   * `notReady` results (backend stub or 5xx) leave rows pending;
///     `failed` results bump retry with exponential backoff.
///
/// First-sign-in: when a particular user logs in on this device for
/// the first time, the engine pulls the cloud snapshot (if any) and
/// replaces local data, then clears the outbox so we don't echo
/// the pull back as a push.
class SyncEngine {
  static final SyncEngine _instance = SyncEngine._internal();
  factory SyncEngine() => _instance;
  SyncEngine._internal();

  final ApiService _api = ApiService();
  final ConnectivityService _connectivity = ConnectivityService();

  AppDatabase? _db;
  SyncDao? _syncDao;
  GameDao? _gameDao;
  StoreDao? _storeDao;
  SettingsDao? _settingsDao;

  static const int _maxRetries = 5;
  static const Duration _debounce = Duration(seconds: 3);
  /// Hard ceiling on how far a burst of mutations can defer the drain.
  /// Without this, a sustained mutation rate >1 / 3s would keep
  /// resetting [_debounceTimer] indefinitely and starve the drain.
  static const Duration _debounceMaxDefer = Duration(seconds: 10);
  static const Duration _periodic = Duration(minutes: 2);

  /// Device-scoped flag — flips true the first time ANY user signs in
  /// successfully on this install. A subsequent reinstall (which
  /// wipes SharedPreferences) returns the flag to false and the
  /// first-sign-in pull runs again to restore cloud data.
  static const String _hasEverSignedInPrefsKey = 'sync_engine_has_ever_signed_in';

  bool _isDraining = false;
  /// Future of the currently-running [_drain] call, or null if idle.
  /// Callers that need to block on the active drain (notably the
  /// first-sign-in pull's pre-fetch step) await this before kicking
  /// off their own drain.
  Future<void>? _drainInFlight;
  /// True once the watcher + periodic-timer + connectivity drain
  /// triggers are attached. Set by [_armDrainLoop]; the method is
  /// idempotent so repeated calls (initialize fast-path + every
  /// maybeRunFirstSignInPull tail + markFirstSignInSkipped) are safe.
  /// The flag also doubles as a gate on [_drain]: until the drain
  /// loop is armed, the engine is "asleep" — cubit-init enqueues
  /// pile up in the outbox without ever shipping, so the cloud
  /// restore gets a clean first crack at populating Drift.
  bool _drainLoopArmed = false;
  StreamSubscription<List<SyncQueueData>>? _outboxWatcher;
  StreamSubscription<bool>? _connectivityWatcher;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  /// The earliest moment a debounce-deferred drain MUST run by, set
  /// the first time the debounce begins ticking. Rapid mutations can
  /// keep restarting [_debounceTimer] but can never push the actual
  /// drain past this deadline.
  DateTime? _debounceDeadline;

  /// Active waiter for the failed-modal's user action ("Try Again" vs
  /// "Continue Anyway"). [maybeRunFirstSignInPull] sets this when it
  /// emits a `failed` state and awaits it before returning, which
  /// keeps the caller (UnifiedUserService._loadOrCreateUser →
  /// signInWithGoogle) blocked — so AuthCubit doesn't emit
  /// authenticated and the router doesn't navigate to home until the
  /// user resolves the modal. [retryFirstSignInPull] /
  /// [dismissFirstSignInOverlay] complete the future to break out.
  Completer<_ModalAction>? _userActionCompleter;

  /// Signals that [initialize] has finished. Callers that race the
  /// init (notably [maybeRunFirstSignInPull] when sign-in fires
  /// during cold start) await this so they don't no-op on a not-
  /// yet-initialized engine.
  final Completer<void> _initialized = Completer<void>();

  /// Broadcast stream the UI subscribes to for the loading modal
  /// during first-sign-in restore.
  final StreamController<FirstSignInState> _firstSignInStateController =
      StreamController<FirstSignInState>.broadcast();
  Stream<FirstSignInState> get firstSignInStateStream =>
      _firstSignInStateController.stream;
  FirstSignInState _firstSignInState = FirstSignInState.idle;
  FirstSignInState get firstSignInState => _firstSignInState;

  /// Root navigator key, wired from main.dart via [attachNavigatorKey].
  /// SyncEngine uses it to grab the Overlay above the current route
  /// without depending on which screen the user is on when sign-in
  /// fires. The sign-in entry point isn't always FirstTimeAuthScreen —
  /// guests upgrading to Google from ProfileScreen, for example, never
  /// visit a dedicated login screen — so the overlay can't be mounted
  /// per-screen.
  GlobalKey<NavigatorState>? _rootNavigatorKey;

  /// The OverlayEntry hosting [SyncRestoreOverlay]. Inserted on the
  /// first non-idle/non-done state emission, removed when state
  /// transitions back to done (success or auto-dismissed failure).
  OverlayEntry? _restoreOverlayEntry;

  /// Wire the root navigator key so this engine can imperatively
  /// insert the first-sign-in overlay above whatever route is active.
  /// Call once during app bootstrap, before any sign-in can fire.
  void attachNavigatorKey(GlobalKey<NavigatorState> key) {
    _rootNavigatorKey = key;
  }

  void _emitFirstSignInState(FirstSignInState state) {
    _firstSignInState = state;
    _firstSignInStateController.add(state);

    final shouldShowOverlay = switch (state) {
      FirstSignInState.welcoming ||
      FirstSignInState.pulling ||
      FirstSignInState.applying ||
      FirstSignInState.restored ||
      FirstSignInState.failed =>
        true,
      FirstSignInState.idle || FirstSignInState.done => false,
    };

    if (shouldShowOverlay) {
      _ensureRestoreOverlayInserted();
    } else {
      _removeRestoreOverlay();
    }
  }

  void _ensureRestoreOverlayInserted() {
    if (_restoreOverlayEntry != null) return;
    final overlay = _rootNavigatorKey?.currentState?.overlay;
    if (overlay == null) {
      // Navigator not mounted yet (extremely early sign-in race). The
      // state stream still fires; if any screen subscribes to it later
      // the UI will catch up — and the next emission will retry the
      // insert anyway. Logging so we notice if it actually happens.
      AppLogger.warning(
        'SyncEngine: no Navigator overlay available — first-sign-in '
        'modal could not be inserted. Was attachNavigatorKey called?',
      );
      return;
    }
    final entry = OverlayEntry(builder: (_) => const SyncRestoreOverlay());
    _restoreOverlayEntry = entry;
    overlay.insert(entry);
  }

  void _removeRestoreOverlay() {
    final entry = _restoreOverlayEntry;
    if (entry == null) return;
    _restoreOverlayEntry = null;
    entry.remove();
  }

  /// Emit [FirstSignInState.failed] and leave the modal up. The
  /// overlay renders two buttons in this state — "Try Again" (calls
  /// [retryFirstSignInPull]) and "Continue Anyway" (calls
  /// [dismissFirstSignInOverlay]) — so the user decides what to do
  /// instead of the engine silently giving up.
  void _emitFailed() {
    _emitFirstSignInState(FirstSignInState.failed);
  }

  /// Signal the in-flight [maybeRunFirstSignInPull] to re-attempt the
  /// pull. Called from the overlay's "Try Again" button. The retry
  /// runs inside the same maybeRunFirstSignInPull invocation that's
  /// already being awaited by sign-in — so the awaiter (signInWithGoogle)
  /// stays blocked until the retry resolves, keeping the user on the
  /// login screen.
  void retryFirstSignInPull() {
    final c = _userActionCompleter;
    if (c != null && !c.isCompleted) {
      c.complete(_ModalAction.retry);
    }
  }

  /// Public dismiss hook for the overlay's "Continue Anyway" button.
  /// The first-sign-in flag stays UNSET so the next launch retries the
  /// pull automatically; the user just chose to keep using the app
  /// without restored data for now. Completing the action completer
  /// also unblocks the awaiting sign-in flow → AuthCubit emits
  /// authenticated → router navigates to home.
  void dismissFirstSignInOverlay() {
    final c = _userActionCompleter;
    if (c != null && !c.isCompleted) {
      c.complete(_ModalAction.dismiss);
      return;
    }
    // Safety net: no in-flight wait (overlay shown without a pending
    // action). Hide it directly.
    _emitFirstSignInState(FirstSignInState.done);
  }

  /// Block until the user resolves the failed modal. Used by every
  /// failure branch in [maybeRunFirstSignInPull] so the caller stays
  /// awaited until the user explicitly chooses.
  Future<_ModalAction> _awaitUserModalAction() async {
    final c = Completer<_ModalAction>();
    _userActionCompleter = c;
    final action = await c.future;
    _userActionCompleter = null;
    return action;
  }

  /// One-shot init. Hook this from app boot after the database +
  /// connectivity + auth singletons are ready.
  ///
  /// Init wires DAOs and signals readiness via [_initialized], but only
  /// arms the drain loop (outbox watcher / connectivity watcher /
  /// periodic timer) when the device has already completed first-sign-in
  /// on a prior launch. For first-time devices, the drain loop is armed
  /// later from [maybeRunFirstSignInPull]'s tail — that way the cloud
  /// restore runs first and any cubit-init outbox enqueues (legacy SP
  /// migration, +50 starting bonus) wait their turn instead of racing
  /// the pull.
  Future<void> initialize(AppDatabase db) async {
    if (_db != null) return; // already initialized
    _db = db;
    _syncDao = db.syncDao;
    _gameDao = db.gameDao;
    _storeDao = db.storeDao;
    _settingsDao = db.settingsDao;

    if (!_initialized.isCompleted) _initialized.complete();

    // Returning-device fast path: if the flag is already set in
    // SharedPreferences, restore has happened before — go straight to
    // the normal drain loop. First-time devices go through
    // maybeRunFirstSignInPull's arming branch instead.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_hasEverSignedInPrefsKey) == true) {
      _armDrainLoop();
    }

    if (kDebugMode) {
      AppLogger.network(
        'SyncEngine initialized (drainLoopArmed=$_drainLoopArmed)',
      );
    }
  }

  /// Attach the outbox watcher, connectivity watcher, and periodic
  /// drain timer. Idempotent — repeated calls are safe so every
  /// settled branch of [maybeRunFirstSignInPull] (plus
  /// [markFirstSignInSkipped]) can call this without worrying about
  /// duplicate subscriptions.
  void _armDrainLoop() {
    if (_drainLoopArmed) return;
    _drainLoopArmed = true;

    // Drift's watch stream fires whenever a row gets added to the
    // outbox. We debounce 3s so a burst of mutations (e.g. a
    // game-end that touches stats + coins + achievements + battle
    // pass all at once) collapses into a single drain.
    _outboxWatcher = _syncDao!.watchPendingSyncItems().listen((_) {
      _scheduleDrain();
    });

    // Drain immediately on reconnect so the user doesn't have to
    // wait for the next periodic tick.
    _connectivityWatcher = _connectivity.onlineStatusStream.listen((isOnline) {
      if (isOnline) _scheduleDrain(immediate: true);
    });

    // Backup heartbeat — handles edge cases where a row was added
    // before the stream was attached, or a previous drain failed
    // silently.
    _periodicTimer = Timer.periodic(_periodic, (_) => _scheduleDrain());

    // Try once on arm in case there's already a pending backlog
    // (cubits enqueued during boot, before first-sign-in resolved).
    _scheduleDrain(immediate: true);

    if (kDebugMode) {
      AppLogger.network('SyncEngine drain loop armed');
    }
  }

  /// Public escape hatch for code paths that DECIDE not to run a real
  /// first-sign-in pull this session but still want the drain loop
  /// running — e.g., anonymous Firebase users (no cross-install
  /// persistence to restore) and users where the backend never
  /// returned a user id. Without this, the engine would stay asleep
  /// and these users' offline gains would never sync.
  void markFirstSignInSkipped() {
    _armDrainLoop();
  }

  /// Run the first-sign-in flow.
  ///
  /// [isNewUser] comes from the `/auth/firebase` response's
  /// `is_new_user` flag — true means the backend just minted this
  /// user record. We use it to disambiguate "brand new user, no
  /// cloud data" (legit empty snapshot) from "returning user but
  /// the pull failed for some reason" (transient — must retry).
  ///
  /// Behaviour:
  ///   * Flag already true → no-op, returns [alreadyDone].
  ///   * isNewUser == true → no cloud data exists by definition;
  ///     set flag + return [brandNew]. The outbox drain seeds cloud
  ///     with whatever the user has played pre-signin.
  ///   * Returning user + populated snapshot → wipe local + apply
  ///     + clear outbox + set flag. Returns [restored].
  ///   * Returning user + null/failed pull → flag stays unset so
  ///     the next launch retries. Returns [pullFailed].
  ///
  /// Order is "pull first, wipe second" so a transient pull failure
  /// can't wipe local data before we have a replacement.
  Future<FirstSignInResult> maybeRunFirstSignInPull({
    required String userId,
    required bool isNewUser,
  }) async {
    // Wait up to 8s for [initialize] to complete. The engine boots
    // from main.dart with `unawaited(...)`, so sign-in can race the
    // init. A timeout means something is very wrong (initialize
    // never resolved) — we treat that as a pull failure so the
    // flag stays unset and next launch retries.
    try {
      await _initialized.future.timeout(const Duration(seconds: 8));
    } catch (e) {
      AppLogger.error(
        'SyncEngine.maybeRunFirstSignInPull: initialize did not complete',
        e,
      );
      // Engine never came up — retry can't help, but still wait for
      // user dismissal so we don't navigate to home behind their back.
      _emitFailed();
      await _awaitUserModalAction();
      _emitFirstSignInState(FirstSignInState.done);
      return FirstSignInResult.pullFailed;
    }

    if (!_api.isAuthenticated) {
      AppLogger.warning(
        'SyncEngine.maybeRunFirstSignInPull: skipped, not authenticated',
      );
      return FirstSignInResult.pullFailed;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_hasEverSignedInPrefsKey) == true) {
      AppLogger.network(
        'SyncEngine.maybeRunFirstSignInPull: flag already set, no-op',
      );
      // initialize() should have already armed the drain loop in this
      // case, but call again idempotently in case of an init-order edge
      // (drain loop only arms in initialize when the flag was true; if
      // a prior session set the flag AFTER initialize ran, we'd land
      // here unarmed).
      _armDrainLoop();
      return FirstSignInResult.alreadyDone;
    }

    AppLogger.network(
      'SyncEngine.maybeRunFirstSignInPull: starting for $userId '
      '(isNewUser=$isNewUser)',
    );

    if (isNewUser) {
      // Backend just created the user — no cloud data exists, no
      // restore needed, and we don't want to flash any overlay either
      // (a brand-new user signing in for the first time shouldn't see
      // "Loading your previous data" — there IS no previous data).
      // Credit the welcome bonus through CoinsCubit so it rides the
      // normal outbox path and lands on both UserCoinBalance and
      // users.Coins via the next drain, then arm the drain loop.
      AppLogger.network(
        'SyncEngine: brand-new user — no overlay, seeding +50, arming drain',
      );
      try {
        await GetIt.I<CoinsCubit>().seedStartingBonus();
      } catch (e) {
        AppLogger.warning(
          'SyncEngine: seedStartingBonus errored (continuing): $e',
        );
      }
      await prefs.setBool(_hasEverSignedInPrefsKey, true);
      _armDrainLoop();
      return FirstSignInResult.brandNew;
    }

    // Returning user — pull, apply, and set the flag. Wrapped in a
    // retry loop: a failure emits FirstSignInState.failed and waits
    // for the user to tap "Try Again" or "Continue Anyway" via the
    // overlay. signInWithGoogle is awaiting THIS method, so navigation
    // to home stays blocked until the user resolves the modal.
    //
    // The pre-flight `_connectivity.isOnline` check was removed: on
    // some Android configs (LAN-only dev backends, captive WiFi, VPN
    // routing) it reports offline even when HTTP works fine. The pull
    // itself is the source of truth — if it can't reach the backend
    // it throws, and we land in the failed branch.
    while (true) {
      final attempt = await _runReturningUserPullAttempt(prefs, userId);
      if (attempt != FirstSignInResult.pullFailed) {
        _armDrainLoop();
        return attempt;
      }
      // Failed → modal is in `failed` state with retry/dismiss buttons.
      // Block here until the user chooses.
      final action = await _awaitUserModalAction();
      if (action == _ModalAction.dismiss) {
        // User gave up. Hide the overlay, arm the drain so the rest of
        // the app can use the network normally, leave the flag unset
        // so next launch retries the pull automatically.
        _emitFirstSignInState(FirstSignInState.done);
        _armDrainLoop();
        return FirstSignInResult.pullFailed;
      }
      // _ModalAction.retry — loop and run another pull attempt.
    }
  }

  /// One attempt at the returning-user pull + apply. Returns
  /// [FirstSignInResult.restored] on success or
  /// [FirstSignInResult.pullFailed] on any failure (HTTP throw, null
  /// snapshot, or apply throw). The failed-modal is emitted but NOT
  /// dismissed — the outer loop in [maybeRunFirstSignInPull] handles
  /// the user-action wait.
  Future<FirstSignInResult> _runReturningUserPullAttempt(
    SharedPreferences prefs,
    String userId,
  ) async {
    // Track the pulling-state start time so we can hold the modal
    // visible for a minimum duration (the actual HTTP call often
    // completes faster than the user's eye can register).
    final pullingStart = DateTime.now();
    _emitFirstSignInState(FirstSignInState.pulling);

    Map<String, dynamic>? snapshot;
    try {
      AppLogger.network('SyncEngine: GET /sync/pull …');
      snapshot = await _api.pullSyncSnapshot();
      if (snapshot == null) {
        AppLogger.warning(
          'SyncEngine: pull returned null — backend has no data for '
          'user $userId. (Either previous syncs never landed OR the '
          'endpoint returned HTTP non-2xx. Check backend logs + DB.)',
        );
      } else {
        AppLogger.network(
          'SyncEngine: pull returned snapshot with sections '
          '${snapshot.keys.toList()}',
        );
        for (final entry in snapshot.entries) {
          final v = entry.value;
          final summary = v == null
              ? 'null'
              : v is List
                  ? '${v.length} item(s)'
                  : v is Map
                      ? '${v.length} field(s)'
                      : v.toString();
          AppLogger.network('  • ${entry.key}: $summary');
        }
      }
    } catch (e) {
      AppLogger.error('SyncEngine: pull threw', e);
      await _ensureMinModalTime(pullingStart);
      _emitFailed();
      return FirstSignInResult.pullFailed;
    }

    if (snapshot == null) {
      await _ensureMinModalTime(pullingStart);
      _emitFailed();
      return FirstSignInResult.pullFailed;
    }

    // Cloud has data → apply each non-null section to local. The DAO
    // apply helpers use insertOnConflictUpdate semantics, so each
    // section that IS in the snapshot replaces the matching local
    // row; sections absent from the snapshot leave local alone. This
    // is the right "cloud-wins-per-section" behaviour for the
    // offline-first build.
    _emitFirstSignInState(FirstSignInState.applying);
    try {
      // Clear the queue FIRST. Any outbox rows that cubits enqueued
      // during boot (settings writes, etc.) get wiped before apply so
      // the cloud snapshot is the only thing writing to Drift. The
      // snapshot apply below RE-ENQUEUES any fields where local is
      // ahead of cloud (max-merge), so local-ahead deltas still ship
      // up after the drain arms. If we cleared AFTER the apply, those
      // re-enqueues would be wiped instantly.
      await _syncDao!.clearSyncQueue();
      await _applyCloudSnapshot(snapshot);
      await prefs.setBool(_hasEverSignedInPrefsKey, true);
      await _ensureMinModalTime(pullingStart);
      _emitFirstSignInState(FirstSignInState.restored);
      AppLogger.network(
        'SyncEngine: first-sign-in restore complete '
        '(sections: ${snapshot.keys.toList()})',
      );
      await Future.delayed(const Duration(milliseconds: 800));
      _emitFirstSignInState(FirstSignInState.done);
      return FirstSignInResult.restored;
    } catch (e) {
      AppLogger.error('SyncEngine: snapshot apply failed', e);
      await _ensureMinModalTime(pullingStart);
      _emitFailed();
      return FirstSignInResult.pullFailed;
    }
  }

  /// Hold the modal visible for a perceptible minimum so the user
  /// gets meaningful feedback even when the pull / apply completes
  /// in tens of milliseconds. Without this, the overlay flashes
  /// invisibly and the user can't tell the flow ran at all.
  Future<void> _ensureMinModalTime(DateTime startedAt) async {
    const minVisible = Duration(milliseconds: 1500);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minVisible) {
      await Future.delayed(minVisible - elapsed);
    }
  }

  /// Schedule a drain after the debounce window. Pass `immediate`
  /// to skip the debounce (e.g. on connectivity restore).
  ///
  /// Sustained bursts can keep resetting the debounce; [_debounceMaxDefer]
  /// caps how far the actual drain can be pushed back from the FIRST
  /// scheduling so the queue isn't starved.
  void _scheduleDrain({bool immediate = false}) {
    _debounceTimer?.cancel();
    if (immediate) {
      _debounceDeadline = null;
      _drain();
      return;
    }

    final now = DateTime.now();
    _debounceDeadline ??= now.add(_debounceMaxDefer);
    final remainingDefer = _debounceDeadline!.difference(now);
    final delay =
        remainingDefer < _debounce ? remainingDefer : _debounce;

    _debounceTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        _debounceDeadline = null;
        _drain();
      },
    );
  }

  Future<void> _drain() async {
    if (_isDraining) {
      // Coalesce concurrent calls onto the in-flight future so the
      // caller still gets a meaningful completion signal (used by the
      // first-sign-in pre-pull blocking drain).
      final inFlight = _drainInFlight;
      if (inFlight != null) return inFlight;
      return;
    }
    if (_db == null || _syncDao == null) return;
    if (!_api.isAuthenticated) return;
    if (!_connectivity.isOnline) return;

    _isDraining = true;
    final completer = Completer<void>();
    _drainInFlight = completer.future;
    try {
      final items = await _syncDao!.getPendingSyncItems();
      // Only handle outbox-owned dataTypes — the legacy
      // DataSyncService still owns 'preferences' and
      // 'fcm_token_register'.
      final mine = items.where(_isOwned).toList();
      if (mine.isEmpty) return;

      final groups = <String, List<SyncQueueData>>{};
      for (final item in mine) {
        groups.putIfAbsent(item.dataType, () => []).add(item);
      }

      for (final entry in groups.entries) {
        await _drainGroup(entry.key, entry.value);
      }
    } catch (e) {
      AppLogger.error('SyncEngine drain failed', e);
    } finally {
      _isDraining = false;
      _drainInFlight = null;
      completer.complete();
    }
  }

  Future<void> _drainGroup(String dataType, List<SyncQueueData> items) async {
    final result = await _dispatch(dataType, items);

    switch (result) {
      case _DispatchResult.success:
        for (final item in items) {
          await _syncDao!.removeSyncItem(item.id);
        }
        AppLogger.network(
          'SyncEngine: drained $dataType x${items.length} OK',
        );
        break;

      case _DispatchResult.notReady:
        // Leave items pending; will retry on next drain.
        AppLogger.warning(
          'SyncEngine: $dataType x${items.length} drain returned null — '
          'will retry. Check backend logs for the failed POST.',
        );
        break;

      case _DispatchResult.failed:
        for (final item in items) {
          await _syncDao!.incrementRetryCount(item.id);
          if (item.retryCount + 1 >= _maxRetries) {
            await _syncDao!.updateSyncItemStatus(
              item.id,
              2, // failed
              error: 'max retries exceeded',
            );
          }
        }
        break;
    }
  }

  Future<_DispatchResult> _dispatch(
    String dataType,
    List<SyncQueueData> items,
  ) async {
    try {
      switch (dataType) {
        case SyncDataType.settings:
          return _dispatchSnapshot(
            read: () async {
              final row = await _settingsDao!.getSettings();
              return row == null ? null : _settingsToPayload(row);
            },
            send: _api.syncSettings,
          );

        case SyncDataType.statistics:
          return _dispatchSnapshot(
            read: () async {
              final row = await _gameDao!.getStatistics();
              if (row == null) return null;
              return {
                'model_json': row.modelJson,
                'updated_at': row.updatedAt.toUtc().toIso8601String(),
              };
            },
            send: _api.syncStatistics,
          );

        case SyncDataType.coinBalance:
          return _dispatchSnapshot(
            read: () async {
              final row = await _storeDao!.getCoinBalanceRow();
              if (row == null) return null;
              return {
                'balance': row.balance,
                // Use the row's actual updatedAt — sending now() here
                // would break server-side LWW (every push would win).
                'updated_at': _utcIso(row.updatedAt),
              };
            },
            send: _api.syncCoinBalance,
          );

        case SyncDataType.premiumStatus:
          return _dispatchSnapshot(
            read: () async {
              final row = await _storeDao!.getPremiumStatus();
              return row == null ? null : _premiumToPayload(row);
            },
            send: _api.syncPremiumStatus,
          );

        case SyncDataType.achievement:
          // Per-row snapshot: collect the unique achievement ids the
          // outbox references, read their current state from Drift
          // in a single batched query, send as a batch.
          final ids = _extractIds(items, prefix: 'achievement:');
          if (ids.isEmpty) return _DispatchResult.success;
          final achievementRows =
              await _gameDao!.getAchievementsByIds(ids);
          if (achievementRows.isEmpty) return _DispatchResult.success;
          final payload =
              achievementRows.map(_achievementToPayload).toList();
          return _mapOutcome(await _api.syncAchievements(payload));

        case SyncDataType.battlePass:
          final ids = _extractIds(items, prefix: 'battle_pass:');
          if (ids.isEmpty) return _DispatchResult.success;
          final passes =
              await _storeDao!.getBattlePassesBySeasonIds(ids);
          if (passes.isEmpty) return _DispatchResult.success;
          final passPayload = passes.map(_battlePassToPayload).toList();
          return _mapOutcome(await _api.syncBattlePass(passPayload));

        case SyncDataType.playerProgress:
          // Lifetime XP + level singleton. Read the current Drift row and
          // send it to the backend's absorbing-merge handler (MAX on totalXp).
          return _dispatchSnapshot(
            read: () async {
              final row = await _gameDao!.getPlayerProgress();
              if (row == null) return null;
              return _playerProgressToPayload(row);
            },
            send: _api.syncPlayerProgress,
          );

        case SyncDataType.stageProgress:
          // Per-row snapshot keyed by stage id — read the live Drift
          // rows so the batch carries the latest merged bests, not
          // whatever was true at enqueue time. Backend handler is an
          // absorbing merge, so resends are harmless.
          final stageIds = _extractIds(items, prefix: 'stage_progress:')
              .map(int.tryParse)
              .whereType<int>()
              .toSet();
          if (stageIds.isEmpty) return _DispatchResult.success;
          final stageRows =
              await _db!.stageProgressDao.getByStageIds(stageIds);
          if (stageRows.isEmpty) return _DispatchResult.success;
          final stagePayload =
              stageRows.map(_stageProgressToPayload).toList();
          return _mapOutcome(await _api.syncStageProgress(stagePayload));

        case SyncDataType.coinTransaction:
          // Event-typed: payload was frozen at outbox-write time.
          final payloads = _extractPayloads(items);
          return _mapOutcome(await _api.syncCoinTransactions(payloads));

        case SyncDataType.unlockedItem:
          final payloads = _extractPayloads(items);
          return _mapOutcome(await _api.syncUnlockedItems(payloads));

        case SyncDataType.dailyChallengeClaim:
          // Per-row snapshot keyed by challenge id — read the current
          // Drift row to get the authoritative coin reward + claim
          // timestamp instead of the frozen outbox payload.
          final ids = _extractIds(items, prefix: 'daily_challenge_claim:');
          if (ids.isEmpty) return _DispatchResult.success;
          final all = await _gameDao!.getTodaysChallenges();
          final rows = all
              .where((c) => ids.contains(c.challengeId))
              .map(_dailyChallengeToPayload)
              .toList();
          if (rows.isEmpty) return _DispatchResult.success;
          return _mapOutcome(await _api.syncDailyChallengeClaims(rows));

        case SyncDataType.weeklyQuestClaim:
          // Mirrors the daily-challenge drain: read current Drift rows by
          // quest id so we send the live state (progress + claim) instead
          // of whatever was frozen into the outbox payload at write time.
          final wqIds = _extractIds(items, prefix: 'weekly_quest_claim:');
          if (wqIds.isEmpty) return _DispatchResult.success;
          final allWq = await _gameDao!.getAllWeeklyQuests();
          final wqRows = allWq
              .where((q) => wqIds.contains(q.questId))
              .map(_weeklyQuestToPayload)
              .toList();
          if (wqRows.isEmpty) return _DispatchResult.success;
          return _mapOutcome(await _api.syncWeeklyQuestClaims(wqRows));

        case SyncDataType.dailyBonusClaim:
          // Singleton snapshot: read the current Drift row and send it
          // to the backend's absorbing-merge handler. Outbox payload is
          // ignored; the latest row state is authoritative.
          return _dispatchSnapshot(
            read: () async {
              final row = await _storeDao!.getDailyBonusRow();
              if (row == null) return null;
              Map<String, dynamic> weekly;
              try {
                weekly =
                    jsonDecode(row.weeklyClaimsJson) as Map<String, dynamic>;
              } catch (_) {
                weekly = const <String, dynamic>{};
              }
              return {
                'last_claim_utc': row.lastClaimUtcMs == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(
                        row.lastClaimUtcMs!,
                        isUtc: true,
                      ).toIso8601String(),
                'last_claim_tz_offset_minutes': row.lastClaimTzOffsetMinutes,
                'current_streak': row.currentStreak,
                'total_claims': row.totalClaims,
                'weekly_claims': weekly,
                'updated_at': _utcIso(row.updatedAt),
              };
            },
            send: _api.syncDailyBonusClaim,
          );

        default:
          // Unknown outbox type — likely a new SyncDataType constant
          // wasn't wired into this switch. Treat as permanent failure
          // so retries bump the counter and the items eventually move
          // to the failed bucket instead of silently dropping (which
          // the previous `return success` did, masking the regression).
          AppLogger.warning('SyncEngine: unknown outbox dataType $dataType');
          return _DispatchResult.failed;
      }
    } catch (e) {
      AppLogger.error('SyncEngine dispatch ($dataType) errored', e);
      return _DispatchResult.failed;
    }
  }

  /// Map an ApiService [SyncOutcome] onto the engine's drain result.
  _DispatchResult _mapOutcome(SyncOutcome outcome) {
    switch (outcome.kind) {
      case SyncOutcomeKind.success:
        return _DispatchResult.success;
      case SyncOutcomeKind.transient:
        return _DispatchResult.notReady;
      case SyncOutcomeKind.permanent:
        return _DispatchResult.failed;
    }
  }

  Future<_DispatchResult> _dispatchSnapshot({
    required Future<Map<String, dynamic>?> Function() read,
    required Future<SyncOutcome> Function(Map<String, dynamic>) send,
  }) async {
    final payload = await read();
    if (payload == null) return _DispatchResult.success; // nothing to send
    return _mapOutcome(await send(payload));
  }

  Set<String> _extractIds(List<SyncQueueData> items, {required String prefix}) {
    final ids = <String>{};
    for (final item in items) {
      try {
        final decoded = jsonDecode(item.data) as Map<String, dynamic>;
        final entityKey = decoded['entityKey'] as String?;
        if (entityKey == null) continue;
        if (entityKey.startsWith(prefix)) {
          ids.add(entityKey.substring(prefix.length));
        }
      } catch (_) {
        // Skip malformed rows
      }
    }
    return ids;
  }

  List<Map<String, dynamic>> _extractPayloads(List<SyncQueueData> items) {
    final out = <Map<String, dynamic>>[];
    for (final item in items) {
      try {
        final decoded = jsonDecode(item.data) as Map<String, dynamic>;
        final payload = decoded['payload'];
        if (payload is Map<String, dynamic>) out.add(payload);
      } catch (_) {
        // Skip malformed rows
      }
    }
    return out;
  }

  bool _isOwned(SyncQueueData item) {
    switch (item.dataType) {
      case SyncDataType.settings:
      case SyncDataType.statistics:
      case SyncDataType.achievement:
      case SyncDataType.coinBalance:
      case SyncDataType.coinTransaction:
      case SyncDataType.premiumStatus:
      case SyncDataType.unlockedItem:
      case SyncDataType.battlePass:
      case SyncDataType.dailyChallengeClaim:
      case SyncDataType.weeklyQuestClaim:
      case SyncDataType.dailyBonusClaim:
      case SyncDataType.playerProgress:
      case SyncDataType.stageProgress:
        return true;
      default:
        return false;
    }
  }

  // Backend uses JsonNamingPolicy.SnakeCaseLower so payloads have to
  // use snake_case keys — every name here mirrors the matching
  // SyncSettingsPayload / SyncAchievementPayload / etc. DTO record
  // property in dotnet land.
  //
  // All DateTimes serialized via `_utcIso` because Postgres + Npgsql
  // refuses `timestamp with time zone` writes for Unspecified-kind
  // values. Drift reads come back as Local; we coerce to UTC at the
  // wire boundary so the backend never sees a non-UTC timestamp.

  Map<String, dynamic> _settingsToPayload(GameSetting r) => {
        'theme_index': r.themeIndex,
        'sound_enabled': r.soundEnabled,
        'music_enabled': r.musicEnabled,
        'd_pad_enabled': r.dPadEnabled,
        'd_pad_position_index': r.dPadPositionIndex,
        'board_size_index': r.boardSizeIndex,
        'high_score': r.highScore,
        'crash_feedback_duration_seconds': r.crashFeedbackDurationSeconds,
        'trail_system_enabled': r.trailSystemEnabled,
        'screen_shake_enabled': r.screenShakeEnabled,
        'selected_skin_id': r.selectedSkinId,
        'selected_trail_id': r.selectedTrailId,
        'updated_at': _utcIso(r.updatedAt),
      };

  Map<String, dynamic> _achievementToPayload(Achievement r) => {
        'id': r.id,
        'current_progress': r.currentProgress,
        'target_progress': r.targetProgress,
        'is_unlocked': r.isUnlocked,
        'unlocked_at': _utcIsoNullable(r.unlockedAt),
        'reward_claimed': r.rewardClaimed,
        'updated_at': _utcIso(r.updatedAt),
      };

  Map<String, dynamic> _premiumToPayload(PremiumStatusData r) => {
        'is_premium_active': r.isPremiumActive,
        'premium_expiration_date': _utcIsoNullable(r.premiumExpirationDate),
        'is_on_trial': r.isOnTrial,
        'trial_start_date': _utcIsoNullable(r.trialStartDate),
        'trial_end_date': _utcIsoNullable(r.trialEndDate),
        'bronze_tournament_entries': r.bronzeTournamentEntries,
        'silver_tournament_entries': r.silverTournamentEntries,
        'gold_tournament_entries': r.goldTournamentEntries,
        'updated_at': _utcIso(r.updatedAt),
      };

  Map<String, dynamic> _playerProgressToPayload(PlayerProgressRow r) => {
        'total_xp': r.totalXp,
        'level': r.level,
        'updated_at': _utcIso(r.updatedAt),
      };

  // Keys match SyncStageProgressPayload on the backend (snake_case via
  // JsonNamingPolicy.SnakeCaseLower).
  Map<String, dynamic> _stageProgressToPayload(StageProgressRow r) => {
        'stage_id': r.stageId,
        'unlocked': r.unlocked,
        'cleared': r.cleared,
        'best_score': r.bestScore,
        'best_time_seconds': r.bestTimeSeconds,
        'best_wave_reached': r.bestWaveReached,
        'cleared_no_hit': r.clearedNoHit,
        'stars': r.stars,
        'clear_count': r.clearCount,
        'first_cleared_at': _utcIsoNullable(r.firstClearedAt),
        'updated_at': _utcIso(r.updatedAt),
      };

  Map<String, dynamic> _battlePassToPayload(BattlePassesData r) => {
        'season_id': r.seasonId,
        'current_tier': r.currentTier,
        'current_xp': r.currentXp,
        'xp_for_next_tier': r.xpForNextTier,
        'is_premium_pass': r.isPremiumPass,
        // Wire schema is a flat List<int>; the local Drift column
        // stores `{"free": [...], "premium": [...]}` (see StoreDao).
        // Flatten via union+sort here. Cross-device restore loses the
        // free-vs-premium split — acceptable until the wire format is
        // updated to carry the structure.
        'claimed_rewards': _flattenClaimedRewards(r.claimedRewards),
        'season_start_date': _utcIsoNullable(r.seasonStartDate),
        'season_end_date': _utcIsoNullable(r.seasonEndDate),
        'updated_at': _utcIso(r.updatedAt),
      };

  /// Reduce the structured `{"free":[...], "premium":[...]}` Drift
  /// payload (or a legacy flat array) to the flat `List<int>` the
  /// backend expects.
  List<int> _flattenClaimedRewards(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final free = (decoded['free'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const <int>[];
        final premium = (decoded['premium'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const <int>[];
        final union = <int>{...free, ...premium}.toList()..sort();
        return union;
      }
      if (decoded is List) {
        return decoded.map((e) => (e as num).toInt()).toList()..sort();
      }
    } catch (_) {
      // Malformed payload — send empty rather than crashing the drain.
    }
    return const <int>[];
  }

  Map<String, dynamic> _dailyChallengeToPayload(DailyChallenge r) => {
        'challenge_id': r.challengeId,
        'challenge_type': r.challengeType,
        'title': r.title,
        'description': r.description,
        'current_progress': r.currentProgress,
        'target_progress': r.targetProgress,
        'reward_coins': r.rewardCoins,
        'is_completed': r.isCompleted,
        'reward_claimed': r.rewardClaimed,
        'challenge_date': _utcIso(r.challengeDate),
        'expires_at': _utcIso(r.expiresAt),
        'completed_at': _utcIsoNullable(r.completedAt),
        'updated_at': _utcIso(r.updatedAt),
      };

  // Mirrors _dailyChallengeToPayload — keys match SyncWeeklyQuestClaimPayload
  // on the backend (snake_case via JsonNamingPolicy.SnakeCaseLower).
  Map<String, dynamic> _weeklyQuestToPayload(WeeklyQuest r) => {
        'quest_id': r.questId,
        'quest_type': r.questType,
        'title': r.title,
        'description': r.description,
        'current_progress': r.currentProgress,
        'target_value': r.targetValue,
        'coin_reward': r.coinReward,
        'battle_pass_xp_reward': r.battlePassXpReward,
        'is_completed': r.isCompleted,
        'claimed_reward': r.claimedReward,
        'week_start_date': _utcIso(r.weekStartDate),
        'completed_at': _utcIsoNullable(r.completedAt),
        'updated_at': _utcIso(r.updatedAt),
      };

  /// Serialize a DateTime as a UTC ISO 8601 string with the trailing
  /// "Z" suffix — required by Postgres + Npgsql on the backend.
  String _utcIso(DateTime dt) => dt.toUtc().toIso8601String();

  String? _utcIsoNullable(DateTime? dt) => dt?.toUtc().toIso8601String();

  /// Apply a server snapshot to local Drift, suppressing outbox
  /// enqueues so the data doesn't echo back as a push. Wrapped in a
  /// single transaction — if any section throws, the whole apply
  /// rolls back so we never leave the DB in a half-restored state.
  ///
  /// Section keys mirror the backend SyncSnapshotDto record. Any
  /// missing / null section is skipped (the user has no cloud data
  /// of that kind yet).
  Future<void> _applyCloudSnapshot(Map<String, dynamic> snapshot) async {
    if (_db == null) return;

    await _db!.transaction(() async {
      // ----- settings -----
      final settings = snapshot['settings'];
      if (settings is Map<String, dynamic>) {
        // High score is max-merged: if local is ahead (e.g., a personal
        // best earned offline before this device ever signed in), the
        // pre-pull drain should have pushed it up, but as a defense in
        // depth we never let the snapshot apply drop a higher local
        // value. All other settings columns are cloud-wins — they're
        // preferences the user explicitly set on whichever device they
        // signed in from most recently, and re-applying old values would
        // surprise them.
        final localSettings = await _settingsDao!.getSettings();
        final cloudHighScore = settings['high_score'] as int? ?? 0;
        final localHighScore = localSettings?.highScore ?? 0;
        final mergedHighScore = cloudHighScore >= localHighScore
            ? cloudHighScore
            : localHighScore;
        if (localHighScore > cloudHighScore) {
          AppLogger.network(
            'SyncEngine: high score restore — local ($localHighScore) ahead '
            'of cloud ($cloudHighScore); keeping local',
          );
          // Re-enqueue so the post-clearSyncQueue drain can push the
          // higher local value to the server. Enqueueing INSIDE the apply
          // transaction is safe — the outbox table is part of the same DB.
          await _db!.enqueueSyncOutbox(
            dataType: SyncDataType.settings,
            entityKey: 'settings:1',
          );
        }

        await _settingsDao!.applySettingsSnapshot(
          GameSettingsCompanion(
            themeIndex: Value(settings['theme_index'] as int? ?? 0),
            soundEnabled: Value(settings['sound_enabled'] as bool? ?? true),
            musicEnabled: Value(settings['music_enabled'] as bool? ?? true),
            dPadEnabled: Value(settings['d_pad_enabled'] as bool? ?? false),
            dPadPositionIndex:
                Value(settings['d_pad_position_index'] as int? ?? 1),
            boardSizeIndex: Value(settings['board_size_index'] as int? ?? 1),
            highScore: Value(mergedHighScore),
            crashFeedbackDurationSeconds: Value(
                settings['crash_feedback_duration_seconds'] as int? ?? 3),
            trailSystemEnabled:
                Value(settings['trail_system_enabled'] as bool? ?? false),
            screenShakeEnabled:
                Value(settings['screen_shake_enabled'] as bool? ?? false),
            selectedSkinId: Value(settings['selected_skin_id'] as String?),
            selectedTrailId: Value(settings['selected_trail_id'] as String?),
            lastUpdated: Value(_parseDate(settings['updated_at']) ?? DateTime.now()),
            updatedAt: Value(_parseDate(settings['updated_at']) ?? DateTime.now()),
          ),
        );
      }

      // ----- statistics -----
      final stats = snapshot['statistics'];
      if (stats is Map<String, dynamic>) {
        final modelJson = stats['model_json'] as String? ?? '{}';
        await _gameDao!.updateStatisticsFromJson(modelJson, enqueueSync: false);
      }

      // ----- coin balance -----
      // Max-merged for the same reason as high score: if a local Drift
      // write happened during boot (legacy SP migration, +50 starting
      // bonus, an offline earn) and the pre-pull drain didn't manage to
      // ship it (e.g., transient backend hiccup), the snapshot apply
      // would otherwise overwrite the higher local total and the
      // subsequent clearSyncQueue would strand the delta. Taking max
      // and re-enqueueing keeps the local value AND ensures the next
      // drain pushes it up to the server.
      final balance = snapshot['coin_balance'];
      if (balance is Map<String, dynamic>) {
        final cloudBalance = balance['balance'] as int? ?? 0;
        final localRow = await _storeDao!.getCoinBalanceRow();
        final localBalance = localRow?.balance ?? 0;
        if (cloudBalance >= localBalance) {
          await _storeDao!.applyCoinBalanceSnapshot(
            balance: cloudBalance,
            updatedAt: _parseDate(balance['updated_at']),
          );
        } else {
          AppLogger.network(
            'SyncEngine: coin balance restore — local ($localBalance) ahead '
            'of cloud ($cloudBalance) by ${localBalance - cloudBalance}; '
            'keeping local and re-enqueueing for push',
          );
          // Re-enqueue so the next drain ships the local-greater value
          // even after the caller's clearSyncQueue wipes the queue.
          await _db!.enqueueSyncOutbox(
            dataType: SyncDataType.coinBalance,
            entityKey: 'coin_balance:1',
          );
          // No Drift write — local already holds the correct value.
        }
      }

      // ----- coin transactions (event-typed, append-only) -----
      //
      // Re-insert via the bare table to skip outbox enqueue AND the
      // running-balance touch — backend already gave us the
      // authoritative balance separately.
      //
      // Dedup by (createdAt, amount, type, source) fingerprint: the
      // local table has an autoIncrement primary key, so
      // InsertMode.insertOrIgnore alone never catches conflicts. Today
      // the apply runs at most once per install (gated by the
      // `sync_engine_has_ever_signed_in` flag), but a future re-import
      // / admin tool / repeated apply would otherwise duplicate every
      // historical row on each run.
      final transactions = snapshot['coin_transactions'];
      if (transactions is List && transactions.isNotEmpty) {
        final existing = await _db!.select(_db!.coinTransactions).get();
        final fingerprints = <String>{};
        for (final row in existing) {
          fingerprints.add(_coinTxnFingerprint(
            row.createdAt,
            row.amount,
            row.type,
            row.source,
          ));
        }
        for (final raw in transactions) {
          if (raw is! Map<String, dynamic>) continue;
          final createdAt =
              _parseDate(raw['created_at']) ?? DateTime.now();
          final amount = raw['amount'] as int? ?? 0;
          final type = raw['type'] as String? ?? 'earned';
          final source = raw['source'] as String? ?? 'cloud';
          final fingerprint =
              _coinTxnFingerprint(createdAt, amount, type, source);
          if (!fingerprints.add(fingerprint)) continue; // duplicate
          await _db!.into(_db!.coinTransactions).insert(
                CoinTransactionsCompanion.insert(
                  amount: amount,
                  type: type,
                  source: source,
                  description: Value(raw['description'] as String?),
                  createdAt: Value(createdAt),
                ),
              );
        }
      }

      // ----- achievements -----
      // Backend doesn't echo name/description because the catalog is
      // client-seeded. Drift's `insertOnConflictUpdate` validates the
      // companion as an INSERT even when the row exists, so EVERY
      // not-null-no-default column has to be present — leaving
      // name/description/category as `Value.absent()` for the "row
      // already exists" path throws InvalidDataException. Always
      // populate them: prefer the existing Drift row (which has
      // already been seeded), fall back to the local default catalog
      // for ids not yet seeded.
      final achievements = snapshot['achievements'];
      if (achievements is List && achievements.isNotEmpty) {
        final defaultsById = {
          for (final a in ach_model.Achievement.getDefaultAchievements())
            a.id: a,
        };
        // Pre-fetch existing rows in a single query instead of doing
        // one Drift round-trip per snapshot entry. 50 achievements ×
        // per-call overhead adds up, even though each lookup is cheap.
        final existingRows = await _gameDao!.getAllAchievements();
        final existingById = {for (final r in existingRows) r.id: r};
        for (final raw in achievements) {
          if (raw is! Map<String, dynamic>) continue;
          final id = raw['id'] as String?;
          if (id == null) continue;

          final existing = existingById[id];
          final ach_model.Achievement? defaultEntry = defaultsById[id];

          String? name;
          String? description;
          String? category;
          int? rewardCoins;
          String? iconName;
          bool? isSecret;

          if (existing != null) {
            // Preserve the local catalog metadata. The synced payload
            // only carries progress/unlock fields; everything else
            // came from the client seed and should not be regenerated
            // from defaults (the catalog can evolve between releases).
            name = existing.name;
            description = existing.description;
            category = existing.category;
            rewardCoins = existing.rewardCoins;
            iconName = existing.iconName;
            isSecret = existing.isSecret;
          } else if (defaultEntry != null) {
            name = defaultEntry.title;
            description = defaultEntry.description;
            category = defaultEntry.type.name;
            rewardCoins = defaultEntry.coinReward;
            iconName = defaultEntry.icon.codePoint.toString();
            isSecret = false;
          } else {
            // Server-side id with no local row and no local default
            // catalog entry. Shouldn't happen but defend — skip rather
            // than crash the whole snapshot apply.
            AppLogger.network(
              'SyncEngine: skipping unknown achievement "$id" — '
              'no local default catalog entry',
            );
            continue;
          }

          await _gameDao!.upsertAchievement(
            AchievementsCompanion(
              id: Value(id),
              name: Value(name),
              description: Value(description),
              category: Value(category),
              rewardCoins: Value(rewardCoins),
              iconName: Value(iconName),
              isSecret: Value(isSecret),
              currentProgress: Value(raw['current_progress'] as int? ?? 0),
              targetProgress: Value(raw['target_progress'] as int? ?? 1),
              isUnlocked: Value(raw['is_unlocked'] as bool? ?? false),
              unlockedAt: Value(_parseDate(raw['unlocked_at'])),
              rewardClaimed: Value(raw['reward_claimed'] as bool? ?? false),
              updatedAt:
                  Value(_parseDate(raw['updated_at']) ?? DateTime.now()),
            ),
            enqueueSync: false,
          );
        }
      }

      // ----- unlocked items -----
      final unlocked = snapshot['unlocked_items'];
      if (unlocked is List) {
        for (final raw in unlocked) {
          if (raw is! Map<String, dynamic>) continue;
          final itemId = raw['item_id'] as String?;
          final itemType = raw['item_type'] as String?;
          if (itemId == null || itemType == null) continue;
          await _storeDao!.unlockItem(
            itemId,
            itemType,
            unlockedBy: raw['unlocked_by'] as String?,
            enqueueSync: false,
          );
        }
      }

      // ----- battle pass (per-season) -----
      final battlePasses = snapshot['battle_passes'];
      if (battlePasses is List) {
        for (final raw in battlePasses) {
          if (raw is! Map<String, dynamic>) continue;
          final seasonId = raw['season_id'] as String?;
          if (seasonId == null) continue;
          // Wire payload is a flat List<int>; store under "free" in the
          // structured local format. The free-vs-premium split is lost
          // on restore (see [_flattenClaimedRewards] comment) — a user
          // who reinstalls may need to re-claim premium-side rewards.
          final wireRewards = raw['claimed_rewards'];
          final wireSet = wireRewards is List
              ? wireRewards.map((e) => (e as num).toInt()).toSet()
              : <int>{};
          // Preserve the LOCAL free/premium split. The wire payload flattens
          // both tracks into one list and can't be un-flattened, so blindly
          // writing it with premium=[] WIPES premium-track claims the user
          // already made locally — which is why a just-claimed premium reward
          // reappeared after a sync. Merge instead: keep local premium claims
          // as-is, and union any wire tiers we don't already know as premium
          // into the free track.
          final existing = await _storeDao!.getBattlePass(seasonId);
          final localSplit = StoreDao.decodeClaimedRewards(
            existing?.claimedRewards ?? '',
          );
          final localPremium = localSplit['premium']!.toSet();
          final mergedFree = <int>{
            ...localSplit['free']!,
            ...wireSet.difference(localPremium),
          };
          final claimedJson = jsonEncode({
            'free': mergedFree.toList()..sort(),
            'premium': localPremium.toList()..sort(),
          });
          await _storeDao!.saveBattlePass(
            BattlePassesCompanion(
              seasonId: Value(seasonId),
              currentTier: Value(raw['current_tier'] as int? ?? 0),
              currentXp: Value(raw['current_xp'] as int? ?? 0),
              xpForNextTier: Value(raw['xp_for_next_tier'] as int? ?? 100),
              isPremiumPass: Value(raw['is_premium_pass'] as bool? ?? false),
              claimedRewards: Value(claimedJson),
              seasonStartDate: Value(_parseDate(raw['season_start_date'])),
              seasonEndDate: Value(_parseDate(raw['season_end_date'])),
            ),
            enqueueSync: false,
          );
        }
      }

      // ----- player progress (lifetime XP + level singleton) -----
      //
      // MAX-merge so a restore never regresses local lifetime XP (the level
      // is recomputed from the merged total inside the DAO). No-op if the
      // snapshot omits it.
      final playerProgress = snapshot['player_progress'];
      if (playerProgress is Map<String, dynamic>) {
        final totalXp = (playerProgress['total_xp'] as num?)?.toInt() ?? 0;
        await _gameDao!.applyPlayerProgressSnapshot(totalXp);
      }

      // ----- campaign stage progress -----
      //
      // Monotonic max-merge inside the DAO (mirrors the backend handler);
      // if local is ahead on any field the DAO re-enqueues that stage for
      // push, surviving the caller's clearSyncQueue. No-op when absent.
      final stageProgress = snapshot['stage_progress'];
      if (stageProgress is List && stageProgress.isNotEmpty) {
        await _db!.stageProgressDao.applyStageProgressSnapshot(
          stageProgress.whereType<Map<String, dynamic>>().toList(),
        );
      }

      // ----- premium status -----
      final premium = snapshot['premium_status'];
      if (premium is Map<String, dynamic>) {
        await _storeDao!.applyPremiumStatusSnapshot(
          PremiumStatusCompanion(
            isPremiumActive: Value(premium['is_premium_active'] as bool? ?? false),
            premiumExpirationDate:
                Value(_parseDate(premium['premium_expiration_date'])),
            isOnTrial: Value(premium['is_on_trial'] as bool? ?? false),
            trialStartDate: Value(_parseDate(premium['trial_start_date'])),
            trialEndDate: Value(_parseDate(premium['trial_end_date'])),
            bronzeTournamentEntries:
                Value(premium['bronze_tournament_entries'] as int? ?? 0),
            silverTournamentEntries:
                Value(premium['silver_tournament_entries'] as int? ?? 0),
            goldTournamentEntries:
                Value(premium['gold_tournament_entries'] as int? ?? 0),
          ),
        );
      }

      // ----- daily challenge claims -----
      final claims = snapshot['daily_challenge_claims'];
      if (claims is List) {
        for (final raw in claims) {
          if (raw is! Map<String, dynamic>) continue;
          final challengeId = raw['challenge_id'] as String?;
          if (challengeId == null) continue;
          await _gameDao!.upsertDailyChallenge(
            DailyChallengesCompanion(
              challengeId: Value(challengeId),
              challengeType: Value(raw['challenge_type'] as String? ?? ''),
              title: Value(raw['title'] as String? ?? ''),
              description: Value(raw['description'] as String? ?? ''),
              currentProgress: Value(raw['current_progress'] as int? ?? 0),
              targetProgress: Value(raw['target_progress'] as int? ?? 0),
              rewardCoins: Value(raw['reward_coins'] as int? ?? 0),
              isCompleted: Value(raw['is_completed'] as bool? ?? false),
              rewardClaimed: Value(raw['reward_claimed'] as bool? ?? false),
              challengeDate:
                  Value(_parseDate(raw['challenge_date']) ?? DateTime.now()),
              expiresAt: Value(_parseDate(raw['expires_at']) ??
                  DateTime.now().add(const Duration(days: 1))),
              completedAt: Value(_parseDate(raw['completed_at'])),
            ),
            enqueueSync: false,
          );
        }
      }

      // ----- weekly quest claims -----
      //
      // Mirrors the daily-challenge-claims block above. Keys match
      // [_weeklyQuestToPayload] / SyncWeeklyQuestClaimPayload. Treated as
      // authoritative client-mirror state; no-op if the snapshot omits it.
      final weeklyClaims = snapshot['weekly_quest_claims'];
      if (weeklyClaims is List) {
        for (final raw in weeklyClaims) {
          if (raw is! Map<String, dynamic>) continue;
          final questId = raw['quest_id'] as String?;
          if (questId == null || questId.isEmpty) continue;
          await _gameDao!.upsertWeeklyQuest(
            WeeklyQuestsCompanion(
              questId: Value(questId),
              questType: Value(raw['quest_type'] as String? ?? ''),
              title: Value(raw['title'] as String? ?? ''),
              description: Value(raw['description'] as String? ?? ''),
              currentProgress: Value(raw['current_progress'] as int? ?? 0),
              targetValue: Value(raw['target_value'] as int? ?? 0),
              coinReward: Value(raw['coin_reward'] as int? ?? 0),
              battlePassXpReward:
                  Value(raw['battle_pass_xp_reward'] as int? ?? 0),
              isCompleted: Value(raw['is_completed'] as bool? ?? false),
              claimedReward: Value(raw['claimed_reward'] as bool? ?? false),
              weekStartDate:
                  Value(_parseDate(raw['week_start_date']) ?? DateTime.now()),
              completedAt: Value(_parseDate(raw['completed_at'])),
            ),
            enqueueSync: false,
          );
        }
      }

      // ----- daily login bonus (singleton) -----
      //
      // Compare server's user-local day against any existing local row
      // and adopt whichever is at-or-newer. If local is ahead, we
      // re-enqueue an outbox row so the next drain ships our value up.
      final dailyBonus = snapshot['daily_bonus'];
      if (dailyBonus is Map<String, dynamic>) {
        final lastClaimUtcStr = dailyBonus['last_claim_utc'] as String?;
        final lastClaimTzMin =
            dailyBonus['last_claim_tz_offset_minutes'] as int?;
        final currentStreak = dailyBonus['current_streak'] as int? ?? 0;
        final totalClaims = dailyBonus['total_claims'] as int? ?? 0;
        final weeklyMap = dailyBonus['weekly_claims'];
        final weeklyJson = weeklyMap is Map
            ? jsonEncode(weeklyMap)
            : '{}';

        final cloudLastUtcMs = lastClaimUtcStr == null
            ? null
            : DateTime.parse(lastClaimUtcStr).millisecondsSinceEpoch;

        final localRow = await _storeDao!.getDailyBonusRow();

        // Compare in user-local days using each side's own tz snapshot.
        String? cloudLocalDay;
        if (cloudLastUtcMs != null) {
          cloudLocalDay = _userLocalDay(
            DateTime.fromMillisecondsSinceEpoch(cloudLastUtcMs, isUtc: true),
            lastClaimTzMin ?? 0,
          );
        }
        String? localLocalDay;
        if (localRow?.lastClaimUtcMs != null) {
          localLocalDay = _userLocalDay(
            DateTime.fromMillisecondsSinceEpoch(
                localRow!.lastClaimUtcMs!, isUtc: true),
            localRow.lastClaimTzOffsetMinutes ?? 0,
          );
        }

        final adoptCloud = localLocalDay == null ||
            (cloudLocalDay != null && cloudLocalDay.compareTo(localLocalDay) >= 0);

        if (adoptCloud) {
          await _storeDao!.applyDailyBonusSnapshot(
            lastClaimUtcMs: cloudLastUtcMs,
            lastClaimTzOffsetMinutes: lastClaimTzMin,
            currentStreak: currentStreak,
            totalClaims: totalClaims,
            weeklyClaimsJson: weeklyJson,
          );
        } else {
          AppLogger.network(
            'SyncEngine: daily-bonus restore — local ($localLocalDay) '
            'ahead of cloud ($cloudLocalDay); keeping local and '
            're-enqueueing for push',
          );
          await _db!.enqueueSyncOutbox(
            dataType: SyncDataType.dailyBonusClaim,
            entityKey: 'daily_bonus_claim:1',
          );
        }
      }
    });

    if (kDebugMode) {
      AppLogger.network('SyncEngine: snapshot apply committed');
    }
  }

  /// Shared math contract — mirrors StoreDao + CoinsState + the backend
  /// handler so client and server agree on which calendar day a UTC
  /// instant belongs to.
  static String _userLocalDay(DateTime utc, int tzOffsetMinutes) {
    final local = utc.add(Duration(minutes: tzOffsetMinutes));
    return local.toIso8601String().substring(0, 10);
  }

  /// Stable identity for a coin-transaction row that doesn't depend
  /// on the local autoIncrement PK. Used by the snapshot apply to
  /// skip rows that already exist locally.
  String _coinTxnFingerprint(
    DateTime createdAt,
    int amount,
    String type,
    String source,
  ) =>
      '${createdAt.toUtc().toIso8601String()}|$amount|$type|$source';

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// Cleanup. Idempotent.
  Future<void> dispose() async {
    await _outboxWatcher?.cancel();
    await _connectivityWatcher?.cancel();
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _outboxWatcher = null;
    _connectivityWatcher = null;
    _debounceTimer = null;
    _periodicTimer = null;
    // Reset the arm latch so a later initialize() / markFirstSignInSkipped()
    // can reattach the watchers we just cancelled. Without this, _armDrainLoop
    // short-circuits on the stale `true` and the engine stays asleep after a
    // dispose → re-init cycle (e.g. sign-out then sign-in).
    _drainLoopArmed = false;
    _removeRestoreOverlay();
  }
}
