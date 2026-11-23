import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/review_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_analytics_client.dart';

class _FakeInAppReview implements InAppReview {
  bool available = true;
  int requests = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async => requests++;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

void main() {
  final now = DateTime(2026, 11, 23, 12);

  group('ReviewGate', () {
    String? check({
      bool onboardingDone = true,
      int runs = 6,
      DateTime? lastPrompt,
      DateTime? lastInterruption,
      bool demo = false,
    }) => ReviewGate.skipReason(
      onboardingDone: onboardingDone,
      runsStarted: runs,
      now: now,
      lastPromptAt: lastPrompt,
      lastInterruptionAt: lastInterruption,
      demo: demo,
    );

    test('eligible after onboarding and 6 runs', () => expect(check(), isNull));
    test('not during onboarding', () => expect(check(onboardingDone: false), 'onboarding'));
    test('not before 6 runs', () => expect(check(runs: 5), isNotNull));
    test('never in DemoMode', () => expect(check(demo: true), 'demo_mode'));
    test('at most once per 60 days', () {
      expect(check(lastPrompt: now.subtract(const Duration(days: 59))), 'cooldown');
      expect(check(lastPrompt: now.subtract(const Duration(days: 60))), isNull);
    });
    test('never right after an ad, purchase or lost ship', () {
      expect(
        check(lastInterruption: now.subtract(const Duration(seconds: 30))),
        'recent_interruption',
      );
      expect(check(lastInterruption: now.subtract(const Duration(minutes: 5))), isNull);
    });
  });

  group('ReviewService.maybeAskForReview', () {
    late _FakeInAppReview platform;
    late RecordingAnalyticsClient client;
    late int runs;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      ReviewService.debugResetInterruption();
      platform = _FakeInAppReview();
      client = RecordingAnalyticsClient();
      runs = 6;
    });

    ReviewService make() => ReviewService(
      inAppReview: platform,
      analytics: AnalyticsFacade([client]),
      runsStarted: () => runs,
      onboardingDone: () => runs >= 3,
      clock: () => now,
      promptDelay: Duration.zero,
      demo: false,
    );

    test('asks the native API once, then respects the 60-day cooldown',
        () async {
      final s = make();
      expect(await s.maybeAskForReview(ReviewTrigger.levelCleared), isTrue);
      expect(await s.debugPendingDispatch, isTrue);
      expect(platform.requests, 1);

      expect(await s.maybeAskForReview(ReviewTrigger.newHighScore), isFalse);
      expect(platform.requests, 1);
    });

    test('skips new players', () async {
      runs = 2;
      expect(await make().maybeAskForReview(ReviewTrigger.levelCleared), isFalse);
      expect(platform.requests, 0);
    });

    test('drops the request when the moment has passed', () async {
      final s = make();
      expect(
        await s.maybeAskForReview(
          ReviewTrigger.levelCleared,
          stillAppropriate: () => false,
        ),
        isTrue,
      );
      expect(await s.debugPendingDispatch, isFalse);
      expect(platform.requests, 0);
      // Not stamped: the next good moment may still ask.
      expect(await s.maybeAskForReview(ReviewTrigger.levelCleared), isTrue);
      expect(await s.debugPendingDispatch, isTrue);
    });

    test('not right after an interruption', () async {
      ReviewService.noteInterruption(now.subtract(const Duration(seconds: 10)));
      expect(await make().maybeAskForReview(ReviewTrigger.levelCleared), isFalse);
    });

    test('unavailable platform API means no request', () async {
      platform.available = false;
      expect(await make().maybeAskForReview(ReviewTrigger.victory), isFalse);
    });
  });
}
