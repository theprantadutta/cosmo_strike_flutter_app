import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';

part 'sync_dao.g.dart';

@DriftAccessor(tables: [SyncQueue, CacheStore, UserProfile])
class SyncDao extends DatabaseAccessor<AppDatabase> with _$SyncDaoMixin {
  SyncDao(super.db);

  // ==================== Sync Queue ====================

  /// Watch pending sync items
  Stream<List<SyncQueueData>> watchPendingSyncItems() =>
      (select(syncQueue)
            ..where((t) =>
                t.status.equals(0) | t.status.equals(2)) // pending or failed
            ..orderBy([(t) => OrderingTerm.asc(t.priority)]))
          .watch();

  /// Get pending sync items. [limit] caps the number of rows returned
  /// per call so a long offline session (thousands of outbox rows)
  /// doesn't load everything into memory or produce a single batch
  /// that times out the 15s HTTP window. The SyncEngine's debounce +
  /// periodic timer will drain the remainder on subsequent ticks.
  Future<List<SyncQueueData>> getPendingSyncItems({int limit = 500}) =>
      (select(syncQueue)
            ..where((t) => t.status.equals(0) | t.status.equals(2))
            ..orderBy([(t) => OrderingTerm.asc(t.priority)])
            ..limit(limit))
          .get();

  /// Get all sync queue items
  Future<List<SyncQueueData>> getAllSyncQueueItems() =>
      (select(syncQueue)..orderBy([(t) => OrderingTerm.asc(t.priority)])).get();

