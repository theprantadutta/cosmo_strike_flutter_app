import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database/app_database.dart';
import '../../utils/constants.dart' show GameMode;
import '../../utils/logger.dart';

/// One-time rewrite of persisted game-mode strings to the 3.2 identifiers
/// (`classic` → `sortie`, `perfectGame` → `knifeEdge`, …).
///
/// Reads are already tolerant (`GameMode.fromWire` accepts every legacy
/// spelling), so this is storage hygiene: it stops legacy ids lingering in
/// Drift and — more importantly — keeps them out of queued sync payloads
/// that would otherwise reach the backend after the upgrade.
///
/// Idempotent: guarded by a SharedPreferences flag, and every rewrite is a
/// no-op on already-migrated data, so a crash mid-way simply re-runs.
///
/// Covers:
/// - `SyncQueue.data` (pending / failed outbox payloads)
/// - `Replays.gameMode` + the `gameMode` inside `Replays.replayData`
/// - `DailyChallenges.requiredGameMode`
/// - `Statistics.modelJson` → `gamesPerMode` keys (counts are merged)
/// - `TournamentsCache.dataJson` → `gameMode` / `game_mode`
/// - SharedPreferences `selected_game_mode` (pre-v3 legacy key)
///
/// `GameSettings.gameModeIndex` is an enum INDEX and the enum order is
/// unchanged, so it needs no rewrite.
const String kLegacyModeMigrationFlag = 'rebrand_v32_modes_migrated';

Future<void> migrateLegacyModes(AppDatabase db) async {
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    AppLogger.warning('LegacyModeMigration: prefs unavailable, skipping: $e');
    return;
  }
  if (prefs.getBool(kLegacyModeMigrationFlag) ?? false) return;

  var rewritten = 0;
  try {
    rewritten += await _migrateSyncQueue(db);
    rewritten += await _migrateReplays(db);
    rewritten += await _migrateDailyChallenges(db);
    rewritten += await _migrateStatistics(db);
    rewritten += await _migrateTournamentsCache(db);
    rewritten += await _migratePrefs(prefs);
  } catch (e, st) {
    // Leave the flag unset so the next launch retries; reads stay tolerant
    // in the meantime.
    AppLogger.error('LegacyModeMigration failed', e, st);
    return;
  }

  await prefs.setBool(kLegacyModeMigrationFlag, true);
  AppLogger.info('LegacyModeMigration: done ($rewritten rows rewritten)');
}

/// JSON keys whose string value is a game-mode id.
const Set<String> _modeKeys = {
  'game_mode',
  'gameMode',
  'required_game_mode',
  'requiredGameMode',
  'favoriteMode',
  'favorite_mode',
};

/// JSON keys whose value is a map keyed by game-mode id.
const Set<String> _modeMapKeys = {'gamesPerMode', 'games_per_mode'};

/// Recursively rewrites mode values / mode-keyed maps. Returns the new
/// value and whether anything changed.
(Object?, bool) _rewrite(Object? node) {
  if (node is Map) {
    var changed = false;
    final out = <String, Object?>{};
    node.forEach((rawKey, value) {
      final key = rawKey.toString();
      if (_modeKeys.contains(key) && value is String) {
        final next = _normalizeModeString(value);
        if (next != value) changed = true;
        out[key] = next;
      } else if (_modeMapKeys.contains(key) && value is Map) {
        final merged = <String, Object?>{};
        value.forEach((k, v) {
          final nk = GameMode.normalizeWire(k.toString());
          if (nk != k.toString()) changed = true;
          final prev = merged[nk];
          merged[nk] = (prev is num && v is num) ? prev + v : v;
        });
        out[key] = merged;
      } else {
        final (nv, c) = _rewrite(value);
        if (c) changed = true;
        out[key] = nv;
      }
    });
    return (changed ? out : node, changed);
  }
  if (node is List) {
    var changed = false;
    final out = node.map((e) {
      final (nv, c) = _rewrite(e);
      if (c) changed = true;
      return nv;
    }).toList();
    return (changed ? out : node, changed);
  }
  return (node, false);
}

/// Only rewrite strings that really are mode ids; unknown values (e.g. a
/// `none` favourite mode) are left untouched.
String _normalizeModeString(String value) {
  final parsed = GameMode.tryFromWire(value);
  return parsed == null ? value : parsed.wireName;
}

/// Decodes [raw], rewrites it, and returns the re-encoded JSON or null when
/// nothing changed (or it isn't JSON).
String? _rewriteJson(String raw) {
  if (raw.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  final (next, changed) = _rewrite(decoded);
  return changed ? jsonEncode(next) : null;
}

Future<int> _migrateSyncQueue(AppDatabase db) async {
  var n = 0;
  // Completed rows (status 3) are history; only touch what may still push.
  final rows = await (db.select(db.syncQueue)
        ..where((t) => t.status.isNotIn(const [3])))
      .get();
  for (final row in rows) {
    final next = _rewriteJson(row.data);
    if (next == null) continue;
    await (db.update(db.syncQueue)..where((t) => t.id.equals(row.id)))
        .write(SyncQueueCompanion(data: Value(next)));
    n++;
  }
  return n;
}

Future<int> _migrateReplays(AppDatabase db) async {
  var n = 0;
  final rows = await db.select(db.replays).get();
  for (final row in rows) {
    final mode = _normalizeModeString(row.gameMode);
    final data = _rewriteJson(row.replayData);
    if (mode == row.gameMode && data == null) continue;
    await (db.update(db.replays)..where((t) => t.id.equals(row.id))).write(
      ReplaysCompanion(
        gameMode: Value(mode),
        replayData: data == null ? const Value.absent() : Value(data),
      ),
    );
    n++;
  }
  return n;
}

Future<int> _migrateDailyChallenges(AppDatabase db) async {
  var n = 0;
  final rows = await db.select(db.dailyChallenges).get();
  for (final row in rows) {
    final raw = row.requiredGameMode;
    if (raw == null) continue;
    final next = _normalizeModeString(raw);
    if (next == raw) continue;
    await (db.update(db.dailyChallenges)..where((t) => t.id.equals(row.id)))
        .write(DailyChallengesCompanion(requiredGameMode: Value(next)));
    n++;
  }
  return n;
}

Future<int> _migrateStatistics(AppDatabase db) async {
  var n = 0;
  final rows = await db.select(db.statistics).get();
  for (final row in rows) {
    final next = _rewriteJson(row.modelJson);
    if (next == null) continue;
    await (db.update(db.statistics)..where((t) => t.id.equals(row.id)))
        .write(StatisticsCompanion(modelJson: Value(next)));
    n++;
  }
  return n;
}

Future<int> _migrateTournamentsCache(AppDatabase db) async {
  var n = 0;
  final rows = await db.select(db.tournamentsCache).get();
  for (final row in rows) {
    final next = _rewriteJson(row.dataJson);
    if (next == null) continue;
    await (db.update(db.tournamentsCache)..where((t) => t.id.equals(row.id)))
        .write(TournamentsCacheCompanion(dataJson: Value(next)));
    n++;
  }
  return n;
}

/// Pre-v3 builds kept the selected mode's display name in prefs;
/// StorageService.getGameMode moves it into Drift on first read. Normalise
/// it here too so it never holds a legacy label.
Future<int> _migratePrefs(SharedPreferences prefs) async {
  const key = 'selected_game_mode';
  final raw = prefs.getString(key);
  if (raw == null) return 0;
  final parsed = GameMode.tryFromWire(raw);
  if (parsed == null || parsed.wireName == raw) return 0;
  await prefs.setString(key, parsed.wireName);
  return 1;
}
