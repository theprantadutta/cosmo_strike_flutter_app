import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/models/power_up.dart';

enum CombinationType {
  synergy, // Two compatible power-ups enhance each other
  fusion, // Two power-ups merge into a new one
  catalyst, // One power-up triggers special effects with another
  amplification, // One power-up amplifies another
  transformation, // Power-ups change into different effects
}

enum ComboEffect {
  // Speed-related combos
  lightSpeed, // Speed boost + Invincibility = Ultra-fast invincible movement
  timeWarp, // Slow motion + Speed boost = Controlled time manipulation
  // Score-related combos
  goldRush, // Score multiplier + Speed boost = Higher speed = higher multiplier
  treasureHunter, // Score multiplier + Invincibility = Safe collection bonus
  // Invincibility-related combos
  ghostMode, // Invincibility + Slow motion = Phase through everything
  berserker, // Invincibility + Speed boost = Aggressive mode
  // Triple combos
  godMode, // All three basic power-ups active = Ultimate power
  // Special environmental combos
  magnetField, // Any power-up + specific conditions
  chainReaction, // Multiple same-type power-ups
  evolution, // Power-up duration extensions
}

class PowerUpCombo {
  final ComboEffect effect;
  final List<PowerUpType> requiredPowerUps;
  final CombinationType type;
  final Duration duration;
  final String name;
  final String description;
  final Color color;
  final double intensity;
  final Map<String, dynamic> properties;

  const PowerUpCombo({
    required this.effect,
    required this.requiredPowerUps,
    required this.type,
    required this.duration,
    required this.name,
    required this.description,
    required this.color,
    this.intensity = 1.0,
    this.properties = const {},
  });

  static const Map<ComboEffect, PowerUpCombo> combos = {
    ComboEffect.lightSpeed: PowerUpCombo(
      effect: ComboEffect.lightSpeed,
      requiredPowerUps: [PowerUpType.speedBoost, PowerUpType.invincibility],
      type: CombinationType.synergy,
      duration: Duration(seconds: 8),
      name: 'Light Speed',
      description: 'Ultra-fast invincible movement with trail effects',
      color: Color(0xFFFFD700),
      intensity: 2.0,
      properties: {
        'speedMultiplier': 3.0,
        'trailIntensity': 2.5,
        'glowRadius': 15.0,
        'invincibilityDuration': 8.0,
      },
    ),

    ComboEffect.timeWarp: PowerUpCombo(
      effect: ComboEffect.timeWarp,
      requiredPowerUps: [PowerUpType.slowMotion, PowerUpType.speedBoost],
      type: CombinationType.fusion,
      duration: Duration(seconds: 10),
      name: 'Time Warp',
      description: 'Control time flow with precision movement',
      color: Color(0xFF9370DB),
      intensity: 1.5,
      properties: {
        'timeScale': 0.5,
        'playerSpeedBoost': 1.8,
        'visualDistortion': true,
        'chronicleEffect': true,
      },
    ),

    ComboEffect.goldRush: PowerUpCombo(
      effect: ComboEffect.goldRush,
      requiredPowerUps: [PowerUpType.scoreMultiplier, PowerUpType.speedBoost],
      type: CombinationType.amplification,
      duration: Duration(seconds: 12),
      name: 'Gold Rush',
      description: 'Higher speed increases score multiplier exponentially',
      color: Color(0xFFFFD700),
      intensity: 1.8,
      properties: {
        'baseMultiplier': 3,
        'speedMultiplierBonus': 0.5,
        'maxMultiplier': 8,
        'particleGoldRain': true,
      },
    ),

    ComboEffect.treasureHunter: PowerUpCombo(
      effect: ComboEffect.treasureHunter,
      requiredPowerUps: [
        PowerUpType.scoreMultiplier,
        PowerUpType.invincibility,
      ],
      type: CombinationType.synergy,
      duration: Duration(seconds: 15),
      name: 'Treasure Hunter',
      description: 'Safe collection with bonus treasure spawns',
      color: Color(0xFF32CD32),
      intensity: 1.3,
      properties: {
        'scoreMultiplier': 4,
        'treasureSpawnChance': 0.3,
        'bonusTreasureValue': 100,
        'magneticCollection': 2.0,
      },
    ),

    ComboEffect.ghostMode: PowerUpCombo(
      effect: ComboEffect.ghostMode,
      requiredPowerUps: [PowerUpType.invincibility, PowerUpType.slowMotion],
      type: CombinationType.transformation,
      duration: Duration(seconds: 12),
      name: 'Ghost Mode',
      description:
          'Phase through everything in slow motion with ethereal effects',
      color: Color(0xFF87CEEB),
      intensity: 1.4,
      properties: {
        'phaseThrough': true,
        'etherealAlpha': 0.6,
        'slowMotionFactor': 0.3,
        'spiritParticles': true,
      },
    ),

    ComboEffect.berserker: PowerUpCombo(
      effect: ComboEffect.berserker,
      requiredPowerUps: [PowerUpType.invincibility, PowerUpType.speedBoost],
      type: CombinationType.synergy,
      duration: Duration(seconds: 6),
      name: 'Berserker Mode',
      description: 'Aggressive high-speed rampage with destruction effects',
      color: Color(0xFFDC143C),
      intensity: 2.5,
      properties: {
        'speedBoost': 2.5,
        'destructionTrail': true,
        'rageFactor': 1.5,
        'screenShakeIntensity': 1.8,
      },
    ),

    ComboEffect.godMode: PowerUpCombo(
      effect: ComboEffect.godMode,
      requiredPowerUps: [
        PowerUpType.speedBoost,
        PowerUpType.invincibility,
        PowerUpType.scoreMultiplier,
        PowerUpType.slowMotion,
      ],
      type: CombinationType.fusion,
      duration: Duration(seconds: 12),
      name: 'God Mode',
      description: 'Ultimate power combining all abilities with divine effects',
      color: Color(0xFFFFD700),
      intensity: 2.0,
      properties: {
        'speedBoost': 1.5,
        'scoreMultiplier': 5,
        'timeControl': true,
        'divineAura': true,
        'realityDistortion': 1.2,
      },
    ),

    ComboEffect.magnetField: PowerUpCombo(
      effect: ComboEffect.magnetField,
      requiredPowerUps: [PowerUpType.scoreMultiplier], // Can combo with any
      type: CombinationType.catalyst,
      duration: Duration(seconds: 8),
      name: 'Magnet Field',
      description: 'Attracts all collectibles within range',
      color: Color(0xFF4169E1),
      intensity: 1.2,
      properties: {
        'magnetRadius': 5.0,
        'attractionSpeed': 2.0,
        'autoCollect': true,
        'magneticField': true,
      },
    ),
  };

