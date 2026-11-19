import 'package:cosmo_strike_flutter_app/game/cosmo_strike_game.dart';
import 'package:cosmo_strike_flutter_app/services/haptic_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/game_over_overlay.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/level_complete_overlay.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/results_motion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _harness(Widget child) => MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildCosmoTheme(),
      home: Scaffold(body: child),
    );

void _landscape(WidgetTester tester) {
  tester.view.physicalSize = const Size(960, 432);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _result = GameResult(
  score: 12450,
  stageReached: 3,
  waveReached: 4,
  enemiesKilled: 88,
  bossesKilled: 2,
  durationSeconds: 245,
  cleared: false,
  startLevel: 1,
  levelsCleared: 2,
  missilesFired: 5,
  revivesUsed: 0,
  levelResults: [],
  maxCombo: 4,
  grazeCount: 31,
);

GameOverOverlay _gameOver({int previousBest = 9000, bool? reduceMotion}) => GameOverOverlay(
      result: _result,
      victory: false,
      previousBest: previousBest,
      unlockedLevel: 0,
      runCoinsEarned: 41,
      runXpEarned: 70,
      coinsDoubled: false,
      canDoubleCoins: false,
      onDoubleCoins: () {},
      onRetry: () {},
      onExit: () {},
      challengeRunStart: const {},
      reduceMotion: reduceMotion,
      directives: const SizedBox(height: 10),
    );

/// The opacity driving the Retry button's entrance.
double _actionsOpacity(WidgetTester tester, String label) {
  final fade = tester.widget<FadeTransition>(
    find.ancestor(of: find.text(label.toUpperCase()), matching: find.byType(FadeTransition)).first,
  );
  return fade.opacity.value;
}

double _recordScale(WidgetTester tester) => tester
    .widget<ScaleTransition>(
      find.ancestor(of: find.text('NEW RECORD'), matching: find.byType(ScaleTransition)).first,
    )
    .scale
    .value;

int _scoreValue(WidgetTester tester) =>
    tester.widget<CsOdometer>(find.byType(CsOdometer).first).value;

void main() {
  late List<MethodCall> haptics;

  setUp(() {
    haptics = [];
    HapticService().setEnabled(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Finder labelText(String s) => find.text(s.toUpperCase());

  group('Game over beat sheet', () {
    testWidgets('starts hidden and plays through to the final state', (tester) async {
      _landscape(tester);
      await tester.pumpWidget(_harness(_gameOver()));

      // t0: score at 0, record chip not popped yet, actions invisible.
      expect(_scoreValue(tester), 0);
      expect(_recordScale(tester), closeTo(0.4, 1e-6)); // pops from 40%
      expect(_actionsOpacity(tester, 'Retry'), 0);

      await tester.pump(const Duration(milliseconds: 300));
      expect(_scoreValue(tester), 12450, reason: 'score beat (200 ms) flips the odometer');
      expect(haptics, isEmpty, reason: 'no record haptic before its beat');

      await tester.pump(const Duration(milliseconds: 700)); // 1000 ms
      expect(haptics, isNotEmpty, reason: 'NEW RECORD fired its haptic at 900 ms');

      await tester.pumpAndSettle();
      expect(_recordScale(tester), closeTo(1, 1e-6));
      expect(_actionsOpacity(tester, 'Retry'), 1);
      // Rewards rolled up to their values.
      final rolls = tester.widgetList<RollUpNumber>(find.byType(RollUpNumber)).map((r) => r.value);
      expect(rolls, [41, 70]);
      expect(_scoreValue(tester), 12450);
    });

    testWidgets('a tap after 1 s skips to the end state', (tester) async {
      _landscape(tester);
      await tester.pumpWidget(_harness(_gameOver(previousBest: 20000)));

      // Too early: the tap is ignored.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(const Offset(400, 400));
      await tester.pump();
      expect(_actionsOpacity(tester, 'Retry'), lessThan(1));

      await tester.pump(const Duration(milliseconds: 600)); // 1100 ms
      expect(_actionsOpacity(tester, 'Retry'), lessThan(1));
      await tester.tapAt(const Offset(400, 400));
      await tester.pump();

      expect(_actionsOpacity(tester, 'Retry'), 1);
      // Settled: odometers render plain text, rewards rolled in already.
      expect(find.text('12,450'), findsOneWidget);
      expect(find.text('+41 CR'), findsOneWidget);
      expect(find.text('+70 XP'), findsOneWidget);
      expect(find.text('BEST 20,000'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('reduce motion shows the final state on the first frame', (tester) async {
      _landscape(tester);
      await tester.pumpWidget(_harness(_gameOver(reduceMotion: true)));
      await tester.pump();

      expect(_actionsOpacity(tester, 'Retry'), 1);
      expect(_recordScale(tester), 1);
      expect(find.text('12,450'), findsOneWidget);
      expect(find.text('+41 CR'), findsOneWidget);
      expect(haptics, isEmpty, reason: 'skipped cues never fire');
      await tester.pumpAndSettle();
    });
  });

  group('Level clear beat sheet', () {
    LevelCompleteOverlay overlay({bool? reduceMotion}) => LevelCompleteOverlay(
          game: CosmoStrikeGame(),
          outcome: null,
          priorBest: null,
          runLabel: 'Sortie',
          onContinue: () {},
          onQuit: () {},
          reduceMotion: reduceMotion,
        );

    testWidgets('header, stars and actions reach their final state', (tester) async {
      _landscape(tester);
      await tester.pumpWidget(_harness(overlay()));
      expect(_actionsOpacity(tester, 'Quit'), 0);

      await tester.pumpAndSettle();
      expect(_actionsOpacity(tester, 'Quit'), 1);
      expect(labelText('Run so far'), findsOneWidget);
      final stars = tester.widgetList<ScaleTransition>(
        find.descendant(of: find.bySemanticsLabel(RegExp(r'of 3 stars')), matching: find.byType(ScaleTransition)),
      );
      for (final s in stars) {
        expect(s.scale.value, closeTo(1, 1e-6));
      }
    });

    testWidgets('a tap after 1 s skips; reduce motion is instant', (tester) async {
      _landscape(tester);
      await tester.pumpWidget(_harness(overlay()));
      await tester.pump(const Duration(milliseconds: 1100));
      expect(_actionsOpacity(tester, 'Quit'), lessThan(1));
      await tester.tapAt(const Offset(480, 400));
      await tester.pump();
      expect(_actionsOpacity(tester, 'Quit'), 1);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_harness(overlay(reduceMotion: true)));
      await tester.pump();
      expect(_actionsOpacity(tester, 'Quit'), 1);
      await tester.pumpAndSettle();
    });

    test('stars pop 120 ms apart on springPop', () {
      final beats = LevelCompleteOverlay.beats(onStar: (_) {});
      expect(beats['star1']!.at - beats['star0']!.at, 120);
      expect(beats['star2']!.at - beats['star1']!.at, 120);
      expect(beats['star0']!.curve, CsMotion.springPop);
      expect(beats['actions']!.end, lessThanOrEqualTo(2200));
    });
  });
}
