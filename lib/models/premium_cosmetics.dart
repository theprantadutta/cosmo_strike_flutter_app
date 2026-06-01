import 'package:flutter/material.dart';

enum SnakeSkinType {
  classic,
  golden,
  rainbow,
  galaxy,
  dragon,
  electric,
  fire,
  ice,
  shadow,
  neon,
  crystal,
  cosmic;

  String get id => name;

  String get displayName {
    switch (this) {
      case SnakeSkinType.classic:
        return 'Classic';
      case SnakeSkinType.golden:
        return 'Golden Snake';
      case SnakeSkinType.rainbow:
        return 'Rainbow Snake';
      case SnakeSkinType.galaxy:
        return 'Galaxy Snake';
      case SnakeSkinType.dragon:
        return 'Dragon Snake';
      case SnakeSkinType.electric:
        return 'Electric Snake';
      case SnakeSkinType.fire:
        return 'Fire Snake';
      case SnakeSkinType.ice:
        return 'Ice Snake';
      case SnakeSkinType.shadow:
        return 'Shadow Snake';
      case SnakeSkinType.neon:
        return 'Neon Snake';
      case SnakeSkinType.crystal:
        return 'Crystal Snake';
      case SnakeSkinType.cosmic:
        return 'Cosmic Snake';
    }
  }

  String get description {
    switch (this) {
      case SnakeSkinType.classic:
        return 'The original snake appearance';
      case SnakeSkinType.golden:
        return 'Gleaming gold snake that shines with every move';
      case SnakeSkinType.rainbow:
        return 'A colorful snake that shifts through rainbow colors';
      case SnakeSkinType.galaxy:
        return 'Cosmic snake with starry patterns';
      case SnakeSkinType.dragon:
        return 'Fierce dragon-scaled snake with mystical powers';
      case SnakeSkinType.electric:
        return 'Crackling with electric energy';
      case SnakeSkinType.fire:
        return 'Burning bright with fiery patterns';
      case SnakeSkinType.ice:
        return 'Frozen beauty with crystalline effects';
      case SnakeSkinType.shadow:
        return 'Dark and mysterious shadow snake';
      case SnakeSkinType.neon:
        return 'Glowing with cyberpunk neon lights';
      case SnakeSkinType.crystal:
        return 'Translucent crystal snake with prismatic effects';
      case SnakeSkinType.cosmic:
        return 'Snake made of stardust and cosmic matter';
    }
  }

  bool get isPremium {
    return this != SnakeSkinType.classic;
  }

  double get price {
    switch (this) {
      case SnakeSkinType.classic:
        return 0.0;
      case SnakeSkinType.golden:
      case SnakeSkinType.fire:
      case SnakeSkinType.ice:
      case SnakeSkinType.electric:
        return 1.99;
      case SnakeSkinType.rainbow:
      case SnakeSkinType.neon:
      case SnakeSkinType.shadow:
        return 2.99;
      case SnakeSkinType.galaxy:
      case SnakeSkinType.crystal:
      case SnakeSkinType.cosmic:
        return 3.99;
      case SnakeSkinType.dragon:
        return 4.99;
    }
  }

