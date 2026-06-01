import 'dart:async';

import 'package:drift/drift.dart' as d;
import 'package:get_it/get_it.dart';
import 'package:cosmo_strike_flutter_app/data/daos/friends_dao.dart';
// Hide the Drift-generated `UserProfile` data class from the
// legacy local-cache table — the model in `models/user_profile.dart`
// is the one the rest of the app already uses.
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart'
    hide UserProfile;
import 'package:cosmo_strike_flutter_app/models/user_profile.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Drift-first social/friends service.
///
/// Reads (friends list + incoming requests) are served from a local
/// Drift cache so the screen has something to show offline; mutations
/// (send / accept / reject / remove) are live API calls — queueing
/// them in the outbox would let a friend request linger for hours
/// before reaching the recipient, which produces confusing UX (the
/// user's been "ignoring" you for the whole drain delay).
///
/// `accept` / `reject` accept the `fromUserId` (what the screen
/// surfaces from a [FriendRequest]) and resolve to the underlying
/// requestId via the cached request row. If no matching cached row
/// exists the call returns false — refresh the cache first.
class SocialService {
  static SocialService? _instance;

  SocialService._internal();

  factory SocialService() {
    _instance ??= SocialService._internal();
    return _instance!;
  }

  final ApiService _api = ApiService();

  FriendsDao get _dao => GetIt.I<AppDatabase>().friendsDao;

  // -------------- Reads (cache-first) --------------

  Future<List<UserProfile>> getFriends() async {
    final rows = await _dao.getFriends();
    return rows.map(_friendRowToProfile).toList();
  }

  Future<List<FriendRequest>> getFriendRequests() async {
    final rows = await _dao.getRequests();
    return rows.map(_requestRowToModel).toList();
  }

  Future<List<UserProfile>> getFriendsLeaderboard() => getFriends();

  Future<UserProfile?> getUserProfile(String userId) async {
    // Friends list is the only locally-cached UserProfile source —
    // arbitrary profiles still require a network round-trip and that
    // surface isn't wired here. Returning the cached friend row when
    // it matches keeps the existing call site working for friend
    // taps; everything else falls back to null.
    final friends = await _dao.getFriends();
    for (final f in friends) {
      if (f.userId == userId) return _friendRowToProfile(f);
    }
    return null;
  }

  Future<bool> hasCachedFriends() async {
    final rows = await _dao.getFriends();
    return rows.isNotEmpty;
  }

  Future<DateTime?> getLastRefreshedAt(String metaKey) async {
    final meta = await _dao.getMeta(metaKey);
    return meta?.lastRefreshedAt;
  }

  Stream<List<UserProfile>> watchFriends() => _dao
      .watchFriends()
      .map((rows) => rows.map(_friendRowToProfile).toList());

  Stream<List<FriendRequest>> watchFriendRequests() => _dao
      .watchRequests()
      .map((rows) => rows.map(_requestRowToModel).toList());

  Future<void> clearCache() => _dao.clear();

  // -------------- Refresh (write-through) --------------

  /// Pull the friend graph and overwrite the cache atomically.
  Future<void> refreshFriends() async {
    if (!_api.isAuthenticated) return;
    final body = await _safeFetch(() => _api.getFriendsList());
    if (body == null) return;
    final raw = body['friends'];
    if (raw is! List) {
      AppLogger.warning(
        'SocialService.refreshFriends: missing friends list',
      );
      return;
    }
    final companions = <FriendsCacheCompanion>[];
    for (final r in raw) {
      if (r is! Map<String, dynamic>) continue;
      companions.add(_friendCompanionFromWire(r));
    }
    await _dao.replaceFriends(
      friends: companions,
      refreshedAt: DateTime.now(),
    );
  }

  /// Pull pending incoming friend requests and replace the cache.
  Future<void> refreshFriendRequests() async {
    if (!_api.isAuthenticated) return;
    final body = await _safeFetch(() => _api.getFriendRequestsList());
    if (body == null) return;
    final raw = body['requests'];
    if (raw is! List) {
      AppLogger.warning(
        'SocialService.refreshFriendRequests: missing requests list',
      );
      return;
    }
    final companions = <FriendRequestsCacheCompanion>[];
    for (final r in raw) {
      if (r is! Map<String, dynamic>) continue;
      companions.add(_requestCompanionFromWire(r));
    }
    await _dao.replaceRequests(
      requests: companions,
      refreshedAt: DateTime.now(),
    );
  }

