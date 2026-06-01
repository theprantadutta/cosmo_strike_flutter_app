import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/models/power_up.dart';
import 'package:cosmo_strike_flutter_app/models/position.dart';

enum PremiumPowerUpType {
  // Mega versions of existing power-ups (2x duration, enhanced effects)
  megaSpeedBoost,
  megaInvincibility,
  megaScoreMultiplier,
  megaSlowMotion,

  // Exclusive premium power-ups
  teleport,
  sizeReducer,
  scoreShield,
  comboMultiplier,
  timeWarp,
  magneticFood,
  ghostMode,
  doubleTrouble,
  luckyCharm,
  powerSurge;

  String get id => name;

  String get displayName {
    switch (this) {
      case PremiumPowerUpType.megaSpeedBoost:
        return 'Mega Speed Boost';
      case PremiumPowerUpType.megaInvincibility:
        return 'Mega Invincibility';
      case PremiumPowerUpType.megaScoreMultiplier:
        return 'Mega Score Multiplier';
      case PremiumPowerUpType.megaSlowMotion:
        return 'Mega Slow Motion';
      case PremiumPowerUpType.teleport:
        return 'Teleport';
      case PremiumPowerUpType.sizeReducer:
        return 'Size Reducer';
      case PremiumPowerUpType.scoreShield:
        return 'Score Shield';
      case PremiumPowerUpType.comboMultiplier:
        return 'Combo Multiplier';
      case PremiumPowerUpType.timeWarp:
        return 'Time Warp';
      case PremiumPowerUpType.magneticFood:
        return 'Magnetic Food';
      case PremiumPowerUpType.ghostMode:
        return 'Ghost Mode';
      case PremiumPowerUpType.doubleTrouble:
        return 'Double Trouble';
      case PremiumPowerUpType.luckyCharm:
        return 'Lucky Charm';
      case PremiumPowerUpType.powerSurge:
        return 'Power Surge';
    }
  }

  String get description {
    switch (this) {
      case PremiumPowerUpType.megaSpeedBoost:
        return 'Extreme speed boost for 20 seconds with trail effects';
      case PremiumPowerUpType.megaInvincibility:
        return 'Complete invincibility for 16 seconds with golden glow';
      case PremiumPowerUpType.megaScoreMultiplier:
        return 'Triple score multiplier for 30 seconds';
      case PremiumPowerUpType.megaSlowMotion:
        return 'Ultra slow motion for 24 seconds with enhanced precision';
      case PremiumPowerUpType.teleport:
        return 'Instantly teleport to a safe random location';
      case PremiumPowerUpType.sizeReducer:
        return 'Temporarily shrink snake by 50% for 15 seconds';
      case PremiumPowerUpType.scoreShield:
        return 'Protect score from loss on crash for 3 attempts';
      case PremiumPowerUpType.comboMultiplier:
        return 'Each food eaten increases multiplier (max 10x) for 20 seconds';
      case PremiumPowerUpType.timeWarp:
        return 'Slow down everything except your snake for 12 seconds';
      case PremiumPowerUpType.magneticFood:
        return 'Food automatically moves toward you for 25 seconds';
      case PremiumPowerUpType.ghostMode:
        return 'Phase through walls and yourself for 10 seconds';
      case PremiumPowerUpType.doubleTrouble:
        return 'Spawn a second snake that copies your moves for 15 seconds';
      case PremiumPowerUpType.luckyCharm:
        return 'Double chance of spawning power-ups for 30 seconds';
      case PremiumPowerUpType.powerSurge:
        return 'Activate all basic power-ups simultaneously for 8 seconds';
    }
  }

  String get icon {
    switch (this) {
      case PremiumPowerUpType.megaSpeedBoost:
        return '🚀';
      case PremiumPowerUpType.megaInvincibility:
        return '🛡️';
      case PremiumPowerUpType.megaScoreMultiplier:
        return '💎';
      case PremiumPowerUpType.megaSlowMotion:
        return '🕰️';
      case PremiumPowerUpType.teleport:
        return '⚡';
      case PremiumPowerUpType.sizeReducer:
        return '🔍';
      case PremiumPowerUpType.scoreShield:
        return '🔰';
      case PremiumPowerUpType.comboMultiplier:
        return '🔥';
      case PremiumPowerUpType.timeWarp:
        return '⏳';
      case PremiumPowerUpType.magneticFood:
        return '🧲';
      case PremiumPowerUpType.ghostMode:
        return '👻';
      case PremiumPowerUpType.doubleTrouble:
        return '🐍';
      case PremiumPowerUpType.luckyCharm:
        return '🍀';
      case PremiumPowerUpType.powerSurge:
        return '⚡';
    }
  }

