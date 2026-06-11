import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/data/daos/settings_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/game_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/store_dao.dart';
import 'package:cosmo_strike_flutter_app/data/daos/sync_dao.dart';
import 'package:cosmo_strike_flutter_app/models/game_replay.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

class StorageService {
  static StorageService? _instance;
  AppDatabase? _database;
  SettingsDao? _settingsDao;
  GameDao? _gameDao;
  StoreDao? _storeDao;
  SyncDao? _syncDao;

  StorageService._internal();

  factory StorageService() {
    _instance ??= StorageService._internal();
    return _instance!;
  }

  /// Initialize the storage service with database
  Future<void> initialize(AppDatabase database) async {
    _database = database;
    _settingsDao = database.settingsDao;
    _gameDao = database.gameDao;
    _storeDao = database.storeDao;
    _syncDao = database.syncDao;

    // Initialize default data
    await _database!.initializeDefaults();
  }

  /// Check if initialized
  bool get isInitialized => _database != null;

  /// Direct DAO access for callers that need to write rows not covered
  /// by the higher-level helpers above (e.g. daily-challenge claim
  /// rows). Throws if accessed before [initialize].
  GameDao get gameDao => _gameDao!;

  /// Direct StoreDao access — used by CoinsCubit.earnCoins so client-side
  /// coin gains propagate to the Drift coins table + sync engine outbox.
  /// Without this, the gain stays in CoinsCubit's SharedPreferences only
  /// and the backend UserCoinBalance falls behind.
  StoreDao get storeDao => _storeDao!;

  // ==================== High Score ====================

  Future<int> getHighScore() async {
    final settings = await _settingsDao?.getSettings();
    return settings?.highScore ?? 0;
  }

  /// Persist a new high score. Never-decrease guard: if the incoming
  /// [score] is not strictly higher than the value already on disk, the
  /// write is skipped. This is the storage-boundary defense against
  /// regressions like the GameCubit reading a stale (loading-state)
  /// cubit value at game start, computing `isNewHighScore` against that
  /// stale anchor, and then overwriting a real record with a lower one.
  ///
  /// Use [resetHighScore] for legitimate clears (e.g. resetStatistics).
  Future<void> saveHighScore(int score) async {
    final current = await getHighScore();
    if (score <= current) return;
    await _settingsDao?.updateHighScore(score);
  }

  /// Explicit reset path that bypasses the never-decrease guard in
  /// [saveHighScore]. Only callers that genuinely want to clear the
  /// stored high score (resetStatistics, user-initiated wipe) should
  /// use this.
  Future<void> resetHighScore() async {
    await _settingsDao?.updateHighScore(0);
  }

  // ==================== Theme ====================

  Future<GameTheme> getSelectedTheme() async {
    final settings = await _settingsDao?.getSettings();
    final themeIndex = settings?.themeIndex ?? 0;
    return GameTheme.values[themeIndex.clamp(0, GameTheme.values.length - 1)];
  }

  Future<void> saveSelectedTheme(GameTheme theme) async {
    await _settingsDao?.updateTheme(theme.index);
  }

  // ==================== Sound Settings ====================

  Future<bool> isSoundEnabled() async {
    final settings = await _settingsDao?.getSettings();
    return settings?.soundEnabled ?? true;
  }

  Future<void> setSoundEnabled(bool enabled) async {
    await _settingsDao?.updateSoundEnabled(enabled);
  }

  Future<bool> isMusicEnabled() async {
    final settings = await _settingsDao?.getSettings();
    return settings?.musicEnabled ?? true;
  }

  Future<void> setMusicEnabled(bool enabled) async {
    await _settingsDao?.updateMusicEnabled(enabled);
  }

  // ==================== Board Size ====================

  Future<BoardSize> getBoardSize() async {
    final settings = await _settingsDao?.getSettings();
    return _resolveBoardSize(settings?.boardSizeIndex ?? 1);
  }

