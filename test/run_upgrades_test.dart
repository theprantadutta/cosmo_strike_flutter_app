import 'dart:math' as math;

import 'package:cosmo_strike_flutter_app/game/run_upgrades.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a draft offers 3 distinct upgrades', () {
    final u = RunUpgrades();
    for (var seed = 0; seed < 50; seed++) {
      final d = u.draft(math.Random(seed));
      expect(d.length, 3);
      expect(d.map((e) => e.id).toSet().length, 3);
    }
  });

  test('maxed upgrades never come back, and stacks cap', () {
    final u = RunUpgrades();
    u.take(UpgradeId.shieldRegen);
    u.take(UpgradeId.shieldRegen); // over the cap: ignored
    expect(u.stacks(UpgradeId.shieldRegen), 1);
    for (var seed = 0; seed < 200; seed++) {
      expect(u.draft(math.Random(seed)).map((e) => e.id), isNot(contains(UpgradeId.shieldRegen)));
    }
  });

  test('draft shrinks then empties when everything is maxed', () {
    final u = RunUpgrades();
    for (final def in UpgradeCatalog.all) {
      for (var i = 0; i < def.maxStacks; i++) {
        u.take(def.id);
      }
    }
    expect(u.draft(math.Random(1)), isEmpty);
  });

  test('derived stats stack', () {
    final u = RunUpgrades()
      ..take(UpgradeId.rapidServos)
      ..take(UpgradeId.rapidServos)
      ..take(UpgradeId.hullPlating)
      ..take(UpgradeId.missileRack)
      ..take(UpgradeId.magnetField);
    expect(u.fireCooldownScale, closeTo(0.85 * 0.85, 1e-9));
    expect(u.damageTakenScale, closeTo(0.8, 1e-9));
    expect(u.missilesPerLevel, 2);
    expect(u.magnetRadius, 170);
    expect(u.history, [
      UpgradeId.rapidServos,
      UpgradeId.rapidServos,
      UpgradeId.hullPlating,
      UpgradeId.missileRack,
      UpgradeId.magnetField,
    ]);
  });

  test('rarer upgrades are offered less often', () {
    final u = RunUpgrades();
    final rng = math.Random(7);
    var common = 0, epic = 0;
    for (var i = 0; i < 3000; i++) {
      for (final d in u.draft(rng, count: 1)) {
        if (d.id == UpgradeId.twinCannon) common++;
        if (d.id == UpgradeId.heavyRounds) epic++;
      }
    }
    expect(common, greaterThan(epic * 2));
  });
}
