import 'package:cosmo_strike_flutter_app/game/tuning.dart';
import 'package:cosmo_strike_flutter_app/services/first_run_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameTuning.onboardingEase', () {
    test('covers exactly the FirstRunService onboarding window', () {
      expect(GameTuning.onboardingEaseRuns, FirstRunService.onboardingGameCount);
    });

    test('full on the first run, ramps down, none once onboarded', () {
      expect(GameTuning.onboardingEase(0), 1.0);
      expect(GameTuning.onboardingEase(1), closeTo(2 / 3, 1e-9));
      expect(GameTuning.onboardingEase(2), closeTo(1 / 3, 1e-9));
      expect(GameTuning.onboardingEase(3), 0.0);
      expect(GameTuning.onboardingEase(50), 0.0);
    });

    test('is strictly decreasing across the window', () {
      for (var r = 1; r <= GameTuning.onboardingEaseRuns; r++) {
        expect(
          GameTuning.onboardingEase(r),
          lessThan(GameTuning.onboardingEase(r - 1)),
        );
      }
    });

    test('negative counts (bad prefs) never ease', () {
      expect(GameTuning.onboardingEase(-1), 0.0);
    });
  });

  group('GameTuning.eased', () {
    test('full ease applies the full-ease multiplier', () {
      expect(GameTuning.eased(GameTuning.onboardingFireRateScale, 1),
          GameTuning.onboardingFireRateScale);
    });

    test('no ease leaves pressure untouched', () {
      expect(GameTuning.eased(GameTuning.onboardingFireRateScale, 0), 1.0);
      expect(GameTuning.eased(GameTuning.onboardingBulletSpeedScale, 0), 1.0);
      expect(GameTuning.eased(GameTuning.onboardingAimedScale, 0), 1.0);
    });

    test('out-of-range ease is clamped', () {
      expect(GameTuning.eased(0.5, 2), 0.5);
      expect(GameTuning.eased(0.5, -1), 1.0);
    });

    test('every multiplier only ever softens and climbs back to 1.0', () {
      for (final full in [
        GameTuning.onboardingFireRateScale,
        GameTuning.onboardingBulletSpeedScale,
        GameTuning.onboardingAimedScale,
      ]) {
        expect(full, inExclusiveRange(0.0, 1.0));
        var prev = 0.0;
        for (var r = 0; r <= GameTuning.onboardingEaseRuns; r++) {
          final m = GameTuning.eased(full, GameTuning.onboardingEase(r));
          expect(m, lessThanOrEqualTo(1.0));
          expect(m, greaterThan(prev));
          prev = m;
        }
        expect(prev, 1.0);
      }
    });
  });
}
