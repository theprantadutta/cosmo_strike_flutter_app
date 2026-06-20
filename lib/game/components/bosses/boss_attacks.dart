import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../../cosmo_strike_game.dart';
import '../../game_audio.dart';
import '../boss.dart';
import '../telegraph.dart';
import 'boss_brain.dart';

/// Shared parameterized boss attacks. Tuning numbers (counts, bullet
/// speed, cadence) come from the level's BossDef; shapes come from here.

/// Velocity that streams a field-spanning bullet OUT of the boss [muzzle]
/// and fans it to its lane, reconverging to [laneY] at [convergeX] (the
/// player's zone) while keeping a constant horizontal [speed]. This makes
/// curtains/rakes read as leaving the boss's gun instead of materialising
/// across the whole screen — yet they still arrive in their lanes with the
/// same gap, so the dodge geometry near the player is unchanged.
Vector2 _fanFromMuzzle(
  Vector2 muzzle,
  double convergeX,
  double laneY,
  double speed,
) {
  // Horizontal travel time to the convergence column; vy is solved so the
  // bullet is exactly on its lane when it gets there.
  final t = ((muzzle.x - convergeX) / speed).clamp(0.0001, double.infinity);
  return Vector2(-speed, (laneY - muzzle.y) / t);
}

/// Left-facing half-circle spray (the old shared pattern, now just one
/// tool among many).
class RadialSprayAttack extends BossAttack {
  const RadialSprayAttack({double telegraph = 0.8}) : _telegraph = telegraph;

  final double _telegraph;

  @override
  double get telegraphSeconds => _telegraph;

  @override
  void execute(Boss boss, CosmoStrikeGame game) {
    final count = boss.def.sprayCount;
    for (var i = 0; i < count; i++) {
      final angle = math.pi * 0.5 + (i / (count - 1)) * math.pi;
      game.pools.enemyBullet(
        spawn: boss.muzzle,
        velocity:
            Vector2(math.cos(angle), math.sin(angle)) * boss.def.bulletSpeed,
        damage: 0.25,
        fromBoss: true,
      );
    }
  }
}

/// Aimed volley along a ray CAPTURED at telegraph start and shown as a
/// dashed line — sidestep it.
class AimedBurstAttack extends BossAttack {
  const AimedBurstAttack();

  @override
  double get telegraphSeconds => 0.9;

  @override
  void telegraph(Boss boss, CosmoStrikeGame game) {
    boss.capturedAim
      ..setFrom(game.player.position - boss.muzzle)
      ..normalize();
    game.add(AimLineMarker(
      origin: boss.muzzle,
      direction: boss.capturedAim,
      life: telegraphSeconds,
    ));
  }

  @override
  void execute(Boss boss, CosmoStrikeGame game) {
    final half = boss.def.aimedCount ~/ 2;
    for (var i = -half; i <= boss.def.aimedCount - half - 1; i++) {
      game.pools.enemyBullet(
        spawn: boss.muzzle,
        velocity: boss.capturedAim * (boss.def.bulletSpeed + 80) +
            Vector2(0, i * 60.0),
        damage: 0.3,
        fromBoss: true,
      );
    }
  }
}

/// Leviathan's wall: full-height bullet curtain with ONE safe gap —
/// telegraphed green so you can be in position before it arrives.
class BulletWallAttack extends BossAttack {
  const BulletWallAttack({this.gapHalf = 55, this.walls = 1});

  final double gapHalf;
  final int walls;

  @override
  double get telegraphSeconds => 1.1;

  @override
  void telegraph(Boss boss, CosmoStrikeGame game) {
    final top = game.playfieldTop + 10;
    final bottom = game.playfieldBottom - 10;
    boss.capturedY = top +
        gapHalf +
        game.rng.nextDouble() * math.max(1, bottom - top - gapHalf * 2);
    game.add(SafeGapMarker(
      centerY: boss.capturedY,
      bandHeight: gapHalf * 2,
      life: telegraphSeconds + 0.5,
    ));
  }

  @override
  void execute(Boss boss, CosmoStrikeGame game) {
    final top = game.playfieldTop + 10;
    final bottom = game.playfieldBottom - 10;
    final muzzle = boss.muzzle;
    final convergeX = game.size.x * 0.16; // the wall "forms" at the player zone
    const step = 46.0;
    for (var w = 0; w < walls; w++) {
      // The second wall trails behind (slower) with its gap shifted —
      // thread one, then drift to the other.
      final gapY = w == 0
          ? boss.capturedY
          : (boss.capturedY + (bottom - top) * 0.35)
              .clamp(top + gapHalf, bottom - gapHalf);
      final speed = boss.def.bulletSpeed * (1 - 0.18 * w);
      for (double y = top; y <= bottom; y += step) {
        if ((y - gapY).abs() < gapHalf) continue;
        // All bullets leave the boss's muzzle and fan out to the curtain.
        game.pools.enemyBullet(
          spawn: muzzle,
          velocity: _fanFromMuzzle(muzzle, convergeX, y, speed),
          damage: 0.3,
          fromBoss: true,
        );
      }
    }
  }
}

