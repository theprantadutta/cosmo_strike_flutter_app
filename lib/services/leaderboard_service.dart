import 'dart:async';

import 'package:drift/drift.dart' as d;
import 'package:get_it/get_it.dart';
import 'package:cosmo_strike_flutter_app/data/daos/leaderboard_dao.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Drift-first leaderboard cache.
///
/// Architecture:
///   * Every read returns whatever the local cache currently holds —
///     fast, never blocks on network, deterministic offline.
///   * [refreshGlobal] / [refreshWeekly] / etc. fetch the matching
///     leaderboard endpoint and write through to the Drift cache via
///     an atomic [LeaderboardDao.replaceBoard]. The reactive streams
///     emit once for the swap; the screen re-renders.
///   * Per-board metadata (last refresh, total players, current user
///     rank) lives in `leaderboard_meta` so the UI can show an
///     "Updated X ago" chip without scanning the entries.
///
/// Public API is map-shaped (`List<Map<String, dynamic>>` with keys
/// `uid`, `username`, `displayName`, `photoURL`, `highScore`, …) so
/// the existing Riverpod providers + screen consume it unchanged.
class LeaderboardService {
  static final LeaderboardService _instance = LeaderboardService._internal();
  factory LeaderboardService() => _instance;
  LeaderboardService._internal();

  final ApiService _api = ApiService();

  LeaderboardDao get _dao => GetIt.I<AppDatabase>().leaderboardDao;

  // -------------- Public reads (cached) --------------

  Future<List<Map<String, dynamic>>> getGlobalLeaderboard({
    int limit = 50,
  }) =>
      _readCachedAsMaps(LeaderboardBoardType.global, limit: limit);

  Future<List<Map<String, dynamic>>> getWeeklyLeaderboard({
    int limit = 50,
  }) =>
      _readCachedAsMaps(LeaderboardBoardType.weekly, limit: limit);

  Future<List<Map<String, dynamic>>> getDailyLeaderboard({
    int limit = 50,
  }) =>
      _readCachedAsMaps(LeaderboardBoardType.daily, limit: limit);

  Future<List<Map<String, dynamic>>> getFriendsLeaderboard(
    List<String> friendIds, {
    int limit = 50,
  }) =>
      // friendIds is unused — backend computes friends from the JWT.
      // Argument preserved for compatibility with existing callers.
      _readCachedAsMaps(LeaderboardBoardType.friends, limit: limit);

  /// Walks the global cache to find the requesting user's rank. Used
  /// by the legacy leaderboard provider's user-rank card.
  Future<Map<String, dynamic>?> getUserRank(String userId) async {
    final entries = await _dao.getEntries(LeaderboardBoardType.global);
    for (final e in entries) {
      if (e.userId == userId) {
        return {
          'rank': e.rank,
          'userScore': e.score,
        };
      }
    }
    return null;
  }

  Future<bool> hasCachedData() async {
    final entries =
        await _dao.getEntries(LeaderboardBoardType.global);
    return entries.isNotEmpty;
  }

  Future<Map<String, dynamic>?> getCacheInfo(String leaderboardType) async {
    final meta = await _dao.getMeta(leaderboardType);
    if (meta == null) return null;
    return {
      'lastRefreshedAt': meta.lastRefreshedAt,
      'totalPlayers': meta.totalPlayers,
      'currentUserRank': meta.currentUserRank,
    };
  }

  Future<DateTime?> getLastRefreshedAt(String boardType) async {
    final meta = await _dao.getMeta(boardType);
    return meta?.lastRefreshedAt;
  }

  // -------------- Refresh paths --------------

  /// Fetch each board from the backend and write through to Drift.
  /// Failures are logged and swallowed; callers shouldn't await success
  /// — the cache holds the previous good data either way.
  Future<void> forceRefreshAll({int limit = 50}) async {
    await Future.wait([
      _refresh(LeaderboardBoardType.global, limit: limit),
      _refresh(LeaderboardBoardType.weekly, limit: limit),
    ]);
  }

  Future<void> refreshGlobal({int limit = 50}) =>
      _refresh(LeaderboardBoardType.global, limit: limit);

