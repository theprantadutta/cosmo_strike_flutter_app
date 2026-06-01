import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing walkthrough/tutorial completion state
/// Uses SharedPreferences to persist walkthrough completion status
class WalkthroughService {
  static WalkthroughService? _instance;
  SharedPreferences? _prefs;

  WalkthroughService._internal();

  factory WalkthroughService() {
    _instance ??= WalkthroughService._internal();
    return _instance!;
  }

  /// Initialize the service with SharedPreferences
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Check if SharedPreferences is initialized
  bool get isInitialized => _prefs != null;

  /// Check if a specific walkthrough has been completed
  bool isComplete(String id) {
    return _prefs?.getBool('${id}_walkthrough_complete') ?? false;
  }

  /// Mark a walkthrough as completed
  Future<void> markComplete(String id) async {
    await _prefs?.setBool('${id}_walkthrough_complete', true);
  }

  /// Reset a walkthrough to show again
  Future<void> reset(String id) async {
    await _prefs?.setBool('${id}_walkthrough_complete', false);
  }

  /// Reset all walkthroughs
  Future<void> resetAll() async {
    await reset('home');
    await reset('game_tutorial');
    await reset('control_choice');
  }

  // ==================== Walkthrough IDs ====================

  /// Home screen walkthrough ID
  static const String homeWalkthroughId = 'home';

  /// Game tutorial walkthrough ID
  static const String gameTutorialId = 'game_tutorial';

  /// First-time control method choice (D-Pad vs Gestures). Asked before
  /// the game tutorial runs so the tutorial demos the right input.
  static const String controlChoiceId = 'control_choice';
}
