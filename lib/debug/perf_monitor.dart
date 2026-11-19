import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Frame-pacing logger for profile builds (see `DemoMode`). Every
/// [windowSeconds] it prints one `[PERF]` line to logcat:
///
/// `[PERF] tag=L3 fps=59.8 frames=299 build avg/p90/p99/max=… raster …
/// jank(>16.7ms)=2 (0.7%) worst=24.1ms`
///
/// Budget is fixed at 60 FPS (16.67 ms): the game targets 60 only. A frame
/// is janky when its build OR raster phase alone overruns that budget —
/// the engine pipelines them, so either one blowing it drops a frame.
/// `fps` is frames actually presented per wall second (≈60 when the game
/// keeps up on a 60 Hz display).
class PerfMonitor {
  PerfMonitor._();
  static final PerfMonitor instance = PerfMonitor._();

  static const int windowSeconds = 5;
  static const double budgetMs = 1000 / 60;

  /// Free-form context appended to each line (the game sets the level).
  String tag = '-';

  final List<double> _build = [];
  final List<double> _raster = [];
  final Stopwatch _clock = Stopwatch();
  bool _started = false;

  // Whole-session totals, printed with every window.
  int _totalFrames = 0;
  int _totalJank = 0;

  void start() {
    if (_started) return;
    _started = true;
    _clock.start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    debugPrint('[PERF] monitor on: budget ${budgetMs.toStringAsFixed(2)} ms '
        '(60 FPS), window ${windowSeconds}s');
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _build.add(t.buildDuration.inMicroseconds / 1000);
      _raster.add(t.rasterDuration.inMicroseconds / 1000);
    }
    final elapsed = _clock.elapsedMilliseconds;
    if (elapsed < windowSeconds * 1000) return;
    _report(elapsed / 1000);
    _clock
      ..reset()
      ..start();
  }

  void _report(double seconds) {
    final n = _build.length;
    if (n == 0) return;
    var jank = 0;
    var worst = 0.0;
    for (var i = 0; i < n; i++) {
      final f = _build[i] > _raster[i] ? _build[i] : _raster[i];
      if (f > budgetMs) jank++;
      if (f > worst) worst = f;
    }
    _totalFrames += n;
    _totalJank += jank;
    debugPrint('[PERF] tag=$tag fps=${(n / seconds).toStringAsFixed(1)} '
        'frames=$n build ${_stats(_build)} raster ${_stats(_raster)} '
        'jank=$jank (${(100 * jank / n).toStringAsFixed(1)}%) '
        'worst=${worst.toStringAsFixed(1)}ms '
        'session=$_totalJank/$_totalFrames '
        '(${(100 * _totalJank / _totalFrames).toStringAsFixed(2)}%)');
    _build.clear();
    _raster.clear();
  }

  static String _stats(List<double> v) {
    final s = [...v]..sort();
    double p(double q) => s[((s.length - 1) * q).round()];
    final avg = s.reduce((a, b) => a + b) / s.length;
    String f(double x) => x.toStringAsFixed(1);
    return '${f(avg)}/${f(p(.9))}/${f(p(.99))}/${f(s.last)}';
  }
}
