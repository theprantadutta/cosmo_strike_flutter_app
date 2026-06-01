import 'package:drift/drift.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';

part 'leaderboard_dao.g.dart';

/// String constants for the `boardType` discriminator.
class LeaderboardBoardType {
  static const String global = 'global';
  static const String weekly = 'weekly';
  static const String daily = 'daily';
  static const String friends = 'friends';
}

@DriftAccessor(tables: [LeaderboardEntries, LeaderboardMeta])
class LeaderboardDao extends DatabaseAccessor<AppDatabase>
    with _$LeaderboardDaoMixin {
  LeaderboardDao(super.db);

  /// Reactive query: ordered list of cached entries for [boardType].
  Stream<List<LeaderboardEntry>> watchEntries(String boardType) =>
      (select(leaderboardEntries)
            ..where((t) => t.boardType.equals(boardType))
            ..orderBy([(t) => OrderingTerm.asc(t.rank)]))
          .watch();

  /// One-shot read of cached entries for [boardType].
  Future<List<LeaderboardEntry>> getEntries(String boardType) =>
      (select(leaderboardEntries)
            ..where((t) => t.boardType.equals(boardType))
            ..orderBy([(t) => OrderingTerm.asc(t.rank)]))
          .get();

  /// Reactive query: per-board metadata (last-refreshed, total players,
  /// current user rank). Returns `null` when the board has never been
  /// refreshed on this device.
  Stream<LeaderboardMetaData?> watchMeta(String boardType) =>
      (select(leaderboardMeta)..where((t) => t.boardType.equals(boardType)))
          .watchSingleOrNull();

  /// One-shot read of per-board metadata.
  Future<LeaderboardMetaData?> getMeta(String boardType) =>
      (select(leaderboardMeta)..where((t) => t.boardType.equals(boardType)))
          .getSingleOrNull();

  /// Atomic replace: wipe everything for [boardType] then re-insert the
  /// freshly-fetched entries + meta in a single Drift transaction so
  /// the UI's reactive stream emits exactly once for the swap and
  /// never sees a half-applied state.
  Future<void> replaceBoard({
    required String boardType,
    required List<LeaderboardEntriesCompanion> entries,
    required LeaderboardMetaCompanion meta,
  }) async {
    await transaction(() async {
      await (delete(leaderboardEntries)
            ..where((t) => t.boardType.equals(boardType)))
          .go();
      if (entries.isNotEmpty) {
        await batch((b) {
          b.insertAll(leaderboardEntries, entries);
        });
      }
      await into(leaderboardMeta).insertOnConflictUpdate(
        meta.copyWith(boardType: Value(boardType)),
      );
    });
  }

  /// Drop everything (used by signOut wipe paths).
  Future<void> clear() async {
    await transaction(() async {
      await delete(leaderboardEntries).go();
      await delete(leaderboardMeta).go();
    });
  }
}
