import 'cosmo_strike_game.dart';

/// Injects the player's ARMED Tactical Gear into a Flame run.
///
/// The inventory keys come from PowerUpCubit (`gear_*`, see
/// PremiumPowerUpType); pre-3.2 snake_case keys are still matched so a key
/// armed from an un-migrated inventory still applies.
/// GameplayScreen consumes the armed slot exactly once (decrementing
/// inventory) and passes the key to `CosmoStrikeGame(armedLoadoutKey:)`;
/// the game applies it on the first levelIntro → playing transition, so
/// the boost starts when the action does.
abstract final class ArmedLoadout {
  static void apply(CosmoStrikeGame game, String key) {
    final player = game.player;
    switch (key) {
      case 'gear_afterburner':
      case 'speed_boost':
        player.speedTimer = 15;
        player.speedTimeTotal = 15;
        break;
      case 'gear_aegis':
      case 'invincibility':
      case 'mega_invincibility': // defensive — normally folded upstream
        player.shielded = true;
        player.grantInvuln(8);
        break;
      case 'gear_bounty':
      case 'score_multiplier':
        game.setScoreMultiplier(2, 30);
        break;
      case 'gear_chrono':
      case 'slow_motion':
        game.applySlowmo(10);
        break;
      case 'gear_warp':
      case 'teleport':
        // One warp-escape charge: the first hit is negated and the ship
        // warps back to spawn with a flash.
        player.teleportCharges += 1;
        break;
      case 'gear_cloak':
      case 'ghost_mode':
        player.ghostTimer = 12;
        player.ghostTimeTotal = 12;
        break;
      case 'gear_lure':
      case 'magnetic_pickup':
        player.magnetTimer = 60;
        player.magnetTimeTotal = 60;
        break;
      case 'gear_laststand':
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
