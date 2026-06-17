import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// Outcome of a `/sync/*` POST. The SyncEngine uses this to route
/// outbox rows correctly: `success` evicts them, `transient` leaves
/// them pending without bumping retry, `permanent` bumps retry and
/// eventually marks the rows failed.
enum SyncOutcomeKind { success, transient, permanent }

class SyncOutcome {
  final SyncOutcomeKind kind;
  final Map<String, dynamic>? body;
  final int? statusCode;

  const SyncOutcome._(this.kind, this.body, this.statusCode);

  factory SyncOutcome.success([Map<String, dynamic>? body]) =>
      SyncOutcome._(SyncOutcomeKind.success, body, null);
  factory SyncOutcome.transient({int? statusCode}) =>
      SyncOutcome._(SyncOutcomeKind.transient, null, statusCode);
  factory SyncOutcome.permanent({int? statusCode}) =>
      SyncOutcome._(SyncOutcomeKind.permanent, null, statusCode);

  bool get isSuccess => kind == SyncOutcomeKind.success;
}

/// HTTP gateway to the backend. After the offline-first refactor this
/// is a narrow surface: only auth (Firebase ↔ JWT exchange, profile,
/// username) and purchase/premium (IAP receipt verification, premium
/// content, equipped cosmetics). Everything else — leaderboards,
/// tournaments, social, scores, achievements, daily challenges, weekly
/// quests, daily bonus, multiplayer, power-ups, battle pass — has been
/// removed from the network surface and now lives in Drift.
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static const String _tokenKey = 'jwt_access_token';
  static const String _userIdKey = 'backend_user_id';

  String? _accessToken;
  String? _userId;

  VoidCallback? onUnauthorized;

  static const String _prodFallbackUrl = 'https://cosmostrike.pranta.dev';

  static String get baseUrl {
    final String backendUrl;
    if (kDebugMode) {
      if (dotenv.env['DEV_API_BACKEND_URL'] == null) {
        throw Exception('DEV_API_BACKEND_URL not set in .env');
      }
      backendUrl = dotenv.env['DEV_API_BACKEND_URL']!;
    } else {
      backendUrl = dotenv.env['PROD_API_BACKEND_URL'] ?? _prodFallbackUrl;
    }
    return '$backendUrl/api/v1';
  }

  static const Duration _timeout = Duration(seconds: 15);

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_tokenKey);
      _userId = prefs.getString(_userIdKey);
      if (_accessToken != null) {
        if (isTokenExpiredOrExpiring) {
          AppLogger.network('Stored JWT is expired — clearing on init');
          await clearToken();
        } else {
          AppLogger.network('Loaded stored JWT token');
        }
      }
    } catch (e) {
      AppLogger.error('Error loading stored token', e);
    }
  }

  /// True when a usable JWT is in memory. Strict: also requires the
  /// JWT to not be expired/expiring, so callers don't fire requests
  /// that are about to eat a 401.
  bool get isAuthenticated =>
      _accessToken != null && !isTokenExpiredOrExpiring;

  String? get currentUserId => _userId;

  bool get isTokenExpiredOrExpiring {
    if (_accessToken == null) return true;
    try {
      final parts = _accessToken!.split('.');
      if (parts.length != 3) return true;

      String payload = parts[1];
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final claims = jsonDecode(decoded) as Map<String, dynamic>;

      final exp = claims['exp'] as int?;
      if (exp == null) return true;

      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(
        expiry.subtract(const Duration(minutes: 5)),
      );
    } catch (e) {
      return true;
    }
  }

  Future<void> _storeToken(String token, String userId) async {
    _accessToken = token;
    _userId = userId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userIdKey, userId);
    } catch (e) {
      AppLogger.error('Error storing token', e);
    }
  }

  Future<void> clearToken() async {
    _accessToken = null;
    _userId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userIdKey);
    } catch (e) {
      AppLogger.error('Error clearing token', e);
    }
  }

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
  };

  Map<String, dynamic>? _handleResponse(http.Response response) {
    if (response.statusCode == 401) {
      AppLogger.error('Unauthorized - token may be expired');
      clearToken();
      onUnauthorized?.call();
      return null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return {'data': decoded};
    }

    AppLogger.error(
      'API error: ${response.statusCode} from ${response.request?.url}',
      response.body,
    );
    return null;
  }

  // ==================== Authentication ====================

  Future<Map<String, dynamic>?> authenticateWithFirebase(
    String firebaseIdToken,
  ) async {
    try {
      AppLogger.network('Authenticating with backend using Firebase token');

      // Send the device's current UTC offset at signup so brand-new
      // accounts get a real local-time anchor immediately, without
      // depending on the FCM-token-register path (which never runs for
      // users who deny notification permission). Backend backfills
      // existing users with NULL offsets too — see
      // AuthenticateWithFirebaseCommandHandler.
      final tzOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;

      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/firebase'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'firebase_token': firebaseIdToken,
              'time_zone_offset_minutes': tzOffsetMinutes,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'] as String?;
        final userId = data['user_id'] as String?;

        if (token != null && userId != null) {
          await _storeToken(token, userId);
          AppLogger.success('Backend authentication successful');
          return data;
        }
      }

      AppLogger.error(
        'Backend authentication failed: ${response.statusCode}',
        response.body,
      );
      return null;
    } catch (e) {
      AppLogger.error('Error authenticating with backend', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/auth/me'), headers: _authHeaders)
          .timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error getting current user', e);
      return null;
    }
  }

  Future<bool> logout() async {
    try {
      await http
          .post(Uri.parse('$baseUrl/auth/logout'), headers: _authHeaders)
          .timeout(_timeout);

      await clearToken();
      return true;
    } catch (e) {
      AppLogger.error('Error logging out', e);
      await clearToken();
      return false;
    }
  }

  // ==================== Users ====================

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/users/$userId'), headers: _authHeaders)
          .timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error getting user profile', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> updateProfile(Map<String, dynamic> data) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/users/me'),
            headers: _authHeaders,
            body: jsonEncode(data),
          )
          .timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error updating profile', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkUsername(String username) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/users/username/check'),
            headers: _authHeaders,
            body: jsonEncode({'username': username}),
          )
          .timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error checking username', e);
      return null;
    }
  }

  Future<List<String>?> suggestUsernames(
    String desiredUsername, {
    int count = 5,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/users/username/suggest'),
            headers: _authHeaders,
            body: jsonEncode({
              'desired_username': desiredUsername,
              'count': count,
            }),
          )
          .timeout(_timeout);

      final result = _handleResponse(response);
      if (result != null && result['suggestions'] != null) {
        return List<String>.from(result['suggestions']);
      }
      return null;
    } catch (e) {
      AppLogger.error('Error suggesting usernames', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> setUsername(String username) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/users/username'),
            headers: _authHeaders,
            body: jsonEncode({'username': username}),
          )
          .timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error setting username', e);
      return null;
    }
  }

  // ==================== Purchases ====================

  Future<Map<String, dynamic>?> verifyPurchase({
    required String platform,
    required String receiptData,
    required String productId,
    required String transactionId,
    String? purchaseToken,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/purchases/verify'),
            headers: _authHeaders,
            body: jsonEncode({
              'purchase_data': {
                'product_id': productId,
                'transaction_id': transactionId,
                'receipt_data': receiptData,
                'purchase_token': purchaseToken,
              },
              'platform': platform,
            }),
          )
          .timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error verifying purchase', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> batchVerifyPurchases(
    List<Map<String, dynamic>> purchases,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/purchases/verify-batch'),
            headers: _authHeaders,
            body: jsonEncode({'purchases': purchases}),
          )
          .timeout(const Duration(seconds: 30));

      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error batch verifying purchases', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getPremiumContent() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/purchases/premium-content'),
            headers: _authHeaders,
          )
          .timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error getting premium content', e);
      return null;
    }
  }

  /// Persist the user's equipped cosmetic IDs so they survive reinstall
  /// and device-switch. Backend uses JsonNamingPolicy.SnakeCaseLower —
  /// keys must be snake_case or they bind to null silently.
  Future<Map<String, dynamic>?> setEquippedCosmetics({
    String? skinId,
    String? trailId,
    String? themeId,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/purchases/equipped-cosmetics'),
            headers: _authHeaders,
            body: jsonEncode({
              'skin_id': ?skinId,
              'trail_id': ?trailId,
              'theme_id': ?themeId,
            }),
          )
          .timeout(_timeout);

      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error setting equipped cosmetics', e);
      return null;
    }
  }

  // ==================== Sync ====================
  //
  // These endpoints back the SyncEngine's outbox drain. The handlers
  // are batch-aware on the backend side — singletons (settings,
  // statistics, coin_balance, premium_status) take the payload
  // directly; lists (achievements, coin_transactions, unlocked_items,
  // battle_pass, daily_challenge_claims) wrap the array in
  // `{"items": [...]}` to match `SyncBatchRequest<T>`.

  Future<SyncOutcome> syncSettings(Map<String, dynamic> payload) =>
      _postSync('settings', payload);

  Future<SyncOutcome> syncStatistics(Map<String, dynamic> payload) =>
      _postSync('statistics', payload);

  Future<SyncOutcome> syncCoinBalance(Map<String, dynamic> payload) =>
      _postSync('coins/balance', payload);

  Future<SyncOutcome> syncPremiumStatus(Map<String, dynamic> payload) =>
      _postSync('premium-status', payload);

  Future<SyncOutcome> syncPlayerProgress(Map<String, dynamic> payload) =>
      _postSync('player-progress', payload);

  Future<SyncOutcome> syncAchievements(List<Map<String, dynamic>> items) =>
      _postSync('achievements', {'items': items});

  Future<SyncOutcome> syncCoinTransactions(
    List<Map<String, dynamic>> items,
  ) =>
      _postSync('coins/transactions', {'items': items});

  Future<SyncOutcome> syncUnlockedItems(List<Map<String, dynamic>> items) =>
      _postSync('unlocked-items', {'items': items});

  Future<SyncOutcome> syncBattlePass(List<Map<String, dynamic>> items) =>
      _postSync('battle-pass', {'items': items});

  /// Fetch the active battle-pass season catalog (tiers + rewards + dates).
  /// Server-driven and `[AllowAnonymous]`; the client caches the result in
  /// Drift and renders/grants from it (offline-first). Returns the season as a
  /// snake_case map that `BattlePassSeason.fromJson` parses, or null when the
  /// request fails or there's no active season.
  Future<Map<String, dynamic>?> getCurrentSeasonRemote() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/battle-pass/current-season'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /battle-pass/current-season', e);
      return null;
    }
  }

  Future<SyncOutcome> syncDailyChallengeClaims(
    List<Map<String, dynamic>> items,
  ) =>
      _postSync('daily-challenge-claims', {'items': items});

  Future<SyncOutcome> syncStageProgress(List<Map<String, dynamic>> items) =>
      _postSync('stage-progress', {'items': items});

  Future<SyncOutcome> syncWeeklyQuestClaims(
    List<Map<String, dynamic>> items,
  ) =>
      _postSync('weekly-quests', {'items': items});

  /// Push the per-user daily-bonus snapshot to the backend's absorbing-
  /// merge handler at `/sync/daily-bonus`. Payload includes:
  ///   `last_claim_utc` (ISO instant, nullable),
  ///   `last_claim_tz_offset_minutes` (int, nullable),
  ///   `current_streak`, `total_claims`,
  ///   `weekly_claims` (map),
  ///   `updated_at`.
  Future<SyncOutcome> syncDailyBonusClaim(Map<String, dynamic> payload) =>
      _postSync('daily-bonus', payload);

  // ==================== Weekly Quests ====================

  /// Fetch the current week's quests with the user's progress.
  /// Backend route shape mirrors daily-challenges.
  Future<Map<String, dynamic>?> getCurrentWeeklyQuestsRemote() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/weekly-quests/current'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /weekly-quests/current', e);
      return null;
    }
  }

  /// Batch progress reports — backend takes a raw JSON array of
  /// `{ type, increment_by, game_mode? }`. Used from GameCubit's
  /// post-game flow so a single round can credit multiple weekly-quest
  /// types in one round-trip.
  Future<Map<String, dynamic>?> updateWeeklyQuestProgressBatch(
    List<Map<String, dynamic>> updates,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/weekly-quests/progress/batch'),
            headers: _authHeaders,
            body: jsonEncode(updates),
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error POST /weekly-quests/progress/batch', e);
      return null;
    }
  }

  /// Claim a completed weekly quest. Returns `{ success, coinReward,
  /// battlePassXp, balance? }` on 200. Server is the authority on the
  /// reward grant; the client UI optimistically credits the local
  /// CoinsCubit before this returns and reconciles afterwards.
  Future<Map<String, dynamic>?> claimWeeklyQuestRewardRemote(String questId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/weekly-quests/claim/$questId'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error POST /weekly-quests/claim', e);
      return null;
    }
  }

  // ==================== Daily Challenges ====================

  /// Fetch today's daily challenges with the user's progress. Backend
  /// returns `{ challenges: [...], completed_count, total_count,
  /// all_completed, bonus_coins }`. The DailyChallengeService feeds
  /// `challenges` through `setChallengesFromBackend` after a refresh.
  Future<Map<String, dynamic>?> getTodaysChallengesRemote() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/daily-challenges'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /daily-challenges', e);
      return null;
    }
  }

  // ==================== Social / Friends ====================
  //
  // Friend graph + friend requests. Drift-cached by SocialService;
  // mutations are live API calls (we don't want a friend request to
  // get queued for hours and then surface as "accepted by user who
  // already removed you").

  Future<Map<String, dynamic>?> getFriendsList() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/social/friends'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /social/friends', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getFriendRequestsList() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/social/requests'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /social/requests', e);
      return null;
    }
  }

  /// Send a friend request. Accepts either the recipient's user id
  /// OR their username — the backend resolves whichever is provided.
  Future<Map<String, dynamic>?> sendFriendRequestRemote({
    String? friendUserId,
    String? friendUsername,
  }) async {
    if (friendUserId == null && friendUsername == null) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/social/friends/request'),
            headers: _authHeaders,
            body: jsonEncode({
              'friend_user_id': ?friendUserId,
              'friend_username': ?friendUsername,
            }),
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error POST /social/friends/request', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> acceptFriendRequestRemote(
    String requestId,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/social/friends/accept/$requestId'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error POST /social/friends/accept/$requestId', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> rejectFriendRequestRemote(
    String requestId,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/social/friends/reject/$requestId'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error POST /social/friends/reject/$requestId', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> removeFriendRemote(String friendUserId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/social/friends/$friendUserId'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error DELETE /social/friends/$friendUserId', e);
      return null;
    }
  }

  /// User search lives on /users/search (not /social/...) — kept in
  /// the social section here because the only consumer is the
  /// friends screen's "Add Friend" flow.
  Future<Map<String, dynamic>?> searchUsersRemote(
    String query, {
    int limit = 20,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/users/search').replace(
        queryParameters: {
          'query': query,
          'limit': '$limit',
        },
      );
      final response =
          await http.get(uri, headers: _authHeaders).timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /users/search', e);
      return null;
    }
  }

  // ==================== Tournaments ====================
  //
  // Server-rendered tournament metadata + per-tournament leaderboards.
  // TournamentService drift-caches the GET responses; join + submit
  // are live calls (can't be outbox-deferred: entry quota + final
  // score ranking are server-validated in real time).

  Future<Map<String, dynamic>?> getActiveTournaments() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/tournaments/active'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /tournaments/active', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getTournamentsList({
    bool activeOnly = false,
    String? status,
    String? type,
  }) async {
    try {
      final query = <String, String>{
        'activeOnly': '$activeOnly',
        'status': ?status,
        'type': ?type,
      };
      final uri = Uri.parse('$baseUrl/tournaments')
          .replace(queryParameters: query);
      final response =
          await http.get(uri, headers: _authHeaders).timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /tournaments', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getTournament(String id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/tournaments/$id'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /tournaments/$id', e);
      return null;
    }
  }

  Future<Map<String, dynamic>?> getTournamentLeaderboardRemote(
    String id, {
    int limit = 100,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/tournaments/$id/leaderboard')
          .replace(queryParameters: {'limit': '$limit'});
      final response =
          await http.get(uri, headers: _authHeaders).timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /tournaments/$id/leaderboard', e);
      return null;
    }
  }

  /// Live join — server validates entry quota / level / status. Returns
  /// the updated tournament DTO on 2xx, null on failure.
  Future<Map<String, dynamic>?> joinTournamentRemote(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/tournaments/$id/join'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error POST /tournaments/$id/join', e);
      return null;
    }
  }

  /// Claim the caller's tournament prize. Idempotent server-side: returns
  /// `{ success, already_claimed, prize_coins, rank, message }`. The client
  /// credits the coins locally only when `already_claimed` is false (the
  /// server never touches the coin balance — it's client-authoritative).
  Future<Map<String, dynamic>?> claimTournamentPrizeRemote(String id) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/tournaments/$id/claim-prize'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error POST /tournaments/$id/claim-prize', e);
      return null;
    }
  }

  /// Live score submission. [idempotencyKey] should be a UUID minted by
  /// the caller so duplicate retries de-dupe server-side.
  Future<Map<String, dynamic>?> submitTournamentScoreRemote({
    required String tournamentId,
    required int score,
    int gameDurationSeconds = 0,
    int foodsEaten = 0,
    String? idempotencyKey,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/tournaments/$tournamentId/score'),
            headers: _authHeaders,
            body: jsonEncode({
              'score': score,
              'game_duration_seconds': gameDurationSeconds,
              'foods_eaten': foodsEaten,
              'idempotency_key': ?idempotencyKey,
            }),
          )
          .timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error(
        'Error POST /tournaments/$tournamentId/score',
        e,
      );
      return null;
    }
  }

  // Per-run score submission is no longer a live call: the gameplay flow
  // queues each run to the SyncEngine outbox (SyncDataType.gameScore), which
  // drains to batchSubmitScores (POST /scores/batch). This keeps offline runs
  // from being lost — they reach the leaderboards on the next online tick.

  // ==================== Leaderboards ====================
  //
  // Server-rendered views of OTHER users' scores. Drift-cached client-
  // side via LeaderboardService — these methods only refresh the
  // cache, they're not part of the SyncEngine outbox.

  /// Fetch the global leaderboard. Backend returns
  /// `{ entries: [...], current_user_rank: int?, total_players: int }`.
  Future<Map<String, dynamic>?> getGlobalLeaderboardPage({
    int page = 1,
    int pageSize = 100,
    String? gameMode,
    String? difficulty,
  }) =>
      _getLeaderboard('global',
          page: page,
          pageSize: pageSize,
          gameMode: gameMode,
          difficulty: difficulty);

  Future<Map<String, dynamic>?> getWeeklyLeaderboardPage({
    int page = 1,
    int pageSize = 100,
    String? gameMode,
    String? difficulty,
  }) =>
      _getLeaderboard('weekly',
          page: page,
          pageSize: pageSize,
          gameMode: gameMode,
          difficulty: difficulty);

  Future<Map<String, dynamic>?> getDailyLeaderboardPage({
    int page = 1,
    int pageSize = 100,
    String? gameMode,
    String? difficulty,
  }) =>
      _getLeaderboard('daily',
          page: page,
          pageSize: pageSize,
          gameMode: gameMode,
          difficulty: difficulty);

  /// Friends leaderboard is gated on auth (the others allow anonymous),
  /// so callers should only invoke it when [isAuthenticated] is true.
  Future<Map<String, dynamic>?> getFriendsLeaderboardPage({
    int page = 1,
    int pageSize = 50,
    String? gameMode,
    String? difficulty,
  }) =>
      _getLeaderboard('friends',
          page: page,
          pageSize: pageSize,
          gameMode: gameMode,
          difficulty: difficulty);

  Future<Map<String, dynamic>?> _getLeaderboard(
    String boardPath, {
    required int page,
    required int pageSize,
    String? gameMode,
    String? difficulty,
  }) async {
    try {
      final query = <String, String>{
        'page': '$page',
        'page_size': '$pageSize',
        'game_mode': ?gameMode,
        'difficulty': ?difficulty,
      };
      final uri =
          Uri.parse('$baseUrl/leaderboard/$boardPath').replace(queryParameters: query);
      final response =
          await http.get(uri, headers: _authHeaders).timeout(_timeout);
      return _handleResponse(response);
    } catch (e) {
      AppLogger.error('Error GET /leaderboard/$boardPath', e);
      return null;
    }
  }

  /// First-sign-in pull. Returns the cloud snapshot, or null when the
  /// user has no synced data yet (SyncEngine treats null as "fresh
  /// user, push local"). Network / 5xx errors also return null so
  /// the engine retries later.
  Future<Map<String, dynamic>?> pullSyncSnapshot() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/sync/pull'), headers: _authHeaders)
          .timeout(_timeout);

      AppLogger.network(
        'GET $baseUrl/sync/pull → ${response.statusCode} '
        '(body length: ${response.body.length})',
      );
      // Debug-only body preview, capped at 200 chars. The full
      // snapshot can include cosmetic IDs / claim history; we don't
      // want production talker logs persisting that breadth.
      if (kDebugMode) {
        final preview = response.body.length > 200
            ? '${response.body.substring(0, 200)}… [truncated, '
                '${response.body.length} bytes total]'
            : response.body;
        AppLogger.network('  body: $preview');
      }

      final body = _handleResponse(response);
      if (body == null) return null;
      // Backend wraps a null payload in `{"data": null}` for 200 OK;
      // unwrap that so the SyncEngine sees the same shape regardless.
      if (body.containsKey('data') && body['data'] == null) return null;
      return body;
    } catch (e) {
      AppLogger.error('Error pulling sync snapshot', e);
      return null;
    }
  }

  /// Shared POST helper for every /sync/* endpoint. Maps HTTP outcomes
  /// to the SyncEngine's three-state dispatch result:
  ///   * 2xx                              → [SyncOutcome.success]
  ///   * 5xx, network errors, timeouts    → [SyncOutcome.transient]
  ///   * 401                              → transient (token is cleared
  ///     as a side effect; the next drain will block on `isAuthenticated`
  ///     and re-auth happens on app resume).
  ///   * other 4xx, JSON decode failures  → [SyncOutcome.permanent]
  ///     so the SyncEngine bumps retry count and eventually marks the
  ///     row failed — without this split, a permanent 400 (schema
  ///     mismatch, missing validator, payload too large) would wedge
  ///     the queue forever.
  Future<SyncOutcome> _postSync(
    String path,
    Map<String, dynamic> body,
  ) =>
      _postOutcome('$baseUrl/sync/$path', body, '/sync/$path');

  /// Offline score batch drain target. The SyncEngine pushes queued game runs
  /// here; the backend BatchSubmitScores handler validates + idempotently
  /// ingests each run (so retries de-dupe on the per-run idempotency key).
  Future<SyncOutcome> batchSubmitScores(List<Map<String, dynamic>> items) =>
      _postOutcome('$baseUrl/scores/batch', {'scores': items}, '/scores/batch');

  /// Server-authoritative statistics wipe. Unlike the rest of the app this is
  /// NOT offline-first: the backend deletes Scores, resets achievements +
  /// daily-challenge claims, zeroes the User aggregate, and clears the synced
  /// statistics blob. We must wait for it to succeed before touching local
  /// state, otherwise the next /sync/statistics MAX-merge would resurrect the
  /// pre-reset totals.
  Future<SyncOutcome> resetStatisticsRemote() => _postOutcome(
        '$baseUrl/users/me/reset-statistics',
        const {},
        '/users/me/reset-statistics',
      );

  /// POST [body] to [url] and map the HTTP result to a [SyncOutcome] with the
  /// same transient/permanent rules the SyncEngine drain relies on. Shared by
  /// the /sync/* senders and the offline score batch (/scores/batch).
  Future<SyncOutcome> _postOutcome(
    String url,
    Map<String, dynamic> body,
    String label,
  ) async {
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(url),
            headers: _authHeaders,
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (e) {
      AppLogger.error('Error POST $label', e);
      return SyncOutcome.transient();
    }

    final code = response.statusCode;

    if (code == 401) {
      AppLogger.error('Unauthorized POST $label - token may be expired');
      clearToken();
      onUnauthorized?.call();
      return SyncOutcome.transient(statusCode: code);
    }

    if (code >= 200 && code < 300) {
      try {
        if (response.body.isEmpty) return SyncOutcome.success({});
        final decoded = jsonDecode(response.body);
        return SyncOutcome.success(
          decoded is Map ? Map<String, dynamic>.from(decoded) : {'data': decoded},
        );
      } catch (e) {
        AppLogger.error(
          'POST $label returned 2xx with undecodable body',
          e,
        );
        // Body is malformed but status was 2xx — treat as a permanent
        // failure rather than retrying forever against a server that
        // thinks it succeeded.
        return SyncOutcome.permanent(statusCode: code);
      }
    }

    if (code >= 500) {
      AppLogger.error('POST $label failed with $code (transient)', response.body);
      return SyncOutcome.transient(statusCode: code);
    }

    // Remaining 4xx — bad request, validation error, payload too large,
    // etc. Bumping retries and eventually marking failed is the right
    // call; retrying forever just spams the backend.
    AppLogger.error('POST $label failed with $code (permanent)', response.body);
    return SyncOutcome.permanent(statusCode: code);
  }

  // ==================== Notifications ====================

  /// Register FCM token. Forwards the device's UTC offset so the backend
  /// can land daily notifications at each user's local 20:00 (see Hangfire
  /// send-daily-reminder job + DailyChallengeJobService.SendDailyReminder).
  Future<bool> registerFcmToken({
    required String fcmToken,
    String platform = 'flutter',
    int? timezoneOffsetMinutes,
  }) async {
    try {
      final body = <String, dynamic>{
        'fcm_token': fcmToken,
        'platform': platform,
      };
      if (timezoneOffsetMinutes != null) {
        body['time_zone_offset_minutes'] = timezoneOffsetMinutes;
      }

      final response = await http
          .post(
            Uri.parse('$baseUrl/users/register-token'),
            headers: _authHeaders,
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.error('Error registering FCM token', e);
      return false;
    }
  }

  // ==================== Dev-only test notifications ====================
  //
  // All four endpoints below back the kDebugMode test panel in
  // settings_screen.dart. They mirror the real production push path
  // (backend → FCM → device) so the dev panel verifies end-to-end
  // delivery, not just OS-local rendering.

  /// POST /test/send-to-me — immediate FCM push to every token the
  /// backend has on file for the caller. Returns true on success.
  Future<bool> sendTestPushToMe({String? title, String? body}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/test/send-to-me'),
            headers: _authHeaders,
            body: jsonEncode({
              'title': ?title,
              'body': ?body,
            }),
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      AppLogger.error('Error sending test push via backend', e);
      return false;
    }
  }

  /// POST /test/preview-daily-reminder — fires the EXACT variant the
  /// daily reminder would send to this user on the next applicable tick.
  /// Returns the variant name (streak_at_risk / daily_challenge /
  /// high_score_nudge) or null when no variant applies / user has no tokens.
  Future<String?> previewDailyReminderViaBackend() async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/test/preview-daily-reminder'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      final parsed = _handleResponse(response);
      if (parsed == null) return null;
      if (parsed['success'] == true) {
        return parsed['variant']?.toString();
      }
      return null;
    } catch (e) {
      AppLogger.error('Error previewing daily reminder via backend', e);
      return null;
    }
  }

  /// POST /test/schedule — schedules a one-off FCM push at the given UTC
  /// moment using Hangfire.BackgroundJob.Schedule. Returns the Hangfire
  /// job id so the caller can cancel later. Returns null on failure.
  Future<String?> scheduleTestNotification({
    required DateTime fireAtUtc,
    String? title,
    String? body,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/test/schedule'),
            headers: _authHeaders,
            body: jsonEncode({
              'fire_at_utc': fireAtUtc.toUtc().toIso8601String(),
              'title': ?title,
              'body': ?body,
            }),
          )
          .timeout(_timeout);
      final parsed = _handleResponse(response);
      if (parsed == null) return null;
      return parsed['job_id']?.toString();
    } catch (e) {
      AppLogger.error('Error scheduling test notification via backend', e);
      return null;
    }
  }

  /// DELETE /test/schedule/{jobId} — cancel a previously scheduled one-off.
  /// Idempotent on the backend side; returns true on HTTP 200 regardless
  /// of whether the job still existed (i.e., already-cancelled / fired
  /// jobs return true too — the caller's "clear pending test" UX expects
  /// that).
  Future<bool> cancelScheduledTestNotification(String jobId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/test/schedule/$jobId'),
            headers: _authHeaders,
          )
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (e) {
      AppLogger.error('Error cancelling scheduled test via backend', e);
      return false;
    }
  }
}
