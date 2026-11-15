import 'dart:async';

/// Pure, dependency-free building blocks of the startup safety net.
///
/// Nothing in here touches Firebase, plugins or widgets, so every piece is
/// unit-tested in `test/startup_guard_test.dart`. The Crashlytics glue lives in
/// `startup_reporter.dart`; the bootstrap that uses both is in `main.dart`.

/// Runs one async job at a time and remembers a success.
///
/// A `Future.timeout` abandons the WAIT, not the work: a bootstrap that blew
/// its budget keeps running in the background. If the recovery screen's
/// "Try again" simply started the bootstrap over, the two runs would race into
/// `configureDependencies` and get_it would throw "already registered", so the
/// retry could never succeed. Through [run], a caller instead:
///  * joins the run that is still in flight,
///  * reuses a run that already succeeded,
///  * starts a fresh run only after the previous one actually failed.
class SingleFlight<T> {
  Future<T>? _current;

  /// Whether a run is in flight or has succeeded.
  bool get hasRun => _current != null;

  Future<T> run(Future<T> Function() body) {
    final existing = _current;
    if (existing != null) return existing;
    late final Future<T> future;
    future = Future<T>.sync(body).catchError((Object e, StackTrace s) {
      // Only clear if nobody replaced it meanwhile.
      if (identical(_current, future)) _current = null;
      Error.throwWithStackTrace(e, s);
    });
    return _current = future;
  }
}

/// Bounds a NON-critical startup step: if [future] has not completed within
/// [timeout], logs through [onTimedOut] and resolves with [orElse] instead of
/// blocking the rest of startup. Errors from [future] still propagate — steps
/// keep their own try/catch for those.
///
/// The step itself keeps running; only the wait is dropped.
Future<T> withStepTimeout<T>(
  Future<T> future,
  Duration timeout, {
  required String label,
  required FutureOr<T> Function() orElse,
  void Function(String label, Duration timeout)? onTimedOut,
}) {
  return future.timeout(
    timeout,
    onTimeout: () {
      onTimedOut?.call(label, timeout);
      return orElse();
    },
  );
}

/// Records which bootstrap phase is running and how long each one took, so a
/// stuck or failed startup reports WHERE it stopped (as Crashlytics custom
/// keys), not just that it did.
class StartupPhaseTracker {
  StartupPhaseTracker({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _startedAt = _clock();
  }

  final DateTime Function() _clock;
  late final DateTime _startedAt;

  String? _phase;
  DateTime? _phaseStartedAt;
  final Map<String, int> _durationsMs = {};

  /// The phase currently running (or the last one begun), or null before any.
  String? get currentPhase => _phase;

  /// Completed phases → milliseconds, in completion order.
  Map<String, int> get durationsMs => Map.unmodifiable(_durationsMs);

  /// Milliseconds since the tracker was created.
  int get elapsedMs => _clock().difference(_startedAt).inMilliseconds;

  /// Ends the running phase (if any) and starts [name].
  void begin(String name) {
    _closeCurrent();
    _phase = name;
    _phaseStartedAt = _clock();
  }

  /// Ends the running phase. [currentPhase] keeps its name so a later failure
  /// report still says what ran last.
  void end() => _closeCurrent();

  void _closeCurrent() {
    final phase = _phase;
    final started = _phaseStartedAt;
    if (phase == null || started == null) return;
    _durationsMs[phase] = _clock().difference(started).inMilliseconds;
    _phaseStartedAt = null;
  }
}

/// One error captured during startup.
class BufferedStartupError {
  const BufferedStartupError(
    this.error,
    this.stack, {
    required this.reason,
    required this.fatal,
  });

  final Object error;
  final StackTrace? stack;
  final String reason;
  final bool fatal;
}

/// Holds errors raised before the crash reporter exists, then hands them over.
///
/// Crashlytics needs Firebase, and Firebase is initialized after `.env` — so a
/// failure in dotenv loading, in `Firebase.initializeApp` itself, or any
/// framework error in that window used to be logged locally and lost. Errors
/// go into this buffer until [attach] is called with the real sink; from then
/// on they are forwarded straight through.
///
/// Bounded at [capacity]: a startup error loop must not grow memory without
/// limit. The oldest entries are dropped first and counted in [dropped].
class EarlyErrorBuffer {
  EarlyErrorBuffer({this.capacity = 20}) : assert(capacity > 0);

  final int capacity;
  final List<BufferedStartupError> _pending = [];
  void Function(BufferedStartupError)? _sink;
  int _dropped = 0;

  /// Entries discarded because the buffer was full.
  int get dropped => _dropped;

  /// Entries waiting for a sink.
  List<BufferedStartupError> get pending => List.unmodifiable(_pending);

  bool get isAttached => _sink != null;

  void add(BufferedStartupError entry) {
    final sink = _sink;
    if (sink != null) {
      sink(entry);
      return;
    }
    if (_pending.length >= capacity) {
      _pending.removeAt(0);
      _dropped++;
    }
    _pending.add(entry);
  }

  /// Sets the sink and flushes everything buffered so far, oldest first.
  /// A sink that throws for one entry does not stop the rest.
  void attach(void Function(BufferedStartupError) sink) {
    _sink = sink;
    final drained = List.of(_pending);
    _pending.clear();
    for (final entry in drained) {
      try {
        sink(entry);
      } catch (_) {}
    }
  }
}
