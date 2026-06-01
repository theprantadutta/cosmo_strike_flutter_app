import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';

class PerformanceMetrics {
  final double fps;
  final double frameTime;
  final int memoryUsage;
  final int renderTime;
  final double cpuUsage;
  final DateTime timestamp;

  PerformanceMetrics({
    required this.fps,
    required this.frameTime,
    required this.memoryUsage,
    required this.renderTime,
    required this.cpuUsage,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'PerformanceMetrics(fps: ${fps.toStringAsFixed(1)}, '
        'frameTime: ${frameTime.toStringAsFixed(2)}ms, '
        'memory: ${(memoryUsage / 1024 / 1024).toStringAsFixed(1)}MB, '
        'renderTime: ${renderTime}ms, '
        'cpuUsage: ${cpuUsage.toStringAsFixed(1)}%)';
  }
}

class FrameInfo {
  final Duration frameTime;
  final DateTime timestamp;
  final bool wasJanky;

  FrameInfo({
    required this.frameTime,
    required this.timestamp,
    required this.wasJanky,
  });
}

class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  static const int _maxSamples = 120; // 2 seconds at 60fps
  static const Duration _targetFrameTime = Duration(milliseconds: 16); // 60fps

  final Queue<FrameInfo> _frameHistory = Queue<FrameInfo>();
  final Queue<PerformanceMetrics> _performanceHistory =
      Queue<PerformanceMetrics>();

  Timer? _performanceTimer;
  bool _isMonitoring = false;
  int _frameCount = 0;
  int _jankyFrameCount = 0;

  // Performance thresholds
  static const double _lowFpsThreshold = 50.0;
  static const double _highFrameTimeThreshold = 20.0; // milliseconds
  static const int _highMemoryThreshold = 100 * 1024 * 1024; // 100MB

  // Callbacks for performance alerts
  Function(String)? onPerformanceAlert;
  Function(PerformanceMetrics)? onMetricsUpdate;

  bool get isMonitoring => _isMonitoring;
  List<FrameInfo> get frameHistory => _frameHistory.toList();
  List<PerformanceMetrics> get performanceHistory =>
      _performanceHistory.toList();

  void startMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _frameCount = 0;
    _jankyFrameCount = 0;

