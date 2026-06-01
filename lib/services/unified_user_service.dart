import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/notification_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/sync/sync_engine.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

enum UserType { guest, anonymous, google }

class UnifiedUser {
  final String uid;
  final UserType userType;
  final String username;
  final String displayName;
  final String? email;
  final String? photoURL;
  final DateTime createdAt;
  final DateTime lastSeen;
  final bool isPublic;

  // Game Data
  final int highScore;
  final int totalGamesPlayed;
  final int totalScore;
  final int level;

  // Preferences
  final Map<String, dynamic> preferences;

  const UnifiedUser({
    required this.uid,
    required this.userType,
    required this.username,
    required this.displayName,
    this.email,
    this.photoURL,
    required this.createdAt,
    required this.lastSeen,
    this.isPublic = true,
    this.highScore = 0,
    this.totalGamesPlayed = 0,
    this.totalScore = 0,
    this.level = 1,
    this.preferences = const {},
  });

  /// True when the account has no identifiable credential. Purchases are
  /// gated on this — anonymous users must link a Google or email/password
  /// credential via the account-upgrade sheet before they can buy.
  bool get isAnonymous =>
      userType == UserType.anonymous || userType == UserType.guest;

  UnifiedUser copyWith({
    String? uid,
    UserType? userType,
    String? username,
    String? displayName,
    String? email,
    String? photoURL,
    DateTime? createdAt,
    DateTime? lastSeen,
    bool? isPublic,
    int? highScore,
    int? totalGamesPlayed,
    int? totalScore,
    int? level,
    Map<String, dynamic>? preferences,
  }) {
    return UnifiedUser(
      uid: uid ?? this.uid,
      userType: userType ?? this.userType,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoURL: photoURL ?? this.photoURL,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
      isPublic: isPublic ?? this.isPublic,
      highScore: highScore ?? this.highScore,
      totalGamesPlayed: totalGamesPlayed ?? this.totalGamesPlayed,
      totalScore: totalScore ?? this.totalScore,
      level: level ?? this.level,
      preferences: preferences ?? this.preferences,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'userType': userType.name,
      'username': username,
      'displayName': displayName,
      'email': email,
      'photoURL': photoURL,
      'createdAt': createdAt.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
      'isPublic': isPublic,
      'highScore': highScore,
      'totalGamesPlayed': totalGamesPlayed,
      'totalScore': totalScore,
      'level': level,
      'preferences': preferences,
    };
  }

  static UnifiedUser fromJson(Map<String, dynamic> data) {
    return UnifiedUser(
      uid: data['uid'] ?? data['id']?.toString() ?? '',
      userType: _parseUserType(data),
      username: data['username'] ?? '',
      displayName: data['displayName'] ?? data['display_name'] ?? '',
      email: data['email'],
      photoURL: data['photoURL'] ?? data['photo_url'],
      createdAt: _parseDateTime(
        data['createdAt'] ?? data['created_at'] ?? data['joined_date'],
      ),
      lastSeen: _parseDateTime(data['lastSeen'] ?? data['last_seen']),
      isPublic: data['isPublic'] ?? data['is_public'] ?? true,
      highScore: data['highScore'] ?? data['high_score'] ?? 0,
      totalGamesPlayed:
          data['totalGamesPlayed'] ?? data['total_games_played'] ?? 0,
      totalScore: data['totalScore'] ?? data['total_score'] ?? 0,
      level: data['level'] ?? 1,
      preferences: Map<String, dynamic>.from(data['preferences'] ?? {}),
    );
  }

  /// Parse user type from backend response
  static UserType _parseUserType(Map<String, dynamic> data) {
    // Check explicit userType field first
    final userType = data['userType'] ?? data['user_type'];
    if (userType != null) {
      return UserType.values.firstWhere(
        (type) => type.name == userType,
        orElse: () => UserType.anonymous,
      );
    }

    // Otherwise, derive from auth_provider/is_anonymous (backend format)
    final authProvider = data['auth_provider'] ?? data['authProvider'];
    final isAnonymous = data['is_anonymous'] ?? data['isAnonymous'];

    // If explicitly marked as anonymous
    if (isAnonymous == true) {
      return UserType.anonymous;
    }

    // If auth provider is google
    if (authProvider == 'google') {
      return UserType.google;
    }

    // If explicitly marked as not anonymous (i.e. is_anonymous == false),
    // the user is a Google user since that's the only non-anonymous option
    if (isAnonymous == false) {
      return UserType.google;
    }

    // Default to anonymous for unknown cases
    return UserType.anonymous;
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }
}

class UnifiedUserService extends ChangeNotifier {
  static final UnifiedUserService _instance = UnifiedUserService._internal();
  factory UnifiedUserService() => _instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final ApiService _apiService = ApiService();

  // Storage keys for offline session persistence
  static const String _cachedUserKey = 'cached_unified_user';

  UnifiedUserService._internal() {
    // Initialize Google Sign-In with client ID
    _googleSignIn.initialize(
      serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'],
    );
  }

