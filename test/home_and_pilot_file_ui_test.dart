import 'package:cosmo_strike_flutter_app/screens/profile_screen.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/home_nav_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _harness(Widget child) => MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildCosmoTheme(),
      home: Scaffold(body: child),
    );

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('Pilot File account rows', () {
    Future<(int, int)> pump(WidgetTester tester, {required bool localGuest, required bool anonymous}) async {
      _setSize(tester, const Size(960, 432));
      var saves = 0, signOuts = 0;
      await tester.pumpWidget(_harness(SingleChildScrollView(
        child: PilotAccountRows(
          isLocalGuest: localGuest,
          isAnonymous: anonymous,
          onSaveProgress: () => saves++,
          onSignOut: () => signOuts++,
        ),
      )));
      if (find.text('Save your progress').evaluate().isNotEmpty) {
        await tester.tap(find.text('Save your progress'));
      }
      if (find.text('Sign out').evaluate().isNotEmpty) {
        await tester.tap(find.text('Sign out'));
      }
      return (saves, signOuts);
    }

    testWidgets('local guest: Save your progress, no Sign out', (tester) async {
      final (saves, signOuts) = await pump(tester, localGuest: true, anonymous: false);
      expect(find.text('Save your progress'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
      expect(saves, 1);
      expect(signOuts, 0);
    });

    testWidgets('anonymous pilot: Save plus a flagged Sign out', (tester) async {
      final (saves, signOuts) = await pump(tester, localGuest: false, anonymous: true);
      expect(find.text('Save your progress'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Erases this unsaved Pilot File'), findsOneWidget);
      expect(saves, 1);
      expect(signOuts, 1);
    });

    testWidgets('signed-in pilot: Sign out only', (tester) async {
      final (saves, signOuts) = await pump(tester, localGuest: false, anonymous: false);
      expect(find.text('Save your progress'), findsNothing);
      expect(find.text('Erases this unsaved Pilot File'), findsNothing);
      expect(signOuts, 1);
      expect(saves, 0);
    });
  });

  group('Home nav bar', () {
    for (final (name, size) in [
      ('640x360 phone', const Size(640, 360)),
      ('A24 phone', const Size(832, 384)),
      ('Tab A9+', const Size(1340, 800)),
      ('13in iPad', const Size(1366, 1024)),
    ]) {
      testWidgets('six items fit with >=48dp targets on $name', (tester) async {
        _setSize(tester, size);
        final taps = <String>[];
        HomeNavItem item(String label, {String? badge, bool dot = false}) => HomeNavItem(
              icon: Symbols.star_rounded,
              label: label,
              badge: badge,
              dot: dot,
              onTap: () => taps.add(label),
            );
        await tester.pumpWidget(_harness(Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            // Home's horizontal screen padding at its largest.
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: HomeNavBar(items: [
              item('Directives', badge: '2/3', dot: true),
              item('Frontline', badge: 'T12'),
              item('Cups'),
              item('Hangar'),
              item('Command'),
              item('Armory'),
            ]),
          ),
        )));
        expect(tester.takeException(), isNull);
        for (final label in ['DIRECTIVES', 'FRONTLINE', 'CUPS', 'HANGAR', 'COMMAND', 'ARMORY']) {
          final cell = find.ancestor(of: find.text(label), matching: find.byType(HomeNavItem));
          final box = tester.getSize(cell);
          expect(box.height, greaterThanOrEqualTo(48), reason: '$label cell height');
          expect(box.width, greaterThanOrEqualTo(48), reason: '$label cell width');
          await tester.tap(cell);
        }
        expect(taps, ['Directives', 'Frontline', 'Cups', 'Hangar', 'Command', 'Armory']);
      });
    }
  });
}
