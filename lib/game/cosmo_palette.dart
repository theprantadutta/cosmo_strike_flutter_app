import 'package:flutter/painting.dart';

import '../utils/constants.dart' show GameTheme;

/// Prism Noir palette for the Cosmo Strike gameplay layer: a near-black
/// #08080B field, graphite hulls, and the cyan → violet → pink → gold prism
/// used for outlines, cores and FX. Kept separate from the app UI tokens so
/// the Flame engine stays self-contained.
///
/// The `const` colours below are fixed. The purchased colour THEME only
/// tints gameplay, through the mutable "skin" half of this class
/// ([applySkin] / [applyGameTheme]): player stripe, thrust, shots, muzzle
/// flashes and the background washes. Components read the cached paints /
/// [skinVersion]; nothing allocates per frame.
class CosmoPalette {
  CosmoPalette._();

  // ---- Prism stops ----
  static const Color cyan = Color(0xFF7CF5FF);
  static const Color violet = Color(0xFFA78BFA);
  static const Color pink = Color(0xFFFF8AD8);
  static const Color gold = Color(0xFFFFD58A);
  static const Color mint = Color(0xFF9BFFC8);
  static const List<Color> prism = [cyan, violet, pink, gold];

  // ---- Graphite / ink ----
  static const Color ink = Color(0xFFF4F3F7);
  static const Color graphite = Color(0xFF1E1E26);
  static const Color raised = Color(0xFF141419);

  // ---- Legacy role names (still read by the HUD) ----
  /// Player hull / primary info accent.
  static const Color hull = cyan;
  static const Color hullDark = Color(0xFF2E7F8A);
  static const Color hullLight = Color(0xFFB8FAFF);

  /// Energy (player shots, ammo meters).
  static const Color energy = cyan;

  /// Highlight / primary ink.
  static const Color highlight = ink;

  // Backgrounds (gameplay canvas, deepest -> raised).
  static const Color bgDeep = Color(0xFF08080B);
  static const Color bgMid = Color(0xFF0E0E12);
  static const Color bgHigh = raised;

  /// Hairline / grid lines.
  static const Color grid = Color(0x1AFFFFFF);

  /// Hazard / enemy / danger.
  static const Color hostile = pink;
  static const Color hostileDeep = Color(0xFFB0558F);

  /// Positive pickup / success.
  static const Color boon = mint;

  // =========================================================================
  // Skin (purchased colour theme → gameplay tint only)
  // =========================================================================

  static const Color defaultAccent = cyan;
  static const Color defaultSecondary = pink;

  static Color _accent = defaultAccent;
  static Color _secondary = defaultSecondary;

  /// Bumped on every skin change so components can lazily rebuild any
  /// gradient shaders they cache (checked once per frame, rebuilt rarely).
  static int skinVersion = 0;

  /// Player shot / thrust / stripe-nose colour.
  static Color get accent => _accent;

  /// Stripe-tail colour + right-hand background wash.
  static Color get secondary => _secondary;

  /// Modulate paint for the neutral-white player sprites (shots, thrust,
  /// muzzle flash): white art × accent. Mutated in place by [applySkin].
  static final Paint accentTint = Paint()
    ..colorFilter = const ColorFilter.mode(defaultAccent, BlendMode.modulate);

  /// Tint the gameplay for a purchased colour theme. Cheap: mutates the
  /// shared paints once; call it before / when the game starts (or again
  /// on a theme change — the next frame picks it up).
  static void applySkin({required Color accent, required Color secondary}) {
    if (accent == _accent && secondary == _secondary) return;
    _accent = accent;
    _secondary = secondary;
    accentTint.colorFilter = ColorFilter.mode(accent, BlendMode.modulate);
    skinVersion++;
  }

  /// Back to the stock Prism cyan / pink.
  static void resetSkin() =>
      applySkin(accent: defaultAccent, secondary: defaultSecondary);

  /// Convenience mapping from the app's [GameTheme]: the default `classic`
  /// slot is Prism Noir itself; every other theme tints with its ship
  /// colour (accent) + food colour (secondary).
  static void applyGameTheme(GameTheme theme) {
    if (theme == GameTheme.classic) {
      resetSkin();
    } else {
      applySkin(accent: theme.shipColor, secondary: theme.foodColor);
    }
  }
}
