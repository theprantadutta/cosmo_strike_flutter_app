import 'package:flutter/foundation.dart';

import 'tuning.dart';

/// Kill-chain combo + bullet-graze state for a single run.
///
/// Combo: every kill extends a chain; the chain decays to zero after
/// [chainWindow] seconds without a kill and BREAKS instantly when a hit
/// actually lands on the player (shield pops / ghost passes don't break
/// it — power-ups doing their job). The chain drives a score multiplier:
/// x1 -> x2 at 5, x3 at 10, x4 at 20.
///
/// Graze: an enemy bullet passing close to the hull without hitting
/// charges the Overdrive meter ([GameTuning.grazesForOverdrive] grazes to
/// fill) and keeps a live chain going a little longer. A full meter stays
/// full until the player spends it. Playing dangerously = more score AND
/// Overdrive.
class ComboGrazeController {
  static const double chainWindow = 3.0;

  /// Current chain length.
  final ValueNotifier<int> comboNotifier = ValueNotifier(0);

  /// Current score multiplier tier (1/2/3/4).
  final ValueNotifier<int> multiplierNotifier = ValueNotifier(1);

  /// Overdrive meter fill, 0..1 (1 = ready to fire).
  final ValueNotifier<double> grazeNotifier = ValueNotifier(0);

  bool get overdriveReady => grazeNotifier.value >= 1;

  int maxCombo = 0;
  int grazeCount = 0;

  double _decay = 0;

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

  /// Registers a graze. Returns true when the Overdrive meter just became
  /// full (caller announces it).
  bool onGraze() {
    grazeCount++;
    if (comboNotifier.value > 0) {
      _decay = (_decay + GameTuning.grazeChainExtend).clamp(0, chainWindow);
    }
    return addCharge(1 / GameTuning.grazesForOverdrive);
  }

  /// Adds Overdrive charge (0..1 of the meter). Returns true when this
  /// call filled it.
  bool addCharge(double amount) {
    if (overdriveReady) return false;
    final next = (grazeNotifier.value + amount).clamp(0.0, 1.0);
    grazeNotifier.value = next;
    return next >= 1;
  }

  /// Spend a full meter. Returns false if it wasn't full.
  bool consumeOverdrive() {
    if (!overdriveReady) return false;
    grazeNotifier.value = 0;
    return true;
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
