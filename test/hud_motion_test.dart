import 'package:cosmo_strike_flutter_app/game/cosmo_strike_game.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/game_dpad.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/hud_motion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: CsReduceMotion(
        reduceMotion: reduce,
        child: Scaffold(body: Center(child: child)),
      ),
    );

double _opacityOf(WidgetTester tester, Finder within) {
  final fade = tester.widget<FadeTransition>(
    find.descendant(of: within, matching: find.byType(FadeTransition)).first,
  );
  return fade.opacity.value;
}

void main() {
  group('HudScore', () {
    testWidgets('coalesces rapid score changes and ends on the latest', (tester) async {
      final game = CosmoStrikeGame();
      await tester.pumpWidget(_app(HudScore(game: game)));
      int shown() => tester.widget<CsOdometer>(find.byType(CsOdometer)).value;
      expect(shown(), 0);

      game.scoreNotifier.value = 10;
      await tester.pump();
      expect(shown(), 10, reason: 'the first change goes straight through');

      game.scoreNotifier.value = 20;
      game.scoreNotifier.value = 30;
      await tester.pump();
      expect(shown(), 10, reason: 'changes inside the window are held back');

      await tester.pump(const Duration(milliseconds: 200));
      expect(shown(), 30, reason: 'the window flushes the latest value only');
      await tester.pumpAndSettle();
    });

    testWidgets('reduce motion shows every change at once', (tester) async {
      final game = CosmoStrikeGame();
      await tester.pumpWidget(_app(HudScore(game: game), reduce: true));
      game.scoreNotifier.value = 5;
      await tester.pump();
      game.scoreNotifier.value = 9;
      await tester.pump();
      expect(find.text('9'), findsOneWidget);
    });
  });

  group('HudChainReadout', () {
    testWidgets('fades in from a 2-chain and fades out holding the last chain', (tester) async {
      final game = CosmoStrikeGame();
      final readout = find.byType(HudChainReadout);
      await tester.pumpWidget(_app(HudChainReadout(game: game)));
      expect(_opacityOf(tester, readout), 0);

      game.combo.comboNotifier.value = 3;
      await tester.pumpAndSettle();
      expect(_opacityOf(tester, readout), 1);
      expect(find.text('CHAIN 3'), findsOneWidget);

      game.combo.comboNotifier.value = 0;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final mid = _opacityOf(tester, readout);
      expect(mid, inExclusiveRange(0, 1));
      expect(find.text('CHAIN 3'), findsOneWidget, reason: 'keeps the last chain while fading');

      await tester.pumpAndSettle();
      expect(_opacityOf(tester, readout), 0);
    });

    testWidgets('settles larger at higher multipliers', (tester) async {
      final game = CosmoStrikeGame();
      await tester.pumpWidget(_app(HudChainReadout(game: game)));
      game.combo.comboNotifier.value = 12;
      game.combo.multiplierNotifier.value = 4;
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, closeTo(1.12, 1e-9));
    });
  });

  group('HudLifePips', () {
    Finder scales() => find.descendant(
          of: find.byType(HudLifePips),
          matching: find.byType(ScaleTransition),
        );

    testWidgets('a lost ship shrinks out and a gained ship pops in', (tester) async {
      final game = CosmoStrikeGame();
      game.livesNotifier.value = 3;
      await tester.pumpWidget(_app(HudLifePips(game: game)));
      expect(scales(), findsNothing, reason: 'starting ships do not pop');

      game.livesNotifier.value = 2;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scales(), findsOneWidget);
      expect(find.text('SHIP DOWN'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(scales(), findsNothing);

      game.livesNotifier.value = 3;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scales(), findsOneWidget);
      await tester.pumpAndSettle();
      expect(scales(), findsNothing);
    });

    testWidgets('reduce motion swaps the slot instantly', (tester) async {
      final game = CosmoStrikeGame();
      game.livesNotifier.value = 3;
      await tester.pumpWidget(_app(HudLifePips(game: game), reduce: true));
      game.livesNotifier.value = 2;
      await tester.pump();
      expect(scales(), findsNothing);
      await tester.pumpAndSettle();
    });
  });

  group('HudEffectChips', () {
    testWidgets('a chip stays to fade out after its effect ends', (tester) async {
      final game = CosmoStrikeGame();
      await tester.pumpWidget(_app(HudEffectChips(game: game)));
      expect(find.byType(Wrap), findsNothing);

      game.effectsNotifier.value = const [ActiveEffectHud(id: 'magnet', remaining01: 1)];
      await tester.pumpAndSettle();
      expect(find.byIcon(Symbols.attractions_rounded), findsOneWidget);

      game.effectsNotifier.value = const [];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byIcon(Symbols.attractions_rounded), findsOneWidget, reason: 'still fading out');

      await tester.pumpAndSettle();
      expect(find.byIcon(Symbols.attractions_rounded), findsNothing);
    });

    testWidgets('reduce motion removes an ended chip at once', (tester) async {
      final game = CosmoStrikeGame();
      await tester.pumpWidget(_app(HudEffectChips(game: game), reduce: true));
      game.effectsNotifier.value = const [ActiveEffectHud(id: 'speed', remaining01: 1)];
      await tester.pump();
      game.effectsNotifier.value = const [];
      await tester.pump();
      expect(find.byIcon(Symbols.speed_rounded), findsNothing);
    });
  });

  group('GameDPad', () {
    double nubX(WidgetTester tester) => tester
        .widget<Transform>(find.descendant(
          of: find.byType(TweenAnimationBuilder<Offset>),
          matching: find.byType(Transform),
        ).first)
        .transform
        .getTranslation()
        .x;

    Future<void> dragRight(WidgetTester tester) async {
      final g = await tester.startGesture(tester.getCenter(find.byType(GameDPad)));
      await g.moveBy(const Offset(40, 0));
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(nubX(tester), greaterThan(0), reason: 'the nub follows the thumb 1:1');
      await g.up();
      await tester.pump();
    }

    testWidgets('the nub springs back to centre on release', (tester) async {
      await tester.pumpWidget(_app(GameDPad(onDirection: (_) {})));
      await dragRight(tester);
      await tester.pump(const Duration(milliseconds: 60));
      expect(nubX(tester), greaterThan(0), reason: 'still travelling home');
      await tester.pumpAndSettle();
      expect(nubX(tester), 0);
    });

    testWidgets('reduce motion snaps the nub home', (tester) async {
      await tester.pumpWidget(_app(GameDPad(onDirection: (_) {}), reduce: true));
      await dragRight(tester);
      expect(nubX(tester), 0);
    });
  });

  group('HudPopOnRise', () {
    testWidgets('pops only when the value goes up', (tester) async {
      final value = ValueNotifier<int>(0);
      await tester.pumpWidget(_app(ValueListenableBuilder<int>(
        valueListenable: value,
        builder: (_, v, _) => HudPopOnRise(value: v, child: const SizedBox(width: 10, height: 10)),
      )));
      Object? trigger() => tester.widget<CsPop>(find.byType(CsPop)).trigger;
      final start = trigger();

      value.value = 2;
      await tester.pump();
      final afterRise = trigger();
      expect(afterRise, isNot(start));

      value.value = 1;
      await tester.pump();
      expect(trigger(), afterRise, reason: 'no pop on the way down');
      await tester.pumpAndSettle();
    });
  });
}
