import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cosmo_strike_flutter_app/services/username_service.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final UsernameService _usernameService = UsernameService();
  final ApiService _apiService = ApiService();

  AuthService._internal() {
    // Initialize Google Sign-In with client ID
    _googleSignIn.initialize(
      serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'],
    );
  }

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => currentUser != null;

  /// Check if authenticated with backend
  bool get isBackendAuthenticated => _apiService.isAuthenticated;

  /// Get backend user ID
  String? get backendUserId => _apiService.currentUserId;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    try {
      AppLogger.firebase('🔐 Starting Google Sign-In...');

      // Check if authentication is supported on this platform
      if (_googleSignIn.supportsAuthenticate()) {
        // Use authenticate method for supported platforms
        final GoogleSignInAccount googleUser = await _googleSignIn
            .authenticate();

        AppLogger.firebase('Google user signed in: ${googleUser.email}');

        // Obtain the auth details from the request
        final GoogleSignInAuthentication googleAuth = googleUser.authentication;

        if (googleAuth.idToken == null) {
          AppLogger.firebase('❌ Failed to get Google ID token');
          throw Exception('Failed to get Google ID token');
        }

        // Create a new credential
        final credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        AppLogger.firebase('Creating Firebase credential...');

        // Sign in to Firebase with the credential
        final UserCredential result = await _auth.signInWithCredential(
          credential,
        );

        if (result.user != null) {
          AppLogger.success('Firebase sign-in successful: ${result.user!.uid}');

          // Authenticate with backend using Firebase token
          // Backend handles user profile creation/update via /auth/firebase
          await _authenticateWithBackend(result.user!);
        }

        return result;
      } else {
        AppLogger.firebase(
          '❌ Google Sign-In authenticate not supported on this platform',
        );
        return null;
      }
    } on FirebaseAuthException catch (e) {
      AppLogger.firebase(
        'Firebase Auth error during Google Sign-In: ${e.code} - ${e.message}',
      );
      return null;
    } catch (e, stackTrace) {
      AppLogger.firebase('Error signing in with Google', e, stackTrace);
      return null;
    }
  }

  Future<void> signInAnonymously() async {
    try {
      final UserCredential result = await _auth.signInAnonymously();
      if (result.user != null) {
        AppLogger.firebase('Anonymous sign-in successful: ${result.user!.uid}');
        // Authenticate with backend - it handles anonymous user profile creation
        await _authenticateWithBackend(result.user!);
      }
    } catch (e) {
      AppLogger.error('Error signing in anonymously', e);
    }
  }

  /// Sign in with an existing email/password account.
  /// Returns the UserCredential on success, throws FirebaseAuthException on
  /// failure so the caller can surface a specific error (wrong-password,
  /// user-not-found, invalid-email, too-many-requests).
  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    AppLogger.firebase('Signing in with email/password: $email');
    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (result.user != null) {
      AppLogger.success('Email sign-in successful: ${result.user!.uid}');
      await _authenticateWithBackend(result.user!);
    }
    return result;
  }

  /// Create a brand-new email/password account. Best-effort sends the
  /// verification email; failures there are non-fatal (the user can request
  /// another from inside the app).
  Future<UserCredential> createAccountWithEmailPassword({
    required String email,
    required String password,
  }) async {
    AppLogger.firebase('Creating email/password account: $email');
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (result.user != null) {
      AppLogger.success('Email account created: ${result.user!.uid}');
      try {
        await result.user!.sendEmailVerification();
      } catch (e) {
        AppLogger.firebase('Failed to send verification email (non-fatal)', e);
      }
      await _authenticateWithBackend(result.user!);
    }
    return result;
  }

  /// Promote the current anonymous user to an email/password account.
  /// Preserves the Firebase UID, so the backend record (game progress,
  /// coins, cosmetics) stays attached.
  Future<UserCredential> linkAnonymousToEmailPassword({
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in user to link.',
      );
    }
    if (!user.isAnonymous) {
      throw FirebaseAuthException(
        code: 'not-anonymous',
        message: 'Current account is not anonymous.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    final result = await user.linkWithCredential(credential);
    AppLogger.success('Linked anonymous account to email: ${result.user?.uid}');
    try {
      await result.user?.sendEmailVerification();
    } catch (e) {
      AppLogger.firebase('Failed to send verification email after link (non-fatal)', e);
    }
    if (result.user != null) {
      await _authenticateWithBackend(result.user!);
    }
    return result;
  }

  /// Promote the current anonymous user to a Google-signed account.
  Future<UserCredential> linkAnonymousToGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in user to link.',
      );
    }
    if (!user.isAnonymous) {
      throw FirebaseAuthException(
        code: 'not-anonymous',
        message: 'Current account is not anonymous.',
      );
    }
    if (!_googleSignIn.supportsAuthenticate()) {
      throw FirebaseAuthException(
        code: 'unsupported-platform',
        message: 'Google Sign-In not supported on this platform.',
      );
    }
    final googleUser = await _googleSignIn.authenticate();
    final googleAuth = googleUser.authentication;
    if (googleAuth.idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Failed to obtain Google ID token.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
    final result = await user.linkWithCredential(credential);
    AppLogger.success('Linked anonymous account to Google: ${result.user?.uid}');
    if (result.user != null) {
      await _authenticateWithBackend(result.user!);
    }
    return result;
  }

  /// Send a password-reset email. Errors propagate so the UI can show
  /// "no account found" vs. "rate-limited" messages.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
    AppLogger.firebase('Password reset email sent to $email');
  }

  Future<void> signOut() async {
    try {
      // Logout from backend first
      await _apiService.logout();

      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      // Error signing out
    }
  }

  /// Authenticate with backend using Firebase ID token
  Future<bool> _authenticateWithBackend(User user) async {
    try {
      // Get Firebase ID token
      final idToken = await user.getIdToken();
      if (idToken == null) {
        AppLogger.error('Failed to get Firebase ID token');
        return false;
      }

      // Authenticate with backend
      final result = await _apiService.authenticateWithFirebase(idToken);
      if (result != null) {
        AppLogger.success('Backend authentication successful');
        return true;
      }

      AppLogger.error('Backend authentication failed');
      return false;
    } catch (e) {
      AppLogger.error('Error authenticating with backend', e);
      return false;
    }
  }

  /// Ensure user is authenticated with backend (call on app startup / resume).
  /// Uses local JWT expiry check to avoid unnecessary GET /auth/me calls.
  Future<bool> ensureBackendAuthentication() async {
    if (!isSignedIn) return false;

    // If we have a token and it's not expired, skip the network call
    if (_apiService.isAuthenticated && !_apiService.isTokenExpiredOrExpiring) {
      return true;
    }

    // Token is missing or expired — need to re-authenticate
    return await _authenticateWithBackend(currentUser!);
  }

  /// Initialize API service (call on app startup)
  Future<void> initializeApiService() async {
    await _apiService.initialize();
  }

  /// Get user profile from backend API
  Future<Map<String, dynamic>?> getUserProfile() async {
    if (currentUser == null) return null;

    try {
      return await _apiService.getCurrentUser();
    } catch (e) {
      AppLogger.error('Error getting user profile', e);
      return null;
    }
  }

  /// Update user profile via backend API
  Future<void> updateUserProfile(Map<String, dynamic> data) async {
    if (currentUser == null) return;

    try {
      await _apiService.updateProfile(data);
    } catch (e) {
      AppLogger.error('Error updating user profile', e);
    }
  }

  /// No-op in the offline-first build. Score persistence is handled
  /// locally by GameCubit → StatisticsService → Drift; nothing is
  /// posted to the backend anymore. Kept as a method so existing
  /// callers (legacy game-over hooks) compile without change.
  Future<void> updateHighScore(
    int score, {
    int gameDuration = 0,
    int foodsEaten = 0,
  }) async {}

  // Username management methods

  Future<bool> updateUsername(String newUsername) async {
    if (currentUser == null) return false;

    final result = await _usernameService.updateUsername(
      currentUser!.uid,
      newUsername,
    );
    return result.success;
  }

  Future<UsernameValidationResult> validateUsername(String username) async {
    return await _usernameService.validateUsernameComplete(username);
  }

  List<String> generateUsernameSuggestions() {
    return _usernameService.generateUsernameSuggestions();
  }

  Future<List<Map<String, dynamic>>> searchUsersByUsername(String query) async {
    return await _usernameService.searchUsersByUsername(query);
  }
}
