/// Hands-free demo / profiling mode, switched on at BUILD time only:
///
/// ```
/// flutter run --profile --dart-define=COSMO_AUTOPILOT=true \
///   [--dart-define=COSMO_AUTOPILOT_LEVEL=7]
/// ```
///
/// With it on, the app skips the Home prompt queue, drops straight into a
/// run, an invincible autopilot flies it (dodging, chasing targets,
/// popping Overdrive and missiles), level clears auto-pick an upgrade, and
/// the run loops forever — so frame pacing can be watched across every
/// level, boss and set piece without touching the phone. `PerfMonitor`
/// logs frame stats to logcat (`[PERF]`) every few seconds.
///
/// Release builds never set the define, so all of this compiles out.
abstract final class DemoMode {
  static const bool enabled = bool.fromEnvironment('COSMO_AUTOPILOT');

  /// Campaign level the demo starts at (1-12).
  static const int startLevel =
      int.fromEnvironment('COSMO_AUTOPILOT_LEVEL', defaultValue: 1);

  /// Frame-stat logging: on with the autopilot, or alone via
  /// `--dart-define=COSMO_PERF_LOG=true` for hand-played profiling.
  static const bool perfLog =
      enabled || bool.fromEnvironment('COSMO_PERF_LOG');
}