  // -------------- Live mutations --------------

  /// Send a friend request to the user with [toUserId]. Returns true
  /// only after the server confirms. Refreshes the requests cache on
  /// success so the "Pending" badge updates without waiting for the
  /// next TTL tick.
  Future<bool> sendFriendRequest(String toUserId) async {
    if (!_api.isAuthenticated) return false;
    final body = await _safeFetch(
      () => _api.sendFriendRequestRemote(friendUserId: toUserId),
    );
    if (body == null) return false;
    unawaited(refreshFriendRequests());
    return true;
  }

  /// Accept a pending friend request. The screen passes the sender's
  /// userId; we resolve to the requestId via the cache.
  Future<bool> acceptFriendRequest(String fromUserId) async {
    if (!_api.isAuthenticated) return false;
    final cached = await _dao.findRequestByFromUserId(fromUserId);
    if (cached == null) {
      AppLogger.warning(
        'SocialService.acceptFriendRequest: no cached request from '
        '$fromUserId — refreshing and aborting',
      );
      unawaited(refreshFriendRequests());
      return false;
    }
    final body = await _safeFetch(
      () => _api.acceptFriendRequestRemote(cached.requestId),
    );
    if (body == null) return false;
    // Optimistic local update: drop the request immediately and
    // refresh both caches in the background so the friend appears in
    // the list as soon as the server's projection lands.
    await _dao.removeRequest(cached.requestId);
    unawaited(refreshFriends());
    unawaited(refreshFriendRequests());
    return true;
  }

  Future<bool> rejectFriendRequest(String fromUserId) async {
    if (!_api.isAuthenticated) return false;
    final cached = await _dao.findRequestByFromUserId(fromUserId);
    if (cached == null) {
      unawaited(refreshFriendRequests());
      return false;
    }
    final body = await _safeFetch(
      () => _api.rejectFriendRequestRemote(cached.requestId),
    );
    if (body == null) return false;
    await _dao.removeRequest(cached.requestId);
    unawaited(refreshFriendRequests());
    return true;
  }

  Future<bool> removeFriend(String friendUserId) async {
    if (!_api.isAuthenticated) return false;
    final body = await _safeFetch(
      () => _api.removeFriendRemote(friendUserId),
    );
    if (body == null) return false;
    // Drop the row immediately so the UI removes the entry without
    // waiting for the next refresh.
    await _dao.removeFriend(friendUserId);
    unawaited(refreshFriends());
    return true;
  }

