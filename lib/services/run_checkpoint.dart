import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/level_run_result.dart';
import '../utils/logger.dart';

/// Safety net for a run that is backgrounded and never comes back (the OS
/// kills the process, or the pilot swipes the app away).
///
/// When the app leaves the foreground mid-run, the gameplay screen merges
/// what is safe to merge right away (high-score candidate and stage
/// progress: both monotonic, cleared levels counted once through the
/// screen's `_persistedClears`) and parks the run's aborted score here
/// instead of queueing it. The score is NOT queued at background time
/// because the backend counts every score row as a game played: a run that
/// resumes and later reaches game over would be counted twice.
///
/// - The pilot returns and keeps flying → [clear]; game over / quit submit
///   as usual.
/// - The process dies → the next launch's [recoverPending] queues the parked
///   score to the sync outbox exactly once.
///
/// Device-only (SharedPreferences): it is a pending write, not user state.
abstract final class RunCheckpoint {
  static const String _kPending = 'run_checkpoint_pending_score';

  /// Serialises stash / clear / recover so a quick background → resume
  /// can't land the stash after the clear.
  static Future<void> _queue = Future.value();

  static Future<T> _serial<T>(Future<T> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Level results that still need merging into stage progress. Uncleared
  /// results only raise monotonic bests (safe to re-apply); a cleared level
  /// bumps its clear count, so it merges once per run.
  static List<LevelRunResult> pendingResults(
    List<LevelRunResult> results,
    Set<int> persistedClears,
  ) =>
      results
          .where((lr) => !lr.cleared || !persistedClears.contains(lr.stageId))
          .toList();

  /// Parks (or replaces) the run's aborted score payload.
  static Future<void> stash({
    required String entityKey,
    required Map<String, dynamic> payload,
  }) =>
      _serial(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            _kPending,
            jsonEncode({'entityKey': entityKey, 'payload': payload}),
          );
        } catch (e) {
          AppLogger.error('RunCheckpoint.stash failed', e);
        }
      });

  /// Drops the parked score: the run resumed, or it was submitted another
  /// way (game over / quit).
  static Future<void> clear() => _serial(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_kPending);
        } catch (_) {}
      });

  /// Queues a score parked by a run that never came back. Returns true when
  /// one was queued. Call once at startup, before any run starts.
  static Future<bool> recoverPending(
    Future<void> Function(String entityKey, Map<String, dynamic> payload)
        enqueue,
  ) =>
      _serial(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString(_kPending);
          if (raw == null) return false;
          // Removed first: a payload that fails to decode or enqueue must
          // not retry forever (a lost aborted score beats a double count).
          await prefs.remove(_kPending);
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          final key = decoded['entityKey'] as String?;
          final payload = decoded['payload'];
          if (key == null || payload is! Map<String, dynamic>) return false;
          await enqueue(key, payload);
          return true;
        } catch (e) {
          AppLogger.error('RunCheckpoint.recoverPending failed', e);
          return false;
        }
      });
}
