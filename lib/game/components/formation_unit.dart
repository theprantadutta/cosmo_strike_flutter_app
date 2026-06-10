import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';
import '../game_audio.dart';
import '../levels/formation.dart';
import '../levels/level_def.dart';
import 'enemy.dart';
import 'power_up.dart';
import 'telegraph.dart';

/// Runtime controller for one [FormationSpec]: spawns the member ships,
/// positions managed shapes as a unit every frame, and tracks the wipe
/// bonus (kill the WHOLE formation fast, nobody escapes → bonus points +
/// a guaranteed orb at the last kill).
///
/// Non-rendering component; members are normal [EnemyShip]s added to the
/// game (their firing, hp, collisions and slow-mo behave exactly like
/// loose enemies).
class Formation extends Component with HasGameReference<CosmoStrikeGame> {
  Formation({required this.spec});

  final FormationSpec spec;

  final List<EnemyShip> _members = [];
  int _spawned = 0;
  int _killed = 0;
  bool _anyEscaped = false;
  bool _wipeAwarded = false;
  double _t = 0;
  double _firstKillAt = -1;
  final Vector2 _lastKillPos = Vector2.zero();

  // Resolved at load.
  late final double _speed;
  late final double _centerY;
  late final double _gap01;
  double _streamTimer = 0;
  bool _ambushSpawned = false;

  bool get managed => spec.managed;

  double get _fieldW => game.size.x;
  double get _top => game.playfieldTop;
  double get _bottom => game.playfieldBottom;
  double get _span => math.max(40, _bottom - _top);

  /// Where the anchor is right now (managed shapes).
  double get _anchorX => spec.shape == FormationShape.ambushRear
      ? -80 + _speed * math.max(0, _t - 1.0) // 1s telegraph head start
      : _fieldW + 70 - _speed * _t;

  @override
  Future<void> onLoad() async {
    final level = game.level;
    final anchorType = spec.shape == FormationShape.escortConvoy
        ? (spec.secondaryType ?? EnemyType.beetle)
        : spec.type;
    _speed = anchorType.baseSpeed *
        level.speedScale *
        game.mode.difficultyMultiplier *
        spec.speedScale;
    _centerY = _top + _span * spec.y01;
    _gap01 = spec.gap01 ?? (0.2 + game.rng.nextDouble() * 0.6);

    switch (spec.shape) {
      case FormationShape.stream:
        // Members trickle in from update().
        break;
      case FormationShape.ambushRear:
        // Telegraph first; members mount at t = 1.0 in update().
        game.add(EdgeWarningMarker(fromLeft: true, y: _centerY, life: 1.0));
        GameAudio.telegraph();
        break;
      default:
        _spawnAllManaged();
    }
  }

  void _spawnAllManaged() {
    for (var i = 0; i < spec.count; i++) {
      _addMember(i, Vector2(_fieldW + 80, _centerY));
    }
    _positionMembers(); // place them before their first frame renders
  }

  void _addMember(int slot, Vector2 at) {
    final level = game.level;
    final type = spec.shape == FormationShape.escortConvoy && slot == 0
        ? (spec.secondaryType ?? EnemyType.beetle)
        : spec.type;
    final ship = EnemyShip(
      type: type,
      pattern: spec.pattern,
      spawn: at,
      hpScale: level.hpScale,
      speedScale: level.speedScale *
          game.mode.difficultyMultiplier *
          spec.speedScale,
      fireRateScale: level.fireRateScale,
      scoreScale: level.scoreScale,
      formation: this,
      slotIndex: slot,
    );
    _members.add(ship);
    _spawned++;
    game.add(ship);
  }

  @override
  void update(double dt) {
    dt *= game.enemyTimeScale;
    _t += dt;

    if (game.phase == GamePhase.playing) _spawnPending(dt);
    if (managed) _positionMembers();
    _checkExit();
  }

  void _spawnPending(double dt) {
    switch (spec.shape) {
      case FormationShape.stream:
        if (_spawned >= spec.count) return;
        _streamTimer -= dt;
        if (_streamTimer <= 0) {
          _streamTimer = spec.spawnInterval;
          final half = _span * spec.ySpread01;
          final y = (_centerY - half + game.rng.nextDouble() * half * 2)
              .clamp(_top + 20, _bottom - 20);
          _addMember(_spawned, Vector2(_fieldW + 50, y));
        }
      case FormationShape.ambushRear:
        if (!_ambushSpawned && _t >= 1.0) {
          _ambushSpawned = true;
          for (var i = 0; i < spec.count; i++) {
            _addMember(i, Vector2(-60.0 - i * spec.spacing, _centerY));
          }
        }
      default:
        break; // managed shapes spawned in onLoad
    }
  }

