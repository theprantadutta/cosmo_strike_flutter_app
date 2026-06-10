/// Time-keyed terrain corridor authoring: how much the floor/ceiling
/// bands swell (squeezing the playable corridor) and how fast the ground
/// scrolls, over a level's PLAYING game-time. Pure data — levels author
/// tunnels, pinch points, and canyon chases as keyframe lists.
class TerrainKeyframe {
  const TerrainKeyframe(
    this.t, {
    this.floor = 1,
    this.ceil = 1,
    this.scroll = 1,
  });

  /// Seconds of playing time into the level.
  final double t;

  /// Multiplier on the biome's base floor band height (1 = neutral).
  final double floor;

  /// Multiplier on the biome's base ceiling band height (1 = neutral).
  final double ceil;

  /// Terrain scroll-speed multiplier (canyon chases crank this).
  final double scroll;
}

/// A piecewise-linear profile over [TerrainKeyframe]s; values clamp to
/// the first/last key outside the authored range.
class TerrainProfile {
  const TerrainProfile(this.keys);

  /// Flat corridor at the biome's base heights for the whole level.
  static const TerrainProfile neutral = TerrainProfile([TerrainKeyframe(0)]);

  final List<TerrainKeyframe> keys;

  double floorAt(double t) => _sample(t, (k) => k.floor);
  double ceilAt(double t) => _sample(t, (k) => k.ceil);
  double scrollAt(double t) => _sample(t, (k) => k.scroll);

  double _sample(double t, double Function(TerrainKeyframe) sel) {
    if (keys.isEmpty) return 1;
    if (t <= keys.first.t) return sel(keys.first);
    for (var i = 0; i < keys.length - 1; i++) {
      final a = keys[i];
      final b = keys[i + 1];
      if (t < b.t) {
        final f = (t - a.t) / (b.t - a.t);
        return sel(a) + (sel(b) - sel(a)) * f;
      }
    }
    return sel(keys.last);
  }
}
