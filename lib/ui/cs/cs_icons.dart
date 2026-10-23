import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../models/premium_power_up.dart';
import '../../utils/constants.dart';

/// Shared Material Symbols mappings so every screen shows the same glyph for
/// the same game concept (modes, power-ups).
class CsIcons {
  CsIcons._();

  static IconData mode(GameMode mode) => mode.icon;

  /// Tactical Gear inventory keys (PowerUpCubit; current or legacy) → glyph.
  static IconData powerUp(String inventoryKey) =>
      PremiumPowerUpType.fromKey(inventoryKey)?.icon ?? Symbols.bolt_rounded;

  static String powerUpLabel(String inventoryKey) =>
      PremiumPowerUpType.fromKey(inventoryKey)?.displayName ?? inventoryKey;
}
