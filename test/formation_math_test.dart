// Pure-math tests for the formation slot functions and terrain profile
// sampling — the only gameplay layer testable without a device.

import 'package:cosmo_strike_flutter_app/game/levels/formation.dart';
import 'package:cosmo_strike_flutter_app/game/levels/level_def.dart';
import 'package:cosmo_strike_flutter_app/game/levels/terrain_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('vWedgeOffset', () {
    test('slot 0 is the tip', () {
      expect(vWedgeOffset(0, 56), equals(vWedgeOffset(0, 100)));
      expect(vWedgeOffset(0, 56).length, 0);
    });

    test('pairs mirror above/below at the same trailing distance', () {
      final up = vWedgeOffset(1, 56);
      final down = vWedgeOffset(2, 56);
      expect(up.x, down.x);
      expect(up.y, -down.y);
      expect(up.x, greaterThan(0)); // trails behind the tip
    });

    test('rows step further back', () {
      expect(vWedgeOffset(3, 56).x, greaterThan(vWedgeOffset(1, 56).x));
    });
  });

  group('ringOffset', () {
    test('stays on the circle radius for all slots and times', () {
      for (var i = 0; i < 8; i++) {
        for (final t in [0.0, 0.7, 3.3]) {
          // Vector2 stores float32 — allow its precision.
          expect(ringOffset(i, 8, t, 90).length, closeTo(90, 1e-3));
        }
      }
    });

    test('rotates over time', () {
      final a = ringOffset(0, 6, 0, 80);
      final b = ringOffset(0, 6, 1, 80);
      expect((a - b).length, greaterThan(1));
    });
  });

  group('snakeY', () {
    test('is bounded by the amplitude', () {
      for (var t = 0.0; t < 10; t += 0.1) {
        expect(snakeY(t, 100).abs(), lessThanOrEqualTo(100));
      }
    });

    test('followers sampling the past reproduce the leader path', () {
      const delay = 0.4;
      expect(snakeY(2.0 - delay, 80), snakeY(1.6, 80));
    });
  });

  group('wallSlotY01', () {
    test('keeps every slot out of the gap window', () {
      const gap = 0.5;
      const gapHalf = 0.18;
      for (var i = 0; i < 9; i++) {
        final y = wallSlotY01(i, 9, gap, gapHalf);
        expect((y - gap).abs(), greaterThanOrEqualTo(gapHalf - 1e-9));
        expect(y, inInclusiveRange(0, 1));
      }
    });

    test('single slot centers when no gap conflict', () {
      expect(wallSlotY01(0, 1, 0.9, 0.1), 0.5);
    });
  });

  group('diveProgress', () {
    test('clamps to [0,1] and later slots lag earlier ones', () {
      expect(diveProgress(-1, 0), 0);
      expect(diveProgress(10, 0), 1);
      expect(diveProgress(0.5, 0), greaterThan(diveProgress(0.5, 2)));
    });
  });

  group('FormationSpec.mirrored', () {
    test('flips y01 and the wall gap, preserves everything else', () {
      const spec = FormationSpec(
        shape: FormationShape.wallWithGap,
        type: EnemyType.dart,
        count: 7,
        y01: 0.3,
        gap01: 0.25,
      );
      final m = spec.mirrored();
      expect(m.y01, closeTo(0.7, 1e-9));
      expect(m.gap01, closeTo(0.75, 1e-9));
      expect(m.shape, spec.shape);
      expect(m.type, spec.type);
      expect(m.count, spec.count);
    });
  });

  group('TerrainProfile', () {
    test('neutral profile is flat 1s', () {
      expect(TerrainProfile.neutral.floorAt(0), 1);
      expect(TerrainProfile.neutral.floorAt(99), 1);
      expect(TerrainProfile.neutral.scrollAt(42), 1);
    });

    test('lerps between keyframes and clamps outside the range', () {
      const profile = TerrainProfile([
        TerrainKeyframe(10, floor: 1),
        TerrainKeyframe(20, floor: 3),
      ]);
      expect(profile.floorAt(0), 1); // clamps before
      expect(profile.floorAt(15), closeTo(2, 1e-9)); // midpoint
      expect(profile.floorAt(25), 3); // clamps after
    });
  });
}
