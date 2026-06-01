import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Central animation preset system for game-like feel.
/// All animations use scale + opacity only (no slides).

// === Durations ===
class GameDurations {
  static const feedback = Duration(milliseconds: 80);
  static const feedbackRelease = Duration(milliseconds: 120);
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 350);
  static const transition = Duration(milliseconds: 300);
  static const breathe = Duration(milliseconds: 2500);
}

// === Curves ===
class GameCurves {
  static const snap = Curves.easeOutCubic;
  static const pop = Curves.easeOutBack;
  static const settle = Curves.easeInOut;
}

// === Widget Extensions ===
extension GameAnimations on Widget {
  /// Standard entrance: fadeIn + scale 0.88→1.0, snap curve, 250ms
  Widget gameEntrance({Duration? delay}) {
    return animate(delay: delay)
        .fadeIn(duration: GameDurations.normal, curve: GameCurves.snap)
        .scale(
          begin: const Offset(0.88, 0.88),
          end: const Offset(1.0, 1.0),
          duration: GameDurations.normal,
          curve: GameCurves.snap,
        );
  }

  /// Zoom in entrance: fadeIn + scale 0.7→1.0, snap curve, 250ms
  /// Replaces slideUp/slideY entrances
  Widget gameZoomIn({Duration? delay}) {
    return animate(delay: delay)
        .fadeIn(duration: GameDurations.normal, curve: GameCurves.snap)
        .scale(
          begin: const Offset(0.7, 0.7),
          end: const Offset(1.0, 1.0),
          duration: GameDurations.normal,
          curve: GameCurves.snap,
        );
  }

  /// Pop entrance: scale 0.5→1.0, pop curve, 250ms
  /// For badges, rewards, emphasis
  Widget gamePop({Duration? delay}) {
    return animate(delay: delay).scale(
      begin: const Offset(0.5, 0.5),
      end: const Offset(1.0, 1.0),
      duration: GameDurations.normal,
      curve: GameCurves.pop,
    );
  }

  /// Hero entrance: fadeIn + scale 0.75→1.0, pop curve, 350ms
  /// For logo, title, hero elements
  Widget gameHero({Duration? delay}) {
    return animate(delay: delay)
        .fadeIn(duration: GameDurations.slow, curve: GameCurves.pop)
        .scale(
          begin: const Offset(0.75, 0.75),
          end: const Offset(1.0, 1.0),
          duration: GameDurations.slow,
          curve: GameCurves.pop,
        );
  }

  /// List item entrance: fadeIn + scale 0.9→1.0, snap curve, 150ms, 50ms stagger
  Widget gameListItem(int index) {
    return animate(delay: Duration(milliseconds: 100 + index * 50))
        .fadeIn(duration: GameDurations.fast, curve: GameCurves.snap)
        .scale(
          begin: const Offset(0.9, 0.9),
          end: const Offset(1.0, 1.0),
          duration: GameDurations.fast,
          curve: GameCurves.snap,
        );
  }

  /// Grid item entrance: fadeIn + scale 0.85→1.0, pop curve, 200ms, 40ms stagger
  Widget gameGridItem(int index) {
    return animate(delay: Duration(milliseconds: 100 + index * 40))
        .fadeIn(
          duration: const Duration(milliseconds: 200),
          curve: GameCurves.snap,
        )
        .scale(
          begin: const Offset(0.85, 0.85),
          end: const Offset(1.0, 1.0),
          duration: const Duration(milliseconds: 200),
          curve: GameCurves.pop,
        );
  }

  /// Calm breathing loop: repeating scale, settle curve, 2500ms
  Widget gameBreathe({double intensity = 1.04}) {
    return animate(onPlay: (controller) => controller.repeat(reverse: true))
        .scale(
      begin: const Offset(1.0, 1.0),
      end: Offset(intensity, intensity),
      duration: GameDurations.breathe,
      curve: GameCurves.settle,
    );
  }
}