/// Slow expanding ring with generous spacing (Hive Queen's organic pulse).
class PulseRingAttack extends BossAttack {
  const PulseRingAttack({this.count = 12});

  final int count;

  @override
  double get telegraphSeconds => 0.8;

  @override
  void execute(Boss boss, CosmoStrikeGame game) {
    for (var i = 0; i < count; i++) {
      final a = (i / count) * math.pi * 2;
      game.pools.enemyBullet(
        spawn: boss.muzzle,
        velocity:
            Vector2(math.cos(a), math.sin(a)) * (boss.def.bulletSpeed * 0.7),
        damage: 0.25,
        fromBoss: true,
      );
    }
  }
}

/// Dense radial burst with one rotating safe wedge (Mothership
/// desperation): the gap angle advances every cast — follow it around.
class RotatingGapRadialAttack extends BossAttack {
  const RotatingGapRadialAttack({this.count = 22});

  final int count;

  @override
  double get telegraphSeconds => 1.0;

  @override
  void execute(Boss boss, CosmoStrikeGame game) {
    const gapWidth = math.pi / 3;
    final gapCenter = boss.scratchAngle % (math.pi * 2);
    boss.scratchAngle += 0.9;
    for (var i = 0; i < count; i++) {
      final a = (i / count) * math.pi * 2;
      var d = (a - gapCenter).abs() % (math.pi * 2);
      if (d > math.pi) d = math.pi * 2 - d;
      if (d < gapWidth / 2) continue;
      game.pools.enemyBullet(
        spawn: boss.muzzle,
        velocity:
            Vector2(math.cos(a), math.sin(a)) * (boss.def.bulletSpeed * 0.85),
        damage: 0.3,
        fromBoss: true,
      );
    }
  }
}

/// War Machine artillery: arcing shells onto marked landing points.
class MortarLobAttack extends BossAttack {
  const MortarLobAttack({this.count = 3});

  final int count;
  static const double _flightTime = 1.15;
  static const double _gravity = 540;

  @override
  double get telegraphSeconds => 1.1;

  @override
  void telegraph(Boss boss, CosmoStrikeGame game) {
    boss.capturedPoints.clear();
    final floorY = game.playfieldBottom - 14;
    final px = game.player.position.x;
    for (var i = 0; i < count; i++) {
      final x = (px + (i - (count - 1) / 2) * 120 +
              (game.rng.nextDouble() - 0.5) * 60)
          .clamp(game.size.x * 0.08, game.size.x * 0.7);
      final p = Vector2(x, floorY);
      boss.capturedPoints.add(p);
      game.add(LandingRingMarker(at: p, life: telegraphSeconds + _flightTime));
    }
    GameAudio.mortar();
  }

  @override
  void execute(Boss boss, CosmoStrikeGame game) {
    final from = boss.position + Vector2(-boss.size.x * 0.2, -boss.size.y * 0.3);
    for (final target in boss.capturedPoints) {
      // Ballistic solve: reach the marker in _flightTime under _gravity.
      final vx = (target.x - from.x) / _flightTime;
      final vy = (target.y - from.y - 0.5 * _gravity * _flightTime * _flightTime) /
          _flightTime;
      game.pools.enemyBullet(
        spawn: from.clone(),
        velocity: Vector2(vx, vy),
        damage: 0.4,
        fromBoss: true,
        gravity: _gravity,
      );
    }
  }
}

/// Dreadnought turret rake: straight volleys stepping top → bottom — a
/// curtain that combs the field row by row.
class TurretSweepAttack extends BossAttack {
  const TurretSweepAttack({this.rows = 6});

  final int rows;
  static const double _rowInterval = 0.22;

  @override
  double get telegraphSeconds => 0.9;

  @override
  bool get sustained => true;

  @override
  void execute(Boss boss, CosmoStrikeGame game) {
    boss.scratchCount = 0;
  }

  @override
  bool updateExecution(Boss boss, CosmoStrikeGame game, double dt) {
    final due = (boss.execClock / _rowInterval).floor() + 1;
    final muzzle = boss.muzzle;
    final convergeX = game.size.x * 0.16;
    final speed = boss.def.bulletSpeed + 40;
    while (boss.scratchCount < due && boss.scratchCount < rows) {
      final top = game.playfieldTop;
      final span = game.playfieldBottom - top;
      final y = top + (boss.scratchCount + 0.5) * span / rows;
      // Each successive shot leaves the muzzle and angles to its row, so
      // the rake reads as the boss's turret sweeping top → bottom.
      game.pools.enemyBullet(
        spawn: muzzle,
        velocity: _fanFromMuzzle(muzzle, convergeX, y, speed),
        damage: 0.25,
        fromBoss: true,
      );
      boss.scratchCount++;
    }
    return boss.scratchCount < rows;
  }
}