  bool canActivate(List<PowerUpType> activePowerUps) {
    return requiredPowerUps.every(
      (required) => activePowerUps.contains(required),
    );
  }

  static ComboEffect? findAvailableCombo(List<PowerUpType> activePowerUps) {
    for (final combo in combos.values) {
      if (combo.canActivate(activePowerUps)) {
        return combo.effect;
      }
    }
    return null;
  }

  static List<ComboEffect> findAllAvailableCombos(
    List<PowerUpType> activePowerUps,
  ) {
    return combos.values
        .where((combo) => combo.canActivate(activePowerUps))
        .map((combo) => combo.effect)
        .toList();
  }
}

class PowerUpComboSystem {
  final List<ComboEffect> _activeCombos = [];
  final Map<ComboEffect, DateTime> _comboStartTimes = {};
  final Map<ComboEffect, double> _comboIntensities = {};

  List<ComboEffect> get activeCombos => List.unmodifiable(_activeCombos);

  bool hasActiveCombo(ComboEffect combo) => _activeCombos.contains(combo);

  double getComboIntensity(ComboEffect combo) =>
      _comboIntensities[combo] ?? 0.0;

  double getComboProgress(ComboEffect combo) {
    final startTime = _comboStartTimes[combo];
    if (startTime == null) return 0.0;

    final comboData = PowerUpCombo.combos[combo];
    if (comboData == null) return 0.0;

    final elapsed = DateTime.now().difference(startTime);
    return (elapsed.inMilliseconds / comboData.duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  Duration getRemainingTime(ComboEffect combo) {
    final startTime = _comboStartTimes[combo];
    if (startTime == null) return Duration.zero;

    final comboData = PowerUpCombo.combos[combo];
    if (comboData == null) return Duration.zero;

    final elapsed = DateTime.now().difference(startTime);
    final remaining = comboData.duration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool activateCombo(ComboEffect combo, {double? customIntensity}) {
    final comboData = PowerUpCombo.combos[combo];
    if (comboData == null) return false;

    if (!_activeCombos.contains(combo)) {
      _activeCombos.add(combo);
    }

    _comboStartTimes[combo] = DateTime.now();
    _comboIntensities[combo] = customIntensity ?? comboData.intensity;

    return true;
  }

  void updateCombos() {
    final now = DateTime.now();
    final expiredCombos = <ComboEffect>[];

    for (final combo in _activeCombos) {
      final startTime = _comboStartTimes[combo];
      final comboData = PowerUpCombo.combos[combo];

      if (startTime != null && comboData != null) {
        final elapsed = now.difference(startTime);
        if (elapsed > comboData.duration) {
          expiredCombos.add(combo);
        } else {
          // Update intensity based on remaining time (fade out effect)
          final progress =
              elapsed.inMilliseconds / comboData.duration.inMilliseconds;
          final fadeStart = 0.8; // Start fading at 80% completion

          if (progress > fadeStart) {
            final fadeProgress = (progress - fadeStart) / (1.0 - fadeStart);
            final originalIntensity = comboData.intensity;
            _comboIntensities[combo] =
                originalIntensity * (1.0 - fadeProgress * 0.3);
          }
        }
      }
    }

    // Remove expired combos
    for (final combo in expiredCombos) {
      deactivateCombo(combo);
    }
  }

  void deactivateCombo(ComboEffect combo) {
    _activeCombos.remove(combo);
    _comboStartTimes.remove(combo);
    _comboIntensities.remove(combo);
  }

  void clearAllCombos() {
    _activeCombos.clear();
    _comboStartTimes.clear();
    _comboIntensities.clear();
  }

  // Combo-specific effect calculations

  double getEffectiveSpeedMultiplier() {
    double multiplier = 1.0;

    for (final combo in _activeCombos) {
      final comboData = PowerUpCombo.combos[combo];
      final intensity = _comboIntensities[combo] ?? 1.0;

      switch (combo) {
        case ComboEffect.lightSpeed:
          multiplier *=
              (comboData?.properties['speedMultiplier'] ?? 1.0) * intensity;
          break;
        case ComboEffect.timeWarp:
          multiplier *=
              (comboData?.properties['playerSpeedBoost'] ?? 1.0) * intensity;
          break;
        case ComboEffect.berserker:
          multiplier *=
              (comboData?.properties['speedBoost'] ?? 1.0) * intensity;
          break;
        case ComboEffect.godMode:
          multiplier *=
              (comboData?.properties['speedBoost'] ?? 1.0) * intensity;
          break;
        default:
          break;
      }
    }

    return multiplier;
  }

  int getEffectiveScoreMultiplier() {
    int multiplier = 1;

    for (final combo in _activeCombos) {
      final comboData = PowerUpCombo.combos[combo];
      final intensity = _comboIntensities[combo] ?? 1.0;

      switch (combo) {
        case ComboEffect.goldRush:
          multiplier =
              (multiplier *
                      (comboData?.properties['baseMultiplier'] ?? 1) *
                      intensity)
                  .round();
          break;
        case ComboEffect.treasureHunter:
          multiplier =
              (multiplier *
                      (comboData?.properties['scoreMultiplier'] ?? 1) *
                      intensity)
                  .round();
          break;
        case ComboEffect.godMode:
          multiplier =
              (multiplier *
                      (comboData?.properties['scoreMultiplier'] ?? 1) *
                      intensity)
                  .round();
          break;
        default:
          break;
      }
    }

    return multiplier;
  }

  double getEffectiveTimeScale() {
    double timeScale = 1.0;

    for (final combo in _activeCombos) {
      final comboData = PowerUpCombo.combos[combo];
      final intensity = _comboIntensities[combo] ?? 1.0;

      switch (combo) {
        case ComboEffect.timeWarp:
          timeScale = math.min(
            timeScale,
            (comboData?.properties['timeScale'] ?? 1.0) * intensity,
          );
          break;
        case ComboEffect.ghostMode:
          timeScale = math.min(
            timeScale,
            (comboData?.properties['slowMotionFactor'] ?? 1.0) * intensity,
          );
          break;
        default:
          break;
      }
    }

    return timeScale;
  }

  bool hasInvincibility() {
    return _activeCombos.any(
      (combo) => [
        ComboEffect.lightSpeed,
        ComboEffect.treasureHunter,
        ComboEffect.ghostMode,
        ComboEffect.berserker,
        ComboEffect.godMode,
      ].contains(combo),
    );
  }

  bool hasPhaseThrough() {
    return _activeCombos.contains(ComboEffect.ghostMode);
  }

  bool hasReality() {
    return _activeCombos.contains(ComboEffect.godMode);
  }

  double getMagnetRadius() {
    for (final combo in _activeCombos) {
      if (combo == ComboEffect.magnetField) {
        final comboData = PowerUpCombo.combos[combo];
        final intensity = _comboIntensities[combo] ?? 1.0;
        return (comboData?.properties['magnetRadius'] ?? 0.0) * intensity;
      }
    }
    return 0.0;
  }

  // Visual effect properties

  List<Color> getActiveComboColors() {
    return _activeCombos
        .map((combo) => PowerUpCombo.combos[combo]?.color ?? Colors.white)
        .toList();
  }

  double getScreenShakeIntensity() {
    double maxIntensity = 1.0;

    for (final combo in _activeCombos) {
      final comboData = PowerUpCombo.combos[combo];
      final comboIntensity = _comboIntensities[combo] ?? 1.0;

      if (combo == ComboEffect.berserker) {
        final berserkerIntensity =
            (comboData?.properties['screenShakeIntensity'] ?? 1.0) *
            comboIntensity;
        maxIntensity = math.max(maxIntensity, berserkerIntensity);
      }
    }

    return maxIntensity;
  }

  Map<String, dynamic> getVisualEffectProperties() {
    final properties = <String, dynamic>{};

    for (final combo in _activeCombos) {
      final comboData = PowerUpCombo.combos[combo];
      if (comboData != null) {
        properties.addAll(comboData.properties);
      }
    }

    return properties;
  }
}

// Extension methods for easier integration
extension PowerUpComboExtensions on List<PowerUpType> {
  ComboEffect? findBestCombo() {
    return PowerUpCombo.findAvailableCombo(this);
  }

  List<ComboEffect> findAllCombos() {
    return PowerUpCombo.findAllAvailableCombos(this);
  }
}