    // Monitor frame rendering
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);

    // Monitor overall performance metrics
    _performanceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _capturePerformanceMetrics();
    });

    if (kDebugMode) {
      print('Performance monitoring started');
    }
  }

  void stopMonitoring() {
    if (!_isMonitoring) return;

    _isMonitoring = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _performanceTimer?.cancel();
    _performanceTimer = null;

    if (kDebugMode) {
      print('Performance monitoring stopped');
      print('Final stats: ${_generateSummary()}');
    }
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_isMonitoring) return;

    final now = DateTime.now();

    for (final timing in timings) {
      final frameTime = timing.totalSpan;
      final wasJanky = frameTime > _targetFrameTime * 1.5; // 50% over target

      _frameHistory.add(
        FrameInfo(frameTime: frameTime, timestamp: now, wasJanky: wasJanky),
      );

      if (wasJanky) {
        _jankyFrameCount++;
      }
      _frameCount++;

      // Remove old samples
      while (_frameHistory.length > _maxSamples) {
        final removed = _frameHistory.removeFirst();
        if (removed.wasJanky) {
          _jankyFrameCount--;
        }
        _frameCount--;
      }
    }
  }

  void _capturePerformanceMetrics() {
    if (!_isMonitoring) return;

    final now = DateTime.now();
    final fps = _calculateCurrentFPS();
    final avgFrameTime = _calculateAverageFrameTime();
    final memoryUsage = _getMemoryUsage();
    final renderTime = _getAverageRenderTime();
    final cpuUsage = _estimateCPUUsage();

    final metrics = PerformanceMetrics(
      fps: fps,
      frameTime: avgFrameTime,
      memoryUsage: memoryUsage,
      renderTime: renderTime,
      cpuUsage: cpuUsage,
      timestamp: now,
    );

    _performanceHistory.add(metrics);

    // Remove old metrics (keep last 60 seconds)
    while (_performanceHistory.length > 60) {
      _performanceHistory.removeFirst();
    }

    // Check for performance issues
    _checkPerformanceAlerts(metrics);

    // Notify listeners
    onMetricsUpdate?.call(metrics);

    if (kDebugMode) {
      developer.log('Performance: $metrics', name: 'PerformanceMonitor');
    }
  }

  double _calculateCurrentFPS() {
    if (_frameHistory.isEmpty) return 60.0;

    final recentFrames = _frameHistory.where((frame) {
      return DateTime.now().difference(frame.timestamp).inSeconds < 1;
    }).toList();

    if (recentFrames.isEmpty) return 60.0;

    return recentFrames.length.toDouble();
  }

  double _calculateAverageFrameTime() {
    if (_frameHistory.isEmpty) return 16.67; // Target frame time

    final recentFrames = _frameHistory.where((frame) {
      return DateTime.now().difference(frame.timestamp).inSeconds < 1;
    }).toList();

    if (recentFrames.isEmpty) return 16.67;

    final totalTime = recentFrames.fold<int>(0, (sum, frame) {
      return sum + frame.frameTime.inMicroseconds;
    });

    return (totalTime / recentFrames.length) / 1000; // Convert to milliseconds
  }

  int _getMemoryUsage() {
    try {
      // This is a simplified approach
      // Memory usage estimation based on app state and rendering
      return 50 * 1024 * 1024; // Estimated baseline memory usage
    } catch (e) {
      return 0;
    }
  }

  int _getAverageRenderTime() {
    if (_frameHistory.isEmpty) return 8;

    final recentFrames = _frameHistory.where((frame) {
      return DateTime.now().difference(frame.timestamp).inSeconds < 1;
    }).toList();

    if (recentFrames.isEmpty) return 8;

    // Estimate render time as a portion of frame time
    final avgFrameTime = _calculateAverageFrameTime();
    return (avgFrameTime * 0.5)
        .round(); // Assume rendering takes ~50% of frame time
  }

  double _estimateCPUUsage() {
    // This is a simplified estimation based on frame performance
    final fps = _calculateCurrentFPS();
    final frameTime = _calculateAverageFrameTime();

    // Estimate CPU usage based on how much we're deviating from target
    final targetFPS = 60.0;
    final targetFrameTime = 16.67;

    final fpsRatio = fps / targetFPS;
    final frameTimeRatio = frameTime / targetFrameTime;

    // Higher frame times and lower FPS indicate higher CPU usage
    final estimatedUsage =
        ((2.0 - fpsRatio) + frameTimeRatio) * 25; // Scale to percentage

    return estimatedUsage.clamp(0.0, 100.0);
  }

  void _checkPerformanceAlerts(PerformanceMetrics metrics) {
    final alerts = <String>[];

    if (metrics.fps < _lowFpsThreshold) {
      alerts.add('Low FPS detected: ${metrics.fps.toStringAsFixed(1)}');
    }

    if (metrics.frameTime > _highFrameTimeThreshold) {
      alerts.add('High frame time: ${metrics.frameTime.toStringAsFixed(2)}ms');
    }

    if (metrics.memoryUsage > _highMemoryThreshold) {
      alerts.add(
        'High memory usage: ${(metrics.memoryUsage / 1024 / 1024).toStringAsFixed(1)}MB',
      );
    }

    final jankyPercent = (_jankyFrameCount / math.max(_frameCount, 1)) * 100;
    if (jankyPercent > 10.0) {
      alerts.add('High jank rate: ${jankyPercent.toStringAsFixed(1)}%');
    }

    for (final alert in alerts) {
      onPerformanceAlert?.call(alert);
      if (kDebugMode) {
        print('Performance Alert: $alert');
      }
    }
  }

  // Analysis methods

  double getAverageFPS({Duration? period}) {
    final cutoff = period != null
        ? DateTime.now().subtract(period)
        : DateTime.now().subtract(const Duration(seconds: 10));

    final relevantMetrics = _performanceHistory.where(
      (m) => m.timestamp.isAfter(cutoff),
    );

    if (relevantMetrics.isEmpty) return 60.0;

    return relevantMetrics.map((m) => m.fps).reduce((a, b) => a + b) /
        relevantMetrics.length;
  }

  double getAverageFrameTime({Duration? period}) {
    final cutoff = period != null
        ? DateTime.now().subtract(period)
        : DateTime.now().subtract(const Duration(seconds: 10));

    final relevantMetrics = _performanceHistory.where(
      (m) => m.timestamp.isAfter(cutoff),
    );

    if (relevantMetrics.isEmpty) return 16.67;

    return relevantMetrics.map((m) => m.frameTime).reduce((a, b) => a + b) /
        relevantMetrics.length;
  }

  double getJankyFramePercentage() {
    if (_frameCount == 0) return 0.0;
    return (_jankyFrameCount / _frameCount) * 100;
  }

  Map<String, dynamic> getCurrentStats() {
    return {
      'fps': _calculateCurrentFPS(),
      'avgFrameTime': _calculateAverageFrameTime(),
      'memoryUsage': _getMemoryUsage(),
      'jankyFramePercent': getJankyFramePercentage(),
      'totalFrames': _frameCount,
      'jankyFrames': _jankyFrameCount,
      'isMonitoring': _isMonitoring,
    };
  }

  String _generateSummary() {
    final stats = getCurrentStats();
    return 'Performance Summary:\n'
        '  Average FPS: ${stats['fps'].toStringAsFixed(1)}\n'
        '  Average Frame Time: ${stats['avgFrameTime'].toStringAsFixed(2)}ms\n'
        '  Memory Usage: ${(stats['memoryUsage'] / 1024 / 1024).toStringAsFixed(1)}MB\n'
        '  Janky Frames: ${stats['jankyFramePercent'].toStringAsFixed(1)}%\n'
        '  Total Frames: ${stats['totalFrames']}\n'
        '  Janky Frames Count: ${stats['jankyFrames']}';
  }

  // Performance optimization helpers

  bool shouldReduceEffects() {
    return getAverageFPS() < 45 || getJankyFramePercentage() > 15;
  }

  bool shouldDisableAnimations() {
    return getAverageFPS() < 30 || getJankyFramePercentage() > 25;
  }

  int getRecommendedParticleCount() {
    final fps = getAverageFPS();
    if (fps >= 55) return 100; // Full particle count
    if (fps >= 45) return 75; // Reduced particles
    if (fps >= 35) return 50; // Half particles
    if (fps >= 25) return 25; // Quarter particles
    return 10; // Minimal particles
  }

  double getRecommendedAnimationScale() {
    final fps = getAverageFPS();
    if (fps >= 55) return 1.0; // Full animations
    if (fps >= 45) return 0.8; // Slightly reduced
    if (fps >= 35) return 0.6; // Moderately reduced
    if (fps >= 25) return 0.4; // Heavily reduced
    return 0.2; // Minimal animations
  }

  // Debug helpers

  void printCurrentStats() {
    if (kDebugMode) {
      print(_generateSummary());
    }
  }

  void logPerformanceToConsole() {
    if (!kDebugMode) return;

    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isMonitoring) {
        timer.cancel();
        return;
      }
      printCurrentStats();
    });
  }

  // Export data for analysis
  Map<String, dynamic> exportData() {
    return {
      'frameHistory': _frameHistory
          .map(
            (frame) => {
              'frameTime': frame.frameTime.inMicroseconds,
              'timestamp': frame.timestamp.millisecondsSinceEpoch,
              'wasJanky': frame.wasJanky,
            },
          )
          .toList(),
      'performanceHistory': _performanceHistory
          .map(
            (metrics) => {
              'fps': metrics.fps,
              'frameTime': metrics.frameTime,
              'memoryUsage': metrics.memoryUsage,
              'renderTime': metrics.renderTime,
              'cpuUsage': metrics.cpuUsage,
              'timestamp': metrics.timestamp.millisecondsSinceEpoch,
            },
          )
          .toList(),
      'summary': getCurrentStats(),
    };
  }

  void reset() {
    _frameHistory.clear();
    _performanceHistory.clear();
    _frameCount = 0;
    _jankyFrameCount = 0;
  }

  void dispose() {
    stopMonitoring();
    reset();
  }
}

