import 'package:equatable/equatable.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';

/// Authentication status
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

/// State class for AuthCubit
class AuthState extends Equatable {
  final AuthStatus status;
  final UnifiedUser? user;
  final String? errorMessage;
  final bool isLoading;
  final bool isFirstTimeUser;
  /// Transient signal: the most recent sign-in created a brand-new backend
  /// account, so the username-setup screen should be shown before the
  /// home screen. Cleared as soon as the screen is dismissed (or skipped).
  final bool needsUsernameSetup;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.errorMessage,
    this.isLoading = false,
    this.isFirstTimeUser =
        true, // Default to true - assume first time until checked
    this.needsUsernameSetup = false,
  });

  /// Initial state
  factory AuthState.initial() => const AuthState();

  /// Create a copy with updated values
  AuthState copyWith({
    AuthStatus? status,
    UnifiedUser? user,
    String? errorMessage,
    bool? isLoading,
    bool? isFirstTimeUser,
    bool? needsUsernameSetup,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
      isFirstTimeUser: isFirstTimeUser ?? this.isFirstTimeUser,
      needsUsernameSetup: needsUsernameSetup ?? this.needsUsernameSetup,
    );
  }

  /// Whether user is signed in
  bool get isSignedIn => status == AuthStatus.authenticated && user != null;

  /// Whether user is anonymous
  bool get isAnonymous => user?.userType == UserType.anonymous;

  /// Whether user is a guest (offline user)
  bool get isGuestUser => user?.userType == UserType.guest;

  /// Whether user signed in with Google
  bool get isGoogleUser => user?.userType == UserType.google;

  /// User's display name (legal name from Google profile, or 'Player'
  /// fallback). Prefer [publicLabel] for any UI surface that identifies
  /// the player to themselves or others — usernames are stable across
  /// Google profile renames and present consistently on leaderboards.
  String get displayName => user?.displayName ?? 'Player';

  /// User's username (auto-generated `Adjective_Noun_NNNN` for new
  /// accounts; user-editable via Settings → Change Username).
  String get username => user?.username ?? 'Guest';

  /// The label every player-facing surface should use: username if
  /// present, then display name, then 'Player'. Mirrors
  /// `UserProfile.publicLabel` for non-self surfaces. Stable across
  /// Google profile renames; aligns with how the leaderboard renders.
  String get publicLabel {
    final u = user?.username;
    if (u != null && u.isNotEmpty && u != 'Guest' && u != 'Anonymous') return u;
    final d = user?.displayName;
    if (d != null && d.isNotEmpty && d != 'Anonymous') return d;
    return 'Player';
  }

  /// User's photo URL
  String? get photoURL => user?.photoURL;

  /// User's high score
  int get highScore => user?.highScore ?? 0;

  /// User's total games played
  int get totalGamesPlayed => user?.totalGamesPlayed ?? 0;

  /// User's total score
  int get totalScore => user?.totalScore ?? 0;

  /// Current user ID
  String? get userId => user?.uid;

  @override
  List<Object?> get props => [
    status,
    user,
    errorMessage,
    isLoading,
    isFirstTimeUser,
    needsUsernameSetup,
  ];
}
