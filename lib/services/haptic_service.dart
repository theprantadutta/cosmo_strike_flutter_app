import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

enum HapticIntensity { light, medium, heavy, success, warning, error }

class HapticService {
  static final HapticService _instance = HapticService._internal();
  factory HapticService() => _instance;
  HapticService._internal();

  bool _isEnabled = true;

  bool get isEnabled => _isEnabled;

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
  }

  /// Basic feedback for button taps and selections
  Future<void> selectionClick() async {
    if (!_isEnabled) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (e) {
      if (kDebugMode) print('Haptic feedback error: $e');
    }
  }

  /// Light impact feedback for subtle interactions
  Future<void> lightImpact() async {
    if (!_isEnabled) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (e) {
      if (kDebugMode) print('Haptic feedback error: $e');
    }
  }

  /// Medium impact feedback for standard interactions
  Future<void> mediumImpact() async {
    if (!_isEnabled) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (e) {
      if (kDebugMode) print('Haptic feedback error: $e');
    }
  }

  /// Heavy impact feedback for significant interactions
  Future<void> heavyImpact() async {
    if (!_isEnabled) return;
    try {
      await HapticFeedback.heavyImpact();
    } catch (e) {
      if (kDebugMode) print('Haptic feedback error: $e');
    }
  }

  /// Custom haptic pattern with intensity
  Future<void> customHaptic(HapticIntensity intensity) async {
    if (!_isEnabled) return;

    switch (intensity) {
      case HapticIntensity.light:
        await lightImpact();
        break;
      case HapticIntensity.medium:
        await mediumImpact();
        break;
      case HapticIntensity.heavy:
        await heavyImpact();
        break;
      case HapticIntensity.success:
        await _successPattern();
        break;
      case HapticIntensity.warning:
        await _warningPattern();
        break;
      case HapticIntensity.error:
        await _errorPattern();
        break;
    }
  }

  /// Game-specific haptic feedback methods

  /// Feedback for snake movement/direction changes
  Future<void> snakeMove() async {
    await lightImpact();
  }

  /// Feedback for food consumption
  Future<void> foodEaten() async {
    await mediumImpact();
  }

  /// Feedback for bonus food consumption
  Future<void> bonusFoodEaten() async {
    await _doubleImpact(HapticFeedback.mediumImpact);
  }

  /// Feedback for special food consumption
  Future<void> specialFoodEaten() async {
    await _tripleImpact(HapticFeedback.heavyImpact);
  }

  /// Feedback for power-up collection
  Future<void> powerUpCollected() async {
    await _successPattern();
  }

  /// Feedback for level up
  Future<void> levelUp() async {
    await _levelUpPattern();
  }

  /// Feedback for game over
  Future<void> gameOver() async {
    await _gameOverPattern();
  }

  /// Feedback for wall collision
  Future<void> wallHit() async {
    await _errorPattern();
  }

  /// Feedback for self collision
  Future<void> selfCollision() async {
    await _warningPattern();
  }

  /// Feedback for achievement unlock
  Future<void> achievementUnlocked() async {
    await _achievementPattern();
  }

  /// Feedback for button press
  Future<void> buttonPress() async {
    await selectionClick();
  }

  /// Feedback for menu navigation
  Future<void> menuNavigation() async {
    await selectionClick();
  }

  /// Feedback for score milestone
  Future<void> scoreMilestone() async {
    await _scoreMilestonePattern();
  }

  /// Feedback for pause/resume
  Future<void> pauseToggle() async {
    await mediumImpact();
  }

  /// Private helper methods for complex patterns

  Future<void> _doubleImpact(Function hapticFunction) async {
    if (!_isEnabled) return;
    await hapticFunction();
    await Future.delayed(const Duration(milliseconds: 50));
    await hapticFunction();
  }

  Future<void> _tripleImpact(Function hapticFunction) async {
    if (!_isEnabled) return;
    await hapticFunction();
    await Future.delayed(const Duration(milliseconds: 50));
    await hapticFunction();
    await Future.delayed(const Duration(milliseconds: 50));
    await hapticFunction();
  }

  Future<void> _successPattern() async {
    if (!_isEnabled) return;
    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 30));
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 30));
    await heavyImpact();
  }

  Future<void> _warningPattern() async {
    if (!_isEnabled) return;
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await heavyImpact();
  }

  Future<void> _errorPattern() async {
    if (!_isEnabled) return;
    await heavyImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await heavyImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await heavyImpact();
  }

  Future<void> _levelUpPattern() async {
    if (!_isEnabled) return;
    // Ascending intensity pattern
    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 40));
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 40));
    await heavyImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await lightImpact();
  }

  Future<void> _gameOverPattern() async {
    if (!_isEnabled) return;
    // Dramatic descending pattern
    await heavyImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    await heavyImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 300));
    await lightImpact();
  }

  Future<void> _achievementPattern() async {
    if (!_isEnabled) return;
    // Celebratory burst pattern
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 30));
    await heavyImpact();
    await Future.delayed(const Duration(milliseconds: 50));
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 30));
    await heavyImpact();
  }

  Future<void> _scoreMilestonePattern() async {
    if (!_isEnabled) return;
    // Quick celebratory double tap
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await heavyImpact();
  }

  /// Sequence patterns for special events

  /// Rapid fire pattern for chain events
  Future<void> chainEffect(int count) async {
    if (!_isEnabled || count <= 0) return;

    for (int i = 0; i < count && i < 5; i++) {
      // Max 5 in chain to avoid overload
      await lightImpact();
      if (i < count - 1) {
        await Future.delayed(const Duration(milliseconds: 80));
      }
    }
  }

  /// Crescendo pattern for building excitement
  Future<void> crescendo() async {
    if (!_isEnabled) return;

    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await heavyImpact();
  }

  /// Pulse pattern for ongoing effects
  Future<void> pulse() async {
    if (!_isEnabled) return;

    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await mediumImpact();
  }

  /// Theme-specific haptic patterns

  Future<void> cyberpunkEffect() async {
    if (!_isEnabled) return;
    // Quick digital bursts
    for (int i = 0; i < 3; i++) {
      await lightImpact();
      await Future.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<void> oceanWaveEffect() async {
    if (!_isEnabled) return;
    // Smooth wave-like pattern
    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    await lightImpact();
  }

  Future<void> crystalChimeEffect() async {
    if (!_isEnabled) return;
    // Delicate crystal-like touches
    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await lightImpact();
  }

  Future<void> forestRustleEffect() async {
    if (!_isEnabled) return;
    // Organic, natural pattern
    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 40));
    await mediumImpact();
  }

  Future<void> desertWindEffect() async {
    if (!_isEnabled) return;
    // Gentle, sustained pattern
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 300));
    await lightImpact();
  }

  /// Utility methods

  /// Check if haptic feedback is available on the device
  static bool get isAvailable {
    // Most modern mobile devices support haptic feedback
    // This could be enhanced with platform-specific checks
    return true;
  }

  /// Test haptic functionality
  Future<void> testHaptics() async {
    if (!_isEnabled) return;

    await lightImpact();
    await Future.delayed(const Duration(milliseconds: 500));
    await mediumImpact();
    await Future.delayed(const Duration(milliseconds: 500));
    await heavyImpact();
  }
}