/// Charge beam: rakes ONE telegraphed row for [duration] seconds — get
/// out of the band before it fires.
class BeamRowAttack extends BossAttack {
  const BeamRowAttack({this.duration = 0.8});

  final double duration;

  @override
  double get telegraphSeconds => 1.2;

  @override
  bool get sustained => true;

  @override
  void telegraph(Boss boss, CosmoStrikeGame game) {
    // Fire along the BOSS's own row, not the player's — the boss holds
    // still through the windup + beam (see Boss._updateMovement freeze),
    // so the beam and the hull stay locked together instead of the beam
    // raking the middle of the screen while the boss sits up top.
    boss.capturedY = boss.muzzle.y;
    game.add(RowBandMarker(
      centerY: boss.capturedY,
      bandHeight: 44,
      life: telegraphSeconds,
    ));
  }

  @override
  void execute(Boss boss, CosmoStrikeGame game) {
    GameAudio.beamFire();
    game.add(BossBeam(
      rowY: boss.capturedY,
      fromX: boss.muzzle.x,
      duration: duration,
    ));
  }

  @override
  bool updateExecution(Boss boss, CosmoStrikeGame game, double dt) =>
      boss.execClock < duration;
}

/// Burrow/dive dash: the boss rakes ACROSS the telegraphed row to the
/// left edge and swings back to station. Contact does the damage.
class DashSweepAttack extends BossAttack {
  const DashSweepAttack();

  static const double _alignTime = 0.3;
  static const double _dashTime = 0.75;
  static const double _returnTime = 0.9;

  @override
  double get telegraphSeconds => 1.1;

  @override
  bool get sustained => true;

  @override
  bool get controlsMovement => true;

  @override
  void telegraph(Boss boss, CosmoStrikeGame game) {
    boss.capturedY = game.player.position.y
        .clamp(game.playfieldTop + boss.size.y / 2,
            game.playfieldBottom - boss.size.y / 2)
        .toDouble();
    game.add(RowBandMarker(
      centerY: boss.capturedY,
      bandHeight: boss.size.y * 0.9,
      life: telegraphSeconds + _alignTime + _dashTime,
    ));
  }

  @override
  void execute(Boss boss, CosmoStrikeGame game) {
    boss.capturedAim.setValues(boss.position.x, boss.position.y);
  }

  @override
  bool updateExecution(Boss boss, CosmoStrikeGame game, double dt) {
    final t = boss.execClock;
    final startX = boss.capturedAim.x;
    final startY = boss.capturedAim.y;
    const leftX = 70.0;
    if (t < _alignTime) {
      final p = t / _alignTime;
      boss.position.y = startY + (boss.capturedY - startY) * p;
      return true;
    }
    if (t < _alignTime + _dashTime) {
      final p = (t - _alignTime) / _dashTime;
      final eased = p * p; // accelerate into the dash
      boss.position.setValues(
          startX + (leftX - startX) * eased, boss.capturedY);
      return true;
    }
    final p = ((t - _alignTime - _dashTime) / _returnTime).clamp(0.0, 1.0);
    final eased = 1 - (1 - p) * (1 - p);
    boss.position.setValues(leftX + (startX - leftX) * eased, boss.capturedY);
    return p < 1;
  }
}

/// The beam itself: a glowing full-row raking damage zone. Procedurally
/// painted; damages the player at most once per 0.45 s while overlapped.
class BossBeam extends PositionComponent
    with HasGameReference<CosmoStrikeGame> {
  BossBeam({
    required this.rowY,
    required this.fromX,
    this.duration = 0.8,
  }) : super(priority: 12);

  final double rowY;
  final double fromX;
  final double duration;
  static const double _halfBand = 22;

  double _age = 0;
  double _damageCd = 0;

  @override
  void update(double dt) {
    dt *= game.enemyTimeScale;
    _age += dt;
    if (_age >= duration) {
      removeFromParent();
      return;
    }
    if (_damageCd > 0) _damageCd -= dt;
    final p = game.player;
    if (_damageCd <= 0 &&
        p.position.x < fromX &&
        (p.position.y - rowY).abs() < _halfBand + p.size.y * 0.35) {
      _damageCd = 0.45;
      game.onPlayerHit(0.4);
    }
  }

  @override
  void render(Canvas canvas) {
    final fade = _age < 0.1
        ? _age / 0.1
        : (_age > duration - 0.15 ? (duration - _age) / 0.15 : 1.0);
    final a = fade.clamp(0.0, 1.0);
    canvas.drawRect(
      Rect.fromLTRB(0, rowY - _halfBand, fromX, rowY + _halfBand),
      Paint()..color = const Color(0xFFFF2D78).withValues(alpha: 0.30 * a),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, rowY - 6, fromX, rowY + 6),
      Paint()..color = const Color(0xFFFFE3EE).withValues(alpha: 0.95 * a),
    );
  }
}
