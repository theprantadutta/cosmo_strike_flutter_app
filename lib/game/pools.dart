import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import 'components/bullets.dart';
import 'components/fx.dart';
import 'components/popups.dart';
import 'cosmo_strike_game.dart';
import 'game_assets.dart';

/// Always-mounted object pools for the high-churn components (bullets,
/// hit sparks, muzzle flashes, score popups). Components are added to the
/// game ONCE and recycled with activate/deactivate — never removed and
/// re-added — which keeps per-shot allocations, GC pressure, and
/// collision-broadphase churn at zero during play.
///
/// Pool exhaustion recycles the oldest slot (round-robin), which is
/// invisible in practice at these sizes.
class GamePools {
  GamePools(this.game);

  final CosmoStrikeGame game;

  static const int playerBulletCount = 48;
  static const int enemyBulletCount = 160;
  static const int sparkCount = 24;
  static const int flashCount = 12;
  static const int popupCount = 16;

  late final List<PlayerBullet> _playerBullets;
  late final List<EnemyBullet> _enemyBullets;
  late final List<PooledFx> _sparks;
  late final List<PooledFx> _flashes;
  late final List<ScorePopup> _popups;

  int _pb = 0, _eb = 0, _sp = 0, _fl = 0, _po = 0;

  late final SpriteAnimation _sparkAnim;
  late final SpriteAnimation _flashAnim;

  /// Pre-mounts every pooled component. Call from the game's onLoad,
  /// after [GameAssets.preload].
  Future<void> mount() async {
    _sparkAnim = oneShotAnimation(GameAssets.hitSparkSheet, 4, fps: 24);
    _flashAnim = oneShotAnimation(GameAssets.muzzleFlashSheet, 3, fps: 30);
    _playerBullets =
        List.generate(playerBulletCount, (_) => PlayerBullet());
    _enemyBullets = List.generate(enemyBulletCount, (_) => EnemyBullet());
    _sparks = List.generate(sparkCount, (_) => PooledFx());
    _flashes = List.generate(flashCount, (_) => PooledFx());
    _popups = List.generate(popupCount, (_) => ScorePopup());
    await game.addAll([
      ..._playerBullets,
      ..._enemyBullets,
      ..._sparks,
      ..._flashes,
      ..._popups,
    ]);
  }

  PlayerBullet playerBullet({
    required Vector2 spawn,
    double speed = 520,
    int damage = 1,
    bool heavy = false,
    double driftY = 0,
  }) {
    final b = _playerBullets[_pb];
    _pb = (_pb + 1) % _playerBullets.length;
    b.activate(
      spawn: spawn,
      speed: speed,
      damage: damage,
      heavy: heavy,
      driftY: driftY,
    );
    return b;
  }

  EnemyBullet enemyBullet({
    required Vector2 spawn,
    required Vector2 velocity,
    double damage = 0.34,
    bool fromBoss = false,
    double gravity = 0,
  }) {
    final b = _enemyBullets[_eb];
    _eb = (_eb + 1) % _enemyBullets.length;
    b.activate(
      spawn: spawn,
      velocity: velocity,
      damage: damage,
      fromBoss: fromBoss,
      gravity: gravity,
    );
    return b;
  }

  void hitSpark(Vector2 at) {
    final fx = _sparks[_sp];
    _sp = (_sp + 1) % _sparks.length;
    fx.play(_sparkAnim, at, Vector2.all(24));
  }

  void muzzleFlash(Vector2 at) {
    final fx = _flashes[_fl];
    _fl = (_fl + 1) % _flashes.length;
    fx.play(_flashAnim, at, Vector2.all(20));
  }

  void scorePopup(
    Vector2 at,
    String text, {
    Color color = ScorePopup.defaultColor,
    double scale = 1,
    double duration = 0.7,
  }) {
    final p = _popups[_po];
    _po = (_po + 1) % _popups.length;
    p.show(at, text, color: color, scale: scale, duration: duration);
  }

  /// Deactivate every live enemy bullet (revive grace / bomb sweep).
  void clearEnemyBullets() {
    for (final b in _enemyBullets) {
      b.deactivate();
    }
  }

  /// Deactivate only boss-fired bullets (boss phase-change fairness).
  void clearBossBullets() {
    for (final b in _enemyBullets) {
      if (b.active && b.fromBoss) b.deactivate();
    }
  }

  /// Deactivate every live enemy bullet within [radius] of [center]
  /// (missile blasts sweep incoming fire).
  void clearEnemyBulletsWithin(Vector2 center, double radius) {
    final r2 = radius * radius;
    for (final b in _enemyBullets) {
      if (b.active && b.position.distanceToSquared(center) <= r2) {
        b.deactivate();
      }
    }
  }
}