  Color get color {
    switch (this) {
      case PremiumPowerUpType.megaSpeedBoost:
        return Colors.orange;
      case PremiumPowerUpType.megaInvincibility:
        return Colors.amber;
      case PremiumPowerUpType.megaScoreMultiplier:
        return Colors.green;
      case PremiumPowerUpType.megaSlowMotion:
        return Colors.indigo;
      case PremiumPowerUpType.teleport:
        return Colors.cyan;
      case PremiumPowerUpType.sizeReducer:
        return Colors.pink;
      case PremiumPowerUpType.scoreShield:
        return Colors.teal;
      case PremiumPowerUpType.comboMultiplier:
        return Colors.red;
      case PremiumPowerUpType.timeWarp:
        return Colors.deepPurple;
      case PremiumPowerUpType.magneticFood:
        return Colors.blueGrey;
      case PremiumPowerUpType.ghostMode:
        return Colors.grey;
      case PremiumPowerUpType.doubleTrouble:
        return Colors.lime;
      case PremiumPowerUpType.luckyCharm:
        return Colors.green;
      case PremiumPowerUpType.powerSurge:
        return Colors.amber;
    }
  }

  Duration get duration {
    switch (this) {
      case PremiumPowerUpType.megaSpeedBoost:
        return const Duration(seconds: 20);
      case PremiumPowerUpType.megaInvincibility:
        return const Duration(seconds: 16);
      case PremiumPowerUpType.megaScoreMultiplier:
        return const Duration(seconds: 30);
      case PremiumPowerUpType.megaSlowMotion:
        return const Duration(seconds: 24);
      case PremiumPowerUpType.teleport:
        return Duration.zero; // Instant effect
      case PremiumPowerUpType.sizeReducer:
        return const Duration(seconds: 15);
      case PremiumPowerUpType.scoreShield:
        return const Duration(minutes: 5); // Lasts 5 minutes or 3 crashes
      case PremiumPowerUpType.comboMultiplier:
        return const Duration(seconds: 20);
      case PremiumPowerUpType.timeWarp:
        return const Duration(seconds: 12);
      case PremiumPowerUpType.magneticFood:
        return const Duration(seconds: 25);
      case PremiumPowerUpType.ghostMode:
        return const Duration(seconds: 10);
      case PremiumPowerUpType.doubleTrouble:
        return const Duration(seconds: 15);
      case PremiumPowerUpType.luckyCharm:
        return const Duration(seconds: 30);
      case PremiumPowerUpType.powerSurge:
        return const Duration(seconds: 8);
    }
  }

  int get rarity {
    switch (this) {
      case PremiumPowerUpType.megaSpeedBoost:
      case PremiumPowerUpType.megaInvincibility:
      case PremiumPowerUpType.megaScoreMultiplier:
      case PremiumPowerUpType.megaSlowMotion:
        return 2; // Uncommon (mega versions)
      case PremiumPowerUpType.teleport:
      case PremiumPowerUpType.sizeReducer:
      case PremiumPowerUpType.magneticFood:
      case PremiumPowerUpType.luckyCharm:
        return 1; // Rare
      case PremiumPowerUpType.scoreShield:
      case PremiumPowerUpType.comboMultiplier:
      case PremiumPowerUpType.timeWarp:
      case PremiumPowerUpType.ghostMode:
        return 1; // Rare
      case PremiumPowerUpType.doubleTrouble:
      case PremiumPowerUpType.powerSurge:
        return 0; // Ultra rare
    }
  }

  bool get isInstantEffect {
    return this == PremiumPowerUpType.teleport;
  }

  bool get isStackable {
    // Some power-ups can be stacked with others
    switch (this) {
      case PremiumPowerUpType.scoreShield:
      case PremiumPowerUpType.luckyCharm:
      case PremiumPowerUpType.sizeReducer:
        return true;
      default:
        return false;
    }
  }

  double get spawnChance {
    // Base spawn chance for premium power-ups (lower than regular ones)
    switch (rarity) {
      case 0: // Ultra rare
        return 0.005; // 0.5%
      case 1: // Rare
        return 0.02; // 2%
      case 2: // Uncommon
        return 0.03; // 3%
      default:
        return 0.01; // 1%
    }
  }
}

