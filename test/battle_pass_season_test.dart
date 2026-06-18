// Guards the server-driven battle-pass season behavior the cubit now depends
// on: progression reads the season's per-level xp_required curve (not a
// hardcoded linear formula), and the free/premium claim split round-trips
// through the Drift encode/decode used by both sync directions.

import 'package:cosmo_strike_flutter_app/data/daos/store_dao.dart';
import 'package:cosmo_strike_flutter_app/models/battle_pass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BattlePassSeason curve (server-driven)', () {
    // A deliberately NON-linear curve — if progression still used the old
    // `100 + tier*50` formula these expectations would fail.
    final season = BattlePassSeason.fromJson({
      'id': 'season_test',
      'name': 'Test Season',
      'theme': 'cosmic',
      'start_date': '2026-01-01T00:00:00.000Z',
      'end_date': '2099-01-01T00:00:00.000Z',
      'price': 9.99,
      'levels': [
        {'level': 1, 'xp_required': 200},
        {'level': 2, 'xp_required': 300},
        {'level': 3, 'xp_required': 1000},
      ],
    });

    test('getXpForLevel returns the season-defined per-level cost', () {
      expect(season.getXpForLevel(1), 200);
      expect(season.getXpForLevel(2), 300);
      expect(season.getXpForLevel(3), 1000);
    });

    test('maxLevel is the season ladder length', () {
      expect(season.maxLevel, 3);
    });

    test('getLevelFromXp maps cumulative XP onto the non-linear ladder', () {
      expect(season.getLevelFromXp(0), 1);
      expect(season.getLevelFromXp(199), 1);
      expect(season.getLevelFromXp(200), 2); // cleared level 1 (200)
      expect(season.getLevelFromXp(499), 2);
      expect(season.getLevelFromXp(500), 3); // cleared level 2 (200+300)
      expect(season.getLevelFromXp(99999), 3); // clamped to maxLevel
    });
  });

  group('StoreDao.decodeClaimedRewards (free/premium split)', () {
    test('decodes the structured split', () {
      final split = StoreDao.decodeClaimedRewards('{"free":[1,5],"premium":[3]}');
      expect(split['free'], [1, 5]);
      expect(split['premium'], [3]);
    });

    test('treats a legacy flat array as free-track claims', () {
      final split = StoreDao.decodeClaimedRewards('[1,2,3]');
      expect(split['free'], [1, 2, 3]);
      expect(split['premium'], isEmpty);
    });

    test('falls back to empty on malformed/empty input', () {
      expect(StoreDao.decodeClaimedRewards('')['free'], isEmpty);
      expect(StoreDao.decodeClaimedRewards('not json')['premium'], isEmpty);
    });
  });
}