  Future<void> refreshWeekly({int limit = 50}) =>
      _refresh(LeaderboardBoardType.weekly, limit: limit);

  Future<void> refreshDaily({int limit = 50}) =>
      _refresh(LeaderboardBoardType.daily, limit: limit);

  /// Skips when the caller isn't authenticated (the friends endpoint
  /// is gated on auth and would 401 every time).
  Future<void> refreshFriends({int limit = 50}) async {
    if (!_api.isAuthenticated) return;
    await _refresh(LeaderboardBoardType.friends, limit: limit);
  }

  Future<void> clearCache() => _dao.clear();

  // -------------- Internals --------------

  Future<List<Map<String, dynamic>>> _readCachedAsMaps(
    String boardType, {
    required int limit,
  }) async {
    final entries = await _dao.getEntries(boardType);
    return entries.take(limit).map(_entryToMap).toList();
  }

  Future<void> _refresh(String boardType, {required int limit}) async {
    Map<String, dynamic>? body;
    try {
      switch (boardType) {
        case LeaderboardBoardType.global:
          body = await _api.getGlobalLeaderboardPage(pageSize: limit);
          break;
        case LeaderboardBoardType.weekly:
          body = await _api.getWeeklyLeaderboardPage(pageSize: limit);
          break;
        case LeaderboardBoardType.daily:
          body = await _api.getDailyLeaderboardPage(pageSize: limit);
          break;
        case LeaderboardBoardType.friends:
          body = await _api.getFriendsLeaderboardPage(pageSize: limit);
          break;
      }
    } catch (e) {
      AppLogger.error('LeaderboardService: refresh $boardType errored', e);
      return;
    }
    if (body == null) {
      AppLogger.network(
        'LeaderboardService: refresh $boardType returned null (offline?)',
      );
      return;
    }

    final rawEntries = body['entries'];
    if (rawEntries is! List) {
      AppLogger.warning(
        'LeaderboardService: refresh $boardType — no entries field',
      );
      return;
    }

    final companions = <LeaderboardEntriesCompanion>[];
    final now = DateTime.now();
    for (final raw in rawEntries) {
      if (raw is! Map<String, dynamic>) continue;
      companions.add(LeaderboardEntriesCompanion.insert(
        boardType: boardType,
        rank: raw['rank'] as int? ?? 0,
        userId: (raw['user_id'] ?? raw['userId'] ?? '').toString(),
        username: d.Value(raw['username'] as String?),
        displayName:
            d.Value((raw['display_name'] ?? raw['displayName']) as String?),
        photoUrl: d.Value((raw['photo_url'] ?? raw['photoUrl']) as String?),
        score: d.Value(raw['score'] as int? ?? 0),
        level: d.Value(raw['level'] as int? ?? 1),
        achievedAt:
            d.Value(_parseDate(raw['achieved_at'] ?? raw['achievedAt'])),
        totalGamesPlayed: d.Value(
          (raw['total_games_played'] ?? raw['totalGamesPlayed']) as int? ?? 0,
        ),
        cachedAt: d.Value(now),
      ));
    }

    final meta = LeaderboardMetaCompanion(
      lastRefreshedAt: d.Value(now),
      totalPlayers: d.Value(body['total_players'] as int? ?? 0),
      currentUserRank: d.Value(
        (body['current_user_rank'] ?? body['currentUserRank']) as int?,
      ),
    );

    await _dao.replaceBoard(
      boardType: boardType,
      entries: companions,
      meta: meta,
    );
  }

  /// Map a typed Drift row onto the legacy `Map<String, dynamic>` shape
  /// the Riverpod providers + leaderboard screen consume. Keys mirror
  /// the historical Firestore-era contract (`uid`, `highScore`, …) so
  /// every downstream reader keeps working untouched.
  Map<String, dynamic> _entryToMap(LeaderboardEntry e) => {
        'uid': e.userId,
        'username': e.username,
        'displayName': e.displayName,
        'photoURL': e.photoUrl,
        'highScore': e.score,
        'level': e.level,
        'rank': e.rank,
        'achievedAt': e.achievedAt?.toIso8601String(),
        'totalGamesPlayed': e.totalGamesPlayed,
      };

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
