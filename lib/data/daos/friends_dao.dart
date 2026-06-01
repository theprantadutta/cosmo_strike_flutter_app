import 'package:drift/drift.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';

part 'friends_dao.g.dart';

/// String keys for the [FriendsMeta] table — centralised so service +
/// screen don't drift on the format.
class FriendsMetaKey {
  static const String friends = 'friends';
  static const String requests = 'requests';
}

@DriftAccessor(tables: [FriendsCache, FriendRequestsCache, FriendsMeta])
class FriendsDao extends DatabaseAccessor<AppDatabase>
    with _$FriendsDaoMixin {
  FriendsDao(super.db);

  // -------------- Friends list --------------

  Stream<List<FriendsCacheData>> watchFriends() =>
      (select(friendsCache)
            ..orderBy([(t) => OrderingTerm.asc(t.username)]))
          .watch();

  Future<List<FriendsCacheData>> getFriends() =>
      (select(friendsCache)
            ..orderBy([(t) => OrderingTerm.asc(t.username)]))
          .get();

  /// Atomic replace: delete the entire friends cache and re-insert
  /// the fresh list. Updates the staleness meta in the same
  /// transaction so the UI's reactive stream sees a single emit
  /// for the swap.
  Future<void> replaceFriends({
    required List<FriendsCacheCompanion> friends,
    required DateTime refreshedAt,
  }) async {
    await transaction(() async {
      await delete(friendsCache).go();
      if (friends.isNotEmpty) {
        await batch((b) {
          b.insertAll(friendsCache, friends);
        });
      }
      await into(friendsMeta).insertOnConflictUpdate(
        FriendsMetaCompanion(
          metaKey: const Value(FriendsMetaKey.friends),
          lastRefreshedAt: Value(refreshedAt),
        ),
      );
    });
  }

  /// Targeted removal — used by the live "remove friend" path so we
  /// can drop a single row from the cache immediately without waiting
  /// for the next refresh.
  Future<void> removeFriend(String userId) async {
    await (delete(friendsCache)..where((t) => t.userId.equals(userId))).go();
  }

  // -------------- Friend requests --------------

  Stream<List<FriendRequestsCacheData>> watchRequests() =>
      (select(friendRequestsCache)
            ..orderBy([(t) => OrderingTerm.desc(t.sentAt)]))
          .watch();

  Future<List<FriendRequestsCacheData>> getRequests() =>
      (select(friendRequestsCache)
            ..orderBy([(t) => OrderingTerm.desc(t.sentAt)]))
          .get();

  /// Look up a cached request by its sender. The screen's UI binds to
  /// `fromUserId` (the entity the user knows about); the backend's
  /// accept/reject endpoints want the requestId. The service uses
  /// this to bridge the two.
  Future<FriendRequestsCacheData?> findRequestByFromUserId(
    String fromUserId,
  ) =>
      (select(friendRequestsCache)
            ..where((t) => t.fromUserId.equals(fromUserId))
            ..limit(1))
          .getSingleOrNull();

  Future<void> replaceRequests({
    required List<FriendRequestsCacheCompanion> requests,
    required DateTime refreshedAt,
  }) async {
    await transaction(() async {
      await delete(friendRequestsCache).go();
      if (requests.isNotEmpty) {
        await batch((b) {
          b.insertAll(friendRequestsCache, requests);
        });
      }
      await into(friendsMeta).insertOnConflictUpdate(
        FriendsMetaCompanion(
          metaKey: const Value(FriendsMetaKey.requests),
          lastRefreshedAt: Value(refreshedAt),
        ),
      );
    });
  }

  /// Drop a single request — used after a successful accept/reject so
  /// the UI removes the row immediately, before the next refresh
  /// brings the authoritative server state down.
  Future<void> removeRequest(String requestId) async {
    await (delete(friendRequestsCache)
          ..where((t) => t.requestId.equals(requestId)))
        .go();
  }

  // -------------- Meta / staleness --------------

  Future<FriendsMetaData?> getMeta(String metaKey) =>
      (select(friendsMeta)..where((t) => t.metaKey.equals(metaKey)))
          .getSingleOrNull();

  Stream<FriendsMetaData?> watchMeta(String metaKey) =>
      (select(friendsMeta)..where((t) => t.metaKey.equals(metaKey)))
          .watchSingleOrNull();

  Future<void> clear() async {
    await transaction(() async {
      await delete(friendsCache).go();
      await delete(friendRequestsCache).go();
      await delete(friendsMeta).go();
    });
  }
}
