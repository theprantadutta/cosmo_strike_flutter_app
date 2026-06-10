import 'dart:math' as math;

import 'package:flame/components.dart';

import '../components/enemy.dart';
import '../components/formation_unit.dart';
import '../components/power_up.dart';
import '../components/telegraph.dart';
import '../cosmo_strike_game.dart';
import 'formation.dart';
import 'level_def.dart';
import 'level_script.dart';

/// Drives one level's choreographed [LevelScript] on GAME time.
///
/// Replaces the WaveRunner. Same discipline: a plain [Component], so
/// `pauseEngine()` freezes the timeline exactly where it stands (pause
/// and revive resume mid-choreography). Event delays are relative to the
/// previous event; barrier events hold until the field is clear and
/// count their delay from that moment.
class ScriptRunner extends Component with HasGameReference<CosmoStrikeGame> {
  LevelScript? _script;
  int _cursor = 0;
  double _sinceLast = 0;
  int _sectionsFired = 0;
  bool _active = false;
  double _spawnGrace = 0;

  /// Onslaught: queued mirrored duplicates of fired formations.
  final List<(double, FormationSpec)> _pendingEchoes = [];

  /// Set-piece window state (mine rain).
  double _setPieceLeft = 0;
  double _mineRate = 0;
  double _mineAccum = 0;

  /// Hard cap so Onslaught echoes can never flood the field.
  static const int maxLiveEnemies = 24;

  /// Begin [script] for the current level. Sweeps anything left over
  /// from the previous level so choreography always starts clean.
  void startLevel(LevelScript script) {
    for (final f in game.children.whereType<Formation>().toList()) {
      f.removeFromParent();
    }
    for (final e in game.children.whereType<EnemyShip>().toList()) {
      e.removeFromParent();
    }
    _script = script;
    _cursor = 0;
    _sinceLast = 0;
    _sectionsFired = 0;
    _active = true;
    _spawnGrace = 0;
    _pendingEchoes.clear();
    _setPieceLeft = 0;
    _mineRate = 0;
    _mineAccum = 0;
  }

  void stop() => _active = false;

  /// Brief no-spawn window right after a revive (fair comeback).
  void notifyRevived() => _spawnGrace = 1.5;

  int get _liveEnemies => game.children.whereType<EnemyShip>().length;

  @override
  void update(double dt) {
    if (!_active || game.phase != GamePhase.playing) return;

    if (_spawnGrace > 0) {
      _spawnGrace -= dt;
      return;
    }

    _tickSetPiece(dt);
    _tickEchoes(dt);

    final script = _script;
    if (script == null || _cursor >= script.events.length) return;

    var event = script.events[_cursor];
    if (event.waitForFieldClear && _liveEnemies > 0) {
      // Barrier: the delay counts from the moment the field clears.
      _sinceLast = 0;
      return;
    }
    _sinceLast += dt;
    while (_cursor < script.events.length) {
      event = script.events[_cursor];
      if (event.waitForFieldClear && _liveEnemies > 0) break;
      if (_sinceLast < event.delay) break;
      _sinceLast -= event.delay;
      _cursor++;
      _fire(event);
    }
  }

  void _tickSetPiece(double dt) {
    if (_setPieceLeft <= 0) return;
    _setPieceLeft -= dt;
    _mineAccum += _mineRate * dt;
    while (_mineAccum >= 1) {
      _mineAccum -= 1;
      _spawnMine();
    }
    if (_setPieceLeft <= 0) {
      _mineRate = 0;
      game.clearCallout();
    }
  }

  void _tickEchoes(double dt) {
    for (var i = _pendingEchoes.length - 1; i >= 0; i--) {
      final (left, spec) = _pendingEchoes[i];
      final next = left - dt;
      if (next <= 0) {
        _pendingEchoes.removeAt(i);
        if (_liveEnemies < maxLiveEnemies) {
          game.add(Formation(spec: spec));
        }
      } else {
        _pendingEchoes[i] = (next, spec);
      }
    }
  }

  void _fire(LevelEvent event) {
    switch (event) {
      case FormationEvent e:
        if (e.countsAsSection) {
          _sectionsFired++;
          game.onScriptSection(_sectionsFired);
        }
        game.add(Formation(spec: e.spec));
        // Onslaught: every formation echoes mirrored a beat later.
        if (game.mode.extraEnemiesPerWave > 0) {
          _pendingEchoes.add((1.2, e.spec.mirrored()));
        }
      case DropEvent e:
        final top = game.playfieldTop;
        final span = math.max(40.0, game.playfieldBottom - top);
        game.add(PowerUp(
          kind: e.kind,
          spawn: Vector2(game.size.x + 20, top + span * e.y01),
        ));
      case SetPieceEvent e:
        _setPieceLeft = e.duration;
        _mineRate = e.mineRainPerSecond;
        _mineAccum = 0;
        final banner = e.banner;
        if (banner != null) game.showCallout(banner);
      case TelegraphEvent e:
        final top = game.playfieldTop;
        final span = math.max(40.0, game.playfieldBottom - top);
        game.add(EdgeWarningMarker(
          fromLeft: e.kind == ScriptTelegraphKind.edgeLeft,
          y: top + span * e.y01,
        ));
      case BossEvent _:
        _active = false;
        game.spawnBoss();
    }
  }

  void _spawnMine() {
    if (_liveEnemies >= maxLiveEnemies) return;
    final top = game.playfieldTop + 24;
    final span = math.max(40.0, game.playfieldBottom - 24 - top);
    final level = game.level;
    game.add(EnemyShip(
      type: EnemyType.mine,
      spawn: Vector2(
          game.size.x + 40, top + game.rng.nextDouble() * span),
      hpScale: level.hpScale,
      // Mines ride the set-piece rush — faster than their lazy default.
      speedScale: level.speedScale *
          game.mode.difficultyMultiplier *
          (1.2 * game.terrainScrollScale),
      fireRateScale: level.fireRateScale,
      scoreScale: level.scoreScale,
    ));
  }
}
