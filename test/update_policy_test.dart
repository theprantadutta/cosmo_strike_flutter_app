import 'package:cosmo_strike_flutter_app/services/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which Play update flow a launch gets. A routine release is offered with
/// our own dialog (whose "Update now" runs Play's blocking flow), the
/// blocking flow runs unasked only for releases marked urgent, a refusal is
/// respected for a day, and nothing but an urgent release is put in front
/// of a pilot's first run.
void main() {
  UpdateFlow decide({
    bool available = true,
    int priority = 0,
    bool immediate = true,
    bool flexible = true,
    Duration? sinceDeclined,
    bool firstSession = false,
  }) => UpdatePolicy.decide(
    updateAvailable: available,
    priority: priority,
    immediateAllowed: immediate,
    flexibleAllowed: flexible,
    sinceDeclined: sinceDeclined,
    firstSession: firstSession,
  );

  test('no update, no flow', () {
    expect(decide(available: false), UpdateFlow.none);
    expect(decide(available: false, priority: 5), UpdateFlow.none);
  });

  test('a routine release is offered (our dialog first, never a wall)', () {
    expect(decide(priority: 0), UpdateFlow.offer);
    expect(decide(priority: 3), UpdateFlow.offer);
  });

  test('an urgent release gets the blocking flow without asking', () {
    expect(decide(priority: 4), UpdateFlow.immediate);
    expect(decide(priority: 5), UpdateFlow.immediate);
  });

  test('an urgent release cuts through a snooze', () {
    expect(
      decide(priority: 5, sinceDeclined: const Duration(minutes: 5)),
      UpdateFlow.immediate,
    );
  });

  test('a snoozed offer is left alone for a day', () {
    expect(decide(sinceDeclined: const Duration(hours: 23)), UpdateFlow.none);
    expect(decide(sinceDeclined: const Duration(hours: 25)), UpdateFlow.offer);
  });

  test('when Play only allows the background download, use it as a fallback', () {
    expect(decide(immediate: false), UpdateFlow.flexible);
    expect(decide(priority: 5, immediate: false), UpdateFlow.flexible);
  });

  test('when Play allows neither, nothing', () {
    expect(decide(immediate: false, flexible: false), UpdateFlow.none);
  });

  group('no gates before the first run', () {
    test('a routine release is not offered in the first session', () {
      expect(decide(firstSession: true), UpdateFlow.none);
      expect(decide(firstSession: true, priority: 3), UpdateFlow.none);
    });

    test('nor is the background-download fallback (Play shows a dialog)', () {
      expect(decide(firstSession: true, immediate: false), UpdateFlow.none);
    });

    test('an urgent release still runs', () {
      expect(decide(firstSession: true, priority: 4), UpdateFlow.immediate);
      expect(
        decide(firstSession: true, priority: 5, immediate: false),
        UpdateFlow.flexible,
      );
    });
  });
}
