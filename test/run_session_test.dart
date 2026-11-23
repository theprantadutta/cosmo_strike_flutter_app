import 'package:cosmo_strike_flutter_app/game/cosmo_strike_game.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_params.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/run_session.dart';
import 'package:cosmo_strike_flutter_app/services/telemetry/telemetry_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_analytics_client.dart';

GameResult _result({
  bool cleared = false,
  int score = 1200,
  int duration = 95,
  int stage = 2,
}) => GameResult(
  score: score,
  stageReached: stage,
  waveReached: 3,
  enemiesKilled: 40,
  bossesKilled: 1,
  durationSeconds: duration,
  cleared: cleared,
  startLevel: 1,
  levelsCleared: stage - 1,
  missilesFired: 2,
  revivesUsed: 0,
  levelResults: const [],
);

void main() {
  late RecordingAnalyticsClient client;
  late AnalyticsFacade facade;
  final telemetry = TelemetryService(enabled: false);

  setUp(() {
    RunSession.debugReset();
    client = RecordingAnalyticsClient();
    facade = AnalyticsFacade([client]);
  });

  RunSession begin({
    int runNumber = 1,
    GameMode mode = GameMode.sortie,
    ValueListenable<GamePhase>? phase,
    DateTime Function()? clock,
  }) => RunSession.begin(
    mode: mode,
    startLevel: 1,
    controlScheme: 'drag',
    runNumber: runNumber,
    analytics: facade,
    telemetry: telemetry,
    phase: phase,
    clock: clock,
  );

  Future<void> gameOver(GameResult r) => facade.trackGameOver(
    score: r.score,
    durationSeconds: r.durationSeconds,
    stageReached: r.stageReached,
    levelsCleared: r.levelsCleared,
    enemiesKilled: r.enemiesKilled,
    maxCombo: 0,
    victory: r.cleared,
    gameMode: 'sortie',
  );

  group('game_over run context', () {
    test('first run: run_number 1, onboarding, end_trigger death', () async {
      final s = begin(runNumber: 1);
      final r = _result();
      s.recordEnd(r);
      await gameOver(r);
      expect(client.gameOvers.single, containsPair('run_number', 1));
      expect(client.gameOvers.single, containsPair('onboarding', true));
      expect(client.gameOvers.single, containsPair('end_trigger', 'death'));
    });

    test('fourth run is past onboarding; victory trigger', () async {
      final s = begin(runNumber: 4);
      final r = _result(cleared: true);
      s.recordEnd(r);
      await gameOver(r);
      expect(client.gameOvers.single, containsPair('run_number', 4));
      expect(client.gameOvers.single, containsPair('onboarding', false));
      expect(client.gameOvers.single, containsPair('end_trigger', 'victory'));
    });

    test('a retry that starts before game_over is logged keeps the old run',
        () async {
      final s = begin(runNumber: 2);
      final r = _result();
      s.recordEnd(r);
      begin(runNumber: 3); // player tapped Retry fast
      await gameOver(r);
      expect(client.gameOvers.single, containsPair('run_number', 2));
    });

    test('Blitz time-out reads as end_trigger time', () {
      expect(
        RunSession.endTriggerFor(cleared: false, durationSeconds: 180, timeLimitSeconds: 180),
        EndTrigger.time,
      );
      expect(
        RunSession.endTriggerFor(cleared: false, durationSeconds: 60, timeLimitSeconds: 180),
        EndTrigger.death,
      );
      final s = begin(mode: GameMode.blitz);
      s.recordEnd(_result(duration: 180));
      expect(s.endTrigger, EndTrigger.time);
    });

    test('quit logs game_abandoned with run context', () {
      final s = begin(runNumber: 2);
      s.recordQuit(_result(score: 300, duration: 40));
      final e = client.named('game_abandoned').single;
      expect(e['run_number'], 2);
      expect(e['onboarding'], 1);
      expect(e['end_trigger'], 'quit');
      expect(e['game_mode'], 'sortie');
      expect(e['score'], 300);
    });

    test('Firebase params use the GA4 names', () {
      final p = AnalyticsParams.gameOver(
        score: 1,
        durationSeconds: 2,
        stageReached: 3,
        levelsCleared: 4,
        enemiesKilled: 5,
        maxCombo: 6,
        victory: false,
        gameMode: 'sortie',
        runNumber: 7,
        onboarding: true,
        endTrigger: 'death',
      );
      expect(p['run_number'], 7);
      expect(p['onboarding'], 1);
      expect(p['end_trigger'], 'death');
      expect(p['game_mode'], 'sortie');
      final legacy = AnalyticsParams.gameOver(
        score: 1,
        durationSeconds: 2,
        stageReached: 3,
        levelsCleared: 4,
        enemiesKilled: 5,
        maxCombo: 6,
        victory: true,
        gameMode: 'sortie',
      );
      expect(legacy.containsKey('run_number'), isFalse);
      expect(legacy.containsKey('onboarding'), isFalse);
    });
  });

  group('first_input', () {
    test('fires once, on the install\'s first run only', () {
      var now = DateTime(2026, 11, 23, 10);
      final s = begin(runNumber: 1, clock: () => now);
      now = now.add(const Duration(seconds: 4));
      s.markFirstInput('drag');
      s.markFirstInput('tap');
      final e = client.named('first_input').single;
      expect(e['seconds_since_run_start'], 4);
      expect(e['control_scheme'], 'drag');
      expect(e['input'], 'drag');

      begin(runNumber: 2).markFirstInput('drag');
      expect(client.named('first_input'), hasLength(1));
    });
  });

  group('revive_offer', () {
    test('timeout wins over the declined that follows', () {
      final phase = ValueNotifier(GamePhase.playing);
      final s = begin(runNumber: 5, phase: phase);
      phase.value = GamePhase.reviveOffer;
      s.recordReviveOffer(ReviveOutcome.timeout);
      phase.value = GamePhase.gameOver;
      final e = client.named('revive_offer').single;
      expect(e['outcome'], 'timeout');
      expect(e['run_number'], 5);
    });

    test('leaving the offer for game over without a choice is declined', () {
      final phase = ValueNotifier(GamePhase.playing);
      begin(phase: phase);
      phase.value = GamePhase.reviveOffer;
      phase.value = GamePhase.gameOver;
      expect(client.named('revive_offer').single['outcome'], 'declined');
    });

    test('a paid revive is logged once, not again at the final game over', () {
      final phase = ValueNotifier(GamePhase.playing);
      final s = begin(phase: phase);
      phase.value = GamePhase.reviveOffer;
      s.recordReviveOffer(ReviveOutcome.ad);
      phase.value = GamePhase.playing;
      phase.value = GamePhase.gameOver;
      expect(client.named('revive_offer').single['outcome'], 'ad');
    });

    test('no game over without an offer means no revive_offer event', () {
      final phase = ValueNotifier(GamePhase.playing);
      begin(phase: phase);
      phase.value = GamePhase.gameOver;
      expect(client.named('revive_offer'), isEmpty);
    });
  });

  group('analytics params', () {
    test('ISO week', () {
      expect(AnalyticsParams.isoWeek(DateTime(2026, 11, 23)), '2026-W48');
      expect(AnalyticsParams.isoWeek(DateTime(2026, 1, 1)), '2026-W01');
      // Jan 1 2027 is a Friday: still the last week of 2026.
      expect(AnalyticsParams.isoWeek(DateTime(2027, 1, 1)), '2026-W53');
      expect(AnalyticsParams.isoWeek(DateTime(2024, 12, 30)), '2025-W01');
    });

    test('push type', () {
      expect(AnalyticsParams.pushType({'type': 'comeback_reminder', 'route': 'home'}),
          'comeback_reminder');
      expect(AnalyticsParams.pushType({'route': 'home'}), 'home');
      expect(AnalyticsParams.pushType(null, fallback: 'local'), 'local');
    });
  });
}
