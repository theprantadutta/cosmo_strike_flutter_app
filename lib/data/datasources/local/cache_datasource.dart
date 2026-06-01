import 'package:cosmo_strike_flutter_app/services/offline_cache_service.dart';

/// Data source for local caching operations
/// Wraps OfflineCacheService for use in repositories
class CacheDataSource {
  final OfflineCacheService _cacheService;

  CacheDataSource(this._cacheService);

  /// Get cached data with TTL validation
  /// Returns null if cache is expired or doesn't exist
  Future<T?> getCached<T>(String key, T Function(Object) decoder) async {
    return await _cacheService.getCached<T>(key, decoder);
  }

  /// Get cached data even if stale (for offline fallback)
  /// Returns expired data if fresh data unavailable
  Future<T?> getCachedFallback<T>(
    String key,
    T Function(Object) decoder,
  ) async {
    return await _cacheService.getCachedFallback<T>(key, decoder);
  }

  /// Store data with default or custom TTL
  Future<void> setCache<T>(
    String key,
    T data,
    Object Function(T) encoder, {
    Duration? customTtl,
  }) async {
    await _cacheService.setCache<T>(key, data, encoder, customTtl: customTtl);
  }

  /// Check if cache is fresh (not expired)
  Future<bool> isCacheFresh(String key) async {
    return await _cacheService.isCacheFresh(key);
  }

  /// Check if cached data exists (regardless of freshness)
  Future<bool> hasCachedData(String key) async {
    return await _cacheService.hasCachedData(key);
  }

  /// Get cache info (cached time, expires, remaining TTL)
  Future<Map<String, dynamic>?> getCacheInfo(String key) async {
    return await _cacheService.getCacheInfo(key);
  }

  /// Invalidate a single cache entry
  Future<void> invalidate(String key) async {
    await _cacheService.invalidateCache(key);
  }

  /// Invalidate cache entries matching a pattern
  Future<void> invalidatePattern(String pattern) async {
    await _cacheService.invalidateCachePattern(pattern);
  }

  /// Clear all cached data
  Future<void> clearAll() async {
    await _cacheService.clearAllCache();
  }

  /// Get cache statistics
  Future<Map<String, dynamic>> getStatistics() async {
    return await _cacheService.getCacheStatistics();
  }
}

/// Cache keys used throughout the app
class CacheKeys {
  CacheKeys._();

  // Leaderboards
  static String leaderboardGlobal(String gameMode, int page) =>
      'leaderboard_global_${gameMode}_$page';
  static String leaderboardWeekly(String gameMode, int page) =>
      'leaderboard_weekly_${gameMode}_$page';
  static String leaderboardDaily(String gameMode, int page) =>
      'leaderboard_daily_${gameMode}_$page';
  static String leaderboardFriends(String gameMode, int page) =>
      'leaderboard_friends_${gameMode}_$page';

  // Achievements
  static const String achievementsMetadata = 'achievements_metadata';
  static const String userAchievements = 'user_achievements';

  // Battle Pass
  static const String battlePassSeason = 'battle_pass_season';
  static const String battlePassLevels = 'battle_pass_levels';
  static const String battlePassProgress = 'battle_pass_progress';

  // User
  static String userProfile(String userId) => 'user_profile_$userId';
  static const String currentUserProfile = 'user_profile_me';
  static const String userStatistics = 'user_statistics';

  // Social
  static const String friendsList = 'friends_list';
  static const String friendRequests = 'friend_requests';

  // Tournaments
  static const String tournamentsActive = 'tournaments_active';
  static const String tournamentsUpcoming = 'tournaments_upcoming';
  static String tournamentDetails(String id) => 'tournament_details_$id';

  // Premium
  static const String premiumContent = 'premium_content';
  static const String shopItems = 'shop_items';

  // Scores
  static const String myScores = 'my_scores';
  static const String myScoreStats = 'my_score_stats';
}

/// Cache TTL configurations
class CacheTtl {
  CacheTtl._();

  // Tier 1 - Excellent candidates (static data)
  static const Duration achievementsMetadata = Duration(hours: 1);
  static const Duration battlePassSeason = Duration(minutes: 60);
  static const Duration battlePassLevels = Duration(hours: 1);
  static const Duration userProfilePublic = Duration(minutes: 60);

  // Tier 2 - Good candidates (medium volatility)
  static const Duration leaderboardGlobal = Duration(minutes: 15);
  static const Duration leaderboardWeekly = Duration(minutes: 5);
  static const Duration scoreStats = Duration(minutes: 5);
  static const Duration premiumContent = Duration(minutes: 60);
  static const Duration friendsList = Duration(minutes: 10);

  // Tier 3 - Short TTL (volatile)
  static const Duration leaderboardDaily = Duration(seconds: 60);
  static const Duration tournamentsActive = Duration(minutes: 5);
  static const Duration friendRequests = Duration(minutes: 2);

  // User data - very short for freshness
  static const Duration userProfileMe = Duration(minutes: 2);
  static const Duration userStatistics = Duration(minutes: 1);
}
