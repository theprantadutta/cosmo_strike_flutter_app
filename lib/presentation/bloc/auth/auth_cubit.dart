import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_settings_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/notification_service.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

import 'auth_state.dart';

export 'auth_state.dart';

/// Cubit for managing authentication state
class AuthCubit extends Cubit<AuthState> {
  final UnifiedUserService _userService;
  final AnalyticsFacade _analytics;
  VoidCallback? _userServiceListener;

  /// Completer that signals when local initialization is done
  final Completer<void> _localInitCompleter = Completer<void>();

  AuthCubit(this._userService, this._analytics) : super(AuthState.initial());

  /// Wait for local initialization (SharedPreferences check) to complete.
  /// This is fast and does not depend on network.
  Future<void> waitForLocalInit() => _localInitCompleter.future;

  /// Initialize the auth cubit
  Future<void> initialize() async {
    if (state.status == AuthStatus.authenticated) return;

    try {
      // FIRST: Load isFirstTimeUser from SharedPreferences (fast, local-only)
      // This must happen before any network calls to prevent race conditions
      final isFirstTime = await _isFirstTimeUser();

      emit(state.copyWith(
        status: AuthStatus.loading,
        isLoading: true,
        isFirstTimeUser: isFirstTime, // Set from local storage IMMEDIATELY
      ));

      // Signal that local init is complete - LoadingScreen can proceed
      if (!_localInitCompleter.isCompleted) {
        _localInitCompleter.complete();
      }

      // Initialize the user service if not already initialized
      // This may involve network calls but isFirstTimeUser is already set
      if (!_userService.isInitialized) {
        await _userService.initialize();
      }

      // Listen to user service changes
      _userServiceListener = () {
        _onUserServiceChanged();
      };
      _userService.addListener(_userServiceListener!);

      // Update state based on current user
      _updateFromUserService(isFirstTime: isFirstTime);
    } catch (e) {
      // Complete the completer even on error to prevent hanging
      if (!_localInitCompleter.isCompleted) {
        _localInitCompleter.complete();
      }
      emit(
        state.copyWith(
          status: AuthStatus.error,
          errorMessage: e.toString(),
          isLoading: false,
        ),
      );
    }
  }

  void _onUserServiceChanged() {
    _updateFromUserService();
  }