  /// Add item to sync queue
  Future<void> addToSyncQueue({
    required String id,
    required String dataType,
    required Map<String, dynamic> data,
    int priority = 2,
  }) async {
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        id: id,
        dataType: dataType,
        data: json.encode(data),
        priority: Value(priority),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  /// Update sync item status
  Future<void> updateSyncItemStatus(String id, int status, {String? error}) async {
    await (update(syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(
        status: Value(status),
        lastError: Value(error),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Increment retry count
  Future<void> incrementRetryCount(String id) async {
    final item = await (select(syncQueue)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (item == null) return;

    await (update(syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(
        retryCount: Value(item.retryCount + 1),
        lastAttemptAt: Value(DateTime.now()),
      ),
    );
  }

  /// Remove completed items
  Future<void> removeCompletedItems() async {
    await (delete(syncQueue)..where((t) => t.status.equals(3))).go();
  }

  /// Remove item by ID
  Future<void> removeSyncItem(String id) async {
    await (delete(syncQueue)..where((t) => t.id.equals(id))).go();
  }

  /// Clear all sync queue
  Future<void> clearSyncQueue() async {
    await delete(syncQueue).go();
  }

  /// Get sync queue count. Uses a COUNT(*) so the result is accurate
  /// regardless of the [getPendingSyncItems] page-limit cap.
  Future<int> getPendingSyncCount() async {
    final countExp = syncQueue.id.count();
    final row = await (selectOnly(syncQueue)
          ..addColumns([countExp])
          ..where(syncQueue.status.equals(0) | syncQueue.status.equals(2)))
        .getSingle();
    return row.read(countExp) ?? 0;
  }

  /// Get failed sync count
  Future<int> getFailedSyncCount() async {
    final items =
        await (select(syncQueue)..where((t) => t.status.equals(2))).get();
    return items.length;
  }

  /// Get sync queue as list of maps (for compatibility)
  Future<List<Map<String, dynamic>>> getSyncQueueAsMaps() async {
    final items = await getAllSyncQueueItems();
    return items
        .map((item) => {
              'id': item.id,
              'dataType': item.dataType,
              'data': json.decode(item.data),
              'priority': item.priority,
              'status': item.status,
              'retryCount': item.retryCount,
              'lastError': item.lastError,
              'queuedAt': item.queuedAt.toIso8601String(),
              'lastAttemptAt': item.lastAttemptAt?.toIso8601String(),
            })
        .toList();
  }

  /// Save sync queue from maps (for compatibility)
  Future<void> saveSyncQueueFromMaps(List<Map<String, dynamic>> queue) async {
    await transaction(() async {
      await delete(syncQueue).go();
      for (final item in queue) {
        await into(syncQueue).insert(SyncQueueCompanion.insert(
          id: item['id'],
          dataType: item['dataType'],
          data: json.encode(item['data']),
          priority: Value(item['priority'] ?? 2),
          status: Value(item['status'] ?? 0),
          retryCount: Value(item['retryCount'] ?? 0),
          lastError: Value(item['lastError']),
        ));
      }
    });
  }

  // ==================== Cache Store ====================

  /// Get cached data by key
  Future<T?> getCached<T>(String key, T Function(Object) decoder) async {
    final entry = await (select(cacheStore)..where((t) => t.key.equals(key)))
        .getSingleOrNull();

    if (entry == null) return null;

    // Check if expired
    if (DateTime.now().isAfter(entry.expiresAt)) {
      return null;
    }

    try {
      final data = json.decode(entry.data);
      return decoder(data);
    } catch (e) {
      return null;
    }
  }

  /// Get cached data even if expired (fallback)
  Future<T?> getCachedFallback<T>(String key, T Function(Object) decoder) async {
    final entry = await (select(cacheStore)..where((t) => t.key.equals(key)))
        .getSingleOrNull();

    if (entry == null) return null;

    try {
      final data = json.decode(entry.data);
      return decoder(data);
    } catch (e) {
      return null;
    }
  }

  /// Set cache data
  Future<void> setCache<T>(
    String key,
    T data,
    Object Function(T) encoder, {
    Duration? ttl,
  }) async {
    final ttlDuration = ttl ?? const Duration(minutes: 5);
    final now = DateTime.now();
    final expiresAt = now.add(ttlDuration);

    await into(cacheStore).insertOnConflictUpdate(
      CacheStoreCompanion.insert(
        key: key,
        data: json.encode(encoder(data)),
        ttlMillis: ttlDuration.inMilliseconds,
        expiresAt: expiresAt,
      ),
    );
  }

  /// Check if cache is fresh
  Future<bool> isCacheFresh(String key) async {
    final entry = await (select(cacheStore)..where((t) => t.key.equals(key)))
        .getSingleOrNull();

    if (entry == null) return false;
    return DateTime.now().isBefore(entry.expiresAt);
  }

  /// Check if cached data exists
  Future<bool> hasCachedData(String key) async {
    final entry = await (select(cacheStore)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return entry != null;
  }

  /// Get cache info
  Future<Map<String, dynamic>?> getCacheInfo(String key) async {
    final entry = await (select(cacheStore)..where((t) => t.key.equals(key)))
        .getSingleOrNull();

    if (entry == null) return null;

    final now = DateTime.now();
    final isExpired = now.isAfter(entry.expiresAt);

    return {
      'cachedAt': entry.cachedAt,
      'ttl': Duration(milliseconds: entry.ttlMillis),
      'expiresAt': entry.expiresAt,
      'isExpired': isExpired,
      'remainingSeconds':
          isExpired ? 0 : entry.expiresAt.difference(now).inSeconds,
    };
  }

  /// Invalidate cache entry
  Future<void> invalidateCache(String key) async {
    await (delete(cacheStore)..where((t) => t.key.equals(key))).go();
  }

  /// Invalidate cache by pattern
  Future<void> invalidateCachePattern(String pattern) async {
    await (delete(cacheStore)..where((t) => t.key.like('%$pattern%'))).go();
  }

  /// Clear all cache
  Future<void> clearAllCache() async {
    await delete(cacheStore).go();
  }

  /// Clean expired cache entries
  Future<int> cleanExpiredCache() async {
    final now = DateTime.now();
    // Add grace period of 24 hours for stale data that might be useful as fallback
    final gracePeriod = now.subtract(const Duration(hours: 24));

    return (delete(cacheStore)
          ..where((t) => t.expiresAt.isSmallerThanValue(gracePeriod)))
        .go();
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStatistics() async {
    final all = await select(cacheStore).get();
    final now = DateTime.now();

    int freshCount = 0;
    int expiredCount = 0;
    int totalSize = 0;

    for (final entry in all) {
      totalSize += entry.data.length;
      if (now.isBefore(entry.expiresAt)) {
        freshCount++;
      } else {
        expiredCount++;
      }
    }

    return {
      'totalEntries': all.length,
      'freshEntries': freshCount,
      'expiredEntries': expiredCount,
      'totalSizeBytes': totalSize,
      'totalSizeKB': (totalSize / 1024).toStringAsFixed(2),
    };
  }

  // ==================== User Profile ====================

  /// Watch user profile
  Stream<UserProfileData?> watchUserProfile() =>
      (select(userProfile)..limit(1)).watchSingleOrNull();

  /// Get user profile
  Future<UserProfileData?> getUserProfile() =>
      (select(userProfile)..limit(1)).getSingleOrNull();

  /// Save user profile
  Future<void> saveUserProfile(UserProfileCompanion profile) async {
    await into(userProfile).insertOnConflictUpdate(profile);
  }

  /// Update last login
  Future<void> updateLastLogin(String id) async {
    await (update(userProfile)..where((t) => t.id.equals(id))).write(
      UserProfileCompanion(lastLoginAt: Value(DateTime.now())),
    );
  }

  /// Update last synced
  Future<void> updateLastSynced(String id) async {
    await (update(userProfile)..where((t) => t.id.equals(id))).write(
      UserProfileCompanion(lastSyncedAt: Value(DateTime.now())),
    );
  }

  /// Clear user profile
  Future<void> clearUserProfile() async {
    await delete(userProfile).go();
  }
}
