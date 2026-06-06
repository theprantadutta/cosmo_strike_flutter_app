import 'cosmo_strike_game.dart';

/// Injects the player's ARMED store power-up into a Flame run.
///
/// The inventory keys come from PowerUpCubit (premium variants are already
/// folded into base keys at grant time — see `_inventoryKeyForPremium`).
/// GameplayScreen consumes the armed slot exactly once (decrementing
/// inventory) and passes the key to `CosmoStrikeGame(armedLoadoutKey:)`;
/// the game applies it on the first levelIntro → playing transition, so
/// the boost starts when the action does.
abstract final class ArmedLoadout {
  static void apply(CosmoStrikeGame game, String key) {
    final player = game.player;
    switch (key) {
      case 'speed_boost':
        player.speedTimer = 15;
        break;
      case 'invincibility':
      case 'mega_invincibility': // defensive — normally folded upstream
        player.shielded = true;
        player.grantInvuln(8);
        break;
      case 'score_multiplier':
        game.setScoreMultiplier(2, 30);
        break;
      case 'slow_motion':
        game.applySlowmo(10);
        break;
      case 'teleport':
        // One warp-escape charge: the first hit is negated and the ship
        // warps back to spawn with a flash.
        player.teleportCharges += 1;
        break;
      case 'ghost_mode':
        player.ghostTimer = 12;
        break;
      case 'magnetic_pickup':
        player.magnetTimer = 60;
        break;
      case 'score_shield':
        // One charge: a would-be-lethal hit restores health to 0.5
        // instead of costing a life.
        player.scoreShieldCharges += 1;
        break;
      default:
        // Unknown key (future store item) — ignore rather than crash.
        break;
    }
  }
}