  void _updateFromUserService({bool? isFirstTime}) {
    final user = _userService.currentUser;

    if (user != null) {
      emit(
        state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          isLoading: false,
          isFirstTimeUser: isFirstTime ?? state.isFirstTimeUser,
          clearError: true,
        ),
      );
      // Post-auth side effects. Gated on having a real backend JWT —
      // an offline-guest UnifiedUser still satisfies `user != null` but
      // doesn't have an authenticated API session, so we'd just 401 if
      // we ran the syncs. PurchaseService.runPostAuthRestore is
      // idempotent across re-emits (only fires the full restore once
      // per process; subsequent calls just drain pending verifies).
      if (user.userType != UserType.guest && ApiService().isAuthenticated) {
        _firePostAuthSyncs();
      }
    } else {
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          clearUser: true,
          isLoading: false,
          isFirstTimeUser: isFirstTime ?? state.isFirstTimeUser,
        ),
      );
    }
  }

  // The last UID we ran the cubit-level syncs for. Reset on UID transition
  // so a sign-out + sign-in-to-different-account, or an anonymous → Google
  // upgrade, re-syncs from the new identity. A simple boolean would have
  // pinned syncs to the first authenticated UID and starved every later
  // user of their own data until the next cold start.
  String? _lastSyncedUid;

  void _firePostAuthSyncs() {
    // PurchaseService manages its own one-shot for the Play Store restore;
    // subsequent calls just drain the pending-verification queue. Safe to
    // call on every authenticated emission.
    unawaited(PurchaseService().runPostAuthRestore());

    final currentUid = _userService.currentUser?.uid;
    if (currentUid == null) return;
    if (currentUid == _lastSyncedUid) return;
    _lastSyncedUid = currentUid;

    AppLogger.info('Firing post-auth syncs for user $currentUid');

    // Premium — authoritative pull from the backend. If the server has
    // revoked Pro (subscription expired, cleanup job ran, RTDN webhook
    // landed), this is what catches the revocation and downgrades local
    // tier. Without this firing on every UID transition, a stale
    // tier=pro could persist for the new account.
    try {
      unawaited(getIt<PremiumCubit>().syncWithBackend());
    } catch (_) {}

    // Coins — pulls server's coins column and merges via max(local, server).
    try {
      unawaited(getIt<CoinsCubit>().syncWithBackend());
    } catch (_) {}

    // High score — same pattern; pulls user.high_score and bumps the
    // local DB via the never-decrease guard. The settings-table stream
    // propagates into GameSettingsCubit state.
    try {
      unawaited(getIt<GameSettingsCubit>().syncWithBackend());
    } catch (_) {}
  }

  /// Sign in with Google
  Future<bool> signInWithGoogle() async {
    emit(state.copyWith(isLoading: true, clearError: true));

    try {
      final result = await _userService.signInWithGoogle();

      if (result) {
        _analytics.trackSignInGoogle();
        final uid = _userService.currentUser?.uid;
        _analytics.setUserId(uid);
        _analytics.setUserProperties(authMethod: 'google');

        // Consume the IsNewUser flag from the auth response. The
        // FirstTimeAuthScreen reads this off state and routes to
        // /username-setup before /home for brand-new accounts.
        final needsSetup = _userService.consumeJustLoadedNewUser();
        emit(state.copyWith(needsUsernameSetup: needsSetup));
      } else {
        emit(
          state.copyWith(
            isLoading: false,
            errorMessage: 'Google sign-in failed',
          ),
        );
      }

      return result;
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
      return false;
    }
  }

  /// Sign in anonymously (guest mode)
  Future<bool> signInAnonymously() async {
    emit(state.copyWith(isLoading: true, clearError: true));

    try {
      final result = await _userService.signInAnonymously();

      if (result) {
        _analytics.trackSignInAnonymous();
        final uid = _userService.currentUser?.uid;
        _analytics.setUserId(uid);
        _analytics.setUserProperties(authMethod: 'anonymous');

        // Same first-time-account path applies to anonymous sign-in —
        // anonymous users get a generated username too and benefit
        // from picking their own.
        final needsSetup = _userService.consumeJustLoadedNewUser();
        emit(state.copyWith(needsUsernameSetup: needsSetup));
      } else {
        emit(
          state.copyWith(
            isLoading: false,
            errorMessage: 'Anonymous sign-in failed',
          ),
        );
      }

      return result;
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
      return false;
    }
  }

  /// Sign in with email/password. Returns true on success. On failure,
  /// emits an errorMessage containing the FirebaseAuthException code so
  /// the UI can map it to a user-friendly inline error.
  Future<bool> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final ok = await _userService.signInWithEmailPassword(
        email: email,
        password: password,
      );
      if (ok) {
        _analytics.trackSignInEmail();
        _analytics.setUserId(_userService.currentUser?.uid);
        _analytics.setUserProperties(authMethod: 'email');
        final needsSetup = _userService.consumeJustLoadedNewUser();
        emit(state.copyWith(needsUsernameSetup: needsSetup));
      } else {
        emit(state.copyWith(isLoading: false, errorMessage: 'sign-in failed'));
      }
      return ok;
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.code));
      return false;
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
      return false;
    }
  }

  /// Create a brand-new email/password account.
  Future<bool> createAccountWithEmailPassword({
    required String email,
    required String password,
  }) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final ok = await _userService.createAccountWithEmailPassword(
        email: email,
        password: password,
      );
      if (ok) {
        _analytics.trackSignInEmail();
        _analytics.setUserId(_userService.currentUser?.uid);
        _analytics.setUserProperties(authMethod: 'email');
        final needsSetup = _userService.consumeJustLoadedNewUser();
        emit(state.copyWith(needsUsernameSetup: needsSetup));
      } else {
        emit(state.copyWith(isLoading: false, errorMessage: 'sign-up failed'));
      }
      return ok;
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.code));
      return false;
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
      return false;
    }
  }

  /// Link the current anonymous account to a new email/password credential.
  /// Same UID = same backend user row, so progress is preserved.
  Future<bool> linkAnonymousToEmailPassword({
    required String email,
    required String password,
  }) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final ok = await _userService.linkAnonymousToEmailPassword(
        email: email,
        password: password,
      );
      if (ok) {
        _analytics.setUserProperties(authMethod: 'email');
        // After linking the cubit's user reference should refresh from
        // the service — the listener picks up the change but we emit
        // here too for snappy UI feedback.
        emit(state.copyWith(user: _userService.currentUser, isLoading: false));
      } else {
        emit(state.copyWith(isLoading: false, errorMessage: 'link failed'));
      }
      return ok;
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.code));
      return false;
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
      return false;
    }
  }

  /// Link the current anonymous account to a Google sign-in.
  Future<bool> linkAnonymousToGoogle() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final ok = await _userService.linkAnonymousToGoogle();
      if (ok) {
        _analytics.setUserProperties(authMethod: 'google');
        emit(state.copyWith(user: _userService.currentUser, isLoading: false));
      } else {
        emit(state.copyWith(isLoading: false, errorMessage: 'link failed'));
      }
      return ok;
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.code));
      return false;
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
      return false;
    }
  }

  /// Send a Firebase password-reset email. Returns true if accepted.
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _userService.sendPasswordResetEmail(email);
      return true;
    } on FirebaseAuthException catch (e) {
      emit(state.copyWith(errorMessage: e.code));
      return false;
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
      return false;
    }
  }

  /// Clear the needs-username-setup flag once the setup screen is done.
  void clearNeedsUsernameSetup() {
    if (state.needsUsernameSetup) {
      emit(state.copyWith(needsUsernameSetup: false));
    }
  }

  /// Sign out
  ///
  /// Eagerly clears the local user object so screens that branch on
  /// [AuthState.isSignedIn] / [AuthState.isAnonymous] stop showing stale
  /// data the moment the user confirms sign-out. Navigation to the sign-in
  /// screen is the responsibility of whichever screen initiated logout
  /// (typically the profile screen via a BlocListener watching for the
  /// transition to AuthStatus.unauthenticated).
  Future<void> signOut() async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      isLoading: true,
      clearUser: true,
      clearError: true,
    ));

    try {
      await _userService.signOut();
      _analytics.trackSignOut();
      _analytics.setUserId(null);

      // Reset the notification backend-integration latch so that the next
      // sign-in re-registers the FCM token under the new user identity.
      // Without this, the latch (set true after the previous session's
      // successful registration) blocks the re-init path entirely.
      NotificationService().resetBackendIntegration();

      // Reset the first-time-setup flag so a closed-and-reopened app routes
      // back through FirstTimeAuthScreen instead of silently re-creating a
      // guest user via initialize()'s offline-guest fallback. The user
      // explicitly asked to be signed out — they should re-pick Guest vs
      // Google on next launch.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('first_time_setup_complete', false);
      } catch (_) {
        // Best-effort; not critical if it fails.
      }
      emit(state.copyWith(isFirstTimeUser: true));
      // The user service listener will emit the final unauthenticated state.
    } catch (e) {
      // Even on error, finalise as unauthenticated so the UI can navigate
      // away — a half-signed-out state is worse than an explicit sign-out.
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        clearUser: true,
        isLoading: false,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Update username
  Future<bool> updateUsername(String newUsername) async {
    try {
      final result = await _userService.updateUsername(newUsername);
      return result;
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
      return false;
    }
  }

  /// Update guest username
  Future<bool> updateGuestUsername(String newUsername) async {
    try {
      final result = await _userService.updateGuestUsername(newUsername);
      return result;
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
      return false;
    }
  }

  /// Update authenticated username
  Future<bool> updateAuthenticatedUsername(String newUsername) async {
    try {
      final result = await _userService.updateAuthenticatedUsername(
        newUsername,
      );
      if (result) {
        // Re-emit state so widgets bound to AuthState see the new
        // username immediately. The service updated _currentUser in
        // memory but Bloc state needs a copyWith to push through.
        emit(state.copyWith(user: _userService.currentUser));
      }
      return result;
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
      return false;
    }
  }

  /// Pull the latest profile from the backend and re-emit AuthState.
  /// Useful when entering screens that depend on fresh user data — e.g.
  /// after a deploy that backfilled NULL usernames, the cached
  /// UnifiedUser would still show a missing username until this is called.
  Future<void> refreshUserFromBackend() async {
    final ok = await _userService.refreshFromBackend();
    if (ok && _userService.currentUser != null) {
      emit(state.copyWith(user: _userService.currentUser));
    }
  }

  /// Update game stats
  Future<void> updateGameStats({
    int? newHighScore,
    int? gamesPlayed,
    int? totalScore,
    int? level,
  }) async {
    await _userService.updateGameStats(
      newHighScore: newHighScore,
      gamesPlayed: gamesPlayed,
      totalScore: totalScore,
      level: level,
    );
  }

  /// Check if this is a first-time user
  Future<bool> _isFirstTimeUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool('first_time_setup_complete') ?? false);
    } catch (e) {
      return true;
    }
  }

  /// Mark first-time setup as complete
  Future<void> markFirstTimeSetupComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('first_time_setup_complete', true);
      emit(state.copyWith(isFirstTimeUser: false));
    } catch (e) {
      // Ignore error, not critical
    }
  }

  /// Clear any error message
  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  @override
  Future<void> close() {
    if (_userServiceListener != null) {
      _userService.removeListener(_userServiceListener!);
    }
    return super.close();
  }
}
