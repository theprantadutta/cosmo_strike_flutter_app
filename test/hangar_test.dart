import 'package:cosmo_strike_flutter_app/game/hangar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owned item ids parse to the highest level per stat', () {
    final levels = HangarCatalog.levelsFrom([
      HangarCatalog.itemId(HangarStat.hull, 1),
      HangarCatalog.itemId(HangarStat.hull, 3),
      HangarCatalog.itemId(HangarStat.hull, 2),
      HangarCatalog.itemId(HangarStat.arsenal, 1),
      'skin_galaxy',
      'hangar_bogus_2',
      'hangar_cannons_x',
    ]);
    expect(levels, {HangarStat.hull: 3, HangarStat.arsenal: 1});
  });

  test('costs escalate and stop at max level', () {
    expect(HangarCatalog.costForNext(0), 150);
    expect(HangarCatalog.costForNext(4), 2000);
    expect(HangarCatalog.costForNext(HangarCatalog.maxLevel), 0);
    for (final s in HangarStat.values) {
      expect(HangarCatalog.itemId(s, 5).length, lessThan(100));
    }
  });

  test('loadout combines Hangar levels with the ship frame', () {
    const l = HangarLoadout(
      levels: {HangarStat.hull: 2, HangarStat.cannons: 1, HangarStat.arsenal: 3, HangarStat.tractor: 1},
      frame: ShipFrame.striker,
    );
    expect(l.damageTakenScale, closeTo(0.94 * 0.94, 1e-9));
    expect(l.fireCooldownScale, closeTo(0.96, 1e-9));
    expect(l.startMissiles, 3);
    expect(l.magnetRadius, 100);
    final lancer = HangarLoadout(frame: ShipFrame.byId('lancer'));
    expect(lancer.fireCooldownScale, closeTo(1.15, 1e-9));
  });

  test('frames unlock by highest cleared level; unknown ids fall back', () {
    expect(ShipFrame.byId('lancer').ownedWith(2), isFalse);
    expect(ShipFrame.byId('lancer').ownedWith(3), isTrue);
    expect(ShipFrame.byId('nope').id, 'striker');
  });
}
