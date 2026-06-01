import 'package:flutter/foundation.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/data/daos/sync_dao.dart';
import '../utils/logger.dart';

/// Cache entry with metadata for TTL management
class CacheEntry<T> {
  final T data;
  final DateTime cachedAt;
  final Duration ttl;

  CacheEntry({required this.data, required this.cachedAt, required this.ttl});

  bool get isExpired => DateTime.now().isAfter(cachedAt.add(ttl));

  Duration get remainingTtl {
    final expiresAt = cachedAt.add(ttl);
    final remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

/// Centralized cache management service with TTL-based freshness
/// Now backed by Drift database for persistence
class OfflineCacheService extends ChangeNotifier {
  static final OfflineCacheService _instance = OfflineCacheService._internal();
  factory OfflineCacheService() => _instance;
  OfflineCacheService._internal();

  SyncDao? _syncDao;

  /// Cache configurations with TTL for each data type
  static const Map<String, Duration> cacheConfigs = {
    // Leaderboards - shorter TTL as they change frequently
    'leaderboard_global': Duration(minutes: 5),
    'leaderboard_weekly': Duration(minutes: 5),
    'leaderboard_daily': Duration(minutes: 2),
    'leaderboard_friends': Duration(minutes: 3),

    // Tournaments - moderate TTL
    'tournaments_active': Duration(minutes: 10),
    'tournaments_upcoming': Duration(minutes: 15),
    'tournament_details': Duration(minutes: 5),

    // Social - moderate TTL
    'friends_list': Duration(minutes: 5),
    'friend_requests': Duration(minutes: 3),

    // Static/semi-static data - longer TTL
    'achievements_metadata': Duration(hours: 24),
    'user_achievements': Duration(minutes: 1),
    'battle_pass_progress': Duration(minutes: 5),
    'shop_items': Duration(hours: 1),

    // User data - short TTL for freshness
    'user_profile': Duration(minutes: 2),
    'user_statistics': Duration(minutes: 1),
  };

  /// Initialize with database
  Future<void> initializeWithDatabase(AppDatabase database) async {
    _syncDao = database.syncDao;
    await initialize();
  }

  /// Initialize the cache service
  Future<void> initialize() async {
    // Clean expired cache entries on startup
    await _cleanExpiredCache();

    if (kDebugMode) {
      print('OfflineCacheService initialized with Drift');
    }
  }

  /// Get cached data if available and not expired
  Future<T?> getCached<T>(String key, T Function(Object) decoder) async {
    if (_syncDao == null) return null;
    return await _syncDao!.getCached<T>(key, decoder);
  }

  /// Get cached data even if expired (for offline fallback)
  Future<T?> getCachedFallback<T>(
    String key,
    T Function(Object) decoder,
  ) async {
    if (_syncDao == null) return null;
    return await _syncDao!.getCachedFallback<T>(key, decoder);
  }

  /// Store data in cache with TTL
  Future<void> setCache<T>(
    String key,
    T data,
    Object Function(T) encoder, {
    Duration? customTtl,
  }) async {
    if (_syncDao == null) return;

    final ttl = customTtl ?? cacheConfigs[key] ?? const Duration(minutes: 5);
    await _syncDao!.setCache<T>(key, data, encoder, ttl: ttl);

    if (kDebugMode) {
      print('Cached data for key: $key (TTL: ${ttl.inMinutes}min)');
    }
  }

  /// Check if cache is fresh (not expired)
  Future<bool> isCacheFresh(String key) async {
    if (_syncDao == null) return false;
    return await _syncDao!.isCacheFresh(key);
  }

  /// Check if any cached data exists (regardless of freshness)
  Future<bool> hasCachedData(String key) async {
    if (_syncDao == null) return false;
    return await _syncDao!.hasCachedData(key);
  }

  /// Get cache metadata (for debugging/status display)
  Future<Map<String, dynamic>?> getCacheInfo(String key) async {
    if (_syncDao == null) return null;
    return await _syncDao!.getCacheInfo(key);
  }

  /// Invalidate specific cache entry
  Future<void> invalidateCache(String key) async {
    if (_syncDao == null) return;
    await _syncDao!.invalidateCache(key);

    if (kDebugMode) {
      print('Invalidated cache for key: $key');
    }
  }

  /// Invalidate all cache entries matching a pattern
  Future<void> invalidateCachePattern(String pattern) async {
    if (_syncDao == null) return;
    await _syncDao!.invalidateCachePattern(pattern);

    if (kDebugMode) {
      print('Invalidated cache entries matching: $pattern');
    }
  }

  /// Clear all cached data
  Future<void> clearAllCache() async {
    if (_syncDao == null) return;
    await _syncDao!.clearAllCache();

    if (kDebugMode) {
      print('Cleared all cache');
    }

    notifyListeners();
  }

  /// Clean expired cache entries
  Future<void> _cleanExpiredCache() async {
    if (_syncDao == null) return;

    final cleanedCount = await _syncDao!.cleanExpiredCache();

    if (cleanedCount > 0) {
      AppLogger.storage('Cleaned $cleanedCount expired cache entries');
    }
  }

  /// Get statistics about cache usage
  Future<Map<String, dynamic>> getCacheStatistics() async {
    if (_syncDao == null) {
      return {
        'totalEntries': 0,
        'freshEntries': 0,
        'expiredEntries': 0,
        'totalSizeBytes': 0,
        'totalSizeKB': '0.00',
      };
    }
    return await _syncDao!.getCacheStatistics();
  }
}
