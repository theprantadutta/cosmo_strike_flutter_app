import 'dart:math' as math;

import 'package:flame/components.dart';

import '../components/enemy.dart';
import '../cosmo_strike_game.dart';
import 'level_def.dart';

/// Drives one level's scripted waves on GAME time.
///
/// Replaces the old `Future.delayed` spawning, which ran on wall-clock and
/// kept spawning behind `pauseEngine()` — breaking pause and making revive
/// impossible (enemies would pile up behind the rewarded ad). Because this
/// is a plain [Component], pausing the engine freezes the spawn timeline
/// exactly where it stands, so the paused state IS the resume state.
class WaveRunner extends Component with HasGameReference<CosmoStrikeGame> {
  LevelDef? _level;
  List<WaveEntry> _entries = const [];
  int _entryCursor = 0;
  int _spawnedInEntry = 0;
  double _clock = 0;
  bool _allSpawned = true;
  bool _active = false;

  /// True while a wave is in progress (spawning or clearing).
  bool get isRunning => _active;

  /// Begin wave [waveIndex] (0-based) of [level]. Mode modifiers fold in
  /// here: Onslaught's extra ships are appended to the wave's LARGEST
  /// entry; per-ship speed scaling happens at spawn time.
  void startWave(LevelDef level, int waveIndex) {
    _level = level;
    final wave = level.waves[waveIndex.clamp(0, level.waves.length - 1)];

    // Apply mode.extraEnemiesPerWave to the biggest entry of the wave.
    final extra = game.mode.extraEnemiesPerWave;
    if (extra > 0) {
      var biggest = 0;
      for (var i = 1; i < wave.entries.length; i++) {
        if (wave.entries[i].count > wave.entries[biggest].count) biggest = i;
      }
      _entries = [
        for (var i = 0; i < wave.entries.length; i++)
          i == biggest
              ? WaveEntry(
                  wave.entries[i].type,
                  pattern: wave.entries[i].pattern,
                  count: wave.entries[i].count + extra,
                  spawnInterval: wave.entries[i].spawnInterval,
                  yBand0: wave.entries[i].yBand0,
                  yBand1: wave.entries[i].yBand1,
                )
              : wave.entries[i],
      ];
    } else {
      _entries = wave.entries;
    }

    _entryCursor = 0;
    _spawnedInEntry = 0;
    _clock = 0;
    _allSpawned = _entries.isEmpty;
    _active = true;
  }

  void stop() {
    _active = false;
    _allSpawned = true;
  }

  @override
  void update(double dt) {
    if (!_active || game.phase != GamePhase.playing) return;

    if (!_allSpawned) {
      _clock += dt;
      final entry = _entries[_entryCursor];
      if (_clock >= entry.spawnInterval) {
        _clock = 0;
        _spawn(entry);
        _spawnedInEntry++;
        if (_spawnedInEntry >= entry.count) {
          _entryCursor++;
          _spawnedInEntry = 0;
          if (_entryCursor >= _entries.length) _allSpawned = true;
        }
      }
      return;
    }

    // All spawned: the wave is clear once no enemy remains.
    if (game.children.whereType<EnemyShip>().isEmpty) {
      _active = false;
      game.onWaveComplete();
    }
  }

  void _spawn(WaveEntry entry) {
    final level = _level!;
    // Vertical band, expressed as fractions of the OPEN playfield
    // (between ceiling and floor strips).
    final top = game.playfieldTop;
    final span = math.max(40.0, game.playfieldBottom - top);
    final y0 = top + span * entry.yBand0;
    final y1 = top + span * entry.yBand1;
    final y = y0 + game.rng.nextDouble() * math.max(1, y1 - y0);

    game.add(EnemyShip(
      type: entry.type,
      pattern: entry.pattern,
      spawn: Vector2(game.size.x + 50, y),
      hpScale: level.hpScale,
      // Mode pacing: Zen drifts slower, Speed Challenge / Time Attack
      // come in hot.
      speedScale: level.speedScale * game.mode.difficultyMultiplier,
      fireRateScale: level.fireRateScale,
      scoreScale: level.scoreScale,
    ));
  }
}