  SharedPreferences? _prefs;
  UnifiedUser? _currentUser;
  StreamSubscription<User?>? _authSubscription;
  bool _isInitialized = false;
  bool _isLoadingUser = false; // Prevents concurrent user loading
  String? _loadingUserId; // Track which user is being loaded
  /// Future of the currently-running _loadOrCreateUser, or null when idle.
  /// Concurrent callers (auth state listener + signInWithGoogle's explicit
  /// await) coalesce onto this future so they both block until the SAME
  /// in-flight load finishes — including maybeRunFirstSignInPull. Without
  /// this, the second caller hits the dedup guard, `return`s immediately,
  /// and signInWithGoogle reports success before the cloud restore has
  /// even started — so router navigates to home BEFORE the overlay shows.
  Future<void>? _loadingFuture;
  bool _isInitializing = false; // Prevents auth listener from duplicating work during initialize()

  /// True if the most recent `_loadOrCreateUser` call corresponded to a
  /// brand-new backend account (backend's AuthResponse.IsNewUser=true).
  /// Consumed by the first-time-username flow to decide whether to show
  /// the username-setup screen. Reset to false on every consumption via
  /// [consumeJustLoadedNewUser].
  bool _justLoadedNewUser = false;

  /// Read-and-clear the new-user flag. The caller (AuthCubit after
  /// signInWithGoogle/signInAnonymously) gets exactly one chance to see
  /// it true; subsequent reads return false.
  bool consumeJustLoadedNewUser() {
    final v = _justLoadedNewUser;
    _justLoadedNewUser = false;
    return v;
  }

  // Getters
  UnifiedUser? get currentUser => _currentUser;
  bool get isInitialized => _isInitialized;
  bool get isSignedIn => _currentUser != null;
  bool get isAnonymous => _currentUser?.userType == UserType.anonymous;
  bool get isGuestUser => _currentUser?.userType == UserType.guest;
  bool get isGoogleUser => _currentUser?.userType == UserType.google;

  String get displayName => _currentUser?.displayName ?? 'Player';
  String get username => _currentUser?.username ?? 'Guest';
  String? get photoURL => _currentUser?.photoURL;
  int get highScore => _currentUser?.highScore ?? 0;

  Future<void> initialize() async {
    try {
      AppLogger.user('STARTING UnifiedUserService initialization...');

      if (_isInitialized) {
        AppLogger.user('Already initialized');
        return;
      }

      AppLogger.user('Getting SharedPreferences...');
      _prefs = await SharedPreferences.getInstance();
      AppLogger.success('SharedPreferences obtained');

      // Initialize API service
      await _apiService.initialize();

      // Start listening to auth state changes
      AppLogger.user('Setting up auth state listener...');
      _authSubscription = _auth.authStateChanges().listen(
        _handleAuthStateChange,
      );
      AppLogger.success('Auth state listener set up');

      // Check if user is already signed in
      final currentFirebaseUser = _auth.currentUser;
      AppLogger.user(
        'Current Firebase user: ${currentFirebaseUser?.uid ?? "null"}',
      );

      if (currentFirebaseUser != null) {
        AppLogger.user('Found existing user: ${currentFirebaseUser.uid}');
        _isInitializing = true;
        try {
          await _loadOrCreateUser(currentFirebaseUser);
        } finally {
          _isInitializing = false;
        }
      } else {
        // No Firebase user — try cached session first, otherwise fall back
        // to a purely-local offline guest so the privacy/login screen has
        // something to render against.
        //
        // IMPORTANT: do NOT eagerly fire Firebase anonymous sign-in here.
        // Anonymous Firebase auth is reserved for the explicit "Continue
        // as Guest" tap on first_time_auth_screen.dart, which calls
        // authCubit.signInAnonymously() with user intent. Auto-firing it
        // on every cold start created an orphan backend user every time
        // someone reinstalled and never clicked anything — exactly the
        // pattern the prune-orphan-anonymous-users job has to clean up.
        // The offline guest below is purely local (no Firebase, no
        // backend) so it costs nothing to keep around.
        final cachedUser = await _loadCachedUserSession();
        if (cachedUser != null) {
          AppLogger.user('Using cached user session (no Firebase auth)');
          _currentUser = cachedUser;
          _isInitialized = true; // Mark initialized with cached user
          notifyListeners();
        } else {
          AppLogger.user('No cache found, creating offline guest user immediately');
          _currentUser = await _createOfflineGuestUser();
          await _cacheUserSession(_currentUser!);
          _isInitialized = true; // Mark initialized with offline guest
          notifyListeners();
        }
      }

      _isInitialized = true;
      AppLogger.success(
        'UnifiedUserService initialization complete. Current user: ${_currentUser?.username}',
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'UnifiedUserService initialization failed',
        e,
        stackTrace,
      );

      // Last resort: try cached user
      try {
        final cachedUser = await _loadCachedUserSession();
        if (cachedUser != null) {
          _currentUser = cachedUser;
          _isInitialized = true;
          AppLogger.warning('Recovered with cached user after init failure');
          notifyListeners();
          return;
        }
      } catch (_) {}

      rethrow;
    }
  }

