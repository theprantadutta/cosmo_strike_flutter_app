import 'package:flutter/material.dart';

enum ShipSkinType {
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
      case ShipSkinType.classic:
        return 'Classic';
      case ShipSkinType.golden:
        return 'Golden Ship';
      case ShipSkinType.rainbow:
        return 'Rainbow Ship';
      case ShipSkinType.galaxy:
        return 'Galaxy Ship';
      case ShipSkinType.dragon:
        return 'Dragon Ship';
      case ShipSkinType.electric:
        return 'Electric Ship';
      case ShipSkinType.fire:
        return 'Fire Ship';
      case ShipSkinType.ice:
        return 'Ice Ship';
      case ShipSkinType.shadow:
        return 'Shadow Ship';
      case ShipSkinType.neon:
        return 'Neon Ship';
      case ShipSkinType.crystal:
        return 'Crystal Ship';
      case ShipSkinType.cosmic:
        return 'Cosmic Ship';
    }
  }

  String get description {
    switch (this) {
      case ShipSkinType.classic:
        return 'The original ship appearance';
      case ShipSkinType.golden:
        return 'Gleaming gold ship that shines with every move';
      case ShipSkinType.rainbow:
        return 'A colorful ship that shifts through rainbow colors';
      case ShipSkinType.galaxy:
        return 'Cosmic ship with starry patterns';
      case ShipSkinType.dragon:
        return 'Fierce dragon-scaled ship with mystical powers';
      case ShipSkinType.electric:
        return 'Crackling with electric energy';
      case ShipSkinType.fire:
        return 'Burning bright with fiery patterns';
      case ShipSkinType.ice:
        return 'Frozen beauty with crystalline effects';
      case ShipSkinType.shadow:
        return 'Dark and mysterious shadow ship';
      case ShipSkinType.neon:
        return 'Glowing with cyberpunk neon lights';
      case ShipSkinType.crystal:
        return 'Translucent crystal ship with prismatic effects';
      case ShipSkinType.cosmic:
        return 'Ship made of stardust and cosmic matter';
    }
  }

  bool get isPremium {
    return this != ShipSkinType.classic;
  }

  double get price {
    switch (this) {
      case ShipSkinType.classic:
        return 0.0;
      case ShipSkinType.golden:
      case ShipSkinType.fire:
      case ShipSkinType.ice:
      case ShipSkinType.electric:
        return 1.99;
      case ShipSkinType.rainbow:
      case ShipSkinType.neon:
      case ShipSkinType.shadow:
        return 2.99;
      case ShipSkinType.galaxy:
      case ShipSkinType.crystal:
      case ShipSkinType.cosmic:
        return 3.99;
      case ShipSkinType.dragon:
        return 4.99;
    }
  }

  List<Color> get colors {
    switch (this) {
      case ShipSkinType.classic:
        return [const Color(0xFF9BBD0F)];
      case ShipSkinType.golden:
        return [const Color(0xFFFFD700), const Color(0xFFB8860B)];
      case ShipSkinType.rainbow:
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
      case ShipSkinType.galaxy:
        return [
          const Color(0xFF1A0033),
          const Color(0xFF4B0082),
          const Color(0xFF9932CC),
          const Color(0xFFBA55D3),
        ];
      case ShipSkinType.dragon:
        return [
          const Color(0xFF8B0000),
          const Color(0xFFDC143C),
          const Color(0xFFFF6347),
          const Color(0xFFFFD700),
        ];
      case ShipSkinType.electric:
        return [
          const Color(0xFF00FFFF),
          const Color(0xFF87CEEB),
          const Color(0xFF4169E1),
          const Color(0xFF0000FF),
        ];
      case ShipSkinType.fire:
        return [
          const Color(0xFFFF4500),
          const Color(0xFFFF6347),
          const Color(0xFFFF8C00),
          const Color(0xFFFFD700),
        ];
      case ShipSkinType.ice:
        return [
          const Color(0xFFB0E0E6),
          const Color(0xFF87CEEB),
          const Color(0xFF4682B4),
          const Color(0xFF1E90FF),
        ];
      case ShipSkinType.shadow:
        return [
          const Color(0xFF2F2F2F),
          const Color(0xFF404040),
          const Color(0xFF696969),
          const Color(0xFF808080),
        ];
      case ShipSkinType.neon:
        return [
          const Color(0xFF00FFFF),
          const Color(0xFF39FF14),
          const Color(0xFFFF1493),
          const Color(0xFFFFFF00),
        ];
      case ShipSkinType.crystal:
        return [
          const Color(0xFFE6E6FA),
          const Color(0xFFDDA0DD),
          const Color(0xFFBA55D3),
          const Color(0xFF9370DB),
        ];
      case ShipSkinType.cosmic:
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
      case ShipSkinType.classic:
        return '🚀';
      case ShipSkinType.golden:
        return '✨';
      case ShipSkinType.rainbow:
        return '🌈';
      case ShipSkinType.galaxy:
        return '🌌';
      case ShipSkinType.dragon:
        return '🐉';
      case ShipSkinType.electric:
        return '⚡';
      case ShipSkinType.fire:
        return '🔥';
      case ShipSkinType.ice:
        return '❄️';
      case ShipSkinType.shadow:
        return '🌑';
      case ShipSkinType.neon:
        return '💡';
      case ShipSkinType.crystal:
        return '💎';
      case ShipSkinType.cosmic:
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
        return 'Clean ship with no trail effects';
      case TrailEffectType.particle:
        return 'Leaves a trail of sparkling particles';
      case TrailEffectType.glow:
        return 'Glowing trail that fades behind the ship';
      case TrailEffectType.rainbow:
        return 'Colorful rainbow trail effect';
      case TrailEffectType.fire:
        return 'Blazing fire trail with ember particles';
      case TrailEffectType.electric:
        return 'Crackling electric trail with lightning effects';
      case TrailEffectType.star:
        return 'Twinkling stars follow the ship\'s path';
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

class ShipCosmetics {
  final ShipSkinType skin;
  final TrailEffectType trail;

  const ShipCosmetics({required this.skin, required this.trail});

  ShipCosmetics copyWith({ShipSkinType? skin, TrailEffectType? trail}) {
    return ShipCosmetics(skin: skin ?? this.skin, trail: trail ?? this.trail);
  }

  bool get isPremium => skin.isPremium || trail.isPremium;

  double get totalPrice => skin.price + trail.price;

  Map<String, dynamic> toJson() {
    return {'skin': skin.id, 'trail': trail.id};
  }

  factory ShipCosmetics.fromJson(Map<String, dynamic> json) {
    return ShipCosmetics(
      skin: ShipSkinType.values.firstWhere(
        (s) => s.id == json['skin'],
        orElse: () => ShipSkinType.classic,
      ),
      trail: TrailEffectType.values.firstWhere(
        (t) => t.id == json['trail'],
        orElse: () => TrailEffectType.none,
      ),
    );
  }

  static const ShipCosmetics defaultCosmetics = ShipCosmetics(
    skin: ShipSkinType.classic,
    trail: TrailEffectType.none,
  );
}

class CosmeticBundle {
  final String id;
  final String name;
  final String description;
  final List<ShipSkinType> skins;
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
      skins: [ShipSkinType.golden, ShipSkinType.fire],
      trails: [TrailEffectType.particle, TrailEffectType.glow],
      bundlePrice: 3.99,
      icon: '🎁',
    ),
    CosmeticBundle(
      id: 'elemental_pack',
      name: 'Elemental Pack',
      description: 'Master the elements with style',
      skins: [ShipSkinType.fire, ShipSkinType.ice, ShipSkinType.electric],
      trails: [TrailEffectType.fire, TrailEffectType.electric],
      bundlePrice: 7.99,
      icon: '🌊',
    ),
    CosmeticBundle(
      id: 'cosmic_collection',
      name: 'Cosmic Collection',
      description: 'Explore the universe in style',
      skins: [
        ShipSkinType.galaxy,
        ShipSkinType.cosmic,
        ShipSkinType.crystal,
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
        ShipSkinType.golden,
        ShipSkinType.rainbow,
        ShipSkinType.galaxy,
        ShipSkinType.dragon,
        ShipSkinType.electric,
        ShipSkinType.fire,
        ShipSkinType.ice,
        ShipSkinType.shadow,
        ShipSkinType.neon,
        ShipSkinType.crystal,
        ShipSkinType.cosmic,
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