// Performance-aware widget builder
class PerformanceAwareBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool shouldOptimize) builder;
  final Duration checkInterval;

  const PerformanceAwareBuilder({
    super.key,
    required this.builder,
    this.checkInterval = const Duration(seconds: 2),
  });

  @override
  State<PerformanceAwareBuilder> createState() =>
      _PerformanceAwareBuilderState();
}

class _PerformanceAwareBuilderState extends State<PerformanceAwareBuilder> {
  late Timer _checkTimer;
  bool _shouldOptimize = false;
  final _monitor = PerformanceMonitor();

  @override
  void initState() {
    super.initState();
    _checkTimer = Timer.periodic(widget.checkInterval, _checkPerformance);
  }

  @override
  void dispose() {
    _checkTimer.cancel();
    super.dispose();
  }

  void _checkPerformance(Timer timer) {
    final newShouldOptimize = _monitor.shouldReduceEffects();
    if (newShouldOptimize != _shouldOptimize) {
      setState(() {
        _shouldOptimize = newShouldOptimize;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _shouldOptimize);
  }
}

// Extension for easy performance monitoring
extension PerformanceUtils on Widget {
  Widget withPerformanceMonitoring() {
    return Builder(
      builder: (context) {
        // Start monitoring when widget is built
        WidgetsBinding.instance.addPostFrameCallback((_) {
          PerformanceMonitor().startMonitoring();
        });
        return this;
      },
    );
  }
}
