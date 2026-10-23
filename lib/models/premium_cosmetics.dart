import 'package:flutter/painting.dart';

/// Hull decal pattern painted over a livery's tint (see
/// `lib/game/livery_decals.dart` for the geometry, shared by the in-game
/// [PlayerShip] render and the Armory preview).
enum LiveryDecal {
  /// Plain tint — no pattern.
  none,

  /// Twin racing stripes along the fuselage.
  stripe,

  /// Three forward-pointing chevrons across the wings.
  chevron,

  /// Two-tone diagonal split with a crisp edge line.
  split,

  /// Fine hex-mesh plating.
  hex,

  /// Animated light sweep running tail to nose.
  pulse,
}

/// Hull paint schemes sold in the Armory. [standard] is the free stock
/// paint; every other livery is a non-consumable whose store product ID is
/// `com.pranta.cosmostrike.<id>` (see `ProductIds`).
///
/// Persisted / synced as [id]. Old Drift rows, prefs and sync payloads may
/// still carry pre-3.2 skin IDs — always parse through [fromId], which
/// folds them onto the new catalog.
enum LiveryType {
  standard,
  aurum,
  vanta,
  redline,
  glacier,
  ionic,
  solstice,
  viridian,
  prism;

  /// Wire / persistence / product-suffix ID.
  String get id => this == LiveryType.standard ? 'standard' : 'livery_$name';

  String get displayName {
    switch (this) {
      case LiveryType.standard:
        return 'Standard Issue';
      case LiveryType.aurum:
        return 'Aurum';
      case LiveryType.vanta:
        return 'Vanta';
      case LiveryType.redline:
        return 'Redline';
      case LiveryType.glacier:
        return 'Glacier';
      case LiveryType.ionic:
        return 'Ionic';
      case LiveryType.solstice:
        return 'Solstice';
      case LiveryType.viridian:
        return 'Viridian';
      case LiveryType.prism:
        return 'Prism';
    }
  }

  String get description {
    switch (this) {
      case LiveryType.standard:
        return 'Factory graphite with the prism keel stripe.';
      case LiveryType.aurum:
        return 'Gold-leaf plating with twin racing stripes.';
      case LiveryType.vanta:
        return 'Light-eating matte black, cut by a cyan edge.';
      case LiveryType.redline:
        return 'Crimson hull with attack chevrons on the wings.';
      case LiveryType.glacier:
        return 'Ice-blue armour over hex-mesh plating.';
      case LiveryType.ionic:
        return 'Charged cyan hull with a violet pulse sweep.';
      case LiveryType.solstice:
        return 'Amber and pink, split on the diagonal.';
      case LiveryType.viridian:
        return 'Mint-to-teal finish with deep chevrons.';
      case LiveryType.prism:
        return 'The full prism, sweeping the hull end to end.';
    }
  }

  bool get isPremium => this != LiveryType.standard;

  /// USD fallback price (live store price wins when loaded).
  double get price {
    switch (this) {
      case LiveryType.standard:
        return 0.0;
      case LiveryType.aurum:
      case LiveryType.vanta:
      case LiveryType.redline:
        return 1.99;
      case LiveryType.glacier:
      case LiveryType.ionic:
      case LiveryType.solstice:
        return 2.99;
      case LiveryType.viridian:
        return 3.99;
      case LiveryType.prism:
        return 4.99;
    }
  }

  LiveryDecal get decal {
    switch (this) {
      case LiveryType.standard:
        return LiveryDecal.none;
      case LiveryType.aurum:
        return LiveryDecal.stripe;
      case LiveryType.vanta:
      case LiveryType.solstice:
        return LiveryDecal.split;
      case LiveryType.redline:
      case LiveryType.viridian:
        return LiveryDecal.chevron;
      case LiveryType.glacier:
        return LiveryDecal.hex;
      case LiveryType.ionic:
      case LiveryType.prism:
        return LiveryDecal.pulse;
    }
  }

