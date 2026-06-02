import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:cosmo_strike_flutter_app/data/daos/settings_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/game_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/store_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/sync_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/leaderboard_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/tournament_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/friends_dao.dart';

part 'app_database.g.dart';

const _outboxIdGen = Uuid();

/// String constants for the `dataType` column on [SyncQueue] rows.
/// Each one corresponds to a class of mutation the SyncEngine drains
/// to its matching backend endpoint.
class SyncDataType {
  static const String settings = 'settings';
  static const String statistics = 'statistics';
  static const String achievement = 'achievement';
  static const String coinBalance = 'coin_balance';
  static const String coinTransaction = 'coin_transaction';
  static const String premiumStatus = 'premium_status';
  static const String unlockedItem = 'unlocked_item';
  static const String battlePass = 'battle_pass';
  static const String dailyChallengeClaim = 'daily_challenge_claim';
  static const String weeklyQuestClaim = 'weekly_quest_claim';
  static const String dailyBonusClaim = 'daily_bonus_claim';
  static const String playerProgress = 'player_progress';
}

// =====================================================
// TABLE 1: Game Settings
// =====================================================
class GameSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get themeIndex => integer().withDefault(const Constant(0))();
  BoolColumn get soundEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get musicEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get dPadEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get dPadPositionIndex =>
      integer().withDefault(const Constant(1))(); // 0=left, 1=center, 2=right
  IntColumn get boardSizeIndex => integer().withDefault(const Constant(1))();
  IntColumn get highScore => integer().withDefault(const Constant(0))();
  IntColumn get crashFeedbackDurationSeconds =>
      integer().withDefault(const Constant(3))();
  BoolColumn get trailSystemEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get screenShakeEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get selectedSkinId => text().nullable()();
  TextColumn get selectedTrailId => text().nullable()();
  DateTimeColumn get lastUpdated =>
      dateTime().withDefault(currentDateAndTime)();
  // Tracked by the sync engine; bumped on every mutation that should
  // round-trip to the backend. Distinct from `lastUpdated` (which is
  // older and inconsistently maintained) so we don't have to retrofit
  // every existing write site.
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// =====================================================
// TABLE 2: Statistics (37 fields for comprehensive game stats)
// =====================================================
class Statistics extends Table {
  IntColumn get id => integer().autoIncrement()();

  // Core stats
  IntColumn get totalGamesPlayed => integer().withDefault(const Constant(0))();
  IntColumn get totalScore => integer().withDefault(const Constant(0))();
  IntColumn get highestScore => integer().withDefault(const Constant(0))();
  IntColumn get totalFoodsEaten => integer().withDefault(const Constant(0))();
  IntColumn get totalGameTimeSeconds =>
      integer().withDefault(const Constant(0))();

  // Ship length stats
  IntColumn get maxShipLength => integer().withDefault(const Constant(0))();
  IntColumn get totalShipLength => integer().withDefault(const Constant(0))();
  RealColumn get averageShipLength =>
      real().withDefault(const Constant(0.0))();

  // Death stats
  IntColumn get deathsByWall => integer().withDefault(const Constant(0))();
  IntColumn get deathsBySelf => integer().withDefault(const Constant(0))();
  IntColumn get totalDeaths => integer().withDefault(const Constant(0))();

  // Session stats
  IntColumn get longestSessionSeconds =>
      integer().withDefault(const Constant(0))();
  IntColumn get shortestGameSeconds =>
      integer().withDefault(const Constant(0))();
  IntColumn get longestGameSeconds =>
      integer().withDefault(const Constant(0))();
  RealColumn get averageGameDuration =>
      real().withDefault(const Constant(0.0))();

  // Streak stats
  IntColumn get currentWinStreak => integer().withDefault(const Constant(0))();
  IntColumn get longestWinStreak => integer().withDefault(const Constant(0))();
  IntColumn get currentPlayStreak =>
      integer().withDefault(const Constant(0))(); // Days in a row
  IntColumn get longestPlayStreak => integer().withDefault(const Constant(0))();