  List<Color> get colors {
    switch (this) {
      case SnakeSkinType.classic:
        return [const Color(0xFF9BBD0F)];
      case SnakeSkinType.golden:
        return [const Color(0xFFFFD700), const Color(0xFFB8860B)];
      case SnakeSkinType.rainbow:
        return [
          const Color(0xFFFF0000),
          const Color(0xFFFF8000),
          const Color(0xFFFFFF00),
          const Color(0xFF80FF00),
          const Color(0xFF00FF00),
          const Color(0xFF00FF80),
          const Color(0xFF00FFFF),
          const Color(0xFF0080FF),
          const Color(0xFF0000FF),
          const Color(0xFF8000FF),
          const Color(0xFFFF00FF),
          const Color(0xFFFF0080),
        ];
      case SnakeSkinType.galaxy:
        return [
          const Color(0xFF1A0033),
          const Color(0xFF4B0082),
          const Color(0xFF9932CC),
          const Color(0xFFBA55D3),
        ];
      case SnakeSkinType.dragon:
        return [
          const Color(0xFF8B0000),
          const Color(0xFFDC143C),
          const Color(0xFFFF6347),
          const Color(0xFFFFD700),
        ];
      case SnakeSkinType.electric:
        return [
          const Color(0xFF00FFFF),
          const Color(0xFF87CEEB),
          const Color(0xFF4169E1),
          const Color(0xFF0000FF),
        ];
      case SnakeSkinType.fire:
        return [
          const Color(0xFFFF4500),
          const Color(0xFFFF6347),
          const Color(0xFFFF8C00),
          const Color(0xFFFFD700),
        ];
      case SnakeSkinType.ice:
        return [
          const Color(0xFFB0E0E6),
          const Color(0xFF87CEEB),
          const Color(0xFF4682B4),
          const Color(0xFF1E90FF),
        ];
      case SnakeSkinType.shadow:
        return [
          const Color(0xFF2F2F2F),
          const Color(0xFF404040),
          const Color(0xFF696969),
          const Color(0xFF808080),
        ];
      case SnakeSkinType.neon:
        return [
          const Color(0xFF00FFFF),
          const Color(0xFF39FF14),
          const Color(0xFFFF1493),
          const Color(0xFFFFFF00),
        ];
      case SnakeSkinType.crystal:
        return [
          const Color(0xFFE6E6FA),
          const Color(0xFFDDA0DD),
          const Color(0xFFBA55D3),
          const Color(0xFF9370DB),
        ];
      case SnakeSkinType.cosmic:
        return [
          const Color(0xFF191970),
          const Color(0xFF4B0082),
          const Color(0xFF8A2BE2),
          const Color(0xFFDA70D6),
        ];
    }
  }

  String get icon {
    switch (this) {
      case SnakeSkinType.classic:
        return '🐍';
      case SnakeSkinType.golden:
        return '✨';
      case SnakeSkinType.rainbow:
        return '🌈';
      case SnakeSkinType.galaxy:
        return '🌌';
      case SnakeSkinType.dragon:
        return '🐉';
      case SnakeSkinType.electric:
        return '⚡';
      case SnakeSkinType.fire:
        return '🔥';
      case SnakeSkinType.ice:
        return '❄️';
      case SnakeSkinType.shadow:
        return '🌑';
      case SnakeSkinType.neon:
        return '💡';
      case SnakeSkinType.crystal:
        return '💎';
      case SnakeSkinType.cosmic:
        return '🌟';
    }
  }
}

enum TrailEffectType {
  none,
  particle,
  glow,
  rainbow,
  fire,
  electric,
  star,
  cosmic,
  neon,
  shadow,
  crystal,
  dragon;

  String get id => this == TrailEffectType.none ? 'none' : 'trail_$name';

  String get displayName {
    switch (this) {
      case TrailEffectType.none:
        return 'No Trail';
      case TrailEffectType.particle:
        return 'Particle Trail';
      case TrailEffectType.glow:
        return 'Glow Trail';
      case TrailEffectType.rainbow:
        return 'Rainbow Trail';
      case TrailEffectType.fire:
        return 'Fire Trail';
      case TrailEffectType.electric:
        return 'Electric Trail';
      case TrailEffectType.star:
        return 'Star Trail';
      case TrailEffectType.cosmic:
        return 'Cosmic Trail';
      case TrailEffectType.neon:
        return 'Neon Trail';
      case TrailEffectType.shadow:
        return 'Shadow Trail';
      case TrailEffectType.crystal:
        return 'Crystal Trail';
      case TrailEffectType.dragon:
        return 'Dragon Trail';
    }
  }

