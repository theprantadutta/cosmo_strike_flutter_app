import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';

class UsernameService {
  static final UsernameService _instance = UsernameService._internal();
  factory UsernameService() => _instance;
  UsernameService._internal();

  final ApiService _apiService = ApiService();
  final Random _random = Random();

  // Username validation rules
  static const int minLength = 3;
  static const int maxLength = 20;
  static final RegExp _validUsernameRegex = RegExp(
    r'^[a-zA-Z][a-zA-Z0-9_]{2,19}$',
  );

  // Reserved/blocked usernames
  static const List<String> _reservedUsernames = [
    'admin',
    'administrator',
    'mod',
    'moderator',
    'system',
    'support',
    'help',
    'api',
    'www',
    'mail',
    'email',
    'test',
    'guest',
    'null',
    'undefined',
    'root',
    'user',
    'player',
    'ship',
    'game',
    'server',
  ];

  // Word lists for username generation
  static const List<String> _adjectives = [
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
    'Thunder',
    'Lightning',
    'Storm',
    'Wind',
    'Ocean',
    'Mountain',
    'Forest',
    'Sky',
  ];

  static const List<String> _nouns = [
    'Ship',
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
    'Stallion',
    'Ranger',
    'Scout',
    'Knight',
    'Ninja',
    'Samurai',
    'Guardian',
    'Defender',
    'Assassin',
    'Ghost',
    'Spirit',
  ];

  /// Validates a username according to the rules
  UsernameValidationResult validateUsername(String username) {
    // Check length
    if (username.length < minLength) {
      return UsernameValidationResult(
        isValid: false,
        error: 'Username must be at least $minLength characters long',
      );
    }

    if (username.length > maxLength) {
      return UsernameValidationResult(
        isValid: false,
        error: 'Username must be no more than $maxLength characters long',
      );
    }

    // Check format (alphanumeric + underscore, must start with letter)
    if (!_validUsernameRegex.hasMatch(username)) {
      return UsernameValidationResult(
        isValid: false,
        error:
            'Username must start with a letter and contain only letters, numbers, and underscores',
      );
    }

    // Check reserved words
    if (_reservedUsernames.contains(username.toLowerCase())) {
      return UsernameValidationResult(
        isValid: false,
        error: 'This username is reserved and cannot be used',
      );
    }

    return UsernameValidationResult(isValid: true);
  }

  /// Check if username is available via backend API
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final result = await _apiService.checkUsername(username);
      return result?['available'] == true;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking username availability: $e');
      }
      return false;
    }
  }

  /// Comprehensive username validation (format + availability)
  Future<UsernameValidationResult> validateUsernameComplete(
    String username,
  ) async {
    // First check format
    final formatResult = validateUsername(username);
    if (!formatResult.isValid) {
      return formatResult;
    }

    // Then check availability
    final isAvailable = await isUsernameAvailable(username);
    if (!isAvailable) {
      return UsernameValidationResult(
        isValid: false,
        error: 'This username is already taken',
      );
    }

    return UsernameValidationResult(isValid: true);
  }

  /// Generate a random username
  String generateRandomUsername() {
    final adjective = _adjectives[_random.nextInt(_adjectives.length)];
    final noun = _nouns[_random.nextInt(_nouns.length)];
    final number = _random.nextInt(9999) + 1;

    return '${adjective}_${noun}_$number';
  }

  /// Generate multiple random username suggestions
  List<String> generateUsernameSuggestions({int count = 5}) {
    final suggestions = <String>[];
    final usedCombinations = <String>{};

    while (suggestions.length < count &&
        usedCombinations.length < _adjectives.length * _nouns.length) {
      final adjective = _adjectives[_random.nextInt(_adjectives.length)];
      final noun = _nouns[_random.nextInt(_nouns.length)];
      final combination = '$adjective$noun';

      if (usedCombinations.contains(combination)) continue;
      usedCombinations.add(combination);

      // Try different variations
      final variations = [
        '${adjective}_$noun',
        '$adjective$noun${_random.nextInt(99) + 1}',
        '${adjective}_${noun}_${_random.nextInt(999) + 1}',
        '$adjective$noun${_random.nextInt(9999) + 1}',
      ];

      for (final variation in variations) {
        if (validateUsername(variation).isValid &&
            !suggestions.contains(variation)) {
          suggestions.add(variation);
          break;
        }
      }
    }

    return suggestions;
  }

  /// Generate username based on display name
  String generateUsernameFromDisplayName(String displayName) {
    // Clean the display name
    String cleaned = displayName
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();

    // If cleaned name is empty or too short, generate random
    if (cleaned.length < 3) {
      return generateRandomUsername();
    }

    // Truncate if too long
    if (cleaned.length > maxLength - 3) {
      cleaned = cleaned.substring(0, maxLength - 3);
    }

    // Add random number to ensure uniqueness
    final number = _random.nextInt(999) + 1;
    final username = '${cleaned}_$number';

    // Ensure it starts with a letter
    if (!RegExp(r'^[a-zA-Z]').hasMatch(username)) {
      return generateRandomUsername();
    }

    return username;
  }

  /// Find available username similar to desired username.
  /// Uses a single server-side API call instead of looping through variations.
  Future<String> findAvailableUsername(String desiredUsername) async {
    // Use server-side suggest endpoint — single API call replaces up to 1000 calls
    try {
      final suggestions = await _apiService.suggestUsernames(
        desiredUsername,
        count: 1,
      );
      if (suggestions != null && suggestions.isNotEmpty) {
        return suggestions.first;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting username suggestions: $e');
      }
    }

    // Fallback: generate a random username locally (no API call)
    return generateRandomUsername();
  }

  /// Update username via backend API
  Future<UsernameUpdateResult> updateUsername(
    String userId,
    String newUsername,
  ) async {
    try {
      // Validate the new username
      final validation = await validateUsernameComplete(newUsername);
      if (!validation.isValid) {
        return UsernameUpdateResult(success: false, error: validation.error!);
      }

      // Update via API
      final result = await _apiService.setUsername(newUsername);
      if (result == null) {
        return UsernameUpdateResult(
          success: false,
          error: 'Failed to update username',
        );
      }

      return UsernameUpdateResult(success: true);
    } catch (e) {
      return UsernameUpdateResult(
        success: false,
        error: 'Failed to update username: $e',
      );
    }
  }

  /// Search users by username. Disabled in the offline-first build —
  /// the user-search endpoint backed the now-hidden friends flow and
  /// has no local equivalent.
  Future<List<Map<String, dynamic>>> searchUsersByUsername(String query) async =>
      const [];

  /// Reserve a username (now handled by backend automatically)
  Future<void> reserveUsername(String username, String userId) async {
    // The backend handles username reservation during user creation
  }

  /// Release a username (now handled by backend automatically)
  Future<void> releaseUsername(String username) async {
    // The backend handles username release during user deletion
  }
}

class UsernameValidationResult {
  final bool isValid;
  final String? error;

  const UsernameValidationResult({required this.isValid, this.error});
}

class UsernameUpdateResult {
  final bool success;
  final String? error;

  const UsernameUpdateResult({required this.success, this.error});
}
