import 'dart:math' as math;

import 'tuning.dart';

/// Adaptive pressure for a run. Pure Dart (no Flame) so it is unit-tested.
///
/// - Clean flying raises [intensity] after [GameTuning.calmBeforeRamp]
///   seconds, up to [GameTuning.maxIntensity] over
///   [GameTuning.rampSeconds]; each landed hit knocks it down.
/// - Standing still: [onPlayerPosition] samples the ship; when it has
///   moved less than [GameTuning.idleDistance] within the last
///   [GameTuning.idleWindow] seconds, [idle] is true and [consumeVolley]
///   hands out a sniper volley every [GameTuning.idleVolleyEvery] s.
class IntensityDirector {
  double _clean = 0;
  double _intensity = 1;
  double _volleyTimer = 0;

  // Rolling position samples (time, x, y) covering the idle window.
  final List<(double, double, double)> _samples = [];
  double _clock = 0;

  /// Multiplier on enemy fire rate / aimed chance (bullet speed takes
  /// half the swing — see [bulletSpeedScale]).
  double get intensity => _intensity;
  double get bulletSpeedScale => 1 + (_intensity - 1) * 0.5;

  bool get idle {
    if (_samples.isEmpty || _clock < GameTuning.idleWindow) return false;
    double minX = double.infinity, maxX = -double.infinity;
    double minY = double.infinity, maxY = -double.infinity;
    for (final s in _samples) {
      minX = math.min(minX, s.$2);
      maxX = math.max(maxX, s.$2);
      minY = math.min(minY, s.$3);
      maxY = math.max(maxY, s.$3);
    }
    return math.max(maxX - minX, maxY - minY) < GameTuning.idleDistance;
  }

  void reset() {
    _clean = 0;
    _intensity = 1;
    _volleyTimer = 0;
    _samples.clear();
    _clock = 0;
  }

  /// Advance by [dt] seconds of live play.
  void update(double dt) {
    _clock += dt;
    _clean += dt;
    final over = _clean - GameTuning.calmBeforeRamp;
    final target = over <= 0
        ? 1.0
        : 1 + (GameTuning.maxIntensity - 1) * math.min(1, over / GameTuning.rampSeconds);
    // Ease toward the target; hits drop it instantly (onPlayerHit) and it
    // recovers gradually.
    const rate = 0.05;
    if (_intensity < target) {
      _intensity = math.min(target, _intensity + dt * rate);
    } else if (_intensity > target) {
      _intensity = math.max(target, _intensity - dt * rate);
    }
    if (_volleyTimer > 0) _volleyTimer -= dt;
  }

  void onPlayerPosition(double x, double y) {
    _samples.add((_clock, x, y));
    while (_samples.isNotEmpty && _clock - _samples.first.$1 > GameTuning.idleWindow) {
      _samples.removeAt(0);
    }
  }

  void onPlayerHit() {
    _clean = 0;
    _intensity = math.max(GameTuning.minIntensity, _intensity - GameTuning.hitRelief);
  }

  /// True when an idle sniper volley should fire now (and arms the cooldown).
  bool consumeVolley() {
    if (!idle || _volleyTimer > 0) return false;
    _volleyTimer = GameTuning.idleVolleyEvery;
    return true;
  }
}