  void _positionMembers() {
    final ax = _anchorX;
    for (final m in _members) {
      final i = m.slotIndex;
      double x;
      double y;
      switch (spec.shape) {
        case FormationShape.stream:
          return; // self-piloting
        case FormationShape.vWedge:
          final o = vWedgeOffset(i, spec.spacing);
          x = ax + o.x;
          y = _centerY + o.y;
        case FormationShape.snakeChain:
          final delay = spec.spacing / math.max(40, _speed);
          x = ax + i * spec.spacing;
          y = _centerY + snakeY(_t - i * delay, _span * 0.32);
        case FormationShape.pincer:
          final j = i ~/ 2;
          final side = i.isEven ? -1.0 : 1.0;
          final progress = (1 - ax / _fieldW).clamp(0.0, 1.0);
          x = ax + j * spec.spacing;
          y = _centerY + side * (1 - progress) * _span * 0.42;
        case FormationShape.wallWithGap:
          x = ax;
          final gapHalf = 70 / _span; // ~ship-and-a-half of safety
          y = _top + _span * wallSlotY01(i, spec.count, _gap01, gapHalf);
        case FormationShape.columnDive:
          x = ax + i * spec.spacing * 0.7;
          final target =
              _centerY + (i.isEven ? 1 : -1) * (i % 4) * spec.spacing * 0.3;
          final p = diveProgress(_t, i);
          y = (_top - 50) + (target - (_top - 50)) * p;
        case FormationShape.ambushRear:
          if (!_ambushSpawned) return;
          x = ax - i * spec.spacing * 0.8;
          y = _centerY + math.sin(_t * 3 + i * 1.3) * 16;
        case FormationShape.ringSpinner:
          final radius = math.min(_span * 0.3, 95.0);
          final o = ringOffset(i, spec.count, _t, radius);
          x = ax + o.x;
          y = _centerY + o.y;
        case FormationShape.escortConvoy:
          final o = convoyOffset(i, spec.spacing * 0.9);
          x = ax + o.x;
          y = _centerY + o.y + math.sin(_t * 2.4 + i) * 6;
      }
      final half = m.size.y / 2;
      m.position.setValues(
        x,
        y.clamp(_top + half, _bottom - half),
      );
    }
  }

  void _checkExit() {
    final exited = spec.shape == FormationShape.ambushRear
        ? _anchorX - spec.count * spec.spacing > _fieldW + 120
        : managed && _anchorX + spec.count * spec.spacing < -140;
    if (exited) {
      _anyEscaped = _members.isNotEmpty;
      for (final m in _members.toList()) {
        m.removeFromParent();
      }
      return;
    }
    if (_spawned >= spec.count && _members.isEmpty) removeFromParent();
  }

  /// A member died to player damage (called from the game's kill path).
  void onMemberKilled(EnemyShip ship) {
    _killed++;
    _lastKillPos.setFrom(ship.position);
    if (_firstKillAt < 0) _firstKillAt = _t;
    final window = spec.wipeWindow +
        (spec.shape == FormationShape.stream
            ? spec.count * spec.spawnInterval
            : 0);
    if (!_wipeAwarded &&
        spec.wipeBonus > 0 &&
        _killed >= spec.count &&
        !_anyEscaped &&
        (_t - _firstKillAt) <= window) {
      _wipeAwarded = true;
      _awardWipe();
    }
  }

  /// A member left the tree for any reason (killed, escaped, swept).
  void onMemberGone(EnemyShip ship) {
    if (!ship.wasKilled) _anyEscaped = true;
    _members.remove(ship);
    if (_spawned >= spec.count && _members.isEmpty && !isRemoving) {
      removeFromParent();
    }
  }

  void _awardWipe() {
    final awarded = game.addKillScore(spec.wipeBonus);
    game.pools.scorePopup(
      _lastKillPos + Vector2(0, -34),
      'FORMATION WIPE +$awarded',
      color: const Color(0xFFFFD37B),
      scale: 1.25,
      duration: 1.0,
    );
    game.hitStop(0.05);
    GameAudio.formationWipe();
    game.add(PowerUp(kind: spec.wipeDrop, spawn: _lastKillPos.clone()));
  }
}
