import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmo_strike_flutter_app/core/startup/startup_guard.dart';

void main() {
  group('SingleFlight', () {
    test('a second caller joins the run in flight', () async {
      final flight = SingleFlight<int>();
      final gate = Completer<int>();
      var calls = 0;
      Future<int> body() {
        calls++;
        return gate.future;
      }

      final a = flight.run(body);
      final b = flight.run(body);
      expect(calls, 1);
      gate.complete(7);
      expect(await a, 7);
      expect(await b, 7);
    });

    test('a success is reused, the body never runs again', () async {
      final flight = SingleFlight<int>();
      var calls = 0;
      expect(await flight.run(() async => ++calls), 1);
      expect(await flight.run(() async => ++calls), 1);
      expect(calls, 1);
      expect(flight.hasRun, isTrue);
    });

    test('a failure clears it so the next caller starts over', () async {
      final flight = SingleFlight<int>();
      var calls = 0;
      await expectLater(
        flight.run(() async {
          calls++;
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(flight.hasRun, isFalse);
      expect(await flight.run(() async => ++calls), 2);
    });

    test('a synchronous throw is delivered as a failed future', () async {
      final flight = SingleFlight<void>();
      await expectLater(
        flight.run(() => throw ArgumentError('sync')),
        throwsArgumentError,
      );
      expect(flight.hasRun, isFalse);
    });

    test('a timed-out wait leaves the run in flight for a retry to join',
        () async {
      final flight = SingleFlight<String>();
      final gate = Completer<String>();
      var calls = 0;
      Future<String> body() {
        calls++;
        return gate.future;
      }

      await expectLater(
        flight.run(body).timeout(const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()),
      );
      expect(flight.hasRun, isTrue);

      final retry = flight.run(body);
      gate.complete('done');
      expect(await retry, 'done');
      expect(calls, 1);
    });
  });

  group('withStepTimeout', () {
    test('passes a value through when in time', () async {
      final v = await withStepTimeout(
        Future.value(3),
        const Duration(seconds: 1),
        label: 'x',
        orElse: () => -1,
      );
      expect(v, 3);
    });

    test('falls back and reports when the step overruns', () async {
      String? timedOut;
      final result = await withStepTimeout<int>(
        Completer<int>().future,
        const Duration(milliseconds: 20),
        label: 'audio',
        orElse: () => -1,
        onTimedOut: (label, _) => timedOut = label,
      );
      expect(result, -1);
      expect(timedOut, 'audio');
    });

    test('errors from the step still propagate', () async {
      await expectLater(
        withStepTimeout<void>(
          Future<void>.error(StateError('bad')),
          const Duration(seconds: 1),
          label: 'x',
          orElse: () {},
        ),
        throwsStateError,
      );
    });
  });

  group('StartupPhaseTracker', () {
    test('records each phase duration and keeps the last phase name', () {
      var now = DateTime(2026, 1, 1);
      final t = StartupPhaseTracker(clock: () => now);
      expect(t.currentPhase, isNull);

      t.begin('dotenv');
      now = now.add(const Duration(milliseconds: 40));
      t.begin('firebase');
      now = now.add(const Duration(milliseconds: 300));
      t.end();
      now = now.add(const Duration(milliseconds: 10));

      expect(t.durationsMs, {'dotenv': 40, 'firebase': 300});
      expect(t.currentPhase, 'firebase');
      expect(t.elapsedMs, 350);
    });

    test('a phase still running has no duration yet', () {
      var now = DateTime(2026, 1, 1);
      final t = StartupPhaseTracker(clock: () => now);
      t.begin('dependencies');
      now = now.add(const Duration(seconds: 30));
      expect(t.durationsMs, isEmpty);
      expect(t.currentPhase, 'dependencies');
    });
  });

  group('EarlyErrorBuffer', () {
    BufferedStartupError err(String m) =>
        BufferedStartupError(m, null, reason: m, fatal: false);

    test('buffers until attached, then flushes in order and forwards', () {
      final buffer = EarlyErrorBuffer();
      final seen = <Object>[];
      buffer.add(err('a'));
      buffer.add(err('b'));
      expect(buffer.pending.length, 2);

      buffer.attach((e) => seen.add(e.error));
      expect(seen, ['a', 'b']);
      expect(buffer.pending, isEmpty);
      expect(buffer.isAttached, isTrue);

      buffer.add(err('c'));
      expect(seen, ['a', 'b', 'c']);
    });

    test('drops the oldest entries past capacity and counts them', () {
      final buffer = EarlyErrorBuffer(capacity: 2);
      buffer
        ..add(err('a'))
        ..add(err('b'))
        ..add(err('c'));
      expect(buffer.pending.map((e) => e.error), ['b', 'c']);
      expect(buffer.dropped, 1);
    });

    test('a sink that throws for one entry still gets the rest', () {
      final buffer = EarlyErrorBuffer();
      final seen = <Object>[];
      buffer
        ..add(err('a'))
        ..add(err('b'));
      buffer.attach((e) {
        if (e.error == 'a') throw StateError('sink');
        seen.add(e.error);
      });
      expect(seen, ['b']);
    });
  });
}
