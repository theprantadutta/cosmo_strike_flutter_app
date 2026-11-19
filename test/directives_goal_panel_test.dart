import 'package:cosmo_strike_flutter_app/services/directive_streak.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/goal_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('DirectiveStreak', () {
    final now = DateTime(2026, 11, 19, 15, 30);
    DateTime day(int d, [int month = 11]) => DateTime(2026, month, d);

    test('fresh install (no history) is 0', () {
      expect(DirectiveStreak.compute(const [], now), 0);
      expect(DirectiveStreak.pastRun(const [], now), 0);
      expect(DirectiveStreak.securedToday(const [], now), isFalse);
    });

    test('counts consecutive days including today', () {
      final days = [day(17), day(18), day(19)];
      expect(DirectiveStreak.compute(days, now), 3);
      expect(DirectiveStreak.securedToday(days, now), isTrue);
    });

    test('an unsecured today keeps the streak alive up to yesterday', () {
      final days = [day(16), day(17), day(18)];
      expect(DirectiveStreak.compute(days, now), 3);
      expect(DirectiveStreak.securedToday(days, now), isFalse);
    });

    test('a gap day breaks the streak', () {
      // 15, 16 then nothing on the 17th: only 18 + 19 count.
      final days = [day(15), day(16), day(18), day(19)];
      expect(DirectiveStreak.compute(days, now), 2);
    });

    test('missing yesterday AND today means the streak is over', () {
      final days = [day(15), day(16), day(17)];
      expect(DirectiveStreak.compute(days, now), 0);
    });

    test('several rows on one day count once; time of day is ignored', () {
      final days = [
        DateTime(2026, 11, 18, 0, 0),
        DateTime(2026, 11, 18, 23, 59),
        DateTime(2026, 11, 19, 8),
        DateTime(2026, 11, 19, 9),
      ];
      expect(DirectiveStreak.compute(days, now), 2);
    });

    test('runs across a month boundary', () {
      final dec2 = DateTime(2026, 12, 2, 10);
      final days = [day(29), day(30), day(1, 12), day(2, 12)];
      expect(DirectiveStreak.compute(days, dec2), 4);
    });
  });

  group('DirectivesResetCountdown.format', () {
    test('counts down to local midnight', () {
      expect(DirectivesResetCountdown.format(DateTime(2026, 11, 19, 16, 47, 20)), '07:12:40');
      expect(DirectivesResetCountdown.format(DateTime(2026, 11, 19, 23, 59, 59)), '00:00:01');
      expect(DirectivesResetCountdown.format(DateTime(2026, 11, 19)), '24:00:00');
    });
  });

  group('DirectivesGoalView', () {
    // 640x360 phone: scale clamps to 0.72, left column = 290 * 0.72.
    const phone = Size(640, 360);
    const columnWidth = 290 * 0.72;
    const columnHeight = 360 - 44 - 60 - 24.0; // top bar, banner, padding

    Future<void> pumpView(
      WidgetTester tester,
      DirectivesGoalView view, {
      Size screen = phone,
      double width = columnWidth,
      double height = columnHeight,
    }) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, nav) => CsReduceMotion(reduceMotion: true, child: nav!),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, height: height, child: view),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
    }

    DirectivesGoalView view({
      int completed = 2,
      int total = 3,
      bool claimed = false,
      int streak = 0,
      bool secured = false,
      int unclaimed = 0,
      VoidCallback? onClaim,
    }) =>
        DirectivesGoalView(
          completed: completed,
          total: total,
          bonusCoins: 50,
          bonusXp: 100,
          bonusClaimed: claimed,
          unclaimedDirectives: unclaimed,
          streakDays: streak,
          streakSecuredToday: secured,
          onClaimBonus: onClaim,
          clock: () => DateTime(2026, 11, 19, 16, 47, 20),
        );

    testWidgets('in progress: "2 of 3 cleared", reward shown, no claim button', (tester) async {
      await pumpView(tester, view(completed: 2));
      expect(find.text('Clear all 3'), findsOneWidget);
      expect(find.text('2 of 3 cleared'), findsOneWidget);
      expect(find.text('+50 CR'), findsOneWidget);
      expect(find.text('+100 XP'), findsOneWidget);
      expect(find.byType(CsButton), findsNothing);
      expect(find.text('Start a streak today'), findsOneWidget);
      expect(find.text('07:12:40'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('claimable: bonus ready + claim button fires', (tester) async {
      var taps = 0;
      await pumpView(tester, view(completed: 3, unclaimed: 1, onClaim: () => taps++));
      expect(find.text('Bonus ready'), findsOneWidget);
      expect(find.text('CLAIM ALL + BONUS'), findsOneWidget);
      await tester.tap(find.byType(CsButton));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('claimable with every directive claimed says "Claim bonus"', (tester) async {
      await pumpView(tester, view(completed: 3));
      expect(find.text('CLAIM BONUS'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('claimed: "Bonus collected", no claim button', (tester) async {
      await pumpView(tester, view(completed: 3, claimed: true, streak: 4, secured: true));
      expect(find.text('Bonus collected'), findsOneWidget);
      expect(find.byType(CsButton), findsNothing);
      expect(find.text('DAY STREAK'), findsOneWidget);
      expect(find.text('SECURED TODAY'), findsOneWidget);
      expect(find.byType(CsOdometer), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('an unsecured streak warns the pilot', (tester) async {
      await pumpView(tester, view(completed: 0, streak: 6));
      expect(find.text('CLEAR 1 TODAY TO KEEP IT'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the countdown ticks each second', (tester) async {
      var now = DateTime(2026, 11, 19, 16, 47, 20);
      await pumpView(
        tester,
        DirectivesGoalView(
          completed: 1,
          total: 3,
          bonusCoins: 50,
          bonusXp: 100,
          bonusClaimed: false,
          streakDays: 0,
          streakSecuredToday: false,
          clock: () => now,
        ),
      );
      expect(find.text('07:12:40'), findsOneWidget);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('07:12:39'), findsOneWidget);
      // The countdown text sits in its own RepaintBoundary.
      expect(
        find.ancestor(of: find.text('07:12:39'), matching: find.byType(RepaintBoundary)),
        findsWidgets,
      );
      await unmount(tester);
    });

    testWidgets('fires onNewDay once local midnight passes', (tester) async {
      var now = DateTime(2026, 11, 19, 23, 59, 59);
      var rolls = 0;
      await pumpView(
        tester,
        DirectivesGoalView(
          completed: 3,
          total: 3,
          bonusCoins: 50,
          bonusXp: 100,
          bonusClaimed: true,
          streakDays: 1,
          streakSecuredToday: true,
          clock: () => now,
          onNewDay: () => rolls++,
        ),
      );
      now = DateTime(2026, 11, 20, 0, 0, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(rolls, 1);
      expect(find.text('24:00:00'), findsOneWidget);
      await unmount(tester);
    });

    for (final (name, v) in [
      ('in progress', view(completed: 1)),
      ('claimable', view(completed: 3, unclaimed: 2)),
      ('claimed + long streak', view(completed: 3, claimed: true, streak: 128, secured: true)),
      ('no orders yet', view(completed: 0, total: 0)),
    ]) {
      testWidgets('fits the 640x360 left column without overflow ($name)', (tester) async {
        await pumpView(tester, v);
        expect(tester.takeException(), isNull);
        final box = tester.getRect(find.byType(DirectivesGoalView));
        expect(box.width, lessThanOrEqualTo(columnWidth + 0.01));
        expect(box.height, lessThanOrEqualTo(columnHeight + 0.01));
        await unmount(tester);
      });
    }

    testWidgets('fits a 13-inch iPad left column', (tester) async {
      await pumpView(
        tester,
        view(completed: 3, unclaimed: 1, streak: 12),
        screen: const Size(1366, 1024),
        width: 320 * 1.4,
        height: 1024 - 200,
      );
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });
}
