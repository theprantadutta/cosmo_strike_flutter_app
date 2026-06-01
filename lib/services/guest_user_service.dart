import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class GuestUser {
  final String guestId;
  final String username;
  final DateTime createdAt;
  final int highScore;
  final int totalGamesPlayed;
  final int totalScore;
  final Map<String, dynamic> gameStats;
  final List<String> achievements;
  final String preferredTheme;
  final bool soundEnabled;
  final bool musicEnabled;

  const GuestUser({
    required this.guestId,
    required this.username,
    required this.createdAt,
    this.highScore = 0,
    this.totalGamesPlayed = 0,
    this.totalScore = 0,
    this.gameStats = const {},
    this.achievements = const [],
    this.preferredTheme = 'classic',
    this.soundEnabled = true,
    this.musicEnabled = true,
  });

  GuestUser copyWith({
    String? guestId,
    String? username,
    DateTime? createdAt,
    int? highScore,
    int? totalGamesPlayed,
    int? totalScore,
    Map<String, dynamic>? gameStats,
    List<String>? achievements,
    String? preferredTheme,
    bool? soundEnabled,
    bool? musicEnabled,
  }) {
    return GuestUser(
      guestId: guestId ?? this.guestId,
      username: username ?? this.username,
      createdAt: createdAt ?? this.createdAt,
      highScore: highScore ?? this.highScore,
      totalGamesPlayed: totalGamesPlayed ?? this.totalGamesPlayed,
      totalScore: totalScore ?? this.totalScore,
      gameStats: gameStats ?? this.gameStats,
      achievements: achievements ?? this.achievements,
      preferredTheme: preferredTheme ?? this.preferredTheme,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      musicEnabled: musicEnabled ?? this.musicEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'guestId': guestId,
      'username': username,
      'createdAt': createdAt.toIso8601String(),
      'highScore': highScore,
      'totalGamesPlayed': totalGamesPlayed,
      'totalScore': totalScore,
      'gameStats': gameStats,
      'achievements': achievements,
      'preferredTheme': preferredTheme,
      'soundEnabled': soundEnabled,
      'musicEnabled': musicEnabled,
    };
  }

  factory GuestUser.fromJson(Map<String, dynamic> json) {
    return GuestUser(
      guestId: json['guestId'] ?? '',
      username: json['username'] ?? '',
      createdAt: DateTime.parse(
        json['createdAt'] ?? DateTime.now().toIso8601String(),
      ),
      highScore: json['highScore'] ?? 0,
      totalGamesPlayed: json['totalGamesPlayed'] ?? 0,
      totalScore: json['totalScore'] ?? 0,
      gameStats: Map<String, dynamic>.from(json['gameStats'] ?? {}),
      achievements: List<String>.from(json['achievements'] ?? []),
      preferredTheme: json['preferredTheme'] ?? 'classic',
      soundEnabled: json['soundEnabled'] ?? true,
      musicEnabled: json['musicEnabled'] ?? true,
    );
  }
}

class GuestUserService {
  static final GuestUserService _instance = GuestUserService._internal();
  factory GuestUserService() => _instance;
  GuestUserService._internal();

  static const String _guestUserKey = 'guest_user_data';
  static const String _hasInitializedKey = 'has_initialized_guest';

  final Uuid _uuid = const Uuid();
  final Random _random = Random();

  SharedPreferences? _prefs;
  GuestUser? _currentGuestUser;

  /// Initialize the guest user service
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Check if a guest user exists
  Future<bool> hasGuestUser() async {
    await initialize();
    return _prefs!.containsKey(_guestUserKey);
  }

  /// Create a new guest user with auto-generated username
  Future<GuestUser> createGuestUser() async {
    await initialize();

    final guestId = _uuid.v4();
    final username = _generateUniqueUsername();
    final now = DateTime.now();

    final guestUser = GuestUser(
      guestId: guestId,
      username: username,
      createdAt: now,
    );

    // Save to local storage
    await _saveGuestUser(guestUser);
    _currentGuestUser = guestUser;

    // Mark as initialized
    await _prefs!.setBool(_hasInitializedKey, true);

    return guestUser;
  }