  /// Palette: first stop tints the hull, last stop paints the decal.
  /// Palettes with more than two stops cycle over time ([cycles]).
  List<Color> get colors {
    switch (this) {
      case LiveryType.standard:
        return const [Color(0xFF7CF5FF), Color(0xFFA78BFA)];
      case LiveryType.aurum:
        return const [Color(0xFFFFD58A), Color(0xFFB8862E)];
      case LiveryType.vanta:
        return const [Color(0xFF15151A), Color(0xFF7CF5FF)];
      case LiveryType.redline:
        return const [Color(0xFFFF4D5E), Color(0xFF7A0F1E)];
      case LiveryType.glacier:
        return const [Color(0xFFBFF3FF), Color(0xFF3A8DDE)];
      case LiveryType.ionic:
        return const [Color(0xFF7CF5FF), Color(0xFFA78BFA)];
      case LiveryType.solstice:
        return const [Color(0xFFFFB347), Color(0xFFFF8AD8)];
      case LiveryType.viridian:
        return const [Color(0xFF9BFFC8), Color(0xFF138A72)];
      case LiveryType.prism:
        return const [
          Color(0xFF7CF5FF),
          Color(0xFFA78BFA),
          Color(0xFFFF8AD8),
          Color(0xFFFFD58A),
        ];
    }
  }

  Color get hullColor => colors.first;
  Color get decalColor => colors.last;

  /// Multi-stop palettes animate through their stops in flight.
  bool get cycles => colors.length > 2;

  /// Parse a persisted / synced / product ID (new or pre-3.2). Unknown
  /// values fall back to [standard] so old data can never crash a render.
  static LiveryType fromId(String? id) => tryParse(id) ?? LiveryType.standard;

  /// Like [fromId] but null for unknown IDs (lets callers drop junk rows).
  static LiveryType? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var id = raw.trim().toLowerCase();
    const prefix = 'com.pranta.cosmostrike.';
    if (id.startsWith(prefix)) id = id.substring(prefix.length);
    for (final l in LiveryType.values) {
      if (l.id == id || l.name == id) return l;
    }
    if (id.startsWith('skin_')) id = id.substring('skin_'.length);
    return _legacy[id];
  }

  /// Pre-3.2 skin IDs (REBRAND_SPEC §2.8).
  static const Map<String, LiveryType> _legacy = {
    'classic': LiveryType.standard,
    'golden': LiveryType.aurum,
    'shadow': LiveryType.vanta,
    'dragon': LiveryType.redline,
    'fire': LiveryType.redline,
    'ice': LiveryType.glacier,
    'electric': LiveryType.ionic,
    'rainbow': LiveryType.prism,
    'neon': LiveryType.solstice,
    'galaxy': LiveryType.viridian,
    'cosmic': LiveryType.viridian,
    'crystal': LiveryType.viridian,
  };

  /// Canonical ID for any persisted value, or null when it maps to nothing.
  static String? normalizeId(String? raw) => tryParse(raw)?.id;
}

/// Engine exhaust effects sold in the Armory. [stock] is the free default
/// (the hull's own thruster sprite, no extra effect).
///
/// Persisted / synced as [id]; parse old trail IDs through [fromId].
enum ExhaustType {
  stock,
  ion,
  plasma,
  ember,
  comet,
  pulse,
  quantum,
  nova;

  /// Wire / persistence / product-suffix ID.
  String get id => this == ExhaustType.stock ? 'stock' : 'exhaust_$name';

  String get displayName {
    switch (this) {
      case ExhaustType.stock:
        return 'Stock Thruster';
      case ExhaustType.ion:
        return 'Ion Wake';
      case ExhaustType.plasma:
        return 'Plasma Plume';
      case ExhaustType.ember:
        return 'Ember Burn';
      case ExhaustType.comet:
        return 'Comet Tail';
      case ExhaustType.pulse:
        return 'Pulse Drive';
      case ExhaustType.quantum:
        return 'Quantum Echo';
      case ExhaustType.nova:
        return 'Nova Stream';
    }
  }