  Future<void> saveBoardSize(BoardSize boardSize) async {
    // Persist the board's WIDTH (a stable identifier), not its position in
    // availableBoardSizes. Index-based storage silently remapped everyone's
    // saved board whenever that list was reordered/trimmed. Widths are >= 15
    // and legacy index values are 0..6, so the ranges never overlap and old
    // saves still resolve correctly (see [_resolveBoardSize]).
    await _settingsDao?.updateBoardSize(boardSize.width);
  }

  /// Resolve a stored board-size value to a [BoardSize]. Values >= 15 are a
  /// board WIDTH (the stable format written by [saveBoardSize]); smaller values
  /// are a legacy list index. Unknown values fall back to Classic.
  BoardSize _resolveBoardSize(int stored) {
    final sizes = GameConstants.availableBoardSizes;
    if (stored >= 15) {
      return sizes.firstWhere(
        (s) => s.width == stored,
        orElse: () => BoardSize.classic,
      );
    }
    return sizes[stored.clamp(0, sizes.length - 1)];
  }

  // ==================== Crash Feedback ====================

  Future<Duration> getCrashFeedbackDuration() async {
    final settings = await _settingsDao?.getSettings();
    final durationSeconds = settings?.crashFeedbackDurationSeconds ??
        GameConstants.defaultCrashFeedbackDuration.inSeconds;
    return Duration(seconds: durationSeconds);
  }

  Future<void> saveCrashFeedbackDuration(Duration duration) async {
    await _settingsDao?.updateCrashFeedbackDuration(duration.inSeconds);
  }

  // ==================== D-Pad Settings ====================

  Future<bool> isDPadEnabled() async {
    final settings = await _settingsDao?.getSettings();
    return settings?.dPadEnabled ?? false;
  }

  Future<void> setDPadEnabled(bool enabled) async {
    await _settingsDao?.updateDPadEnabled(enabled);
  }

  Future<DPadPosition> getDPadPosition() async {
    final settings = await _settingsDao?.getSettings();
    final positionIndex = settings?.dPadPositionIndex ?? 1;
    return DPadPosition.values[positionIndex.clamp(
      0,
      DPadPosition.values.length - 1,
    )];
  }

  Future<void> setDPadPosition(DPadPosition position) async {
    await _settingsDao?.updateDPadPosition(position.index);
  }

  // ==================== Trail System ====================

  Future<bool> isTrailSystemEnabled() async {
    final settings = await _settingsDao?.getSettings();
    return settings?.trailSystemEnabled ?? false;
  }

  Future<void> setTrailSystemEnabled(bool enabled) async {
    await _settingsDao?.updateTrailSystemEnabled(enabled);
  }

  // ==================== Screen Shake ====================

  Future<bool> isScreenShakeEnabled() async {
    final settings = await _settingsDao?.getSettings();
    return settings?.screenShakeEnabled ?? false;
  }

  Future<void> setScreenShakeEnabled(bool enabled) async {
    await _settingsDao?.updateScreenShakeEnabled(enabled);
  }

  // ==================== Haptics ====================

  Future<bool> isHapticsEnabled() async {
    final settings = await _settingsDao?.getSettings();
    return settings?.hapticsEnabled ?? true;
  }

  Future<void> setHapticsEnabled(bool enabled) async {
    await _settingsDao?.updateHapticsEnabled(enabled);
  }

  // ==================== Statistics ====================

  Future<String?> getStatistics() async {
    return await _gameDao?.getStatisticsAsJson();
  }

  Future<void> saveStatistics(String statisticsJson) async {
    await _gameDao?.updateStatisticsFromJson(statisticsJson);
  }

  // ==================== Achievements ====================

  Future<String?> getAchievements() async {
    return await _gameDao?.getAchievementsAsJson();
  }

  Future<void> saveAchievements(String achievementsJson) async {
    // Local-save path: enqueue outbox rows so AchievementService progress
    // actually rides the SyncEngine drain. loadAchievementsFromJson's
    // diff check ensures only rows whose synced fields changed get queued.
    await _gameDao?.loadAchievementsFromJson(
      achievementsJson,
      enqueueSync: true,
    );
  }

