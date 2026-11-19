import 'package:cosmo_strike_flutter_app/theme/cosmo_theme.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/run_context.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/run_stat_tiles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('RunContext.runsTutorial', () {
    test('a pending tutorial runs on a plain Level-1 start', () {
      expect(
        RunContext.runsTutorial(startLevel: 1, tutorialPending: true),
        isTrue,
      );
    });

    test('never on a Daily Run (seeded) start', () {
      expect(
        RunContext.runsTutorial(
          startLevel: 1,
          tutorialPending: true,
          dailySeed: 20261119,
          tournamentId: 'daily',
        ),
        isFalse,
      );
    });

    test('never on a Sector Cup run', () {
      expect(
        RunContext.runsTutorial(
          startLevel: 1,
          tutorialPending: true,
          tournamentId: 'cup-1',
        ),
        isFalse,
      );
    });

    test('not past Level 1 or once finished', () {
      expect(
        RunContext.runsTutorial(startLevel: 2, tutorialPending: true),
        isFalse,
      );
      expect(
        RunContext.runsTutorial(startLevel: 1, tutorialPending: false),
        isFalse,
      );
    });
  });

  group('RunContext.label', () {
    test('Daily Run wins over the cup it is attributed to and the mode', () {
      expect(
        RunContext.label(
          mode: GameMode.sortie,
          dailySeed: 1,
          tournamentId: 'daily',
        ),
        'Daily Run',
      );
    });

    test('a cup run is named as a Sector Cup', () {
      expect(
        RunContext.label(mode: GameMode.blitz, tournamentId: 'cup-1'),
        'Sector Cup',
      );
    });

    test('a normal run uses the mode display name', () {
      expect(
        RunContext.label(mode: GameMode.sortie),
        GameMode.sortie.name,
      );
    });
  });

  group('ScrollEdgeFade', () {
    Future<void> pump(WidgetTester tester, int rows) async {
      tester.view.physicalSize = const Size(960, 432);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: buildCosmoTheme(),
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: ScrollEdgeFade(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < rows; i++)
                        const SizedBox(height: 40, child: Text('row')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('builds over overflowing content and scrolls to the end', (
      tester,
    ) async {
      await pump(tester, 20);
      expect(find.byType(ShaderMask), findsOneWidget);
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('builds over content that fits', (tester) async {
      await pump(tester, 2);
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