  /// Load existing guest user from local storage
  Future<GuestUser?> loadGuestUser() async {
    await initialize();

    final userData = _prefs!.getString(_guestUserKey);
    if (userData == null) return null;

    try {
      final userMap = jsonDecode(userData);
      final guestUser = GuestUser.fromJson(userMap);
      _currentGuestUser = guestUser;
      return guestUser;
    } catch (e) {
      // If there's an error loading, remove corrupted data
      await _prefs!.remove(_guestUserKey);
      return null;
    }
  }

  /// Get or create guest user
  Future<GuestUser> getOrCreateGuestUser() async {
    final existingUser = await loadGuestUser();
    if (existingUser != null) {
      return existingUser;
    }

    return await createGuestUser();
  }

  /// Update guest user data
  Future<void> updateGuestUser(GuestUser updatedUser) async {
    await _saveGuestUser(updatedUser);
    _currentGuestUser = updatedUser;
  }

  /// Update high score for guest user
  Future<void> updateHighScore(int score) async {
    if (_currentGuestUser == null) return;

    final currentHighScore = _currentGuestUser!.highScore;
    final newTotalGames = _currentGuestUser!.totalGamesPlayed + 1;
    final newTotalScore = _currentGuestUser!.totalScore + score;

    final updatedUser = _currentGuestUser!.copyWith(
      highScore: score > currentHighScore ? score : currentHighScore,
      totalGamesPlayed: newTotalGames,
      totalScore: newTotalScore,
    );

    await updateGuestUser(updatedUser);
  }

  /// Update username for guest user (with validation)
  Future<bool> updateUsername(String newUsername) async {
    if (_currentGuestUser == null) return false;

    // Validate username
    if (!_isValidUsername(newUsername)) return false;

    final updatedUser = _currentGuestUser!.copyWith(username: newUsername);
    await updateGuestUser(updatedUser);
    return true;
  }

  /// Get current guest user
  GuestUser? get currentGuestUser => _currentGuestUser;

  /// Check if app has been initialized with guest user before
  Future<bool> hasBeenInitialized() async {
    await initialize();
    return _prefs!.getBool(_hasInitializedKey) ?? false;
  }

  /// Clear guest user data (used when migrating to authenticated user)
  Future<void> clearGuestUser() async {
    await initialize();
    await _prefs!.remove(_guestUserKey);
    await _prefs!.remove(_hasInitializedKey);
    _currentGuestUser = null;
  }

  /// Export guest user data for migration
  Map<String, dynamic> exportGuestData() {
    if (_currentGuestUser == null) return {};

    return {
      'highScore': _currentGuestUser!.highScore,
      'totalGamesPlayed': _currentGuestUser!.totalGamesPlayed,
      'totalScore': _currentGuestUser!.totalScore,
      'gameStats': _currentGuestUser!.gameStats,
      'achievements': _currentGuestUser!.achievements,
      'preferredTheme': _currentGuestUser!.preferredTheme,
      'soundEnabled': _currentGuestUser!.soundEnabled,
      'musicEnabled': _currentGuestUser!.musicEnabled,
      'username': _currentGuestUser!.username,
    };
  }

  // Private methods

  Future<void> _saveGuestUser(GuestUser guestUser) async {
    await initialize();
    final userData = jsonEncode(guestUser.toJson());
    await _prefs!.setString(_guestUserKey, userData);
  }

  String _generateUniqueUsername() {
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
    ];

    final adjective = adjectives[_random.nextInt(adjectives.length)];
    final noun = nouns[_random.nextInt(nouns.length)];
    final number = _random.nextInt(9999) + 1;

    return '${adjective}_${noun}_$number';
  }

  bool _isValidUsername(String username) {
    // Username validation rules
    if (username.length < 3 || username.length > 20) return false;

    // Allow alphanumeric characters and underscores
    final validRegex = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!validRegex.hasMatch(username)) return false;

    // Must start with a letter
    if (!RegExp(r'^[a-zA-Z]').hasMatch(username)) return false;

    return true;
  }
}
