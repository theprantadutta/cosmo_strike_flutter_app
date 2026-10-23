import 'dart:math' as math;
import 'dart:ui';

import '../models/premium_cosmetics.dart' show LiveryDecal;

/// Hull decal geometry for liveries, shared by the in-game [PlayerShip]
/// render and the Armory preview so both show the same paint job.
///
/// Everything is authored in the 192x128 player-sprite space (nose at
/// x=186, centreline y=64) and scaled by `k` = rendered width / 192. Build
/// once and cache — nothing here is meant to run per frame.
abstract final class LiveryDecals {
  /// Silhouette of the level-flight hull (traced from the sprite's alpha),
  /// used as the clip so decals never paint outside the ship.
  static Path hull(double k) {
    const top = [
      (14.0, 40.0), (16.0, 37.0), (24.0, 32.0), (32.0, 27.0), (40.0, 22.0),
      (50.0, 15.0), (56.0, 17.0), (64.0, 25.0), (72.0, 32.0), (80.0, 39.0),
      (88.0, 46.0), (96.0, 49.0), (112.0, 52.0), (128.0, 54.0),
      (144.0, 57.0), (160.0, 60.0), (176.0, 62.0), (187.0, 64.0),
    ];
    final path = Path()..moveTo(top.first.$1 * k, top.first.$2 * k);
    for (final (x, y) in top.skip(1)) {
      path.lineTo(x * k, y * k);
    }
    // Bottom edge mirrors the top about the centreline (y = 64).
    for (final (x, y) in top.reversed.skip(1)) {
      path.lineTo(x * k, (128 - y) * k);
    }
    return path..close();
  }

  /// The filled / stroked decal pattern for [decal] (empty for
  /// [LiveryDecal.none] and [LiveryDecal.pulse] — the pulse is a moving
  /// band, see [pulseBand]).
  static Path pattern(LiveryDecal decal, double k) {
    switch (decal) {
      case LiveryDecal.none:
      case LiveryDecal.pulse:
        return Path();
      case LiveryDecal.stripe:
        // Twin racing stripes either side of the keel stripe.
        return Path()
          ..addRect(Rect.fromLTRB(14 * k, 50 * k, 182 * k, 55 * k))
          ..addRect(Rect.fromLTRB(14 * k, 73 * k, 182 * k, 78 * k));
      case LiveryDecal.chevron:
        // Three forward-pointing chevrons across the wing roots.
        final path = Path();
        for (var i = 0; i < 3; i++) {
          final x = 30.0 + i * 26;
          path
            ..moveTo(x * k, 14 * k)
            ..lineTo((x + 24) * k, 64 * k)
            ..lineTo(x * k, 114 * k)
            ..lineTo((x + 9) * k, 114 * k)
            ..lineTo((x + 33) * k, 64 * k)
            ..lineTo((x + 9) * k, 14 * k)
            ..close();
        }
        return path;
      case LiveryDecal.split:
        // Forward half of the hull, cut on the diagonal.
        return Path()
          ..moveTo(_splitA.dx * k, _splitA.dy * k)
          ..lineTo(_splitB.dx * k, _splitB.dy * k)
          ..lineTo(192 * k, 0)
          ..lineTo(192 * k, 128 * k)
          ..close();
      case LiveryDecal.hex:
        // Hex-mesh plating: pointy-top hexagons on an offset grid.
        const r = 11.0;
        final w = math.sqrt(3) * r;
        final path = Path();
        var row = 0;
        for (var cy = 0.0; cy <= 128 + r; cy += r * 1.5, row++) {
          final offset = row.isOdd ? w / 2 : 0.0;
          for (var cx = offset; cx <= 192 + w; cx += w) {
            for (var i = 0; i < 6; i++) {
              final a = math.pi / 3 * i - math.pi / 2;
              final px = (cx + r * math.cos(a)) * k;
              final py = (cy + r * math.sin(a)) * k;
              i == 0 ? path.moveTo(px, py) : path.lineTo(px, py);
            }
            path.close();
          }
        }
        return path;
    }
  }

  /// Ends of the split decal's diagonal edge (sprite space).
  static const Offset _splitA = Offset(56, 128);
  static const Offset _splitB = Offset(136, 0);

  /// The crisp edge line drawn along a split decal's diagonal.
  static Path splitEdge(double k) => Path()
    ..moveTo(_splitA.dx * k, _splitA.dy * k)
    ..lineTo(_splitB.dx * k, _splitB.dy * k);

  /// Whether [decal] is drawn as strokes (true) or fills (false).
  static bool isStroked(LiveryDecal decal) => decal == LiveryDecal.hex;

  /// Width of the pulse sweep band (sprite space).
  static const double pulseWidth = 46;

  /// The pulse band at x = 0 (translate it along the hull to animate).
  static Rect pulseBand(double k) =>
      Rect.fromLTWH(-pulseWidth / 2 * k, 0, pulseWidth * k, 128 * k);

  /// Soft-edged white band shader for [pulseBand]; tint it with a
  /// modulate colour filter so palette changes never rebuild the shader.
  static Shader pulseShader(double k) => Gradient.linear(
        Offset(-pulseWidth / 2 * k, 0),
        Offset(pulseWidth / 2 * k, 0),
        const [Color(0x00FFFFFF), Color(0xD9FFFFFF), Color(0x00FFFFFF)],
        // Required with 3+ colours — without stops dart:ui throws and the
        // whole paint pass (Armory card text, in-game hull) is lost.
        const [0.0, 0.5, 1.0],
      );

  /// Sweep travel range (sprite space): starts behind the tail, ends past
  /// the nose so the band fully enters and leaves.
  static const double pulseStart = -pulseWidth / 2;
  static const double pulseEnd = 192 + pulseWidth / 2;
}