  String get description {
    switch (this) {
      case TrailEffectType.none:
        return 'Clean snake with no trail effects';
      case TrailEffectType.particle:
        return 'Leaves a trail of sparkling particles';
      case TrailEffectType.glow:
        return 'Glowing trail that fades behind the snake';
      case TrailEffectType.rainbow:
        return 'Colorful rainbow trail effect';
      case TrailEffectType.fire:
        return 'Blazing fire trail with ember particles';
      case TrailEffectType.electric:
        return 'Crackling electric trail with lightning effects';
      case TrailEffectType.star:
        return 'Twinkling stars follow the snake\'s path';
      case TrailEffectType.cosmic:
        return 'Cosmic dust and nebula effects';
      case TrailEffectType.neon:
        return 'Bright neon glow with cyberpunk style';
      case TrailEffectType.shadow:
        return 'Dark shadow trail with smoky effects';
      case TrailEffectType.crystal:
        return 'Crystalline shards that fade away';
      case TrailEffectType.dragon:
        return 'Mystical dragon breath trail';
    }
  }

  bool get isPremium {
    return this != TrailEffectType.none;
  }

  double get price {
    switch (this) {
      case TrailEffectType.none:
        return 0.0;
      case TrailEffectType.particle:
      case TrailEffectType.glow:
        return 0.99;
      case TrailEffectType.rainbow:
      case TrailEffectType.neon:
      case TrailEffectType.shadow:
        return 1.99;
      case TrailEffectType.fire:
      case TrailEffectType.electric:
      case TrailEffectType.star:
        return 2.99;
      case TrailEffectType.cosmic:
      case TrailEffectType.crystal:
      case TrailEffectType.dragon:
        return 3.99;
    }
  }

  List<Color> get colors {
    switch (this) {
      case TrailEffectType.none:
        return [];
      case TrailEffectType.particle:
        return [const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)];
      case TrailEffectType.glow:
        return [const Color(0xFF00FFFF), const Color(0xFF87CEEB)];
      case TrailEffectType.rainbow:
        return [
          const Color(0xFFFF0000),
          const Color(0xFFFFFF00),
          const Color(0xFF00FF00),
          const Color(0xFF00FFFF),
          const Color(0xFF0000FF),
          const Color(0xFFFF00FF),
        ];
      case TrailEffectType.fire:
        return [const Color(0xFFFF4500), const Color(0xFFFFD700)];
      case TrailEffectType.electric:
        return [const Color(0xFF00FFFF), const Color(0xFF0000FF)];
      case TrailEffectType.star:
        return [const Color(0xFFFFFFFF), const Color(0xFFFFD700)];
      case TrailEffectType.cosmic:
        return [const Color(0xFF4B0082), const Color(0xFFDA70D6)];
      case TrailEffectType.neon:
        return [const Color(0xFF39FF14), const Color(0xFFFF1493)];
      case TrailEffectType.shadow:
        return [const Color(0xFF2F2F2F), const Color(0xFF000000)];
      case TrailEffectType.crystal:
        return [const Color(0xFFBA55D3), const Color(0xFFE6E6FA)];
      case TrailEffectType.dragon:
        return [const Color(0xFF8B0000), const Color(0xFFFFD700)];
    }
  }

  String get icon {
    switch (this) {
      case TrailEffectType.none:
        return '🚫';
      case TrailEffectType.particle:
        return '✨';
      case TrailEffectType.glow:
        return '🌟';
      case TrailEffectType.rainbow:
        return '🌈';
      case TrailEffectType.fire:
        return '🔥';
      case TrailEffectType.electric:
        return '⚡';
      case TrailEffectType.star:
        return '⭐';
      case TrailEffectType.cosmic:
        return '🌌';
      case TrailEffectType.neon:
        return '💡';
      case TrailEffectType.shadow:
        return '🌑';
      case TrailEffectType.crystal:
        return '💎';
      case TrailEffectType.dragon:
        return '🐉';
    }
  }
}

class SnakeCosmetics {
  final SnakeSkinType skin;
  final TrailEffectType trail;

  const SnakeCosmetics({required this.skin, required this.trail});

  SnakeCosmetics copyWith({SnakeSkinType? skin, TrailEffectType? trail}) {
    return SnakeCosmetics(skin: skin ?? this.skin, trail: trail ?? this.trail);
  }