  // Per-mode stats (stored as JSON)
  TextColumn get classicModeStats =>
      text().withDefault(const Constant('{}'))();
  TextColumn get zenModeStats => text().withDefault(const Constant('{}'))();
  TextColumn get speedModeStats => text().withDefault(const Constant('{}'))();
  TextColumn get survivalModeStats =>
      text().withDefault(const Constant('{}'))();
  TextColumn get timeAttackModeStats =>
      text().withDefault(const Constant('{}'))();

  // Power-up stats
  IntColumn get powerUpsCollected => integer().withDefault(const Constant(0))();
  IntColumn get speedBoostsUsed => integer().withDefault(const Constant(0))();
  IntColumn get shieldsUsed => integer().withDefault(const Constant(0))();
  IntColumn get scoreMultipliersUsed =>
      integer().withDefault(const Constant(0))();

  // Special achievements data
  IntColumn get perfectGames =>
      integer().withDefault(const Constant(0))(); // No deaths in session
  IntColumn get closeCallsSurvived =>
      integer().withDefault(const Constant(0))(); // Near-miss scenarios
  IntColumn get foodsEatenInSingleGame =>
      integer().withDefault(const Constant(0))();

  // Multiplayer stats
  IntColumn get multiplayerGamesPlayed =>
      integer().withDefault(const Constant(0))();
  IntColumn get multiplayerWins => integer().withDefault(const Constant(0))();
  IntColumn get multiplayerLosses => integer().withDefault(const Constant(0))();

  // Tournament stats
  IntColumn get tournamentsEntered =>
      integer().withDefault(const Constant(0))();
  IntColumn get tournamentsWon => integer().withDefault(const Constant(0))();
  IntColumn get bestTournamentPlacement =>
      integer().withDefault(const Constant(0))();

  // Timestamps
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
  DateTimeColumn get lastUpdated =>
      dateTime().withDefault(currentDateAndTime)();
  /// Sync-engine timestamp — see [GameSettings.updatedAt].
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  // Full GameStatistics model serialized as JSON.
  //
  // Background: this table's typed columns were designed independently of
  // the GameStatistics Dart model and use different field names
  // (highestScore vs highScore, totalFoodsEaten vs totalFoodConsumed,
  // totalGameTimeSeconds vs totalGameTime, longestGameSeconds vs
  // longestSurvivalTime, ...). The old JSON serializer translated between
  // those names lossily — every game-end save dropped most of the model
  // and every app-launch load returned zeros, which is why the stats
  // screen kept showing 0 for win streak / play time / perfect games /
  // highest level / etc.
  //
  // Rather than maintain a brittle name-translation layer, this column
  // stores the full model JSON verbatim. The DAO writes/reads it; the
  // typed columns above stay as-is for any code that already uses them
  // (none in production, but kept to avoid breaking change). All new
  // statistics persistence goes through this column.
  TextColumn get modelJson => text().withDefault(const Constant('{}'))();
}

// =====================================================
// TABLE 3: Achievements
// =====================================================
class Achievements extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text()();
  TextColumn get category =>
      text().withDefault(const Constant('general'))(); // general, skill, etc.
  IntColumn get currentProgress => integer().withDefault(const Constant(0))();
  IntColumn get targetProgress => integer().withDefault(const Constant(1))();
  BoolColumn get isUnlocked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get unlockedAt => dateTime().nullable()();
  IntColumn get rewardCoins => integer().withDefault(const Constant(0))();
  BoolColumn get rewardClaimed => boolean().withDefault(const Constant(false))();
  TextColumn get iconName => text().nullable()();
  BoolColumn get isSecret => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastUpdated =>
      dateTime().withDefault(currentDateAndTime)();
  /// Sync-engine timestamp — see [GameSettings.updatedAt].
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// =====================================================
// TABLE 4: Coins (Balance & Transactions)
// =====================================================
class Coins extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get balance => integer().withDefault(const Constant(0))();
  IntColumn get totalEarned => integer().withDefault(const Constant(0))();
  IntColumn get totalSpent => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastUpdated =>
      dateTime().withDefault(currentDateAndTime)();
  /// Sync-engine timestamp — see [GameSettings.updatedAt].
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

class CoinTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get amount => integer()();
  TextColumn get type =>
      text()(); // 'earned', 'spent', 'bonus', 'purchase', 'refund'
  TextColumn get source =>
      text()(); // 'game', 'achievement', 'daily_bonus', 'purchase', etc.
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  /// Sync-engine timestamp — see [GameSettings.updatedAt]. For an
  /// append-only log this matches `createdAt` on insert, but kept for
  /// schema symmetry with the other synced tables.
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// =====================================================
// TABLE 5: Premium Status
// =====================================================
class PremiumStatus extends Table {
  IntColumn get id => integer().autoIncrement()();
  BoolColumn get isPremiumActive =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get premiumExpirationDate => dateTime().nullable()();
  BoolColumn get isOnTrial => boolean().withDefault(const Constant(false))();
  DateTimeColumn get trialStartDate => dateTime().nullable()();
  DateTimeColumn get trialEndDate => dateTime().nullable()();
  IntColumn get bronzeTournamentEntries =>
      integer().withDefault(const Constant(0))();
  IntColumn get silverTournamentEntries =>
      integer().withDefault(const Constant(0))();
  IntColumn get goldTournamentEntries =>
      integer().withDefault(const Constant(0))();
  TextColumn get purchaseReceiptData =>
      text().nullable()(); // For purchase validation
  DateTimeColumn get lastUpdated =>
      dateTime().withDefault(currentDateAndTime)();
  /// Sync-engine timestamp — see [GameSettings.updatedAt].
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// =====================================================
// TABLE 6: Unlocked Items
// =====================================================
class UnlockedItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get itemId => text()();
  TextColumn get itemType =>
      text()(); // 'theme', 'skin', 'trail', 'powerup', 'board_size', 'game_mode', 'bundle'
  DateTimeColumn get unlockedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get unlockedBy =>
      text().withDefault(const Constant('purchase'))(); // 'purchase', 'achievement', 'battle_pass', 'gift'
  /// Sync-engine timestamp — see [GameSettings.updatedAt].
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// =====================================================
// TABLE 7: Battle Pass
// =====================================================
class BattlePasses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get seasonId => text()();
  IntColumn get currentTier => integer().withDefault(const Constant(0))();
  IntColumn get currentXp => integer().withDefault(const Constant(0))();
  IntColumn get xpForNextTier => integer().withDefault(const Constant(100))();
  BoolColumn get isPremiumPass =>
      boolean().withDefault(const Constant(false))();
  TextColumn get claimedRewards =>
      text().withDefault(const Constant('[]'))(); // JSON array of tier numbers
  DateTimeColumn get seasonStartDate => dateTime().nullable()();
  DateTimeColumn get seasonEndDate => dateTime().nullable()();
  DateTimeColumn get lastUpdated =>
      dateTime().withDefault(currentDateAndTime)();
  /// Sync-engine timestamp — see [GameSettings.updatedAt].
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// =====================================================
// TABLE 8: Daily Challenges
// =====================================================
class DailyChallenges extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get challengeId => text()();
  TextColumn get challengeType =>
      text()(); // 'score', 'length', 'time', 'foods', etc.
  TextColumn get title => text()();
  TextColumn get description => text()();
  IntColumn get currentProgress => integer().withDefault(const Constant(0))();
  IntColumn get targetProgress => integer()();
  IntColumn get rewardCoins => integer().withDefault(const Constant(0))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get rewardClaimed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get challengeDate => dateTime()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  /// Sync-engine timestamp — see [GameSettings.updatedAt].
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// =====================================================
// TABLE 8b: Weekly Quests (claim mirror — analogous to DailyChallenges)
// =====================================================
class WeeklyQuests extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get questId => text()();
  TextColumn get questType => text()(); // WeeklyQuestType.apiValue
  TextColumn get title => text()();
  TextColumn get description => text()();
  IntColumn get currentProgress => integer().withDefault(const Constant(0))();
  IntColumn get targetValue => integer()();
  IntColumn get coinReward => integer().withDefault(const Constant(0))();
  IntColumn get battlePassXpReward =>
      integer().withDefault(const Constant(0))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  BoolColumn get claimedReward => boolean().withDefault(const Constant(false))();
  DateTimeColumn get weekStartDate => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  /// Sync-engine timestamp — see [GameSettings.updatedAt].
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// =====================================================
// TABLE 8c: Daily Login Bonus state (singleton)
// =====================================================
//
// Drift-first source of truth for the daily login bonus popup gate.
// One row per device (id = 1). The SyncEngine pushes this snapshot to
// the backend's existing DailyLoginBonus table via the new
// /sync/daily-bonus endpoint, and pulls it back on cold start.
//
// Why we snapshot the tz offset at claim time: "today" is computed as
// `(lastClaimUtc + tzOffsetMinutes).date`, so we can replay the user-
// local day boundary even if the device's timezone changes later.
class DailyBonusState extends Table {
  IntColumn get id => integer().autoIncrement()();
  // UTC moment the most recent claim happened, ms since epoch. Null
  // means "never claimed."
  IntColumn get lastClaimUtcMs => integer().nullable()();
  // The user's tz offset (in minutes east of UTC) at claim time. Used
  // together with [lastClaimUtcMs] to derive the user-local day.
  IntColumn get lastClaimTzOffsetMinutes => integer().nullable()();
  IntColumn get currentStreak => integer().withDefault(const Constant(0))();
  IntColumn get totalClaims => integer().withDefault(const Constant(0))();
  // JSON map { "1": "<utcIso>", "2": "<utcIso>", ... } tracking which
  // days of the current 7-day cycle have been claimed. Resets on a
  // streak break or cycle wrap (newStreak < oldStreak or newStreak %
  // 7 == 1).
  TextColumn get weeklyClaimsJson =>
      text().withDefault(const Constant('{}'))();
  /// Sync-engine timestamp — see [GameSettings.updatedAt].
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// =====================================================
// TABLE 9: Replays
// =====================================================
class Replays extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  IntColumn get score => integer()();
  IntColumn get shipLength => integer()();
  IntColumn get gameDurationSeconds => integer()();
  TextColumn get gameMode => text().withDefault(const Constant('classic'))();
  TextColumn get boardSize =>
      text().withDefault(const Constant('20x20'))(); // e.g., "20x20"
  TextColumn get replayData => text()(); // JSON encoded replay frames
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get recordedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

// =====================================================
// TABLE 10: Sync Queue (Pending items to sync to backend)
// =====================================================
class SyncQueue extends Table {
  TextColumn get id => text()();
  TextColumn get dataType =>
      text()(); // 'score', 'profile', 'preferences', 'achievement', etc.
  TextColumn get data => text()(); // JSON encoded data
  IntColumn get priority =>
      integer().withDefault(const Constant(2))(); // 0=critical, 1=high, 2=normal, 3=low
  IntColumn get status =>
      integer().withDefault(const Constant(0))(); // 0=pending, 1=syncing, 2=failed, 3=completed
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get queuedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// =====================================================
// TABLE 11: Cache Store (Offline cache with TTL)
// =====================================================
class CacheStore extends Table {
  TextColumn get key => text()();
  TextColumn get data => text()(); // JSON encoded data
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get ttlMillis => integer()(); // Time to live in milliseconds
  DateTimeColumn get expiresAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

// =====================================================
// TABLE: Leaderboard cache
// =====================================================
//
// Drift-cached snapshot of the server-rendered leaderboards. The
// SyncEngine doesn't drain these (they're read-only from the device's
// POV — the user's own score syncs via the settings/statistics tables
// and shows up here only after the backend's score-aggregation has
// landed). Refreshes are write-through replace operations from the
// LeaderboardService.
//
// `boardType` is the discriminator — 'global', 'weekly', 'daily',
// 'friends'. Each board can have N entries; we cache up to ~100 per
// board to keep the table size bounded.
class LeaderboardEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get boardType => text()();
  IntColumn get rank => integer()();
  TextColumn get userId => text()();
  TextColumn get username => text().nullable()();
  TextColumn get displayName => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  IntColumn get score => integer().withDefault(const Constant(0))();
  IntColumn get level => integer().withDefault(const Constant(1))();
  DateTimeColumn get achievedAt => dateTime().nullable()();
  IntColumn get totalGamesPlayed => integer().withDefault(const Constant(0))();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();
}

// Per-board metadata. One row per boardType holds the last refresh
// timestamp + the global "you are rank X of Y" the server returned so
// the UI can render an "Updated X ago" chip without having to scan
// every cached entry.
class LeaderboardMeta extends Table {
  TextColumn get boardType => text()();
  DateTimeColumn get lastRefreshedAt =>
      dateTime().withDefault(currentDateAndTime)();
  IntColumn get totalPlayers => integer().withDefault(const Constant(0))();
  IntColumn get currentUserRank => integer().nullable()();