  String get description {
    switch (this) {
      case ExhaustType.stock:
        return 'Standard thruster burn. No extra effect.';
      case ExhaustType.ion:
        return 'A thin cyan ion line that flickers at full burn.';
      case ExhaustType.plasma:
        return 'A fat violet-pink plume of superheated plasma.';
      case ExhaustType.ember:
        return 'Orange sparks shed from the nozzle as you fly.';
      case ExhaustType.comet:
        return 'A long white-to-cyan tail that fades out slow.';
      case ExhaustType.pulse:
        return 'Shock rings fired off the engine at intervals.';
      case ExhaustType.quantum:
        return 'Ghost after-images of your hull trail behind.';
      case ExhaustType.nova:
        return 'A stream of particles across the full prism.';
    }
  }

  bool get isPremium => this != ExhaustType.stock;

  /// USD fallback price (live store price wins when loaded).
  double get price {
    switch (this) {
      case ExhaustType.stock:
        return 0.0;
      case ExhaustType.ion:
        return 0.99;
      case ExhaustType.plasma:
      case ExhaustType.ember:
        return 1.99;
      case ExhaustType.comet:
      case ExhaustType.pulse:
        return 2.99;
      case ExhaustType.quantum:
      case ExhaustType.nova:
        return 3.99;
    }
  }

  List<Color> get colors {
    switch (this) {
      case ExhaustType.stock:
        return const [];
      case ExhaustType.ion:
        return const [Color(0xFF7CF5FF), Color(0xFFB8FAFF)];
      case ExhaustType.plasma:
        return const [Color(0xFFA78BFA), Color(0xFFFF8AD8)];
      case ExhaustType.ember:
        return const [Color(0xFFFF8A3D), Color(0xFFFFC24B), Color(0xFFFF5A1F)];
      case ExhaustType.comet:
        return const [Color(0xFFFFFFFF), Color(0xFF7CF5FF)];
      case ExhaustType.pulse:
        return const [Color(0xFF7CF5FF), Color(0xFF9BFFC8)];
      case ExhaustType.quantum:
        return const [Color(0xFFA78BFA), Color(0xFF7CF5FF)];
      case ExhaustType.nova:
        return const [
          Color(0xFF7CF5FF),
          Color(0xFFA78BFA),
          Color(0xFFFF8AD8),
          Color(0xFFFFD58A),
          Color(0xFF9BFFC8),
        ];
    }
  }

  /// Parse a persisted / synced / product ID (new or pre-3.2). Unknown
  /// values fall back to [stock].
  static ExhaustType fromId(String? id) => tryParse(id) ?? ExhaustType.stock;

  static ExhaustType? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var id = raw.trim().toLowerCase();
    const prefix = 'com.pranta.cosmostrike.';
    if (id.startsWith(prefix)) id = id.substring(prefix.length);
    for (final e in ExhaustType.values) {
      if (e.id == id || e.name == id) return e;
    }
    if (id.startsWith('trail_')) id = id.substring('trail_'.length);
    return _legacy[id];
  }

  /// Pre-3.2 trail IDs, bare or `trail_`-prefixed (REBRAND_SPEC §2.8).
  static const Map<String, ExhaustType> _legacy = {
    'none': ExhaustType.stock,
    'particle': ExhaustType.ion,
    'glow': ExhaustType.ion,
    'neon': ExhaustType.plasma,
    'cosmic': ExhaustType.plasma,
    'fire': ExhaustType.ember,
    'dragon': ExhaustType.ember,
    'star': ExhaustType.comet,
    'electric': ExhaustType.pulse,
    'shadow': ExhaustType.quantum,
    'rainbow': ExhaustType.nova,
    'crystal': ExhaustType.nova,
  };

  static String? normalizeId(String? raw) => tryParse(raw)?.id;
}

class ShipCosmetics {
  final LiveryType livery;
  final ExhaustType exhaust;

  const ShipCosmetics({required this.livery, required this.exhaust});

  ShipCosmetics copyWith({LiveryType? livery, ExhaustType? exhaust}) {
    return ShipCosmetics(
      livery: livery ?? this.livery,
      exhaust: exhaust ?? this.exhaust,
    );
  }

  bool get isPremium => livery.isPremium || exhaust.isPremium;

