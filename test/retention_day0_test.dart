import 'package:cosmo_strike_flutter_app/game/cosmo_strike_game.dart';
import 'package:cosmo_strike_flutter_app/models/daily_challenge.dart';
import 'package:cosmo_strike_flutter_app/models/level_run_result.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/services/new_best_reminder_ask.dart';
import 'package:cosmo_strike_flutter_app/services/run_checkpoint.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/game_over_overlay.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/new_best_reminder_row.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/next_up.dart';
import 'package:cosmo_strike_flutter_app/widgets/gameplay/run_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _harness(Widget child) => MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildCosmoTheme(),
      home: Scaffold(body: child),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(640, 360);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

DailyChallenge _directive(
  String id, {
  required int progress,
  required int target,
  bool completed = false,
  bool claimed = false,
  String title = 'Down 40 raiders',
}) =>
    DailyChallenge(
      id: id,
      title: title,
      description: 'Destroy raiders in any run',
      type: ChallengeType.enemiesKilled,
      difficulty: ChallengeDifficulty.easy,
      targetValue: target,
      currentProgress: progress,
      isCompleted: completed,
      claimedReward: claimed,
      coinReward: 40,
      xpReward: 60,
    );

const _result = GameResult(
  score: 9170,
  stageReached: 2,
  waveReached: 3,
  enemiesKilled: 51,
  bossesKilled: 1,
  durationSeconds: 180,
  cleared: false,
  startLevel: 1,
  levelsCleared: 1,
  missilesFired: 2,
  revivesUsed: 0,
  levelResults: [],
  maxCombo: 3,
  grazeCount: 12,
);

const _level1Clear = LevelRunResult(stageId: 1, cleared: true, score: 4000, timeSeconds: 90, waveReached: 5, noHit: false);
const _level2Partial = LevelRunResult(stageId: 2, cleared: false, score: 900, timeSeconds: 40, waveReached: 2, noHit: false);

