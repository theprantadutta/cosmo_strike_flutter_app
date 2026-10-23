// GameMode wire parsing: the 3.2 rebrand renamed every mode, but Drift rows,
// prefs, replays, cached API payloads and older backend builds may still carry
// the legacy identifiers (or their display labels). fromWire must map all of
// them, and stats keyed by legacy names must fold into the new keys.

import 'package:cosmo_strike_flutter_app/models/game_statistics.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameMode.fromWire', () {
    test('round-trips every current identifier', () {
      for (final m in GameMode.values) {
        expect(GameMode.fromWire(m.wireName), m);
        expect(GameMode.fromWire(m.wireName.toUpperCase()), m);
      }
    });

    test('maps legacy identifiers', () {
      const legacy = {
        'classic': GameMode.sortie,
        'zen': GameMode.cruise,
        'speedChallenge': GameMode.afterburn,
        'onslaught': GameMode.swarm,
        'survival': GameMode.holdout,
        'timeAttack': GameMode.blitz,
        'powerUpMadness': GameMode.overload,
        'perfectGame': GameMode.knifeEdge,
      };
      legacy.forEach((raw, expected) {
        expect(GameMode.fromWire(raw), expected, reason: raw);
      });
    });

    test('accepts snake_case, PascalCase and legacy display labels', () {
      expect(GameMode.fromWire('knife_edge'), GameMode.knifeEdge);
      expect(GameMode.fromWire('KnifeEdge'), GameMode.knifeEdge);
      expect(GameMode.fromWire('PerfectGame'), GameMode.knifeEdge);
      expect(GameMode.fromWire('power_up_madness'), GameMode.overload);
      expect(GameMode.fromWire('Speed Challenge'), GameMode.afterburn);
      expect(GameMode.fromWire('Zen Mode'), GameMode.cruise);
      expect(GameMode.fromWire('speed_run'), GameMode.afterburn);
      expect(GameMode.fromWire('no_walls'), GameMode.cruise);
    });

    test('unknown or empty falls back', () {
      expect(GameMode.tryFromWire('nope'), isNull);
      expect(GameMode.tryFromWire(null), isNull);
      expect(GameMode.fromWire(''), GameMode.sortie);
      expect(GameMode.fromWire('nope', fallback: GameMode.blitz), GameMode.blitz);
    });

    test('display names carry no legacy mode names', () {
      const banned = [
        'classic', 'zen', 'speed challenge', 'time attack',
        'power-up madness', 'perfect game', 'survival', 'onslaught',
      ];
      for (final m in GameMode.values) {
        final text = '${m.name} ${m.description}'.toLowerCase();
        for (final b in banned) {
          expect(text.contains(b), isFalse, reason: '${m.wireName}: $b');
        }
      }
    });
  });

  test('GameStatistics folds legacy per-mode keys into the new ones', () {
    final restored = GameStatistics.fromJson({
      'gamesPerMode': {'classic': 2, 'sortie': 3, 'Speed Challenge': 1},
    });
    expect(restored.gamesPerMode['sortie'], 5);
    expect(restored.gamesPerMode['afterburn'], 1);
    expect(restored.gamesPerMode.containsKey('classic'), isFalse);

    final next = restored.updateWithGameResult(
      score: 10,
      durationSeconds: 5,
      stageReached: 1,
      waveReached: 1,
      enemiesKilled: 1,
      bossesKilled: 0,
      levelsCleared: 0,
      gameMode: 'survival',
    );
    expect(next.gamesPerMode['holdout'], 1);
  });
}