  bool get isPremium => skin.isPremium || trail.isPremium;

  double get totalPrice => skin.price + trail.price;

  Map<String, dynamic> toJson() {
    return {'skin': skin.id, 'trail': trail.id};
  }

  factory SnakeCosmetics.fromJson(Map<String, dynamic> json) {
    return SnakeCosmetics(
      skin: SnakeSkinType.values.firstWhere(
        (s) => s.id == json['skin'],
        orElse: () => SnakeSkinType.classic,
      ),
      trail: TrailEffectType.values.firstWhere(
        (t) => t.id == json['trail'],
        orElse: () => TrailEffectType.none,
      ),
    );
  }

  static const SnakeCosmetics defaultCosmetics = SnakeCosmetics(
    skin: SnakeSkinType.classic,
    trail: TrailEffectType.none,
  );
}

class CosmeticBundle {
  final String id;
  final String name;
  final String description;
  final List<SnakeSkinType> skins;
  final List<TrailEffectType> trails;
  final double bundlePrice;
  final String icon;

  const CosmeticBundle({
    required this.id,
    required this.name,
    required this.description,
    required this.skins,
    required this.trails,
    required this.bundlePrice,
    required this.icon,
  });

  /// Computed from the sum of individual skin and trail prices.
  double get originalPrice {
    double total = 0;
    for (final skin in skins) {
      total += skin.price;
    }
    for (final trail in trails) {
      total += trail.price;
    }
    return total;
  }

  double get savings => originalPrice - bundlePrice;
  double get savingsPercentage =>
      originalPrice > 0 ? (savings / originalPrice) * 100 : 0;

  static const List<CosmeticBundle> availableBundles = [
    CosmeticBundle(
      id: 'starter_pack',
      name: 'Starter Pack',
      description: 'Perfect for new premium players',
      skins: [SnakeSkinType.golden, SnakeSkinType.fire],
      trails: [TrailEffectType.particle, TrailEffectType.glow],
      bundlePrice: 3.99,
      icon: '🎁',
    ),
    CosmeticBundle(
      id: 'elemental_pack',
      name: 'Elemental Pack',
      description: 'Master the elements with style',
      skins: [SnakeSkinType.fire, SnakeSkinType.ice, SnakeSkinType.electric],
      trails: [TrailEffectType.fire, TrailEffectType.electric],
      bundlePrice: 7.99,
      icon: '🌊',
    ),
    CosmeticBundle(
      id: 'cosmic_collection',
      name: 'Cosmic Collection',
      description: 'Explore the universe in style',
      skins: [
        SnakeSkinType.galaxy,
        SnakeSkinType.cosmic,
        SnakeSkinType.crystal,
      ],
      trails: [
        TrailEffectType.cosmic,
        TrailEffectType.star,
        TrailEffectType.crystal,
      ],
      bundlePrice: 14.99,
      icon: '🌌',
    ),
    CosmeticBundle(
      id: 'ultimate_collection',
      name: 'Ultimate Collection',
      description: 'Every premium cosmetic item',
      skins: [
        SnakeSkinType.golden,
        SnakeSkinType.rainbow,
        SnakeSkinType.galaxy,
        SnakeSkinType.dragon,
        SnakeSkinType.electric,
        SnakeSkinType.fire,
        SnakeSkinType.ice,
        SnakeSkinType.shadow,
        SnakeSkinType.neon,
        SnakeSkinType.crystal,
        SnakeSkinType.cosmic,
      ],
      trails: [
        TrailEffectType.particle,
        TrailEffectType.glow,
        TrailEffectType.rainbow,
        TrailEffectType.fire,
        TrailEffectType.electric,
        TrailEffectType.star,
        TrailEffectType.cosmic,
        TrailEffectType.neon,
        TrailEffectType.shadow,
        TrailEffectType.crystal,
        TrailEffectType.dragon,
      ],
      bundlePrice: 29.99,
      icon: '👑',
    ),
  ];
}