  Future<void> _handleAuthStateChange(User? firebaseUser) async {
    if (firebaseUser != null) {
      // Skip if initialize() is already handling the first load
      if (_isInitializing) {
        AppLogger.user(
          'Skipping auth state change during initialization for ${firebaseUser.uid}',
        );
        return;
      }
      // Skip if this user is already loaded or currently being loaded
      if (_currentUser != null && _currentUser!.uid == firebaseUser.uid) {
        return;
      }
      if (_isLoadingUser && _loadingUserId == firebaseUser.uid) {
        AppLogger.user(
          'User ${firebaseUser.uid} is already being loaded, skipping duplicate',
        );
        return;
      }
      await _loadOrCreateUser(firebaseUser);
    } else {
      _currentUser = null;
      notifyListeners();
    }
  }

  Future<void> _loadOrCreateUser(User firebaseUser) async {
    // Dedup concurrent loads of the same user by AWAITING the in-flight
    // call instead of returning immediately. Two callers race in here:
    // the Firebase auth state listener (line ~349) and signInWithGoogle's
    // explicit `await _loadOrCreateUser(...)` (line ~878). The listener
    // almost always wins by a microsecond, so the explicit caller used
    // to hit a `return;` here and signInWithGoogle would resolve before
    // the backend handoff (and especially maybeRunFirstSignInPull) had
    // run. That made AuthCubit emit authenticated and the router navigate
    // to home BEFORE the first-sign-in overlay could appear — so the
    // restore modal ended up rendering above home instead of above the
    // login screen the user came from. Awaiting the in-flight future
    // here means signInWithGoogle stays blocked until the WHOLE flow
    // (Firebase + backend + cloud restore) is complete.
    final inFlight = _loadingFuture;
    if (inFlight != null && _loadingUserId == firebaseUser.uid) {
      AppLogger.user(
        'Already loading user ${firebaseUser.uid}, awaiting in-flight',
      );
      await inFlight;
      return;
    }

    _isLoadingUser = true;
    _loadingUserId = firebaseUser.uid;
    final completer = Completer<void>();
    _loadingFuture = completer.future;

    try {
      AppLogger.user('Loading/creating user for UID: ${firebaseUser.uid}');

      // Try to get ID token - may fail if offline with expired token
      String? idToken;
      try {
        idToken = await firebaseUser.getIdToken();
      } catch (tokenError) {
        AppLogger.warning(
          'Failed to get ID token (may be offline): $tokenError',
        );
        // Continue without token - we'll try cached data
      }

      if (idToken != null) {
        // Online path - authenticate with backend
        final authResult = await _apiService.authenticateWithFirebase(idToken);

        if (authResult != null) {
          AppLogger.success('Backend authentication successful');

          // Capture the IsNewUser flag for the first-time username flow.
          // The auth response is snake-cased server-side; accept both
          // shapes for forward compatibility.
          _justLoadedNewUser =
              (authResult['is_new_user'] ?? authResult['isNewUser']) == true;

          // Load user profile from backend
          final userProfile = await _apiService.getCurrentUser();
          if (userProfile != null) {
            _currentUser = UnifiedUser.fromJson(userProfile);
            // Cache the session for offline use
            await _cacheUserSession(_currentUser!);
            AppLogger.success(
              'User loaded from backend: ${_currentUser?.username}',
            );

            // Kick off the first-sign-in cloud pull. Two guards:
            //
            // 1. Skip anonymous Firebase users. Each anonymous
            //    sign-in mints a fresh uid, so the backend always
            //    treats them as is_new_user=true. If we let that
            //    set the `has_ever_signed_in` flag, a subsequent
            //    real Google/email sign-in would short-circuit with
            //    "alreadyDone" and never restore the user's actual
            //    cloud data. Anonymous accounts have no cross-
            //    install persistence anyway — there's nothing to
            //    restore.
            //
            // 2. The engine uses [isNewUser] to disambiguate "no
            //    cloud data exists yet" vs "transient pull failure
            //    that should retry next launch".
            //
            // Awaited so the SyncRestoreOverlay (inserted by SyncEngine
            // into the root navigator's Overlay during the pull/apply
            // states) stays visible above whatever route is active
            // until restore finishes. Otherwise the user could land on
            // home with empty defaults before the snapshot arrives.
            final backendUserId = _apiService.currentUserId;
            final isAnonFirebaseUser = firebaseUser.isAnonymous;
            if (backendUserId != null && !isAnonFirebaseUser) {
              try {
                final result = await GetIt.I<SyncEngine>()
                    .maybeRunFirstSignInPull(
                  userId: backendUserId,
                  isNewUser: _justLoadedNewUser,
                );
                AppLogger.network(
                  'First-sign-in pull result: ${result.name}',
                );
                // If we just restored from cloud, re-load the user
                // profile so the in-memory _currentUser reflects
                // any restored fields (high score, coins, …).
                if (result == FirstSignInResult.restored) {
                  final refreshed = await _apiService.getCurrentUser();
                  if (refreshed != null) {
                    _currentUser = UnifiedUser.fromJson(refreshed);
                    await _cacheUserSession(_currentUser!);
                  }
                }
              } catch (e) {
                AppLogger.error(
                  'First-sign-in pull errored, continuing with local data',
                  e,
                );
                // Even on an unexpected throw, arm the drain loop so
                // this session can still sync. The pull-failed branches
                // inside SyncEngine already do this, but a defensive
                // catch out here covers any path that bypasses them.
                GetIt.I<SyncEngine>().markFirstSignInSkipped();
              }
            } else if (isAnonFirebaseUser) {
              AppLogger.network(
                'Skipping first-sign-in pull for anonymous Firebase user '
                '(no cross-install persistence to restore)',
              );
              // Anonymous users skip restore but still need the drain
              // loop armed so any local-side syncable state (a +50
              // starting bonus enqueued during cubit init, settings
              // changes, etc.) ships to the backend.
              GetIt.I<SyncEngine>().markFirstSignInSkipped();
            } else if (backendUserId == null) {
              AppLogger.warning(
                'Skipping first-sign-in pull — backend never returned '
                'a user id. Arming drain loop anyway so this session '
                "isn't completely silent on sync.",
              );
              GetIt.I<SyncEngine>().markFirstSignInSkipped();
            }
          } else {
            // /auth/me returned null — backend was reachable for the
            // token verify but not for the profile fetch (transient).
            // Prefer the cached user over a fresh-from-Firebase rebuild
            // so we don't lose offline-accurate fields (highScore, etc).
            await _restoreFromCacheOrCreate(firebaseUser,
                reason: '/auth/me unreachable');
          }
        } else {
          // Backend auth failed entirely. This is the common offline path
          // when Firebase still has a cached ID token (so we entered the
          // online branch) but our backend is unreachable. Before this
          // fix we'd call _createUserFromFirebase here, which rebuilds
          // _currentUser from `guest_user_data` SharedPreferences (often
          // 0 or stale) and CACHES that — wiping a previously-correct
          // cached UnifiedUser. The user then sees their high score drop
          // to 0/stale offline. Restore from cache when possible instead.
          await _restoreFromCacheOrCreate(firebaseUser,
              reason: 'backend auth failed (likely offline)');
        }
      } else {
        // Offline path - try to load cached session
        final cachedUser = await _loadCachedUserSession();
        if (cachedUser != null && cachedUser.uid == firebaseUser.uid) {
          _currentUser = cachedUser;
          AppLogger.success(
            'Restored user from cache (offline): ${_currentUser?.username}',
          );
        } else {
          // No matching cache, create minimal local user
          _currentUser = await _createUserFromFirebase(firebaseUser);
          await _cacheUserSession(_currentUser!);
        }
      }

      notifyListeners();

      // Initialize notification backend integration after user is loaded
      _initializeNotificationIntegration();
    } catch (e, stackTrace) {
      AppLogger.user('Error loading/creating user', e, stackTrace);

      // Fallback: try to restore from cache
      final cachedUser = await _loadCachedUserSession();
      if (cachedUser != null) {
        _currentUser = cachedUser;
        AppLogger.warning('Restored user from cache after error');
        notifyListeners();
      }
    } finally {
      _isLoadingUser = false;
      _loadingUserId = null;
      _loadingFuture = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Backend-unreachable fallback inside the "online" branch of
  /// _loadOrCreateUser. Prefers a matching cached UnifiedUser (preserves
  /// highScore, gamesPlayed, level, etc. from the last good fetch) over a
  /// blank rebuild via _createUserFromFirebase (which seeds from stale
  /// guest_user_data and clobbers the cache). Falls through to the rebuild
  /// only when there's no usable cache.
  Future<void> _restoreFromCacheOrCreate(
    User firebaseUser, {
    required String reason,
  }) async {
    final cachedUser = await _loadCachedUserSession();
    if (cachedUser != null && cachedUser.uid == firebaseUser.uid) {
      _currentUser = cachedUser;
      AppLogger.user(
        'Restored cached user (reason: $reason): highScore=${_currentUser?.highScore}',
      );
      return;
    }
    _currentUser = await _createUserFromFirebase(firebaseUser);
    await _cacheUserSession(_currentUser!);
    AppLogger.user(
      'No usable cache (reason: $reason); created fresh user from Firebase',
    );
  }

  Future<UnifiedUser> _createUserFromFirebase(User firebaseUser) async {
    // Determine user type
    UserType userType = UserType.anonymous;
    if (firebaseUser.providerData.any(
      (provider) => provider.providerId == 'google.com',
    )) {
      userType = UserType.google;
    }

    // Generate unique username
    final username = await _generateUniqueUsername();

    // Get default preferences
    final preferences = await _getDefaultPreferences();

    // Check if we have local guest data to migrate
    final guestData = await _getLocalGuestData();

    return UnifiedUser(
      uid: firebaseUser.uid,
      userType: userType,
      username: username,
      displayName: firebaseUser.displayName ?? username,
      email: firebaseUser.email,
      photoURL: firebaseUser.photoURL,
      createdAt: DateTime.now(),
      lastSeen: DateTime.now(),
      highScore: guestData['highScore'] ?? 0,
      totalGamesPlayed: guestData['totalGamesPlayed'] ?? 0,
      totalScore: guestData['totalScore'] ?? 0,
      level: guestData['level'] ?? 1,
      preferences: preferences,
    );
  }

  Future<String> _generateUniqueUsername() async {
    final adjectives = [
      'Swift',
      'Quick',
      'Fast',
      'Sneaky',
      'Sharp',
      'Cool',
      'Epic',
      'Super',
      'Mega',
      'Ultra',
      'Pro',
      'Elite',
      'Master',
      'Ace',
      'Clever',
      'Smart',
      'Brave',
      'Bold',
      'Wild',
      'Fierce',
      'Mighty',
      'Strong',
      'Agile',
      'Smooth',
      'Silent',
      'Shadow',
      'Golden',
      'Silver',
      'Diamond',
      'Ruby',
      'Fire',
      'Ice',
    ];

    final nouns = [
      'Snake',
      'Viper',
      'Python',
      'Cobra',
      'Serpent',
      'Player',
      'Gamer',
      'Champion',
      'Hunter',
      'Racer',
      'Striker',
      'Warrior',
      'Hero',
      'Legend',
      'Dragon',
      'Phoenix',
      'Eagle',
      'Hawk',
      'Wolf',
      'Tiger',
      'Lion',
      'Bear',
      'Fox',
      'Shark',
      'Panther',
      'Falcon',
      'Raven',
      'Knight',
      'Ninja',
      'Samurai',
    ];

    final random = Random();
    final adjective = adjectives[random.nextInt(adjectives.length)];
    final noun = nouns[random.nextInt(nouns.length)];
    final number = random.nextInt(9999) + 1;

    return '${adjective}_${noun}_$number';
  }

  Future<Map<String, dynamic>> _getDefaultPreferences() async {
    return {
      'theme': 'classic',
      'soundEnabled': true,
      'musicEnabled': true,
      'trailSystemEnabled': false,
      'boardSize': {'width': 20, 'height': 20, 'name': 'Classic'},
    };
  }

  Future<Map<String, dynamic>> _getLocalGuestData() async {
    if (_prefs == null) return {};

    try {
      final guestDataJson = _prefs!.getString('guest_user_data');
      if (guestDataJson != null) {
        final data = jsonDecode(guestDataJson);
        return {
          'highScore': data['highScore'] ?? 0,
          'totalGamesPlayed': data['totalGamesPlayed'] ?? 0,
          'totalScore': data['totalScore'] ?? 0,
          'level': 1,
        };
      }
    } catch (e) {
      AppLogger.storage('Error loading local guest data', e);
    }

    return {};
  }

  // ignore: unused_element - May be useful later for guest data migration
  Future<void> _clearLocalGuestData() async {
    if (_prefs == null) return;

    await _prefs!.remove('guest_user_data');
    await _prefs!.remove('has_initialized_guest');
  }

  /// Save user session to local storage for offline access
  Future<void> _cacheUserSession(UnifiedUser user) async {
    if (_prefs == null) return;
    try {
      await _prefs!.setString(_cachedUserKey, jsonEncode(user.toJson()));
      AppLogger.user('Cached user session for offline use');
    } catch (e) {
      AppLogger.error('Failed to cache user session', e);
    }
  }

  /// Load cached user session from local storage.
  /// Bumps the highScore field to max(cached, localDb) before returning so
  /// the offline auth state can't be stale relative to disk — the local
  /// Drift settings table is monotonic (never-decrease guard in
  /// StorageService.saveHighScore) and gets updated by both local plays
  /// and cloud syncs, so it's never lower than what we should display.
  /// Without this, a stale cached UnifiedUser persists across app launches
  /// and the home screen's max(authState, settings) workaround can't paper
  /// over the gap when settings is also stale.
  Future<UnifiedUser?> _loadCachedUserSession() async {
    if (_prefs == null) return null;
    try {
      final cachedJson = _prefs!.getString(_cachedUserKey);
      if (cachedJson != null) {
        final userData = jsonDecode(cachedJson) as Map<String, dynamic>;
        AppLogger.user('Loaded cached user session');
        var user = UnifiedUser.fromJson(userData);
        try {
          final dbHighScore = await StorageService().getHighScore();
          if (dbHighScore > user.highScore) {
            AppLogger.user(
              'Cached user highScore=${user.highScore} < DB highScore=$dbHighScore, bumping cached user',
            );
            user = user.copyWith(highScore: dbHighScore);
          }
        } catch (e) {
          AppLogger.user('Failed to enrich cached user with DB highScore', e);
        }
        return user;
      }
    } catch (e) {
      AppLogger.error('Failed to load cached user session', e);
    }
    return null;
  }

  /// Clear cached user session
  Future<void> _clearCachedUserSession() async {
    if (_prefs == null) return;
    await _prefs!.remove(_cachedUserKey);
  }

  /// Create a purely offline guest user (no Firebase auth required)
  Future<UnifiedUser> _createOfflineGuestUser() async {
    AppLogger.user('Creating offline guest user...');

    // Generate a local ID for offline guest
    final offlineId =
        'offline_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
    final username = await _generateUniqueUsername();

    // Try to get data from local guest data if available
    final guestData = await _getLocalGuestData();

    return UnifiedUser(
      uid: offlineId,
      userType: UserType.guest,
      username: username,
      displayName: username,
      createdAt: DateTime.now(),
      lastSeen: DateTime.now(),
      highScore: guestData['highScore'] ?? 0,
      totalGamesPlayed: guestData['totalGamesPlayed'] ?? 0,
      totalScore: guestData['totalScore'] ?? 0,
      level: guestData['level'] ?? 1,
      preferences: await _getDefaultPreferences(),
    );
  }

  // Public methods

  Future<bool> _signInAnonymously() async {
    try {
      AppLogger.firebase('Attempting anonymous sign-in...');

      final result = await _auth.signInAnonymously();

      AppLogger.success('Anonymous sign-in successful: ${result.user?.uid}');

      // Directly await the backend handoff instead of relying on the
      // authStateChanges listener — the listener fires in a microtask
      // that races against the caller's routing decision (AuthCubit
      // consumes _justLoadedNewUser the instant we return, and the FE
      // routing decision happens right after). Awaiting here means the
      // backend response — including is_new_user and the real username
      // — is fully landed by the time we hand back control. The dedup
      // guard in _loadOrCreateUser (line 344-347) makes this safe even
      // when the listener fires too.
      if (result.user != null) {
        await _loadOrCreateUser(result.user!);
      }

      return true;
    } catch (e, stackTrace) {
      AppLogger.firebase('Error signing in anonymously', e, stackTrace);

      // If we can't sign in anonymously (likely offline),
      // try to restore a cached session or create an offline guest
      final cachedUser = await _loadCachedUserSession();
      if (cachedUser != null) {
        _currentUser = cachedUser;
        AppLogger.warning(
          'Restored cached user after anonymous sign-in failed',
        );
        notifyListeners();
        return true;
      }

      // Create a purely offline guest user
      _currentUser = await _createOfflineGuestUser();
      await _cacheUserSession(_currentUser!);
      AppLogger.warning('Created offline guest user');
      notifyListeners();
      return true;
    }
  }

  Future<bool> signInWithGoogle() async {
    try {
      AppLogger.user('Starting Google Sign-In from UnifiedUserService...');

      // Check if authentication is supported on this platform
      if (_googleSignIn.supportsAuthenticate()) {
        // Use authenticate method for supported platforms
        final GoogleSignInAccount googleUser = await _googleSignIn
            .authenticate();

        AppLogger.user('Google user signed in: ${googleUser.email}');

        // Obtain the auth details from the request
        final GoogleSignInAuthentication googleAuth = googleUser.authentication;

        if (googleAuth.idToken == null) {
          AppLogger.user('Failed to get Google ID token');
          return false;
        }

        // Create a new credential
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        AppLogger.user('Creating Firebase credential...');

        // Sign in to Firebase with the credential
        final UserCredential result = await _auth.signInWithCredential(
          credential,
        );

        if (result.user != null) {
          AppLogger.success('Firebase sign-in successful: ${result.user!.uid}');

          // Directly await the backend handoff. Previously this returned
          // immediately and relied on the authStateChanges listener to
          // call _loadOrCreateUser — but the listener fires in a microtask
          // that races against the AuthCubit consumption of
          // _justLoadedNewUser and the FE routing decision. Awaiting here
          // means by the time we return, _justLoadedNewUser, _currentUser,
          // and the cubit state all reflect authoritative backend data.
          // The dedup guard in _loadOrCreateUser (line 344-347) prevents
          // double-loading when the listener still fires.
          await _loadOrCreateUser(result.user!);

          return true;
        }

        return false;
      } else {
        AppLogger.user(
          'Google Sign-In authenticate not supported on this platform',
        );
        return false;
      }
    } on FirebaseAuthException catch (e) {
      AppLogger.user(
        'Firebase Auth error during Google Sign-In: ${e.code} - ${e.message}',
      );
      return false;
    } catch (e, stackTrace) {
      AppLogger.user('Error signing in with Google', e, stackTrace);
      return false;
    }
  }

  /// Public wrapper for anonymous sign-in
  Future<bool> signInAnonymously() async {
    return _signInAnonymously();
  }

  /// Sign in with an existing email/password account.
  Future<bool> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.user('Email sign-in: $email');
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (result.user != null) {
        AppLogger.success('Email sign-in OK: ${result.user!.uid}');
        await _loadOrCreateUser(result.user!);
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      AppLogger.user('Error signing in with email/password', e, stackTrace);
      rethrow;
    }
  }

  /// Create a new email/password account.
  Future<bool> createAccountWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.user('Creating email/password account: $email');
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (result.user != null) {
        AppLogger.success('Email account created: ${result.user!.uid}');
        try {
          await result.user!.sendEmailVerification();
        } catch (e) {
          AppLogger.user('Failed to send verification email (non-fatal)', e);
        }
        await _loadOrCreateUser(result.user!);
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      AppLogger.user('Error creating email/password account', e, stackTrace);
      rethrow;
    }
  }

