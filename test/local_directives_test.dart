// Guards the client-side Daily Directives that accountless (local guest)
// pilots receive, since the backend catalog is only served to signed-in
// accounts.

import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/services/local_directives.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart' show GameMode;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalDirectives.forDay', () {
    test('issues one directive per difficulty', () {
      final set = LocalDirectives.forDay(DateTime(2026, 11, 19));
      expect(set, hasLength(3));
      expect(
        set.map((c) => c.difficulty).toList(),
        ChallengeDifficulty.values,
      );
    });

    test('is deterministic for a local day, ignoring the time of day', () {
      final morning = LocalDirectives.forDay(DateTime(2026, 11, 19, 0, 5));
      final night = LocalDirectives.forDay(DateTime(2026, 11, 19, 23, 55));
      expect(
        morning.map((c) => '${c.id}|${c.title}').toList(),
        night.map((c) => '${c.id}|${c.title}').toList(),
      );
    });

    test('ids are local, day-scoped and unique', () {
      final set = LocalDirectives.forDay(DateTime(2026, 1, 2));
      for (final c in set) {
        expect(LocalDirectives.isLocalId(c.id), isTrue);
        expect(c.id, contains('2026-01-02'));
      }
      expect(set.map((c) => c.id).toSet(), hasLength(3));

      final nextDay = LocalDirectives.forDay(DateTime(2026, 1, 3));
      expect(
        nextDay.map((c) => c.id).toSet().intersection(set.map((c) => c.id).toSet()),
        isEmpty,
      );
    });

    test('directives are winnable, start fresh and use current copy', () {
      for (var d = 1; d <= 60; d++) {
        for (final c in LocalDirectives.forDay(DateTime(2026, 1, d))) {
          expect(c.targetValue, greaterThan(0));
          expect(c.coinReward, greaterThan(0));
          expect(c.xpReward, greaterThan(0));
          expect(c.currentProgress, 0);
          expect(c.isCompleted, isFalse);
          expect(c.claimedReward, isFalse);
          expect(kLegacyDirectiveCopy.hasMatch(c.title), isFalse, reason: c.title);
          expect(kLegacyDirectiveCopy.hasMatch(c.description), isFalse,
              reason: c.description);
          if (c.type == ChallengeType.gameMode) {
            expect(GameMode.tryFromWire(c.requiredGameMode), isNotNull);
          }
        }
      }
    });

    test('backend-style ids are not treated as local', () {
      expect(LocalDirectives.isLocalId('3f2a9c1e-0000-4000-8000-000000000000'), isFalse);
      expect(LocalDirectives.isLocalId('all_complete_bonus_2026-11-19'), isFalse);
    });
  });
}
