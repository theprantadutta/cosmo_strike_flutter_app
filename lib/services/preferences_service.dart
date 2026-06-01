import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/services/data_sync_service.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

class PreferencesService extends ChangeNotifier {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  final DataSyncService _syncService = DataSyncService();
  final UnifiedUserService _userService = UnifiedUserService();

  SharedPreferences? _prefs;
  Map<String, dynamic> _preferences = {};
  bool _isInitialized = false;

  // Getters
  bool get isInitialized => _isInitialized;
  Map<String, dynamic> get preferences => Map.from(_preferences);

  // Specific preference getters
  GameTheme get selectedTheme {
    final themeName = _preferences['theme'] as String? ?? 'classic';
    return GameTheme.values.firstWhere(
      (theme) => theme.name.toLowerCase() == themeName.toLowerCase(),
      orElse: () => GameTheme.classic,
    );
  }

  bool get soundEnabled => _preferences['soundEnabled'] as bool? ?? true;
  bool get musicEnabled => _preferences['musicEnabled'] as bool? ?? true;
  bool get trailSystemEnabled =>
      _preferences['trailSystemEnabled'] as bool? ?? false;

  BoardSize get boardSize {
    final sizeData = _preferences['boardSize'] as Map<String, dynamic>?;
    if (sizeData != null) {
      return BoardSize(
        sizeData['width'] ?? 20,
        sizeData['height'] ?? 20,
        sizeData['name'] ?? 'Classic',
        sizeData['description'] ?? 'Classic 20x20 grid',
      );
    }
    return GameConstants.availableBoardSizes[1]; // Default to Classic
  }

  Duration get crashFeedbackDuration {
    final seconds =
        _preferences['crashFeedbackDurationSeconds'] as int? ??
        GameConstants.defaultCrashFeedbackDuration.inSeconds;
    return Duration(seconds: seconds);
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    _prefs = await SharedPreferences.getInstance();

    // Load local preferences first (fast, always works)
    await _loadLocalPreferences();

    // Mark initialized BEFORE cloud sync - this is critical for offline-first
    _isInitialized = true;

    if (kDebugMode) {
      print('PreferencesService initialized (local data loaded)');
    }

    notifyListeners();

    // Cloud sync in background - don't await, don't block app startup
    if (_userService.isSignedIn) {
      _syncWithCloudInBackground();
    }
  }

  /// Sync with cloud in background without blocking initialization
  void _syncWithCloudInBackground() {
    // Use Future.microtask to avoid blocking
    Future.microtask(() async {
      try {
        await _syncWithCloud();
        if (kDebugMode) {
          print('PreferencesService: Background cloud sync completed');
        }
      } catch (e) {
        if (kDebugMode) {
          print('PreferencesService: Background cloud sync failed: $e');
        }
        // Silently fail - local data is already loaded
      }
    });
  }

  Future<void> _loadLocalPreferences() async {
    if (_prefs == null) return;

    try {
      // Load individual preferences from SharedPreferences
      _preferences = {
        'theme': _getLocalTheme(),
        'soundEnabled': _prefs!.getBool(GameConstants.soundEnabledKey) ?? true,
        'musicEnabled': _prefs!.getBool('music_enabled') ?? true,
        'trailSystemEnabled':
            _prefs!.getBool(GameConstants.trailSystemEnabledKey) ?? false,
        'boardSize': await _getLocalBoardSize(),
        'crashFeedbackDurationSeconds':
            _prefs!.getInt(GameConstants.crashFeedbackDurationKey) ??
            GameConstants.defaultCrashFeedbackDuration.inSeconds,
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error loading local preferences: $e');
      }
      _preferences = _getDefaultPreferences();
    }
  }

  String _getLocalTheme() {
    final themeIndex = _prefs!.getInt(GameConstants.selectedThemeKey) ?? 0;
    final clampedIndex = themeIndex.clamp(0, GameTheme.values.length - 1);
    return GameTheme.values[clampedIndex].name;
  }

  Future<Map<String, dynamic>> _getLocalBoardSize() async {
    final boardSizeIndex = _prefs!.getInt(GameConstants.boardSizeKey) ?? 1;
    final clampedIndex = boardSizeIndex.clamp(
      0,
      GameConstants.availableBoardSizes.length - 1,
    );
    final boardSize = GameConstants.availableBoardSizes[clampedIndex];

    return {
      'width': boardSize.width,
      'height': boardSize.height,
      'name': boardSize.name,
      'description': boardSize.description,
    };
  }