  double get totalPrice => livery.price + exhaust.price;

  Map<String, dynamic> toJson() {
    return {'livery': livery.id, 'exhaust': exhaust.id};
  }

  /// Reads both the current keys and the pre-3.2 `skin` / `trail` keys.
  factory ShipCosmetics.fromJson(Map<String, dynamic> json) {
    return ShipCosmetics(
      livery: LiveryType.fromId((json['livery'] ?? json['skin']) as String?),
      exhaust:
          ExhaustType.fromId((json['exhaust'] ?? json['trail']) as String?),
    );
  }

  static const ShipCosmetics defaultCosmetics = ShipCosmetics(
    livery: LiveryType.standard,
    exhaust: ExhaustType.stock,
  );
}

/// Non-consumable cosmetic bundle ("Fleet Kit"). [id] is both the owned
/// bundle ID and the store product suffix.
class FleetKit {
  final String id;
  final String name;
  final String description;
  final List<LiveryType> liveries;
  final List<ExhaustType> exhausts;
  final double kitPrice;

  const FleetKit({
    required this.id,
    required this.name,
    required this.description,
    required this.liveries,
    required this.exhausts,
    required this.kitPrice,
  });

  /// Sum of the individual fallback prices.
  double get originalPrice {
    double total = 0;
    for (final l in liveries) {
      total += l.price;
    }
    for (final e in exhausts) {
      total += e.price;
    }
    return total;
  }

  double get savings => originalPrice - kitPrice;
  double get savingsPercentage =>
      originalPrice > 0 ? (savings / originalPrice) * 100 : 0;

  static FleetKit? byId(String id) {
    for (final k in availableKits) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// Canonical kit / bundle ID for a persisted bundle row. Only the
  /// pre-3.2 bundle whose contents survive 1:1 is carried over (Ultimate →
  /// Flagship: both are "everything"); the others' items are already owned
  /// individually after the item remap, so the bundle row itself is dropped
  /// (null). The themes bundle maps to the Star Atlas sector bundle.
  static String? normalizeBundleId(String raw) {
    final id = raw.trim().toLowerCase();
    if (availableKits.any((k) => k.id == id)) return id;
    if (id == sectorAtlasId) return id;
    switch (id) {
      case 'ultimate_collection':
        return 'kit_flagship';
      case 'premium_themes_bundle':
        return sectorAtlasId;
      default:
        return null;
    }
  }

  /// Owned-bundle ID recorded for the all-sectors bundle.
  static const String sectorAtlasId = 'sector_atlas';

  static const List<FleetKit> availableKits = [
    FleetKit(
      id: 'kit_recruit',
      name: 'Recruit Kit',
      description: 'Two liveries and two exhausts to fly out of basic.',
      liveries: [LiveryType.aurum, LiveryType.vanta],
      exhausts: [ExhaustType.ion, ExhaustType.ember],
      kitPrice: 3.99,
    ),
    FleetKit(
      id: 'kit_vanguard',
      name: 'Vanguard Kit',
      description: 'Front-line paint and engines for a full wing.',
      liveries: [
        LiveryType.redline,
        LiveryType.glacier,
        LiveryType.ionic,
        LiveryType.solstice,
      ],
      exhausts: [ExhaustType.plasma, ExhaustType.comet, ExhaustType.pulse],
      kitPrice: 9.99,
    ),
    FleetKit(
      id: 'kit_flagship',
      name: 'Flagship Kit',
      description: 'Every livery and every exhaust in the Armory.',
      liveries: [
        LiveryType.aurum,
        LiveryType.vanta,
        LiveryType.redline,
        LiveryType.glacier,
        LiveryType.ionic,
        LiveryType.solstice,
        LiveryType.viridian,
        LiveryType.prism,
      ],
      exhausts: [
        ExhaustType.ion,
        ExhaustType.plasma,
        ExhaustType.ember,
        ExhaustType.comet,
        ExhaustType.pulse,
        ExhaustType.quantum,
        ExhaustType.nova,
      ],
      kitPrice: 19.99,
    ),
  ];
}
