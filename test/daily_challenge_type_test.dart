// Guards the ChallengeType wire-mapping. The backend serializes its
// ChallengeType enum as snake_case (JsonStringEnumConverter(SnakeCaseLower)),
// so the client MUST map enemies_killed / game_mode / games_played — earlier
// these fell through to a silent `score` default, mis-tracking those
// challenges.

import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChallengeType.tryParse', () {
    test('maps backend snake_case values', () {
      expect(ChallengeType.tryParse('score'), ChallengeType.score);
      expect(ChallengeType.tryParse('enemies_killed'), ChallengeType.foodEaten);
      expect(ChallengeType.tryParse('game_mode'), ChallengeType.gameMode);
      expect(ChallengeType.tryParse('survival'), ChallengeType.survival);
      expect(ChallengeType.tryParse('games_played'), ChallengeType.gamesPlayed);
    });

    test('maps legacy PascalCase / camelCase values', () {
      expect(ChallengeType.tryParse('Score'), ChallengeType.score);
      expect(ChallengeType.tryParse('FoodEaten'), ChallengeType.foodEaten);
      expect(ChallengeType.tryParse('GameMode'), ChallengeType.gameMode);
      expect(ChallengeType.tryParse('GamesPlayed'), ChallengeType.gamesPlayed);
    });

    test('returns null for an unrecognized type (no silent score default)', () {
      expect(ChallengeType.tryParse('totally_unknown'), isNull);
      expect(ChallengeType.tryParse(''), isNull);
    });
  });

  group('ChallengeType.apiValue', () {
    test('emits backend snake_case', () {
      expect(ChallengeType.score.apiValue, 'score');
      expect(ChallengeType.foodEaten.apiValue, 'enemies_killed');
      expect(ChallengeType.gameMode.apiValue, 'game_mode');
      expect(ChallengeType.survival.apiValue, 'survival');
      expect(ChallengeType.gamesPlayed.apiValue, 'games_played');
    });

    test('round-trips through tryParse for every value', () {
      for (final type in ChallengeType.values) {
        expect(ChallengeType.tryParse(type.apiValue), type);
      }
    });
  });
}