  /// Seed the Drift achievements catalog from the client's default
  /// definitions. Idempotent (insert-or-ignore on the id primary key) so
  /// it's safe to call on every cold start. Without this seed a fresh
  /// install's `achievements` table starts empty, and the Map-format
  /// branch of [GameDao.loadAchievementsFromJson] silently skips every
  /// row (existing == null guard), so [_saveProgress] in AchievementService
  /// never enqueues a sync_outbox row — which is why a freshly-installed
  /// user's achievements never reached the dashboard.
  Future<void> seedAchievementCatalog(
    List<({
      String id,
      String title,
      String description,
      String category,
      int targetValue,
      int coinReward,
      int iconCodePoint,
    })> defaults,
  ) async {
    if (_gameDao == null) return;
    final companions = defaults.map((d) => AchievementsCompanion(
          id: Value(d.id),
          name: Value(d.title),
          description: Value(d.description),
          category: Value(d.category),
          currentProgress: const Value(0),
          targetProgress: Value(d.targetValue),
          isUnlocked: const Value(false),
          rewardCoins: Value(d.coinReward),
          rewardClaimed: const Value(false),
          iconName: Value(d.iconCodePoint.toString()),
          isSecret: const Value(false),
        ));
    await _gameDao!.seedDefaultAchievementsIfMissing(companions);
  }

  // ==================== Replays ====================

  Future<void> saveReplay(String replayId, String replayJson) async {
    final data = json.decode(replayJson) as Map<String, dynamic>;
    await _gameDao?.saveReplay(ReplaysCompanion(
      id: Value(replayId),
      name: Value(data['name']),
      score: Value(data['score'] ?? 0),
      shipLength: Value(data['shipLength'] ?? 0),
      gameDurationSeconds: Value(data['gameDurationSeconds'] ?? 0),
      gameMode: Value(data['gameMode'] ?? 'classic'),
      boardSize: Value(data['boardSize'] ?? '20x20'),
      replayData: Value(json.encode(data['replayData'] ?? [])),
      isFavorite: Value(data['isFavorite'] ?? false),
    ));
  }

  Future<String?> getReplay(String replayId) async {
    final replay = await _gameDao?.getReplay(replayId);
    if (replay == null) return null;
    // Drift stores the full GameReplay JSON (frames + metadata) in
    // replayData. Earlier this method wrapped that string in a second
    // envelope — but every caller (ReplaysScreen, ReplayViewerScreen)
    // passes the result straight into GameReplay.fromJsonString which
    // expects the *inner* shape. The wrapper made fromJson see no
    // frames / no totalFrames / no playerName at the top level, so
    // every freshly-saved replay deserialized as empty and was then
    // auto-deleted by the screen's 0-frame sanitize step.
    return replay.replayData;
  }

  Future<List<String>> getReplayKeys() async {
    return await _gameDao?.getReplayKeys() ?? [];
  }

  /// Reactive stream of all stored replays as GameReplay models, sorted
  /// newest-first by recordedAt. Drift wires this to the underlying
  /// `replays` table so any insert / delete (e.g. saving a fresh replay
  /// from the game-over flow, or the screen's auto-cleanup of bad rows)
  /// emits a new list immediately — the Replays screen subscribes to
  /// this instead of doing a one-shot DB read on entry, so it always
  /// shows the latest data without needing a manual refresh.
  Stream<List<GameReplay>> watchReplays() {
    final dao = _gameDao;
    if (dao == null) return const Stream.empty();
    return dao.watchReplays().map((rows) {
      final out = <GameReplay>[];
      for (final row in rows) {
        try {
          out.add(GameReplay.fromJsonString(row.replayData));
        } catch (_) {
          // Malformed row — skip it here; the screen's sanitize pass
          // will delete it on the next sweep.
        }
      }
      return out;
    });
  }