  Map<String, dynamic> _getDefaultPreferences() {
    return {
      'theme': 'classic',
      'soundEnabled': true,
      'musicEnabled': true,
      'trailSystemEnabled': false,
      'boardSize': {
        'width': 20,
        'height': 20,
        'name': 'Classic',
        'description': 'Classic 20x20 grid',
      },
      'crashFeedbackDurationSeconds':
          GameConstants.defaultCrashFeedbackDuration.inSeconds,
    };
  }

  Future<void> _syncWithCloud() async {
    try {
      // Get cloud preferences
      final cloudPrefs = await _syncService.getData('preferences');

      if (cloudPrefs != null) {
        // Merge with local preferences (cloud wins for newer data)
        final mergedPrefs = _syncService.mergeData(_preferences, cloudPrefs);
        _preferences = mergedPrefs;

        // Save merged preferences locally
        await _saveLocalPreferences();
      } else {
        // No cloud preferences, upload local ones
        await _uploadPreferencesToCloud();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing preferences with cloud: $e');
      }
    }
  }

  Future<void> _uploadPreferencesToCloud() async {
    final preferencesWithTimestamp = Map<String, dynamic>.from(_preferences);
    preferencesWithTimestamp['lastUpdated'] = DateTime.now().toIso8601String();

    await _syncService.queueSync('preferences', preferencesWithTimestamp);
  }

  Future<void> _saveLocalPreferences() async {
    if (_prefs == null) return;

    try {
      // Save individual preferences to SharedPreferences for backward compatibility
      await _prefs!.setInt(
        GameConstants.selectedThemeKey,
        GameTheme.values.indexWhere((t) => t.name == _preferences['theme']),
      );

      await _prefs!.setBool(GameConstants.soundEnabledKey, soundEnabled);
      await _prefs!.setBool('music_enabled', musicEnabled);
      await _prefs!.setBool(
        GameConstants.trailSystemEnabledKey,
        trailSystemEnabled,
      );

      final boardSizeData = _preferences['boardSize'] as Map<String, dynamic>;
      final boardSizeIndex = GameConstants.availableBoardSizes.indexWhere(
        (size) => size.name == boardSizeData['name'],
      );
      await _prefs!.setInt(
        GameConstants.boardSizeKey,
        boardSizeIndex.clamp(0, GameConstants.availableBoardSizes.length - 1),
      );

      await _prefs!.setInt(
        GameConstants.crashFeedbackDurationKey,
        crashFeedbackDuration.inSeconds,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error saving local preferences: $e');
      }
    }
  }

  // Public methods for updating preferences

  Future<void> setTheme(GameTheme theme) async {
    await _updatePreference('theme', theme.name);
  }

  Future<void> setSoundEnabled(bool enabled) async {
    await _updatePreference('soundEnabled', enabled);
  }

  Future<void> setMusicEnabled(bool enabled) async {
    await _updatePreference('musicEnabled', enabled);
  }

  Future<void> setTrailSystemEnabled(bool enabled) async {
    await _updatePreference('trailSystemEnabled', enabled);
  }

  Future<void> setBoardSize(BoardSize boardSize) async {
    await _updatePreference('boardSize', {
      'width': boardSize.width,
      'height': boardSize.height,
      'name': boardSize.name,
      'description': boardSize.description,
    });
  }

  Future<void> setCrashFeedbackDuration(Duration duration) async {
    await _updatePreference('crashFeedbackDurationSeconds', duration.inSeconds);
  }

  Future<void> _updatePreference(String key, dynamic value) async {
    if (!_isInitialized) {
      await initialize();
    }

    _preferences[key] = value;

    // Save locally
    await _saveLocalPreferences();

    // Sync to cloud if signed in
    if (_userService.isSignedIn) {
      await _uploadPreferencesToCloud();
    }

    notifyListeners();
  }

  // Bulk update preferences
  Future<void> updatePreferences(Map<String, dynamic> newPreferences) async {
    if (!_isInitialized) {
      await initialize();
    }

    _preferences.addAll(newPreferences);

    // Save locally
    await _saveLocalPreferences();

    // Sync to cloud if signed in
    if (_userService.isSignedIn) {
      await _uploadPreferencesToCloud();
    }

    notifyListeners();
  }

  // Reset all preferences to defaults
  Future<void> resetToDefaults() async {
    _preferences = _getDefaultPreferences();

    await _saveLocalPreferences();

    if (_userService.isSignedIn) {
      await _uploadPreferencesToCloud();
    }

    notifyListeners();
  }

  // Force sync with cloud (for manual sync)
  Future<bool> forceSyncWithCloud() async {
    if (!_userService.isSignedIn) return false;

    try {
      await _syncWithCloud();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error in force sync: $e');
      }
      return false;
    }
  }
}

// Using BoardSize from constants.dart