  @override
  Set<Column> get primaryKey => {boardType};
}

// =====================================================
// TABLE: Tournament cache
// =====================================================
//
// Mirrors the server-rendered tournament lists locally so the screen
// has something to show offline. Like the leaderboard cache, the
// TournamentService writes through to these tables and the screen
// reads from them; no SyncEngine round-trip — tournaments are a
// server-side concept the device only consumes.
//
// `dataJson` holds the full Tournament model JSON verbatim so the
// existing Tournament.fromJson() consumer keeps working unchanged.
// `status` / `endDate` are duplicated as typed columns purely for
// fast filtering / ordering.
class TournamentsCache extends Table {
  TextColumn get id => text()(); // server Guid as string
  TextColumn get dataJson => text()();
  TextColumn get status =>
      text()(); // 'upcoming' | 'active' | 'ended' | 'completed'
  DateTimeColumn get endDate => dateTime()();
  // True iff this row was last seen in the "active" list (vs the
  // history list). Used to discriminate between the two list views
  // without re-parsing the JSON blob on every read.
  BoolColumn get isActiveList => boolean().withDefault(const Constant(false))();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class TournamentLeaderboardCache extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tournamentId => text()();
  IntColumn get rank => integer()();
  TextColumn get userId => text()();
  TextColumn get username => text().nullable()();
  TextColumn get displayName => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  IntColumn get bestScore => integer().withDefault(const Constant(0))();
  IntColumn get gamesPlayed => integer().withDefault(const Constant(0))();
  BoolColumn get prizeClaimed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();
}

class TournamentMeta extends Table {
  // metaKey discriminates the various per-resource staleness markers:
  //   'active'           — list of active tournaments
  //   'history'          — list of past tournaments
  //   'detail:{id}'      — single tournament detail refresh
  //   'leaderboard:{id}' — per-tournament leaderboard refresh
  TextColumn get metaKey => text()();
  DateTimeColumn get lastRefreshedAt =>
      dateTime().withDefault(currentDateAndTime)();
  IntColumn get currentUserRank => integer().nullable()();