  Future<void> deleteReplay(String replayId) async {
    await _gameDao?.deleteReplay(replayId);
  }

  // ==================== Premium ====================

  Future<bool> isPremiumActive() async {
    return await _storeDao?.isPremiumActive() ?? false;
  }

  Future<void> setPremiumActive(bool active) async {
    await _storeDao?.setPremiumActive(active);
  }

  Future<String?> getPremiumExpirationDate() async {
    return await _storeDao?.getPremiumExpirationDate();
  }

  Future<void> setPremiumExpirationDate(String? date) async {
    DateTime? expirationDate;
    if (date != null) {
      expirationDate = DateTime.tryParse(date);
    }
    await _storeDao?.setPremiumActive(
      expirationDate != null && DateTime.now().isBefore(expirationDate),
      expirationDate: expirationDate,
    );
  }

  // ==================== Selected Skin/Trail ====================

  Future<String?> getSelectedSkinId() async {
    final settings = await _settingsDao?.getSettings();
    return settings?.selectedSkinId;
  }

  Future<void> setSelectedSkinId(String? skinId) async {
    await _settingsDao?.updateSelectedSkin(skinId);
  }

  Future<String?> getSelectedTrailId() async {
    final settings = await _settingsDao?.getSettings();
    return settings?.selectedTrailId;
  }

  Future<void> setSelectedTrailId(String? trailId) async {
    await _settingsDao?.updateSelectedTrail(trailId);
  }

  // ==================== Unlocked Items ====================

  Future<List<String>> getUnlockedThemes() async {
    return await _storeDao?.getUnlockedThemes() ?? [];
  }

  Future<void> setUnlockedThemes(List<String> themes) async {
    await _storeDao?.setUnlockedThemes(themes);
  }

  Future<List<String>> getUnlockedSkins() async {
    return await _storeDao?.getUnlockedSkins() ?? [];
  }

  Future<void> setUnlockedSkins(List<String> skins) async {
    await _storeDao?.setUnlockedSkins(skins);
  }

  Future<List<String>> getUnlockedTrails() async {
    return await _storeDao?.getUnlockedTrails() ?? [];
  }

  Future<void> setUnlockedTrails(List<String> trails) async {
    await _storeDao?.setUnlockedTrails(trails);
  }

  Future<List<String>> getUnlockedPowerUps() async {
    return await _storeDao?.getUnlockedPowerUps() ?? [];
  }

  Future<void> setUnlockedPowerUps(List<String> powerUps) async {
    await _storeDao?.setUnlockedPowerUps(powerUps);
  }

  Future<List<String>> getUnlockedBoardSizes() async {
    return await _storeDao?.getUnlockedBoardSizes() ?? [];
  }

  Future<void> setUnlockedBoardSizes(List<String> boardSizes) async {
    await _storeDao?.setUnlockedBoardSizes(boardSizes);
  }

  Future<List<String>> getUnlockedGameModes() async {
    return await _storeDao?.getUnlockedGameModes() ?? [];
  }

  Future<void> setUnlockedGameModes(List<String> gameModes) async {
    await _storeDao?.setUnlockedGameModes(gameModes);
  }

  Future<List<String>> getUnlockedBundles() async {
    return await _storeDao?.getUnlockedBundles() ?? [];
  }

  /// Single-item unlock (additive, idempotent). Preferred over
  /// setUnlockedXxx(fullSet) for the "user just unlocked one new item"
  /// case — the wipe-and-reinsert path queues every owned item to the
  /// outbox, not just the new one.
  Future<void> unlockItem(
    String itemId,
    String itemType, {
    String? unlockedBy,
  }) async {
    await _storeDao?.unlockItem(itemId, itemType, unlockedBy: unlockedBy);
  }

