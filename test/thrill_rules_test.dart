import 'package:cosmo_strike_flutter_app/game/combo_graze.dart';
import 'package:cosmo_strike_flutter_app/game/intensity_director.dart';
import 'package:cosmo_strike_flutter_app/game/tuning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntensityDirector', () {
    test('stays neutral during the calm window, then ramps to the cap', () {
      final d = IntensityDirector();
      for (var i = 0; i < 110; i++) {
        d.update(0.1); // 11s of clean flying
      }
      expect(d.intensity, 1.0);
      for (var i = 0; i < 600; i++) {
        d.update(0.1); // a minute more
      }
      expect(d.intensity, closeTo(GameTuning.maxIntensity, 1e-9));
    });

    test('a landed hit drops pressure immediately and restarts the calm', () {
      final d = IntensityDirector();
      for (var i = 0; i < 400; i++) {
        d.update(0.1);
      }
      final before = d.intensity;
      d.onPlayerHit();
      expect(d.intensity, closeTo(before - GameTuning.hitRelief, 1e-9));
      for (var i = 0; i < 4000; i++) {
        d.onPlayerHit();
      }
      expect(d.intensity, GameTuning.minIntensity);
    });

    test('standing still is idle and earns a volley on a cooldown', () {
      final d = IntensityDirector();
      for (var i = 0; i < 50; i++) {
        d.update(0.1);
        d.onPlayerPosition(100, 200);
      }
      expect(d.idle, isTrue);
      expect(d.consumeVolley(), isTrue);
      expect(d.consumeVolley(), isFalse, reason: 'cooldown armed');
      for (var i = 0; i < 31; i++) {
        d.update(0.1);
        d.onPlayerPosition(100, 200);
      }
      expect(d.consumeVolley(), isTrue);
    });

    test('a moving ship is never idle', () {
      final d = IntensityDirector();
      for (var i = 0; i < 80; i++) {
        d.update(0.1);
        d.onPlayerPosition(100, 200 + (i % 20) * 6.0);
      }
      expect(d.idle, isFalse);
      expect(d.consumeVolley(), isFalse);
    });
  });

  group('Overdrive meter', () {
    test('fills after the configured number of grazes and stays full', () {
      final c = ComboGrazeController();
      for (var i = 0; i < GameTuning.grazesForOverdrive - 1; i++) {
        expect(c.onGraze(), isFalse);
      }
      expect(c.onGraze(), isTrue, reason: 'this graze filled it');
      expect(c.overdriveReady, isTrue);
      expect(c.onGraze(), isFalse, reason: 'already full');
      expect(c.grazeCount, GameTuning.grazesForOverdrive + 1);
    });

    test('consuming empties it; consuming an empty meter fails', () {
      final c = ComboGrazeController();
      expect(c.consumeOverdrive(), isFalse);
      c.addCharge(1);
      expect(c.consumeOverdrive(), isTrue);
      expect(c.grazeNotifier.value, 0);
    });

    test('a graze extends a live chain but never past the window', () {
      final c = ComboGrazeController();
      c.onKill();
      c.update(ComboGrazeController.chainWindow - 0.1);
      c.onGraze(); // +0.6s
      c.update(0.5);
      expect(c.chain, 1, reason: 'graze kept the chain alive');
      c.update(1.0);
      expect(c.chain, 0);
    });
  });
}