void main() {
  group('No revive in the onboarding runs', () {
    test('onboarding runs (1-3) never allow the continue', () {
      for (final run in [1, 2, 3]) {
        expect(RunContext.allowsRevive(onboardingRunNumber: run), isFalse);
      }
      expect(RunContext.allowsRevive(onboardingRunNumber: null), isTrue);
    });

    test('the game offers the continue only when allowed, unused and not one-hit', () {
      expect(CosmoStrikeGame.offersRevive(allowRevive: true, reviveUsed: false, oneHitRun: false), isTrue);
      expect(CosmoStrikeGame.offersRevive(allowRevive: false, reviveUsed: false, oneHitRun: false), isFalse);
      expect(CosmoStrikeGame.offersRevive(allowRevive: true, reviveUsed: true, oneHitRun: false), isFalse);
      expect(CosmoStrikeGame.offersRevive(allowRevive: true, reviveUsed: false, oneHitRun: true), isFalse);
    });

    test('the game defaults to allowing the continue', () {
      expect(CosmoStrikeGame().allowRevive, isTrue);
      expect(CosmoStrikeGame(allowRevive: false).allowRevive, isFalse);
    });
  });

  group('NEXT UP content', () {
    test('shows from the second run on', () {
      expect(NextUp.showsFor(runsStarted: 1), isFalse);
      expect(NextUp.showsFor(runsStarted: 2), isTrue);
      expect(NextUp.showsFor(runsStarted: 9), isTrue);
    });

    test('picks the unfinished directive closest to done', () {
      final picked = NextUp.pickFocus([
        _directive('a', progress: 10, target: 40),
        _directive('b', progress: 6, target: 10),
        _directive('c', progress: 3, target: 3, completed: true),
        _directive('d', progress: 9, target: 9, completed: true, claimed: true),
      ]);
      expect(picked?.id, 'b');
    });

    test('ties on share go to the one with fewer steps left', () {
      final picked = NextUp.pickFocus([
        _directive('big', progress: 50, target: 100),
        _directive('small', progress: 2, target: 4),
      ]);
      expect(picked?.id, 'small');
    });

    test('no focus when every directive is done', () {
      expect(NextUp.pickFocus([_directive('a', progress: 3, target: 3, completed: true)]), isNull);
      expect(NextUp.pickFocus(const []), isNull);
    });

    test('streak copy: secured, at risk, not started', () {
      expect(NextUp.streakLine(days: 3, securedToday: true), '3-day streak secured');
      expect(NextUp.streakLine(days: 1, securedToday: true), 'Streak started · day 1 secured');
      expect(NextUp.streakLine(days: 3, securedToday: false), 'Clear 1 directive to keep your 3-day streak');
      expect(NextUp.streakLine(days: 0, securedToday: false), 'Clear 1 directive to start a streak');
    });

    test('Supply Drop: tomorrow after today\'s claim, today while unopened', () {
      // First ever claim today (streak 1) → tomorrow is Day 2 (+3 CR).
      final tomorrow = NextUp.supplyDrop(claimedToday: true, currentStreak: 1, nextClaimDay: 1)!;
      expect(tomorrow.day, 2);
      expect(tomorrow.coins, 3);
      expect(tomorrow.readyToday, isFalse);
      expect(tomorrow.line, 'Tomorrow · Day 2 · +3 CR');

      // Day 7 claimed → the ladder wraps to Day 1.
      final wrapped = NextUp.supplyDrop(claimedToday: true, currentStreak: 7, nextClaimDay: 1)!;
      expect(wrapped.day, 1);

      // Day 2 claimed → Day 3 carries the bonus gear.
      final gear = NextUp.supplyDrop(claimedToday: true, currentStreak: 2, nextClaimDay: 1)!;
      expect(gear.line, 'Tomorrow · Day 3 · +4 CR + ${DailyLoginBonus.getWeeklyBonuses()[2].bonusItem}');

      // Not opened yet today → point at today's drop.
      final ready = NextUp.supplyDrop(claimedToday: false, currentStreak: 3, nextClaimDay: 4)!;
      expect(ready.readyToday, isTrue);
      expect(ready.line, 'Supply Drop ready · Day 4 · +5 CR');
    });

    testWidgets('the strip fits a 640×360 phone column and opens Directives', (tester) async {
      _phone(tester);
      var opened = 0;
      await tester.pumpWidget(_harness(SizedBox(
        width: 280,
        child: NextUpView(
          focus: _directive('b', progress: 6, target: 10),
          runDelta: 4,
          streakDays: 3,
          streakSecuredToday: false,
          drop: const SupplyDropPreview(day: 2, coins: 3, readyToday: false),
          onOpenDirectives: () => opened++,
        ),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Down 40 raiders'), findsOneWidget);
      expect(find.text('CLEAR 1 DIRECTIVE TO KEEP YOUR 3-DAY STREAK'), findsOneWidget);
      expect(find.text('TOMORROW · DAY 2 · +3 CR'), findsOneWidget);
      await tester.tap(find.text('Down 40 raiders'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('game over hosts NEXT UP + the reminder ask on a phone; onboarding Retry is early', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_harness(GameOverOverlay(
        result: _result,
        victory: false,
        previousBest: 5000,
        unlockedLevel: 0,
        runCoinsEarned: 41,
        runXpEarned: 70,
        coinsDoubled: false,
        canDoubleCoins: false,
        onDoubleCoins: () {},
        onRetry: () {},
        onExit: () {},
        challengeRunStart: const {},
        directives: const SizedBox(height: 10),
        quickRetry: true,
        nextUp: NextUpView(
          focus: _directive('b', progress: 6, target: 10),
          streakDays: 2,
          streakSecuredToday: true,
          drop: const SupplyDropPreview(day: 3, coins: 4, readyToday: false),
        ),
        reminderAsk: NewBestReminderRow(bestScore: 9170, onAccept: () async => true, onDismiss: () {}),
      )));
      await tester.pump(const Duration(milliseconds: 800));
      final retryFade = tester.widget<FadeTransition>(
        find.ancestor(of: find.text('RETRY'), matching: find.byType(FadeTransition)).first,
      );
      expect(retryFade.opacity.value, 1, reason: 'quickRetry lands the actions by ~770 ms');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('NEXT UP'), findsOneWidget);
      expect(find.text('2-DAY STREAK SECURED'), findsOneWidget);
      expect(find.text('Beat 9,170 tomorrow?'), findsOneWidget);
    });
  });

  group('New-best reminder ask', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<bool> off() async => false;
    Future<bool> on() async => true;

    test('offered once per install, only on a new best with notifications off', () async {
      expect(await NewBestReminderAsk.shouldOffer(isNewBest: false, notificationsEnabled: off), isFalse);
      expect(await NewBestReminderAsk.shouldOffer(isNewBest: true, notificationsEnabled: on), isFalse);
      expect(await NewBestReminderAsk.shouldOffer(isNewBest: true, notificationsEnabled: off), isTrue);
      await NewBestReminderAsk.recordShown();
      expect(await NewBestReminderAsk.shouldOffer(isNewBest: true, notificationsEnabled: off), isFalse);
    });

    test('answering retires it and the Home soft-ask fallback', () async {
      await NewBestReminderAsk.recordAnswered();
      expect(await NewBestReminderAsk.shouldOffer(isNewBest: true, notificationsEnabled: off), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_soft_ask_shown'), isTrue);
    });

    test('an unanswered impression leaves the Home soft-ask in place', () async {
      await NewBestReminderAsk.recordShown();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_soft_ask_shown'), isNull);
    });

    testWidgets('the row: Remind me runs the flow, then confirms', (tester) async {
      _phone(tester);
      var asked = 0;
      await tester.pumpWidget(_harness(SizedBox(
        width: 300,
        child: NewBestReminderRow(
          bestScore: 9170,
          onAccept: () async {
            asked++;
            return true;
          },
          onDismiss: () {},
        ),
      )));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('REMIND ME'));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(find.text('REMINDER SET · SEE YOU TOMORROW'), findsOneWidget);
    });

    testWidgets('the row: dismiss folds it away', (tester) async {
      _phone(tester);
      var dismissed = 0;
      await tester.pumpWidget(_harness(SizedBox(
        width: 300,
        child: NewBestReminderRow(bestScore: 9170, onAccept: () async => true, onDismiss: () => dismissed++),
      )));
      await tester.tap(find.byTooltip('Not now'));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
      expect(find.text('REMIND ME'), findsNothing);
    });
  });

  group('Background persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a cleared level merges once across background, resume and game over', () {
      final persisted = <int>{};
      final applied = <LevelRunResult>[];
      void persist(List<LevelRunResult> all) {
        final pending = RunCheckpoint.pendingResults(all, persisted);
        applied.addAll(pending);
        persisted.addAll(pending.where((lr) => lr.cleared).map((lr) => lr.stageId));
      }

      persist(const [_level1Clear, _level2Partial]); // backgrounded
      persist(const [_level1Clear, _level2Partial]); // backgrounded again
      persist(const [_level1Clear, _level2Partial]); // game over
      expect(applied.where((lr) => lr.cleared && lr.stageId == 1).length, 1,
          reason: 'clearCount must not double');
      // The in-progress level re-applies (monotonic best-wave merge).
      expect(applied.where((lr) => !lr.cleared).length, 3);
    });

    test('a resumed run drops its parked score; nothing is queued twice', () async {
      final queued = <String>[];
      Future<void> enqueue(String key, Map<String, dynamic> payload) async => queued.add(key);

      await RunCheckpoint.stash(entityKey: 'run-1', payload: {'score': 100});
      await RunCheckpoint.stash(entityKey: 'run-1', payload: {'score': 400}); // replaced
      await RunCheckpoint.clear(); // resumed (or game over / quit submitted it)
      expect(await RunCheckpoint.recoverPending(enqueue), isFalse);
      expect(queued, isEmpty);
    });

    test('a killed run queues its last checkpoint exactly once at next launch', () async {
      final queued = <Map<String, dynamic>>[];
      Future<void> enqueue(String key, Map<String, dynamic> payload) async => queued.add({'key': key, ...payload});

      await RunCheckpoint.stash(entityKey: 'run-2', payload: {'score': 100});
      await RunCheckpoint.stash(entityKey: 'run-2', payload: {'score': 750});
      expect(await RunCheckpoint.recoverPending(enqueue), isTrue);
      expect(await RunCheckpoint.recoverPending(enqueue), isFalse);
      expect(queued, [
        {'key': 'run-2', 'score': 750},
      ]);
    });

    test('a quick background → resume can\'t leave a stale checkpoint', () async {
      final queued = <String>[];
      // Fired without awaiting, as the lifecycle callbacks do.
      final a = RunCheckpoint.stash(entityKey: 'run-3', payload: {'score': 10});
      final b = RunCheckpoint.clear();
      await Future.wait([a, b]);
      expect(await RunCheckpoint.recoverPending((k, _) async => queued.add(k)), isFalse);
    });
  });
}