  // Server-apply (merge-only, no outbox enqueue). Use these from
  // PremiumCubit._applyBackendEntitlements so refreshing entitlements
  // doesn't echo back to the server or delete locally-owned items
  // unknown to /purchases/premium-content.
  Future<void> applyUnlockedThemesFromServer(List<String> ids) async {
    await _storeDao?.applyUnlockedThemesFromServer(ids);
  }

  Future<void> applyUnlockedSkinsFromServer(List<String> ids) async {
    await _storeDao?.applyUnlockedSkinsFromServer(ids);
  }

  Future<void> applyUnlockedTrailsFromServer(List<String> ids) async {
    await _storeDao?.applyUnlockedTrailsFromServer(ids);
  }

  Future<void> applyUnlockedBundlesFromServer(List<String> ids) async {
    await _storeDao?.applyUnlockedBundlesFromServer(ids);
  }

  Future<void> setUnlockedBundles(List<String> bundles) async {
    await _storeDao?.setUnlockedBundles(bundles);
  }

  // ==================== Coins ====================

  Future<int> getCoins() async {
    return await _storeDao?.getCoinBalance() ?? 0;
  }

  Future<void> setCoins(int coins) async {
    await _storeDao?.setCoinBalance(coins);
  }

  // ==================== Battle Pass ====================

  Future<String?> getBattlePassData() async {
    return await _storeDao?.getBattlePassData();
  }

  Future<void> setBattlePassData(String? data) async {
    // Local-save path: enqueue an outbox row so BattlePassCubit
    // progress rides the SyncEngine drain.
    await _storeDao?.setBattlePassData(data, enqueueSync: true);
  }

  Future<DateTime?> getLastPlayDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = prefs.getString('last_play_date');
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  // ==================== Game Mode ====================
  // Lives in the Drift settings row (synced to the backend). The old
  // build stored it in SharedPreferences only — migrated one-shot below.

  static const String _gameModeKey = 'selected_game_mode';
  static const String _gameModePromptedKey = 'game_mode_first_launch_prompted';

  Future<GameMode> getGameMode() async {
    // One-time legacy migration: pre-v3 builds stored the mode's DISPLAY
    // name (GameMode.name is shadowed — 'Classic', 'Zen Mode', …) in
    // SharedPreferences and never synced it. Move it into Drift (which
    // also enqueues the first sync push) and drop the old key.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_gameModeKey);
    if (legacy != null) {
      var mode = GameMode.classic;
      for (final m in GameMode.values) {
        if (m.name == legacy) {
          mode = m;
          break;
        }
      }
      await _settingsDao?.updateGameMode(mode.index);
      await prefs.remove(_gameModeKey);
      return mode;
    }

    final settings = await _settingsDao?.getSettings();
    final idx =
        (settings?.gameModeIndex ?? 0).clamp(0, GameMode.values.length - 1);
    return GameMode.values[idx];
  }

  Future<void> saveGameMode(GameMode mode) async {
    await _settingsDao?.updateGameMode(mode.index);
  }