class PremiumPowerUp extends PowerUp {
  final PremiumPowerUpType premiumType;
  final bool hasVisualEffect;
  final bool hasSoundEffect;
  final List<Color> glowColors;

  PremiumPowerUp({
    required super.position,
    required this.premiumType,
    super.createdAt,
    this.hasVisualEffect = true,
    this.hasSoundEffect = true,
    List<Color>? glowColors,
  }) : glowColors = glowColors ?? [premiumType.color],
       super(
         type: _mapToBasicType(
           premiumType,
         ), // Map to basic type for compatibility
       );

  static PowerUpType _mapToBasicType(PremiumPowerUpType premiumType) {
    // Map premium types to basic types for backward compatibility
    switch (premiumType) {
      case PremiumPowerUpType.megaSpeedBoost:
        return PowerUpType.speedBoost;
      case PremiumPowerUpType.megaInvincibility:
        return PowerUpType.invincibility;
      case PremiumPowerUpType.megaScoreMultiplier:
        return PowerUpType.scoreMultiplier;
      case PremiumPowerUpType.megaSlowMotion:
        return PowerUpType.slowMotion;
      default:
        return PowerUpType.speedBoost; // Default fallback
    }
  }

  static PremiumPowerUp? generateRandomPremium(
    int boardWidth,
    int boardHeight,
    snake, {
    foodPosition,
    bool premiumOnly = false,
  }) {
    final random = Random();

    // Check if any premium power-up should spawn
    double totalChance = 0.0;
    for (final type in PremiumPowerUpType.values) {
      totalChance += type.spawnChance;
    }

    if (!premiumOnly && random.nextDouble() > totalChance) {
      return null; // No premium power-up spawned
    }

    // Select which premium power-up to spawn
    final randomValue = random.nextDouble() * totalChance;
    double currentChance = 0.0;

    for (final type in PremiumPowerUpType.values) {
      currentChance += type.spawnChance;
      if (randomValue <= currentChance) {
        final position = PowerUp.generateRandomPosition(
          boardWidth,
          boardHeight,
          snake,
          foodPosition: foodPosition,
        );

        return PremiumPowerUp(position: position, premiumType: type);
      }
    }

    return null;
  }

  @override
  double get pulsePhase {
    // Enhanced pulsing effect for premium power-ups
    final secondsSinceCreated =
        DateTime.now().difference(createdAt).inMilliseconds / 1000.0;
    return (sin(secondsSinceCreated * 4.0) + 1.0) / 2.0; // Faster pulse
  }

  double get glowIntensity {
    // Intensity of the glow effect (0.0 to 1.0)
    final secondsSinceCreated =
        DateTime.now().difference(createdAt).inMilliseconds / 1000.0;
    return (sin(secondsSinceCreated * 2.0) * 0.3 + 0.7).clamp(0.4, 1.0);
  }

  List<Offset> get sparklePositions {
    // Generate sparkle effect positions around the power-up
    final sparkles = <Offset>[];

    for (int i = 0; i < 6; i++) {
      final angle =
          (i * pi * 2 / 6) + (DateTime.now().millisecondsSinceEpoch / 1000.0);
      final radius = 15.0 + sin(angle * 2) * 5.0;
      final x = position.x + cos(angle) * radius;
      final y = position.y + sin(angle) * radius;
      sparkles.add(Offset(x, y));
    }

    return sparkles;
  }

  Map<String, dynamic> toJson() {
    return {
      'position': {'x': position.x, 'y': position.y},
      'premium_type': premiumType.id,
      'created_at': createdAt.toIso8601String(),
      'has_visual_effect': hasVisualEffect,
      'has_sound_effect': hasSoundEffect,
      'glow_colors': glowColors.map((c) => c.toARGB32()).toList(),
    };
  }

  factory PremiumPowerUp.fromJson(Map<String, dynamic> json) {
    final premiumType = PremiumPowerUpType.values.firstWhere(
      (t) => t.id == json['premium_type'],
      orElse: () => PremiumPowerUpType.megaSpeedBoost,
    );

    final glowColors =
        (json['glow_colors'] as List<dynamic>?)
            ?.map((c) => Color(c as int))
            .toList() ??
        [premiumType.color];

    return PremiumPowerUp(
      position: Position.fromJson(json['position']),
      premiumType: premiumType,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      hasVisualEffect: json['has_visual_effect'] ?? true,
      hasSoundEffect: json['has_sound_effect'] ?? true,
      glowColors: glowColors,
    );
  }
}