  @override
  Set<Column> get primaryKey => {metaKey};
}

// =====================================================
// TABLE: Friends cache
// =====================================================
//
// Server-rendered friend graph mirrored locally. Cache-first reads
// give the screen something to show offline; mutations (send /
// accept / reject / remove) are live API calls — accepting a friend
// request that already 410'd server-side and queueing it for retry
// would be confusing for the user, so we keep these synchronous.

class FriendsCache extends Table {
  TextColumn get userId => text()(); // server Guid as string
  TextColumn get username => text().nullable()();
  TextColumn get displayName => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get status =>
      text().withDefault(const Constant('offline'))(); // online | offline | playing
  IntColumn get highScore => integer().withDefault(const Constant(0))();
  IntColumn get level => integer().withDefault(const Constant(1))();
  DateTimeColumn get friendsSince =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {userId};
}

class FriendRequestsCache extends Table {
  TextColumn get requestId => text()(); // server Guid as string
  TextColumn get fromUserId => text()();
  TextColumn get fromUsername => text().nullable()();
  TextColumn get fromDisplayName => text().nullable()();
  TextColumn get fromPhotoUrl => text().nullable()();
  DateTimeColumn get sentAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {requestId};
}

class FriendsMeta extends Table {
  // 'friends' | 'requests'
  TextColumn get metaKey => text()();
  DateTimeColumn get lastRefreshedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {metaKey};
}

// =====================================================
// TABLE 12: User Profile (for offline access)
// =====================================================
class UserProfile extends Table {
  TextColumn get id => text()();
  TextColumn get firebaseUid => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get displayName => text().nullable()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get providerId =>
      text().nullable()(); // 'google', 'apple', 'guest'
  BoolColumn get isGuest => boolean().withDefault(const Constant(true))();
  IntColumn get globalRank => integer().nullable()();
  IntColumn get weeklyRank => integer().nullable()();
  TextColumn get country => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastLoginAt =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// =====================================================
// Purchase History (for tracking)
// =====================================================
class PurchaseHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get purchaseId => text()();
  TextColumn get productId => text()();
  TextColumn get transactionId => text().nullable()();
  IntColumn get amount => integer()(); // Price in cents
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get status =>
      text()(); // 'pending', 'completed', 'failed', 'refunded'
  TextColumn get receiptData => text().nullable()();
  DateTimeColumn get purchasedAt => dateTime().withDefault(currentDateAndTime)();
}

// =====================================================
// TABLE: Player Progress (singleton — lifetime XP + level)
// =====================================================
// Offline-first lifetime progression, parallel to (and independent of) the
// per-season BattlePasses table. Single row (autoIncrement id, like
// Statistics). `totalXp` is the source of truth; `level` is derived from the
// PlayerLevel curve and stored for sync/display. SyncEngine pushes this to the
// backend's User.Experience/Level via the `player_progress` dataType.
@DataClassName('PlayerProgressRow')
class PlayerProgressTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get totalXp => integer().withDefault(const Constant(0))();
  IntColumn get level => integer().withDefault(const Constant(1))();
  /// Sync-engine timestamp — see [GameSettings.updatedAt].
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();
}

// =====================================================
// DATABASE CLASS
// =====================================================
@DriftDatabase(
  tables: [
    GameSettings,
    Statistics,
    Achievements,
    Coins,
    CoinTransactions,
    PremiumStatus,
    UnlockedItems,
    BattlePasses,
    DailyChallenges,
    WeeklyQuests,
    DailyBonusState,
    Replays,
    SyncQueue,
    CacheStore,
    UserProfile,
    PurchaseHistory,
    LeaderboardEntries,
    LeaderboardMeta,
    TournamentsCache,
    TournamentLeaderboardCache,
    TournamentMeta,
    FriendsCache,
    FriendRequestsCache,
    FriendsMeta,
    PlayerProgressTable,
  ],
  daos: [
    SettingsDao,
    GameDao,
    StoreDao,
    SyncDao,
    LeaderboardDao,
    TournamentDao,
    FriendsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 12;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Create indexes on initial database creation
      await _createIndexes();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // Add indexes for frequently queried columns
        await _createIndexes();
      }
      if (from < 3) {
        // v3: add the modelJson catch-all column to Statistics so the full
        // GameStatistics model can round-trip without the per-field name
        // translation that lost data on every save/load cycle.
        await m.addColumn(statistics, statistics.modelJson);
      }
      if (from < 4) {
        // v4: add `updatedAt` to every synced table so the sync engine
        // has a uniform "this row changed at X" signal independent of
        // the older / inconsistently-maintained `lastUpdated` columns.
        //
        // SQLite ALTER TABLE ADD COLUMN only accepts *constant*
        // defaults — `CURRENT_TIMESTAMP` is non-constant and gets
        // rejected. We add the column with a literal-0 default, then
        // backfill the actual now() value in a follow-up UPDATE so
        // existing rows aren't stuck at the epoch. New inserts pick
        // up the proper currentDateAndTime default from the regular
        // Drift companion path going forward.
        const tables = <String>[
          'game_settings',
          'statistics',
          'achievements',
          'coins',
          'coin_transactions',
          'premium_status',
          'unlocked_items',
          'battle_passes',
          'daily_challenges',
        ];
        for (final t in tables) {
          await customStatement(
            'ALTER TABLE "$t" ADD COLUMN "updated_at" INTEGER NOT NULL DEFAULT 0',
          );
          await customStatement(
            "UPDATE \"$t\" SET \"updated_at\" = CAST(strftime('%s', 'now') AS INTEGER)",
          );
        }
      }
      if (from < 5) {
        // v5: leaderboard cache + meta. Server-rendered leaderboards
        // are mirrored locally so the screen has something to show
        // when offline; refreshes are write-through replaces from
        // LeaderboardService.
        await m.createTable(leaderboardEntries);
        await m.createTable(leaderboardMeta);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_leaderboard_entries_board_rank '
          'ON leaderboard_entries(board_type, rank)',
        );
      }
      if (from < 6) {
        // v6: tournament cache (list + per-tournament leaderboard +
        // staleness meta). Same pattern as the leaderboard cache.
        await m.createTable(tournamentsCache);
        await m.createTable(tournamentLeaderboardCache);
        await m.createTable(tournamentMeta);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tournaments_cache_active_end '
          'ON tournaments_cache(is_active_list, end_date)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_tournament_leaderboard_tid_rank '
          'ON tournament_leaderboard_cache(tournament_id, rank)',
        );
      }
      if (from < 7) {
        // v7: friends cache (friend list + friend requests +
        // staleness meta). Mutations are live API calls, the cache
        // only serves the read path.
        await m.createTable(friendsCache);
        await m.createTable(friendRequestsCache);
        await m.createTable(friendsMeta);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_friend_requests_from_user '
          'ON friend_requests_cache(from_user_id)',
        );
      }
      if (from < 8) {
        // v8: weekly quests claim mirror, analogous to daily_challenges.
        // Sync engine writes here; backend's UserWeeklyQuestClaim table
        // is the canonical sync destination. The legacy
        // /weekly-quests/progress endpoint still maintains the
        // gameplay-side UserWeeklyQuest table; the two coexist.
        await m.createTable(weeklyQuests);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_weekly_quests_week_start '
          'ON weekly_quests(week_start_date)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_quests_quest_id '
          'ON weekly_quests(quest_id)',
        );
      }
      if (from < 9) {
        // v9: daily bonus state singleton. Drift-first replacement for
        // the legacy SharedPreferences-only gate ('last_daily_bonus_claim_date',
        // 'daily_bonuses'). SyncEngine pushes the snapshot to the
        // backend's DailyLoginBonus table.
        await m.createTable(dailyBonusState);
      }
      if (from < 10) {
        // v10: lifetime player progression singleton (XP + level), parallel
        // to the per-season battle pass. SyncEngine pushes it to the
        // backend's User.Experience/Level via the player_progress dataType.
        await m.createTable(playerProgressTable);
      }
      if (from < 11) {
        // v11: daily_challenges had no unique index on challenge_id, so
        // upsertDailyChallenge (insertOnConflictUpdate) kept INSERTing new
        // rows instead of upserting — once offline-first progress writes
        // started, duplicate rows piled up and the sync batch shipped the
        // same challenge_id twice, 500ing the backend. Dedupe (keep the
        // latest row per challenge_id) then add the unique index so upserts
        // behave like weekly_quests.
        await customStatement(
          'DELETE FROM daily_challenges WHERE id NOT IN '
          '(SELECT MAX(id) FROM daily_challenges GROUP BY challenge_id)',
        );
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_challenges_challenge_id '
          'ON daily_challenges(challenge_id)',
        );
      }
      // v12: rebrand entity columns to the 'ship_*' length names. The schema is
      // produced fresh by onCreate; this rebrand ships with a clean dev-data
      // reset (fresh install), so no in-place column migration is required.
    },
  );

  /// Create indexes for better query performance
  Future<void> _createIndexes() async {
    // SyncQueue indexes for faster pending item queries
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_priority ON sync_queue(priority)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_queued_at ON sync_queue(queued_at)',
    );

    // DailyChallenges index for date-based queries
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_daily_challenges_date ON daily_challenges(challenge_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_daily_challenges_expires ON daily_challenges(expires_at)',
    );
    // Unique per challenge so upsertDailyChallenge (insertOnConflictUpdate)
    // updates in place instead of inserting duplicate rows — matches the
    // weekly_quests setup.
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_challenges_challenge_id ON daily_challenges(challenge_id)',
    );

    // WeeklyQuests index for week-based queries + unique quest id
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_weekly_quests_week_start ON weekly_quests(week_start_date)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_quests_quest_id ON weekly_quests(quest_id)',
    );

    // CoinTransactions index for timestamp-based queries
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_coin_transactions_created ON coin_transactions(created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_coin_transactions_type ON coin_transactions(type)',
    );

    // Achievements index for unlock status queries
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_achievements_unlocked ON achievements(is_unlocked)',
    );

    // UnlockedItems index for item type queries
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_unlocked_items_type ON unlocked_items(item_type)',
    );

    // Replays index for sorting by date
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_replays_recorded ON replays(recorded_at)',
    );

    // CacheStore index for expiration checks
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cache_store_expires ON cache_store(expires_at)',
    );
  }

  /// Enqueue an outbox row signaling that a synced entity has changed.
  /// Call this from inside the same Drift transaction as the data
  /// write so the row and its outbox marker land atomically.
  ///
  /// [dataType] is one of [SyncDataType]'s constants. [entityKey] is
  /// the stable identifier of the row (e.g. `'settings:1'`,
  /// `'achievement:first_blood'`). [payload] is optional — for
  /// snapshot types the SyncEngine reads the latest row at drain
  /// time, so we can skip the payload; for event-typed rows we
  /// freeze the payload here because the row's content may change
  /// before the drain.
  Future<void> enqueueSyncOutbox({
    required String dataType,
    required String entityKey,
    Map<String, dynamic>? payload,
    int priority = 2,
  }) async {
    // UUID-suffixed primary key rather than microsecondsSinceEpoch:
    // two enqueues for the same entity key in the same microsecond
    // used to share an id, and InsertMode.insertOrIgnore would drop
    // the second one. UUIDs make collisions effectively impossible.
    final id = '$dataType:$entityKey:${_outboxIdGen.v4()}';
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        id: id,
        dataType: dataType,
        data: jsonEncode({
          'entityKey': entityKey,
          'payload': ?payload,
        }),
        priority: Value(priority),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Initialize default data if tables are empty
  Future<void> initializeDefaults() async {
    // Initialize game settings if not exists
    final existingSettings = await select(gameSettings).getSingleOrNull();
    if (existingSettings == null) {
      await into(gameSettings).insert(GameSettingsCompanion.insert());
    }

    // Initialize statistics if not exists
    final existingStats = await select(statistics).getSingleOrNull();
    if (existingStats == null) {
      await into(statistics).insert(StatisticsCompanion.insert());
    }

    // Initialize coins if not exists
    final existingCoins = await select(coins).getSingleOrNull();
    if (existingCoins == null) {
      await into(coins).insert(CoinsCompanion.insert());
    }

    // Initialize premium status if not exists
    final existingPremium = await select(premiumStatus).getSingleOrNull();
    if (existingPremium == null) {
      await into(premiumStatus).insert(PremiumStatusCompanion.insert());
    }
  }

  /// Clear all data (for logout/reset). Wipes per-user tables AND the
  /// drift-cached views (leaderboards, tournaments) so an account
  /// switch on the same device doesn't show the previous user's
  /// join states, friend ranks, or any per-user-flagged rows.
  Future<void> clearAllData() async {
    await transaction(() async {
      await delete(gameSettings).go();
      await delete(statistics).go();
      await delete(achievements).go();
      await delete(coins).go();
      await delete(coinTransactions).go();
      await delete(premiumStatus).go();
      await delete(unlockedItems).go();
      await delete(battlePasses).go();
      await delete(dailyChallenges).go();
      await delete(replays).go();
      await delete(syncQueue).go();
      await delete(cacheStore).go();
      await delete(userProfile).go();
      await delete(purchaseHistory).go();
      // Drift-cached server views — these mix in per-user fields
      // (currentUserRank, isJoined, …) so they must be cleared too.
      await delete(leaderboardEntries).go();
      await delete(leaderboardMeta).go();
      await delete(tournamentsCache).go();
      await delete(tournamentLeaderboardCache).go();
      await delete(tournamentMeta).go();
      // Friend graph is per-user by definition — must not leak
      // across an account switch on the same device.
      await delete(friendsCache).go();
      await delete(friendRequestsCache).go();
      await delete(friendsMeta).go();
    });

    // Reinitialize defaults
    await initializeDefaults();
  }
}

/// Opens a connection to the SQLite database
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'cosmo_strike.db'));
    return NativeDatabase.createInBackground(file);
  });
}