  Future<bool> hasGameModeBeenPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_gameModePromptedKey) ?? false;
  }

  Future<void> markGameModePrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_gameModePromptedKey, true);
  }

  Future<void> saveLastPlayDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_play_date', date.toIso8601String());
  }

  Future<String?> getCachedSeasonJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('battle_pass_season');
  }

  Future<void> setCachedSeasonJson(String? seasonJson) async {
    final prefs = await SharedPreferences.getInstance();
    if (seasonJson == null) {
      await prefs.remove('battle_pass_season');
    } else {
      await prefs.setString('battle_pass_season', seasonJson);
    }
  }

  // ==================== Purchase History ====================

  Future<List<String>> getPurchaseHistory() async {
    return await _storeDao?.getPurchaseHistoryJson() ?? [];
  }

  Future<void> addPurchaseToHistory(String purchaseJson) async {
    await _storeDao?.addPurchaseFromJson(purchaseJson);
  }

  // ==================== Sync Queue ====================

  Future<List<Map<String, dynamic>>> getSyncQueue() async {
    return await _syncDao?.getSyncQueueAsMaps() ?? [];
  }

  Future<void> saveSyncQueue(List<Map<String, dynamic>> queue) async {
    await _syncDao?.saveSyncQueueFromMaps(queue);
  }

  Future<Map<String, dynamic>?> getSyncQueueMeta() async {
    // Sync metadata is now part of the sync queue items
    final pending = await _syncDao?.getPendingSyncCount() ?? 0;
    final failed = await _syncDao?.getFailedSyncCount() ?? 0;
    return {
      'pendingCount': pending,
      'failedCount': failed,
    };
  }

  Future<void> saveSyncQueueMeta(Map<String, dynamic> meta) async {
    // Metadata is managed automatically through sync queue
  }

  Future<void> clearSyncQueue() async {
    await _syncDao?.clearSyncQueue();
  }

  // ==================== Local Scores Queue ====================

  Future<List<Map<String, dynamic>>> getPendingLocalScores() async {
    final items = await _syncDao?.getSyncQueueAsMaps() ?? [];
    return items.where((item) => item['dataType'] == 'score').toList();
  }

  Future<void> addPendingLocalScore(Map<String, dynamic> score) async {
    final id = 'score_${DateTime.now().millisecondsSinceEpoch}';
    await _syncDao?.addToSyncQueue(
      id: id,
      dataType: 'score',
      data: score,
      priority: 1, // High priority
    );
  }

  Future<void> clearPendingLocalScores() async {
    final items = await _syncDao?.getSyncQueueAsMaps() ?? [];
    for (final item in items) {
      if (item['dataType'] == 'score') {
        await _syncDao?.removeSyncItem(item['id']);
      }
    }
  }

  Future<void> removePendingLocalScores(List<String> ids) async {
    for (final id in ids) {
      await _syncDao?.removeSyncItem(id);
    }
  }

  // ==================== Trial Data ====================

  Future<Map<String, dynamic>> getTrialData() async {
    return await _storeDao?.getTrialData() ?? {
      'isOnTrial': false,
      'trialStartDate': null,
      'trialEndDate': null,
    };
  }

  Future<void> setTrialData({
    required bool isOnTrial,
    DateTime? trialStartDate,
    DateTime? trialEndDate,
  }) async {
    await _storeDao?.setTrialData(
      isOnTrial: isOnTrial,
      trialStartDate: trialStartDate,
      trialEndDate: trialEndDate,
    );
  }

  // ==================== Tournament Entries ====================

  Future<Map<String, int>> getTournamentEntries() async {
    return await _storeDao?.getTournamentEntries() ?? {
      'bronze': 0,
      'silver': 0,
      'gold': 0,
    };
  }

  Future<void> setTournamentEntries({
    required int bronze,
    required int silver,
    required int gold,
  }) async {
    await _storeDao?.setTournamentEntries(
      bronze: bronze,
      silver: silver,
      gold: gold,
    );
  }

  // ==================== Clear All Data ====================

  Future<void> clearAllData() async {
    await _database?.clearAllData();
  }

  // ==================== Watch Streams (Reactive) ====================

  /// Watch settings for reactive UI updates
  Stream<GameSetting?> watchSettings() {
    return _settingsDao?.watchSettings() ?? const Stream.empty();
  }

  /// Watch coin balance for reactive UI updates
  Stream<int> watchCoinBalance() {
    return _storeDao?.watchCoinBalance() ?? const Stream.empty();
  }

  /// Watch statistics for reactive UI updates
  Stream<Statistic?> watchStatistics() {
    return _gameDao?.watchStatistics() ?? const Stream.empty();
  }

  /// Watch achievements for reactive UI updates
  Stream<List<Achievement>> watchAchievements() {
    return _gameDao?.watchAchievements() ?? const Stream.empty();
  }

  /// Watch pending sync items
  Stream<List<SyncQueueData>> watchPendingSyncItems() {
    return _syncDao?.watchPendingSyncItems() ?? const Stream.empty();
  }
}
