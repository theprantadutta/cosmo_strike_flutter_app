import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../utils/constants.dart';

/// Shared Material Symbols mappings so every screen shows the same glyph for
/// the same game concept (modes, power-ups).
class CsIcons {
  CsIcons._();

  static IconData mode(GameMode mode) => switch (mode) {
        GameMode.classic => Symbols.rocket_rounded,
        GameMode.zen => Symbols.self_improvement_rounded,
        GameMode.speedChallenge => Symbols.speed_rounded,
        GameMode.onslaught => Symbols.swords_rounded,
        GameMode.survival => Symbols.favorite_rounded,
        GameMode.timeAttack => Symbols.timer_rounded,
        GameMode.powerUpMadness => Symbols.bolt_rounded,
        GameMode.perfectGame => Symbols.verified_rounded,
      };

  /// Store power-up inventory keys (PowerUpCubit) → glyph.
  static IconData powerUp(String inventoryKey) => switch (inventoryKey) {
        'speed_boost' => Symbols.speed_rounded,
        'invincibility' => Symbols.shield_rounded,
        'score_multiplier' => Symbols.star_rounded,
        'slow_motion' => Symbols.slow_motion_video_rounded,
        'teleport' => Symbols.swap_calls_rounded,
        'ghost_mode' => Symbols.blur_on_rounded,
        'magnetic_pickup' => Symbols.attractions_rounded,
        'score_shield' => Symbols.security_rounded,
        _ => Symbols.bolt_rounded,
      };

  static String powerUpLabel(String inventoryKey) => switch (inventoryKey) {
        'speed_boost' => 'Speed Boost',
        'invincibility' => 'Invincibility',
        'score_multiplier' => 'Score Multiplier',
        'slow_motion' => 'Slow Motion',
        'teleport' => 'Warp Escape',
        'ghost_mode' => 'Ghost Mode',
        'magnetic_pickup' => 'Orb Magnet',
        'score_shield' => 'Last Stand',
        _ => inventoryKey,
      };
}