  /// Live search — results are ephemeral by definition (search is a
  /// query, not a state) so they're not Drift-cached. The caller
  /// (provider) holds the results in memory for as long as the
  /// search query is active.
  Future<List<UserProfile>> searchUsers(String query) async {
    if (!_api.isAuthenticated || query.trim().isEmpty) return const [];
    final body = await _safeFetch(
      () => _api.searchUsersRemote(query, limit: 20),
    );
    if (body == null) return const [];
    final raw = body['users'] ?? body['results'] ?? body['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(_searchResultToProfile)
        .toList();
  }

  /// Status / privacy updates were backend-only in the prior build.
  /// Left as no-ops here so existing call sites compile until a
  /// proper offline-first port is decided.
  Future<void> updateUserStatus(
    UserStatus status, {
    String? statusMessage,
  }) async {}

  Future<bool> updatePrivacySetting(bool isPublic) async => false;

  // -------------- Internals --------------

  Future<Map<String, dynamic>?> _safeFetch(
    Future<Map<String, dynamic>?> Function() fetch,
  ) async {
    try {
      return await fetch();
    } catch (e) {
      AppLogger.error('SocialService fetch errored', e);
      return null;
    }
  }

  FriendsCacheCompanion _friendCompanionFromWire(Map<String, dynamic> raw) {
    return FriendsCacheCompanion.insert(
      userId: (raw['user_id'] ?? raw['userId'] ?? '').toString(),
      username: d.Value(raw['username'] as String?),
      displayName:
          d.Value((raw['display_name'] ?? raw['displayName']) as String?),
      photoUrl: d.Value((raw['photo_url'] ?? raw['photoUrl']) as String?),
      status: d.Value(_statusString(raw['status'])),
      highScore:
          d.Value((raw['high_score'] ?? raw['highScore']) as int? ?? 0),
      level: d.Value(raw['level'] as int? ?? 1),
      friendsSince: d.Value(_parseDate(raw['friends_since'] ??
              raw['friendsSince']) ??
          DateTime.now()),
    );
  }

  FriendRequestsCacheCompanion _requestCompanionFromWire(
    Map<String, dynamic> raw,
  ) {
    return FriendRequestsCacheCompanion.insert(
      requestId: (raw['request_id'] ?? raw['requestId'] ?? '').toString(),
      fromUserId: (raw['from_user_id'] ?? raw['fromUserId'] ?? '').toString(),
      fromUsername:
          d.Value((raw['from_username'] ?? raw['fromUsername']) as String?),
      fromDisplayName: d.Value(
        (raw['from_display_name'] ?? raw['fromDisplayName']) as String?,
      ),
      fromPhotoUrl:
          d.Value((raw['from_photo_url'] ?? raw['fromPhotoUrl']) as String?),
      sentAt: d.Value(_parseDate(raw['sent_at'] ?? raw['sentAt']) ??
          DateTime.now()),
    );
  }

  UserProfile _friendRowToProfile(FriendsCacheData row) {
    return UserProfile(
      uid: row.userId,
      displayName: row.displayName ?? row.username ?? 'Player',
      username: row.username ?? row.displayName ?? 'Player',
      email: '',
      photoUrl: row.photoUrl,
      highScore: row.highScore,
      level: row.level,
      joinedDate: row.friendsSince,
      lastSeen: row.cachedAt,
      status: UserStatus.values.firstWhere(
        (s) => s.name == row.status,
        orElse: () => UserStatus.offline,
      ),
    );
  }

  FriendRequest _requestRowToModel(FriendRequestsCacheData row) {
    return FriendRequest(
      id: row.requestId,
      fromUserId: row.fromUserId,
      toUserId: '', // Receiver is implicitly the current user.
      fromUserName: row.fromUsername ??
          row.fromDisplayName ??
          'Unknown',
      toUserName: '',
      fromUserPhotoUrl: row.fromPhotoUrl,
      createdAt: row.sentAt,
      type: FriendRequestType.received,
    );
  }

  UserProfile _searchResultToProfile(Map<String, dynamic> raw) {
    return UserProfile(
      uid: (raw['id'] ?? raw['user_id'] ?? raw['uid'] ?? '').toString(),
      displayName: (raw['display_name'] ??
              raw['displayName'] ??
              raw['username'] ??
              'Player')
          .toString(),
      username:
          (raw['username'] ?? raw['display_name'] ?? raw['displayName'] ?? '')
              .toString(),
      email: '',
      photoUrl: (raw['photo_url'] ?? raw['photoUrl']) as String?,
      highScore:
          (raw['high_score'] ?? raw['highScore']) as int? ?? 0,
      level: raw['level'] as int? ?? 1,
      joinedDate: _parseDate(raw['joined_date'] ?? raw['joinedDate']) ??
          DateTime.now(),
      lastSeen:
          _parseDate(raw['last_active_at'] ?? raw['lastActiveAt']) ??
              DateTime.now(),
      status: UserStatus.values.firstWhere(
        (s) => s.name == raw['status'],
        orElse: () => UserStatus.offline,
      ),
    );
  }

  /// Normalise backend's status enum to the lowercase name we store
  /// in the cache. The wire format is either the enum name as string
  /// ('Online'/'Offline'/'Playing') or its int index.
  String _statusString(dynamic raw) {
    if (raw is String) return raw.toLowerCase();
    if (raw is int && raw >= 0 && raw < UserStatus.values.length) {
      return UserStatus.values[raw].name;
    }
    return 'offline';
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }
}
