// Guards the 3.2 commendation catalog (72 `cmd_*` rows that replaced the
// inherited achievement list), the legacy id remap, and the day-streak
// helper the Service commendations read.

import 'package:cosmo_strike_flutter_app/models/achievement.dart';
import 'package:cosmo_strike_flutter_app/services/rebrand/legacy_achievement_migration.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart' show GameMode;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalog = Achievement.getDefaultAchievements();
  final ids = catalog.map((a) => a.id).toSet();

  group('commendation catalog', () {
    test('has 72 unique cmd_ ids', () {
      expect(catalog, hasLength(72));
      expect(ids, hasLength(72));
      expect(ids.every((id) => id.startsWith('cmd_')), isTrue);
    });

    test('covers every category', () {
      expect(
        catalog.map((a) => a.category).toSet(),
        CommendationCategory.values.toSet(),
      );
    });

    test('targets and rewards are positive', () {
      for (final a in catalog) {
        expect(a.targetValue, greaterThan(0), reason: a.id);
        expect(a.xpReward, greaterThan(0), reason: a.id);
        expect(a.coinReward, greaterThan(0), reason: a.id);
      }
    });

    test('mode filters use current mode wire names', () {
      final filtered = catalog.where((a) => a.gameModeFilter != null);
      expect(filtered, isNotEmpty);
      for (final a in filtered) {
        final mode = GameMode.tryFromWire(a.gameModeFilter);
        expect(mode, isNotNull, reason: a.id);
        expect(mode!.wireName, a.gameModeFilter, reason: a.id);
      }
      expect(
        catalog
            .where((a) => a.metric == CommendationMetric.gamesInMode)
            .every((a) => a.gameModeFilter != null),
        isTrue,
      );
    });

    test('copy is free of retired vocabulary', () {
      final banned = RegExp(
        r'\b(snake|food|eat|bite|slither|classic|zen|speed challenge|'
        r'time attack|perfect game|trophy|trophies|achievement|coins?)\b',
        caseSensitive: false,
      );
      for (final a in catalog) {
        expect(banned.hasMatch(a.title), isFalse, reason: a.title);
        expect(banned.hasMatch(a.description), isFalse, reason: a.description);
      }
    });

    test('rarity names follow the Commendation ladder', () {
      String nameOf(AchievementRarity r) =>
          catalog.firstWhere((a) => a.rarity == r).rarityName;
      expect(nameOf(AchievementRarity.common), 'Service');
      expect(nameOf(AchievementRarity.rare), 'Bronze Star');
      expect(nameOf(AchievementRarity.epic), 'Silver Star');
      expect(nameOf(AchievementRarity.legendary), 'Gold Star');
      expect(nameOf(AchievementRarity.diamond), 'Nova');
    });
  });

  group('legacy remap', () {
    test('every mapping targets a real commendation', () {
      for (final entry in kLegacyAchievementMap.entries) {
        expect(ids, contains(entry.value), reason: entry.key);
        expect(entry.key.startsWith('cmd_'), isFalse, reason: entry.key);
      }
    });
  });

  group('consecutiveDayStreak', () {
    final now = DateTime(2026, 10, 23, 12);

    test('counts back from today across padded and legacy keys', () {
      final streak = consecutiveDayStreak({
        '2026-10-23': 30,
        '2026-10-22': 10,
        '2026-10-1': 5, // legacy unpadded key, not contiguous
        '2026-10-21': 5,
      }, now: now);
      expect(streak, 3);
    });

    test('a streak ending yesterday is still live', () {
      final streak = consecutiveDayStreak({
        '2026-10-22': 10,
        '2026-10-21': 10,
      }, now: now);
      expect(streak, 2);
    });

    test('zero-second days and gaps break the streak', () {
      final streak = consecutiveDayStreak({
        '2026-10-23': 10,
        '2026-10-22': 0,
        '2026-10-21': 10,
      }, now: now);
      expect(streak, 1);
    });
  });
}