class PremiumActivePowerUp extends ActivePowerUp {
  final PremiumPowerUpType premiumType;
  final Map<String, dynamic> additionalData;

  PremiumActivePowerUp({
    required this.premiumType,
    super.activatedAt,
    super.duration,
    this.additionalData = const {},
  }) : super(type: _mapToBasicType(premiumType));

  static PowerUpType _mapToBasicType(PremiumPowerUpType premiumType) {
    switch (premiumType) {
      case PremiumPowerUpType.megaSpeedBoost:
        return PowerUpType.speedBoost;
      case PremiumPowerUpType.megaInvincibility:
        return PowerUpType.invincibility;
      case PremiumPowerUpType.megaScoreMultiplier:
        return PowerUpType.scoreMultiplier;
      case PremiumPowerUpType.megaSlowMotion:
        return PowerUpType.slowMotion;
      default:
        return PowerUpType.speedBoost;
    }
  }

  // Specific getters for different premium power-up effects
  int get comboMultiplier => additionalData['combo_multiplier'] ?? 1;
  int get crashesRemaining => additionalData['crashes_remaining'] ?? 0;
  bool get isSizeReduced =>
      premiumType == PremiumPowerUpType.sizeReducer && !isExpired;
  bool get hasDoubleSnake =>
      premiumType == PremiumPowerUpType.doubleTrouble && !isExpired;
  bool get isMagneticActive =>
      premiumType == PremiumPowerUpType.magneticFood && !isExpired;

  PremiumActivePowerUp copyWith({Map<String, dynamic>? additionalData}) {
    return PremiumActivePowerUp(
      premiumType: premiumType,
      activatedAt: activatedAt,
      duration: duration,
      additionalData: additionalData ?? this.additionalData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'premium_type': premiumType.id,
      'activated_at': activatedAt.toIso8601String(),
      'duration_seconds': duration.inSeconds,
      'additional_data': additionalData,
    };
  }

  factory PremiumActivePowerUp.fromJson(Map<String, dynamic> json) {
    final premiumType = PremiumPowerUpType.values.firstWhere(
      (t) => t.id == json['premium_type'],
      orElse: () => PremiumPowerUpType.megaSpeedBoost,
    );

    return PremiumActivePowerUp(
      premiumType: premiumType,
      activatedAt: DateTime.parse(json['activated_at']),
      duration: Duration(seconds: json['duration_seconds']),
      additionalData: json['additional_data'] ?? {},
    );
  }
}

class PowerUpBundle {
  final String id;
  final String name;
  final String description;
  final List<PremiumPowerUpType> powerUps;
  final double originalPrice;
  final double bundlePrice;
  final String icon;

  const PowerUpBundle({
    required this.id,
    required this.name,
    required this.description,
    required this.powerUps,
    required this.originalPrice,
    required this.bundlePrice,
    required this.icon,
  });

  double get savings => originalPrice - bundlePrice;
  double get savingsPercentage => (savings / originalPrice) * 100;

  static const List<PowerUpBundle> availableBundles = [
    // bundlePrice values MUST match ProductCatalog.PowerUpBundles on the
    // backend — server validates against its own catalog and rejects any
    // tampered request.
    PowerUpBundle(
      id: 'mega_pack',
      name: 'Mega Power Pack',
      description: 'Enhanced versions of classic power-ups',
      powerUps: [
        PremiumPowerUpType.megaSpeedBoost,
        PremiumPowerUpType.megaInvincibility,
        PremiumPowerUpType.megaScoreMultiplier,
        PremiumPowerUpType.megaSlowMotion,
      ],
      originalPrice: 11000, // 4 mega power-ups at ~2,750 coins each individually
      bundlePrice: 8000,
      icon: '⚡',
    ),
    PowerUpBundle(
      id: 'tactical_pack',
      name: 'Tactical Power Pack',
      description: 'Strategic power-ups for skilled players',
      powerUps: [
        PremiumPowerUpType.teleport,
        PremiumPowerUpType.sizeReducer,
        PremiumPowerUpType.scoreShield,
        PremiumPowerUpType.ghostMode,
      ],
      originalPrice: 16000,
      bundlePrice: 12000,
      icon: '🎯',
    ),
    PowerUpBundle(
      id: 'ultimate_pack',
      name: 'Ultimate Power Pack',
      description: 'Every premium power-up available',
      powerUps: PremiumPowerUpType.values,
      originalPrice: 35000, // Sum of all individual premium prices
      bundlePrice: 25000,
      icon: '👑',
    ),
  ];
}
