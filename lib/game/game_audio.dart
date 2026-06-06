import 'package:cosmo_strike_flutter_app/services/audio_service.dart';

/// Thin static facade over [AudioService] for the Flame game layer.
///
/// Every hook is fire-and-forget and safe to call while the sound files
/// are still missing (AudioService no-ops silently for gameplay keys —
/// see `_playSystemSound`). The shoot hook is throttled because rapid
/// fire can request a sound every ~120 ms per ship and SoLoud voices
/// are a finite resource.
abstract final class GameAudio {
  static const Duration _shootThrottle = Duration(milliseconds: 90);
  static DateTime _lastShoot = DateTime.fromMillisecondsSinceEpoch(0);

  static void shoot() {
    final now = DateTime.now();
    if (now.difference(_lastShoot) < _shootThrottle) return;
    _lastShoot = now;
    AudioService().playSound('shoot');
  }

  static void enemyDown() => AudioService().playSound('enemy_down');
  static void playerHit() => AudioService().playSound('player_hit');
  static void pickup() => AudioService().playSound('pickup');
  static void bossWarn() => AudioService().playSound('boss_warn');
  static void bossDown() => AudioService().playSound('boss_down');
  static void missile() => AudioService().playSound('missile');
  static void revive() => AudioService().playSound('revive');
  static void levelClear() => AudioService().playSound('level_clear');
  static void gameOver() => AudioService().playSound('game_over');
  static void gameStart() => AudioService().playSound('game_start');
}
