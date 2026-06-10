import 'package:flutter/foundation.dart';

/// Kill-chain combo + bullet-graze state for a single run.
///
/// Combo: every kill extends a chain; the chain decays to zero after
/// [chainWindow] seconds without a kill and BREAKS instantly when a hit
/// actually lands on the player (shield pops / ghost passes don't break
/// it — power-ups doing their job). The chain drives a score multiplier:
/// x1 -> x2 at 5, x3 at 10, x4 at 20.
///
/// Graze: an enemy bullet passing close to the hull without hitting
/// charges a meter; a full meter ([grazesPerMissile] grazes) converts to
/// +1 missile. Playing dangerously = more score AND more ammo.
class ComboGrazeController {
  static const double chainWindow = 3.0;
  static const int grazesPerMissile = 15;

  /// Current chain length.
  final ValueNotifier<int> comboNotifier = ValueNotifier(0);

  /// Current score multiplier tier (1/2/3/4).
  final ValueNotifier<int> multiplierNotifier = ValueNotifier(1);

  /// Graze meter fill, 0..1.
  final ValueNotifier<double> grazeNotifier = ValueNotifier(0);

  int maxCombo = 0;
  int grazeCount = 0;

  double _decay = 0;
  int _grazeMeter = 0;

  int get multiplier => multiplierNotifier.value;
  int get chain => comboNotifier.value;

  static int _tierFor(int chain) {
    if (chain >= 20) return 4;
    if (chain >= 10) return 3;
    if (chain >= 5) return 2;
    return 1;
  }

  /// Registers a kill. Returns true when the multiplier tier just rose
  /// (callers celebrate with a popup + sfx).
  bool onKill() {
    final chain = comboNotifier.value + 1;
    comboNotifier.value = chain;
    if (chain > maxCombo) maxCombo = chain;
    _decay = chainWindow;
    final tier = _tierFor(chain);
    if (tier != multiplierNotifier.value) {
      multiplierNotifier.value = tier;
      return true;
    }
    return false;
  }

  /// A hit landed on the player: the chain breaks.
  void onPlayerDamaged() {
    comboNotifier.value = 0;
    multiplierNotifier.value = 1;
    _decay = 0;
  }

  /// Registers a graze. Returns true when the meter just filled (caller
  /// grants +1 missile).
  bool onGraze() {
    grazeCount++;
    _grazeMeter++;
    if (_grazeMeter >= grazesPerMissile) {
      _grazeMeter = 0;
      grazeNotifier.value = 0;
      return true;
    }
    grazeNotifier.value = _grazeMeter / grazesPerMissile;
    return false;
  }

  /// Tick the chain decay (sim time, only while playing).
  void update(double dt) {
    if (comboNotifier.value == 0) return;
    _decay -= dt;
    if (_decay <= 0) {
      comboNotifier.value = 0;
      multiplierNotifier.value = 1;
    }
  }

  void dispose() {
    comboNotifier.dispose();
    multiplierNotifier.dispose();
    grazeNotifier.dispose();
  }
}
