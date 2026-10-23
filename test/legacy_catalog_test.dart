import 'package:flutter_test/flutter_test.dart';
import 'package:cosmo_strike_flutter_app/models/premium_cosmetics.dart';
import 'package:cosmo_strike_flutter_app/models/premium_power_up.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/services/rebrand/legacy_catalog_migration.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

void main() {
  group('Liveries', () {
    test('legacy skin IDs map per REBRAND_SPEC §2.8', () {
      const expected = {
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
      expected.forEach((legacy, livery) {
        expect(LiveryType.fromId(legacy), livery, reason: legacy);
        expect(LiveryType.fromId('skin_$legacy'), livery, reason: legacy);
      });
    });

    test('current IDs round-trip and unknown falls back to standard', () {
      for (final l in LiveryType.values) {
        expect(LiveryType.fromId(l.id), l);
        expect(LiveryType.fromId('com.pranta.cosmostrike.${l.id}'), l);
      }
      expect(LiveryType.fromId('nonsense'), LiveryType.standard);
      expect(LiveryType.tryParse('nonsense'), isNull);
    });
  });

  group('Exhausts', () {
    test('legacy trail IDs map per REBRAND_SPEC §2.8', () {
      const expected = {
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
      expected.forEach((legacy, exhaust) {
        expect(ExhaustType.fromId(legacy), exhaust, reason: legacy);
        expect(ExhaustType.fromId('trail_$legacy'), exhaust, reason: legacy);
      });
      for (final e in ExhaustType.values) {
        expect(ExhaustType.fromId(e.id), e);
      }
    });
  });

  group('Sectors', () {
    test('legacy theme names, product IDs and labels map', () {
      const expected = {
        'classic': GameTheme.prismNoir,
        'modern': GameTheme.prismNoir,
        'retro': GameTheme.monochrome,
        'accessible': GameTheme.highContrast,
        'neon': GameTheme.neonGrid,
        'forest': GameTheme.aurora,
        'desert': GameTheme.solar,
        'ocean': GameTheme.abyss,
        'cyberpunk': GameTheme.ion,
        'crystal': GameTheme.ion,
        'space': GameTheme.crimson,
      };
      expected.forEach((legacy, sector) {
        expect(GameTheme.fromId(legacy), sector, reason: legacy);
        expect(GameTheme.fromId('${legacy}_theme'), sector, reason: legacy);
      });
      expect(GameTheme.fromId('Amber Phosphor'), GameTheme.prismNoir);
      expect(GameTheme.fromId('Space'), GameTheme.crimson);
      for (final t in GameTheme.values) {
        expect(GameTheme.fromId(t.id), t);
        expect(GameTheme.fromId(t.enumName), t);
      }
    });

    test('legacy indices decode to the mapped sector', () {
      const legacyNames = [
        'classic', 'modern', 'neon', 'retro', 'space', 'ocean',
        'cyberpunk', 'forest', 'desert', 'crystal', 'accessible',
      ];
      for (var i = 0; i < legacyNames.length; i++) {
        expect(GameTheme.fromLegacyIndex(i), GameTheme.fromId(legacyNames[i]));
      }
      // Indices 0 and 2–8 are stable across the rename.
      for (final i in [0, 2, 3, 4, 5, 6, 7, 8]) {
        expect(GameTheme.fromIndex(i), GameTheme.fromLegacyIndex(i));
      }
      expect(GameTheme.fromIndex(9), GameTheme.ion);
      expect(GameTheme.fromIndex(10), GameTheme.highContrast);
    });
  });

  group('Tactical Gear', () {
    test('legacy inventory keys fold onto gear keys and merge', () {
      final inv = PremiumPowerUpType.normalizeInventory({
        'speed_boost': 2,
        'gear_afterburner': 1,
        'magnetic_pickup': 3,
        'future_item': 4,
      });
      expect(inv, {'gear_afterburner': 3, 'gear_lure': 3, 'future_item': 4});
    });

    test('legacy credit bundle IDs resolve', () {
      expect(PowerUpBundle.byId('mega_pack')?.id, 'gear_supply_crate');
      expect(PowerUpBundle.byId('tactical_pack')?.id, 'gear_tactical_case');
      expect(PowerUpBundle.byId('ultimate_pack')?.id, 'gear_arsenal');
    });
  });

  test('unlocked-item normalisation', () {
    expect(normalizeUnlockedItemId('skin', 'golden'), 'livery_aurum');
    expect(normalizeUnlockedItemId('skin', 'classic'), isNull);
    expect(normalizeUnlockedItemId('trail', 'trail_star'), 'exhaust_comet');
    expect(normalizeUnlockedItemId('theme', 'crystal_theme'), 'sector_ion');
    expect(normalizeUnlockedItemId('theme', 'Modern'), isNull);
    expect(normalizeUnlockedItemId('bundle', 'ultimate_collection'), 'kit_flagship');
    expect(normalizeUnlockedItemId('bundle', 'starter_pack'), isNull);
    expect(normalizeUnlockedItemId('bundle', 'premium_themes_bundle'), 'sector_atlas');
    expect(normalizeUnlockedItemId('hangar', 'hangar_hull_2'), 'hangar_hull_2');
  });

  // REBRAND_SPEC §2 totals "36", but its exhaust row counts the free Stock
  // Thruster: the sellable catalog is 2 + 4 + 8 + 7 + 6 + 3 + 5 = 35.
  test('store catalog has every sellable spec product', () {
    expect(ProductIds.allProductIds.length, 35);
    expect(ProductIds.allProductIds.toSet().length, 35);
    for (final l in LiveryType.values.where((l) => l.isPremium)) {
      expect(ProductIds.allProductIds, contains(ProductIds.withPrefix(l.id)));
    }
    for (final e in ExhaustType.values.where((e) => e.isPremium)) {
      expect(ProductIds.allProductIds, contains(ProductIds.withPrefix(e.id)));
    }
    for (final t in GameTheme.values.where((t) => t.isPremium)) {
      expect(ProductIds.allProductIds, contains(ProductIds.withPrefix(t.id)));
    }
    for (final k in FleetKit.availableKits) {
      expect(ProductIds.allProductIds, contains(ProductIds.withPrefix(k.id)));
    }
  });
}
