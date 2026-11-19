import 'dart:math' as math;

import 'package:flame/components.dart';

import '../debug/perf_monitor.dart';
import 'components/boss.dart';
import 'components/enemy.dart';
import 'components/power_up.dart';
import 'components/terrain.dart';
import 'cosmo_strike_game.dart';

/// Demo / profiling pilot (see `DemoMode`). Flies the ship like a busy
/// player so frame pacing is measured under real load: weaves through
/// incoming fire, lines up on the nearest target, grabs drops, and spends
/// Overdrive and missiles as they come up. The game runs it invincible
/// (`CosmoStrikeGame.demoInvincible`) so a run never ends early.
///
/// Decisions run at 10 Hz and scan a fixed set of lanes, so the pilot's
/// own cost stays negligible next to the frame being measured.
class Autopilot extends Component with HasGameReference<CosmoStrikeGame> {
  static const double _thinkInterval = 0.1;
  static const int _lanes = 15;
  static const double _horizon = 1.2; // seconds of bullet look-ahead
  static const double _hitRadius = 42;

  double _think = 0;
  double _time = 0;
  double _missileCooldown = 0;
  double _laneY = -1;
  final Vector2 _target = Vector2.zero();

  @override
  void update(double dt) {
    super.update(dt);
    PerfMonitor.instance.tag = 'L${game.levelIndex}:${game.phase.name}';
    if (game.phase != GamePhase.playing) return;
    _time += dt;
    _missileCooldown -= dt;
    _think -= dt;
    if (_think > 0) return;
    _think = _thinkInterval;
    _decide();
  }

  void _decide() {
    final player = game.player;
    final px = player.position.x;
    final py = player.position.y;
    final top = game.playfieldTop + 28;
    final bottom = game.playfieldBottom - 28;
    if (bottom <= top) return;

    // One pass over the scene for targets, drops and obstacles.
    double? targetY;
    var targetX = double.infinity;
    double? dropY;
    var dropDist = double.infinity;
    var bossUp = false;
    final obstacles = <TerrainObstacle>[];
    for (final c in game.children) {
      if (c is EnemyShip) {
        if (c.position.x > px && c.position.x < targetX) {
          targetX = c.position.x;
          targetY = c.position.y;
        }
      } else if (c is Boss) {
        bossUp = true;
        targetY ??= c.position.y;
      } else if (c is PowerUp) {
        final d = c.position.distanceTo(player.position);
        if (d < dropDist) {
          dropDist = d;
          dropY = c.position.y;
        }
      } else if (c is TerrainObstacle) {
        obstacles.add(c);
      }
    }
    if (dropDist > game.size.x * 0.45) dropY = null;

    var bestY = py;
    var bestCost = double.infinity;
    for (var i = 0; i < _lanes; i++) {
      final lane = top + (bottom - top) * i / (_lanes - 1);
      var cost = 0.0;

      for (final b in game.pools.enemyBullets) {
        if (!b.active) continue;
        final vx = b.velocity.x;
        final dx = b.position.x - px;
        double t;
        if (vx < -1) {
          t = dx / -vx;
        } else if (dx.abs() < 60) {
          t = 0; // already alongside
        } else {
          continue;
        }
        if (t < 0 || t > _horizon) continue;
        final y = b.position.y + b.velocity.y * t;
        final miss = (y - lane).abs();
        if (miss < _hitRadius) cost += (_horizon - t + 0.2) * (1 - miss / _hitRadius) * 10;
      }
      for (final o in obstacles) {
        final dx = o.position.x - px;
        if (dx < -40 || dx > game.size.x * 0.4) continue;
        if ((o.position.y - lane).abs() < o.size.y / 2 + 30) cost += 6;
      }

      final aimY = dropY ?? targetY;
      if (aimY != null) cost += (lane - aimY).abs() / game.size.y * (bossUp ? 2 : 3);
      cost += (lane - py).abs() / game.size.y * 0.6; // don't thrash
      if (cost < bestCost) {
        bestCost = cost;
        bestY = lane;
      }
    }

    // Smooth lane changes a little so the ship flies, not teleports.
    _laneY = _laneY < 0 ? bestY : _laneY + (bestY - _laneY) * 0.7;
    final x = player.rightBound * (0.62 + 0.18 * math.sin(_time * 0.7));
    game.steerTo(_target..setValues(x, _laneY));

    if (game.combo.overdriveReady) game.activateOverdrive();
    if (_missileCooldown <= 0 && game.missileAmmoNotifier.value > 0 &&
        (bossUp || targetY != null)) {
      game.fireMissile();
      _missileCooldown = bossUp ? 2.5 : 6;
    }
  }
}