  /// Promote the current anonymous account to email/password. Firebase
  /// keeps the same UID, so the backend user record (progress, coins,
  /// cosmetics) is preserved — the next /auth/firebase call updates
  /// AuthProvider/Email/IsAnonymous on the existing row.
  Future<bool> linkAnonymousToEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null || !user.isAnonymous) {
        AppLogger.user('linkAnonymousToEmailPassword called without anon user');
        return false;
      }
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      final result = await user.linkWithCredential(credential);
      AppLogger.success('Linked anon → email: ${result.user?.uid}');
      try {
        await result.user?.sendEmailVerification();
      } catch (e) {
        AppLogger.user('Failed to send verification email after link', e);
      }
      if (result.user != null) {
        await _loadOrCreateUser(result.user!);
      }
      return true;
    } catch (e, stackTrace) {
      AppLogger.user('Error linking anon → email', e, stackTrace);
      rethrow;
    }
  }

  /// Promote the current anonymous account to a Google sign-in.
  Future<bool> linkAnonymousToGoogle() async {
    try {
      final user = _auth.currentUser;
      if (user == null || !user.isAnonymous) {
        AppLogger.user('linkAnonymousToGoogle called without anon user');
        return false;
      }
      if (!_googleSignIn.supportsAuthenticate()) {
        AppLogger.user('Google sign-in unsupported on this platform');
        return false;
      }
      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      if (googleAuth.idToken == null) {
        AppLogger.user('Failed to obtain Google ID token');
        return false;
      }
      final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
      final result = await user.linkWithCredential(credential);
      AppLogger.success('Linked anon → Google: ${result.user?.uid}');
      if (result.user != null) {
        await _loadOrCreateUser(result.user!);
      }
      return true;
    } catch (e, stackTrace) {
      AppLogger.user('Error linking anon → Google', e, stackTrace);
      rethrow;
    }
  }

  /// Best-effort password reset. Errors bubble up.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<bool> updateUsername(String newUsername) async {
    if (_currentUser == null) return false;

    try {
      // Update via backend API
      final result = await _apiService.setUsername(newUsername);
      if (result == null) return false;

      // Update local user
      _currentUser = _currentUser!.copyWith(username: newUsername);

      notifyListeners();
      return true;
    } catch (e, stackTrace) {
      AppLogger.user('Error updating username', e, stackTrace);
      return false;
    }
  }

  /// Update username for guest users (local only)
  Future<bool> updateGuestUsername(String newUsername) async {
    if (_currentUser == null) return false;
    if (_currentUser!.userType != UserType.guest &&
        _currentUser!.userType != UserType.anonymous) {
      return false;
    }

    try {
      _currentUser = _currentUser!.copyWith(
        username: newUsername,
        displayName: newUsername,
      );
      await _cacheUserSession(_currentUser!);
      notifyListeners();
      return true;
    } catch (e, stackTrace) {
      AppLogger.user('Error updating guest username', e, stackTrace);
      return false;
    }
  }

  /// Pull the latest user profile from the backend and overlay it onto
  /// the local `_currentUser`. Useful when the cached UnifiedUser is
  /// known to be stale — e.g. right after the backend backfilled a
  /// previously-NULL username, or after any server-side admin edit.
  /// No-op for guest users (no backend identity).
  Future<bool> refreshFromBackend() async {
    if (_currentUser == null) return false;
    if (_currentUser!.userType == UserType.guest) return false;
    if (!_apiService.isAuthenticated) return false;

    try {
      final fresh = await _apiService.getCurrentUser();
      if (fresh == null) return false;

      // Update the in-memory user with the freshly-fetched fields. Keep
      // the local userType (Firebase/auth provider) since the backend
      // doesn't return it in a form we map; everything else is overlay.
      //
      // High score / cumulative-aggregate fields use max(server, local) so
      // a stale server response can't regress local data. This matters when
      // an offline-earned high score has been recorded locally but the
      // score-submit queue hasn't drained to the server yet — without the
      // max guard, refreshFromBackend would clobber the fresh local high
      // score with the older server value until the next score-submit
      // brought them back in sync.
      final serverHighScore = (fresh['high_score'] ?? fresh['highScore'] ?? 0) as int;
      final serverGames = (fresh['total_games_played'] ?? fresh['totalGamesPlayed'] ?? 0) as int;
      final serverTotal = (fresh['total_score'] ?? fresh['totalScore'] ?? 0) as int;

      _currentUser = _currentUser!.copyWith(
        username: fresh['username'] ?? _currentUser!.username,
        displayName: fresh['display_name'] ?? fresh['displayName'] ?? _currentUser!.displayName,
        photoURL: fresh['photo_url'] ?? fresh['photoURL'] ?? _currentUser!.photoURL,
        email: fresh['email'] ?? _currentUser!.email,
        highScore: max(serverHighScore, _currentUser!.highScore),
        totalGamesPlayed: max(serverGames, _currentUser!.totalGamesPlayed),
        totalScore: max(serverTotal, _currentUser!.totalScore),
        level: fresh['level'] ?? _currentUser!.level,
      );
      await _cacheUserSession(_currentUser!);
      notifyListeners();
      return true;
    } catch (e, stackTrace) {
      AppLogger.user('Error refreshing user from backend', e, stackTrace);
      return false;
    }
  }

  /// Update username for authenticated users (via backend)
  Future<bool> updateAuthenticatedUsername(String newUsername) async {
    if (_currentUser == null) return false;
    if (_currentUser!.userType != UserType.google) {
      return false;
    }

    return updateUsername(newUsername);
  }

  Future<void> updateGameStats({
    int? newHighScore,
    int? gamesPlayed,
    int? totalScore,
    int? level,
  }) async {
    if (_currentUser == null) return;

    // High score is strictly monotonic — only accept upward moves.
    final updatedHighScore = newHighScore != null
        ? max(newHighScore, _currentUser!.highScore)
        : _currentUser!.highScore;

    _currentUser = _currentUser!.copyWith(
      highScore: updatedHighScore,
      totalGamesPlayed: (_currentUser!.totalGamesPlayed + (gamesPlayed ?? 0)),
      totalScore: (_currentUser!.totalScore + (totalScore ?? 0)),
      level: level ?? _currentUser!.level,
    );

    // Update via backend API. high_score is omitted intentionally — the
    // backend's UpdateProfileCommand DTO doesn't accept it (it's mutated
    // server-side only via SubmitScoreCommandHandler's GREATEST clause),
    // so sending it was a no-op that risked confusing future maintainers.
    if (_apiService.isAuthenticated) {
      await _apiService.updateProfile({
        'total_games_played': _currentUser!.totalGamesPlayed,
        'total_score': _currentUser!.totalScore,
        'level': _currentUser!.level,
      });
    }

    notifyListeners();
  }

  Future<void> updatePreferences(Map<String, dynamic> newPreferences) async {
    if (_currentUser == null) return;

    final updatedPrefs = Map<String, dynamic>.from(_currentUser!.preferences);
    updatedPrefs.addAll(newPreferences);

    _currentUser = _currentUser!.copyWith(preferences: updatedPrefs);

    // Update via backend API
    if (_apiService.isAuthenticated) {
      await _apiService.updateProfile({'preferences': updatedPrefs});
    }

    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      // Logout from backend (clears JWT). Keep going even on failure so
      // local state still gets cleared.
      try {
        await _apiService.logout();
      } catch (e) {
        AppLogger.user('Backend logout failed (continuing)', e);
      }

      // Wipe local sync state so the *next* user — whether the same
      // account on the same device or a different one — starts from a
      // clean slate. Without this:
      //   * The previous user's Drift tables (settings, stats, coins,
      //     achievements, unlocked items, battle pass, daily challenge
      //     claims, replays, sync queue) stay populated.
      //   * The `sync_engine_has_ever_signed_in` SharedPref stays true,
      //     so `maybeRunFirstSignInPull` short-circuits with
      //     `alreadyDone` for the next sign-in.
      //   * Pending outbox rows from user A drain under user B's JWT,
      //     leaking A's data onto B's backend account.
      // Best-effort — failures here don't block the rest of sign-out.
      try {
        await _wipeLocalSyncState();
      } catch (e) {
        AppLogger.user('Local sync-state wipe failed (continuing)', e);
      }

      // Sign out from Google + Firebase. The Firebase auth listener will
      // fire with firebaseUser=null and clear _currentUser; we also clear
      // it explicitly to handle the edge case where the listener is slow.
      await _googleSignIn.signOut();
      await _auth.signOut();
      _currentUser = null;

      // Clear cached session so a stale UnifiedUser doesn't get restored
      // on next launch.
      await _clearCachedUserSession();

      // Notify listeners so AuthCubit emits unauthenticated and the UI
      // can route the user to the sign-in screen. Do NOT auto-create an
      // anonymous account here — the user explicitly asked to sign out
      // and should be the one to choose how to continue (guest vs Google).
      notifyListeners();
    } catch (e) {
      AppLogger.user('Error signing out', e);
      // Even on failure, ensure local state reflects signed-out so the UI
      // can route to the sign-in screen instead of getting stuck.
      _currentUser = null;
      notifyListeners();
    }
  }

  /// Reset every device-local store that's scoped to the authenticated
  /// user, so the next sign-in (any account) runs through a clean
  /// first-sign-in flow.
  Future<void> _wipeLocalSyncState() async {
    // Drift: deletes every synced table + the outbox, then reinstalls
    // the singleton defaults so subsequent loads find a usable row.
    if (GetIt.I.isRegistered<AppDatabase>()) {
      await GetIt.I<AppDatabase>().clearAllData();
    }

    // SharedPrefs: the SyncEngine reads this to decide whether to run
    // the first-sign-in pull. Clearing forces the next sign-in through
    // the welcoming / restore flow.
    if (_prefs != null) {
      await _prefs!.remove('sync_engine_has_ever_signed_in');
    }
  }

  /// Initialize notification backend integration
  Future<void> _initializeNotificationIntegration() async {
    try {
      // Use a brief delay to ensure notification service is fully initialized
      await Future.delayed(const Duration(seconds: 1));

      // Initialize backend integration (FCM token register + topic subscribe)
      await NotificationService().initializeBackendIntegration();

      // Daily reminder scheduling lives in the backend now — the Hangfire
      // job `send-daily-reminder` evaluates each user's local 20:00 anchor
      // against their stored timezone offset and pushes via FCM. The local
      // OS scheduler isn't reliable enough for this on OEM Android (Doze,
      // Samsung alarm cap, etc.). RegisterFcmTokenCommandHandler keeps the
      // timezone offset fresh on every token register, which is the only
      // device → backend handoff we still need here.
    } catch (e) {
      AppLogger.user('Error initializing notification integration', e);
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
