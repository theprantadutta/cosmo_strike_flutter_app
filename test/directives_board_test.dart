import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/directive_card.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/directives_board.dart';
import 'package:cosmo_strike_flutter_app/widgets/directives/weekly_ops_strip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

DailyChallenge _directive(
  String id, {
  ChallengeType type = ChallengeType.enemiesKilled,
  ChallengeDifficulty difficulty = ChallengeDifficulty.easy,
  int progress = 7,
  int target = 15,
  bool completed = false,
  bool claimed = false,
}) =>
    DailyChallenge(
      id: id,
      title: 'Trigger Warmup',
      description: 'Destroy $target hostiles today',
      type: type,
      difficulty: difficulty,
      targetValue: target,
      currentProgress: progress,
      isCompleted: completed,
      claimedReward: claimed,
      coinReward: 8,
      xpReward: 20,
    );

final _mixed = [
  _directive('a'),
  _directive('b',
      type: ChallengeType.survival,
      difficulty: ChallengeDifficulty.medium,
      progress: 1000,
      target: 1000,
      completed: true),
  _directive('c',
      type: ChallengeType.score,
      difficulty: ChallengeDifficulty.hard,
      progress: 1000,
      target: 1000,
      completed: true,
      claimed: true),
];

/// The real screen frame: CsScaffold (top bar + padding) → CsSplit with the
/// board in the right column, at a device size.
Future<void> _pumpBoard(
  WidgetTester tester,
  Size size, {
  List<DailyChallenge>? challenges,
  bool bonus = true,
  bool guest = false,
  VoidCallback? onFly,
  ValueChanged<DailyChallenge>? onClaim,
  VoidCallback? onOpenWeekly,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: CsScaffold(
      title: 'Directives',
      body: CsSplit(
        left: const SizedBox.shrink(),
        right: DirectivesBoard(
          challenges: challenges ?? _mixed,
          onClaim: onClaim ?? (_) {},
          onFly: onFly ?? () {},
          bonusStrip: bonus ? const DirectivesBonusStrip(bonusCoins: 25, claimed: false) : null,
          weeklyStrip: WeeklyOpsStrip(
            completed: 2,
            total: 5,
            isGuest: guest,
            resetsIn: const Duration(days: 3),
            onOpen: onOpenWeekly,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('DirectiveCard states', () {
    testWidgets('in progress offers Fly', (tester) async {
      var flown = 0;
      await _pumpBoard(tester, const Size(1340, 800),
          challenges: [_directive('a')], onFly: () => flown++);
      expect(find.text('FLY'), findsOneWidget);
      expect(find.text('CLAIM'), findsNothing);
      expect(find.text('+8 CR'), findsOneWidget);
      expect(find.text('+20 XP'), findsOneWidget);
      await tester.tap(find.text('FLY'));
      expect(flown, 1);
      expect(DirectiveCardStatus.of(_directive('a')), DirectiveCardStatus.inProgress);
    });

    testWidgets('complete offers Claim (button and card tap)', (tester) async {
      final claimed = <String>[];
      await _pumpBoard(tester, const Size(1340, 800),
          challenges: [_directive('b', progress: 15, completed: true)], onClaim: (c) => claimed.add(c.id));
      expect(find.text('CLAIM'), findsOneWidget);
      expect(find.text('FLY'), findsNothing);
      await tester.tap(find.text('CLAIM'));
      await tester.tap(find.text('Trigger Warmup'));
      expect(claimed, ['b', 'b']);
    });

    testWidgets('claimed shows the mint done state and pops on claim', (tester) async {
      await _pumpBoard(tester, const Size(1340, 800),
          challenges: [_directive('c', progress: 15, completed: true)]);
      expect(find.descendant(of: find.byType(DirectiveCard), matching: find.byType(CsPop)), findsWidgets);
      await _pumpBoard(tester, const Size(1340, 800),
          challenges: [_directive('c', progress: 15, completed: true, claimed: true)]);
      expect(find.text('CLAIMED'), findsOneWidget);
      expect(find.text('FLY'), findsNothing);
      expect(find.text('CLAIM'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('type glyphs', () {
      expect(directiveIcon(_directive('x', type: ChallengeType.survival)), Symbols.timer_rounded);
      expect(directiveIcon(_directive('x', type: ChallengeType.gamesPlayed)), Symbols.rocket_launch_rounded);
      expect(directiveIcon(_directive('x', type: ChallengeType.enemiesKilled)), Symbols.crisis_alert_rounded);
    });
  });

  group('DirectivesBoard layout', () {
    const sizes = [
      Size(640, 360),
      Size(800, 360),
      Size(932, 430),
      Size(1024, 600),
      Size(1194, 834),
      Size(1340, 800),
      Size(1366, 1024),
    ];
    for (final size in sizes) {
      testWidgets('3 cards fit without overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await _pumpBoard(tester, size);
        expect(tester.takeException(), isNull);
        expect(find.byType(DirectiveCard), findsNWidgets(3));
        // The cards share the column: together they cover most of its height.
        final cards = find.byType(DirectiveCard);
        final top = tester.getTopLeft(cards.first).dy;
        final bottom = tester.getBottomLeft(cards.last).dy;
        expect(bottom - top, greaterThan(size.height * 0.45));
      });
    }

    testWidgets('tablet keeps both strips; short phone drops the extra one', (tester) async {
      await _pumpBoard(tester, const Size(1340, 800));
      expect(find.byType(WeeklyOpsStrip), findsOneWidget);
      expect(find.byType(DirectivesBonusStrip), findsOneWidget);

      await _pumpBoard(tester, const Size(640, 360));
      // The bonus outranks Weekly Ops when only one fits.
      expect(find.byType(DirectivesBonusStrip), findsOneWidget);
      expect(find.byType(WeeklyOpsStrip), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('WeeklyOpsStrip', () {
    testWidgets('shows progress and opens the Weekly Ops tab', (tester) async {
      var opened = 0;
      await _pumpBoard(tester, const Size(1340, 800), bonus: false, onOpenWeekly: () => opened++);
      expect(find.text('2 of 5 · resets in 3d'), findsOneWidget);
      await tester.tap(find.byType(WeeklyOpsStrip));
      expect(opened, 1);
    });

    testWidgets('guests get the compact sign-in CTA', (tester) async {
      await _pumpBoard(tester, const Size(640, 360), bonus: false, guest: true);
      expect(find.text('Sign in for Weekly Ops'), findsOneWidget);
      expect(find.text('SIGN IN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('reset formatting', () {
      expect(formatResetsIn(const Duration(days: 3)), '3d');
      expect(formatResetsIn(const Duration(days: 1, hours: 4)), '1d 4h');
      expect(formatResetsIn(const Duration(hours: 5, minutes: 3)), '5h');
      expect(formatResetsIn(const Duration(minutes: 12)), '12m');
      // Wednesday noon → Monday 00:00 is 4.5 days away.
      expect(weeklyOpsResetsIn(DateTime(2026, 11, 18, 12)), const Duration(days: 4, hours: 12));
    });
  });
}
