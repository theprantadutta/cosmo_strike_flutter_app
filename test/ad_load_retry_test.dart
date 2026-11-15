import 'dart:async';

import 'package:cosmo_strike_flutter_app/services/ads/ad_load_retry.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_load_tally.dart';
import 'package:flutter_test/flutter_test.dart';

/// A timer the test fires by hand.
class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  group('AdLoadRetry', () {
    late List<_FakeTimer> timers;
    late double jitter;
    late int cap;

    AdLoadRetry build({List<Duration>? delays}) => AdLoadRetry(
      delays: delays ?? AdLoadRetry.defaultDelays,
      maxAttempts: () => cap,
      random: () => jitter,
      timerFactory: (delay, cb) {
        final t = _FakeTimer(delay, cb);
        timers.add(t);
        return t;
      },
    );

    setUp(() {
      timers = [];
      jitter = 0.5; // factor 0.85 + 0.5 * 0.40 = 1.05
      cap = 5;
    });

    test('delays grow along the ladder with jitter applied', () {
      final retry = build();
      final delays = <Duration>[];
      for (var i = 0; i < 5; i++) {
        delays.add(retry.schedule('rewarded', () {})!);
        timers.last.fire();
      }
      expect(
        delays,
        AdLoadRetry.defaultDelays.map((d) => d * 1.05).toList(),
      );
      for (var i = 1; i < delays.length; i++) {
        expect(delays[i] > delays[i - 1], isTrue);
      }
    });

    test('jitter stays within the band', () {
      jitter = 0;
      expect(build().schedule('a', () {}), const Duration(seconds: 3) * 0.85);
      jitter = 0.999999;
      final high = build().schedule('a', () {})!;
      expect(high < const Duration(seconds: 3) * 1.25, isTrue);
      expect(high > const Duration(seconds: 3) * 1.24, isTrue);
    });

    test('stops after the attempt cap', () {
      final retry = build();
      for (var i = 0; i < 5; i++) {
        expect(retry.schedule('interstitial', () {}), isNotNull);
        timers.last.fire();
      }
      expect(retry.isExhausted('interstitial'), isTrue);
      expect(retry.schedule('interstitial', () {}), isNull);
      expect(timers.length, 5);
    });

    test('remote cap lowers attempts; 0 disables, oversize is clamped', () {
      cap = 2;
      final retry = build();
      retry.schedule('a', () {});
      timers.last.fire();
      retry.schedule('a', () {});
      timers.last.fire();
      expect(retry.schedule('a', () {}), isNull);

      cap = 0;
      expect(build().schedule('b', () {}), isNull);

      cap = 99;
      expect(build().attemptCap, AdLoadRetry.defaultDelays.length);
    });

    test('only one retry pending per format', () {
      final retry = build();
      expect(retry.schedule('rewarded', () {}), isNotNull);
      expect(retry.schedule('rewarded', () {}), isNull);
      expect(retry.attemptsFor('rewarded'), 1);
      // Other formats have their own track.
      expect(retry.schedule('interstitial', () {}), isNotNull);
      expect(timers.length, 2);
    });

    test('firing runs the load and clears the pending flag', () {
      final retry = build();
      var loads = 0;
      retry.schedule('rewarded', () => loads++);
      expect(retry.isPending('rewarded'), isTrue);
      timers.single.fire();
      expect(loads, 1);
      expect(retry.isPending('rewarded'), isFalse);
    });

    test('success resets the ladder and cancels a pending retry', () {
      final retry = build();
      var loads = 0;
      retry.schedule('rewarded', () => loads++);
      timers.last.fire();
      retry.schedule('rewarded', () => loads++);
      retry.succeeded('rewarded');
      timers.last.fire(); // cancelled — no-op
      expect(loads, 1);
      expect(retry.attemptsFor('rewarded'), 0);
      expect(
        retry.schedule('rewarded', () {}),
        AdLoadRetry.defaultDelays.first * 1.05,
      );
    });

    test('cancelAll keeps counts; resetAll forgets them', () {
      final retry = build();
      var loads = 0;
      retry.schedule('a', () => loads++);
      retry.cancelAll();
      timers.last.fire();
      expect(loads, 0);
      expect(retry.attemptsFor('a'), 1);
      expect(retry.isPending('a'), isFalse);

      retry.resetAll();
      expect(retry.attemptsFor('a'), 0);
    });
  });

  group('AdLoadTally', () {
    test('drains per-format counts with codes most frequent first', () {
      final tally = AdLoadTally()
        ..requested('rewarded')
        ..requested('rewarded')
        ..requested('rewarded')
        ..failed('rewarded', 2)
        ..failed('rewarded', 3)
        ..failed('rewarded', 3)
        ..requested('interstitial')
        ..filled('interstitial');

      final out = {for (final s in tally.drain()) s.format: s};
      expect(out['rewarded']!.requests, 3);
      expect(out['rewarded']!.filled, 0);
      expect(out['rewarded']!.failed, 3);
      expect(out['rewarded']!.errorCodes, '3:2,2:1');
      expect(out['interstitial']!.filled, 1);
      expect(out['interstitial']!.errorCodes, '');

      expect(tally.isEmpty, isTrue);
      expect(tally.drain(), isEmpty);
    });
  });
}
