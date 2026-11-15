import 'dart:async';
import 'dart:math' as math;

/// Creates the timer behind a scheduled retry. Injectable so tests can drive
/// the schedule without real time passing.
typedef AdRetryTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// Backoff scheduler for failed full-screen ad loads, one track per format.
///
/// Without it, a single `onAdFailedToLoad` (routine no-fill, a flaky network
/// at startup) left that slot empty until the next natural trigger — so the
/// revive / double-credits buttons often found no ad when the player asked.
///
/// Storm guards, all enforced here so callers can't get them wrong:
///  * at most one pending retry per format (a second [schedule] while one is
///    pending is ignored);
///  * attempts are capped ([maxAttempts], further limited by the length of
///    [delays]); an exhausted format stays quiet until [succeeded] or
///    [resetAll] (network back, consent granted, subscription lapsed);
///  * every delay is jittered so formats that failed together don't retry on
///    the same tick and collide again.
///
/// It only owns timing. Whether a load is allowed (ads on, consent, online,
/// nothing already in flight) is still decided by the load function itself
/// when the timer fires.
class AdLoadRetry {
  AdLoadRetry({
    List<Duration> delays = defaultDelays,
    int Function()? maxAttempts,
    AdRetryTimerFactory? timerFactory,
    double Function()? random,
  }) : _delays = List.unmodifiable(delays),
       _maxAttempts = maxAttempts,
       _timerFactory = timerFactory ?? Timer.new,
       _random = random ?? math.Random().nextDouble;

  /// Grows roughly ×4–5 per step. The long tail is deliberate: fill often
  /// comes back minutes later, and a retry costs nothing while the slot is
  /// empty anyway.
  static const List<Duration> defaultDelays = [
    Duration(seconds: 3),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 4),
    Duration(minutes: 12),
  ];

  /// Jitter band: each delay is scaled by a factor in [0.85, 1.25).
  static const double jitterMin = 0.85;
  static const double jitterSpan = 0.40;

  final List<Duration> _delays;
  final int Function()? _maxAttempts;
  final AdRetryTimerFactory _timerFactory;
  final double Function() _random;

  final Map<String, int> _attempts = {};
  final Map<String, Timer> _timers = {};

  /// Effective attempt cap: the remote cap (if any), never above the number
  /// of configured delays and never negative.
  int get attemptCap {
    final remote = _maxAttempts?.call() ?? _delays.length;
    return remote.clamp(0, _delays.length);
  }

  int attemptsFor(String format) => _attempts[format] ?? 0;

  bool isPending(String format) => _timers[format]?.isActive ?? false;

  bool isExhausted(String format) => attemptsFor(format) >= attemptCap;

  /// Schedule [load] for [format] after the next backoff delay. Returns the
  /// (jittered) delay used, or null when nothing was scheduled because a
  /// retry is already pending or the attempts are used up.
  Duration? schedule(String format, void Function() load) {
    if (isPending(format)) return null;
    final attempt = attemptsFor(format);
    if (attempt >= attemptCap) return null;
    _attempts[format] = attempt + 1;
    final delay = _delays[attempt] * (jitterMin + _random() * jitterSpan);
    _timers[format] = _timerFactory(delay, () {
      _timers.remove(format);
      load();
    });
    return delay;
  }

  /// A load for [format] filled: forget its failures and any pending retry.
  void succeeded(String format) {
    _attempts.remove(format);
    _timers.remove(format)?.cancel();
  }

  /// Stop every pending retry but keep the attempt counts (ads just went
  /// off — a subscription started, consent was withdrawn).
  void cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  /// Cancel everything and forget all failures: a transition from "cannot
  /// load" to "can" deserves a fresh set of attempts.
  void resetAll() {
    cancelAll();
    _attempts.clear();
  }
}
