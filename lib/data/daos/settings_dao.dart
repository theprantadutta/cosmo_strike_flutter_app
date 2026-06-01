import 'package:drift/drift.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [GameSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  /// Watch settings changes for reactive UI
  Stream<GameSetting?> watchSettings() => select(gameSettings).watchSingleOrNull();

  /// Get current settings
  Future<GameSetting?> getSettings() => select(gameSettings).getSingleOrNull();

  /// Apply a partial update to the singleton settings row inside a
  /// transaction, bump both timestamps, and enqueue an outbox row so
  /// the SyncEngine knows the user's preferences need to round-trip
  /// to the backend.
  Future<void> _writeSettings(GameSettingsCompanion patch) async {
    final now = DateTime.now();
    await transaction(() async {
      await (update(gameSettings)..where((t) => t.id.equals(1))).write(
        patch.copyWith(
          lastUpdated: Value(now),
          updatedAt: Value(now),
        ),
      );
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.settings,
        entityKey: 'settings:1',
      );
    });
  }

  /// Update theme index
  Future<void> updateTheme(int themeIndex) =>
      _writeSettings(GameSettingsCompanion(themeIndex: Value(themeIndex)));

  /// Update sound enabled
  Future<void> updateSoundEnabled(bool enabled) =>
      _writeSettings(GameSettingsCompanion(soundEnabled: Value(enabled)));

  /// Update music enabled
  Future<void> updateMusicEnabled(bool enabled) =>
      _writeSettings(GameSettingsCompanion(musicEnabled: Value(enabled)));

  /// Update D-Pad enabled
  Future<void> updateDPadEnabled(bool enabled) =>
      _writeSettings(GameSettingsCompanion(dPadEnabled: Value(enabled)));

  /// Update D-Pad position
  Future<void> updateDPadPosition(int positionIndex) =>
      _writeSettings(
          GameSettingsCompanion(dPadPositionIndex: Value(positionIndex)));

  /// Update board size
  Future<void> updateBoardSize(int boardSizeIndex) =>
      _writeSettings(GameSettingsCompanion(boardSizeIndex: Value(boardSizeIndex)));

  /// Update high score
  Future<void> updateHighScore(int score) =>
      _writeSettings(GameSettingsCompanion(highScore: Value(score)));

  /// Update crash feedback duration
  Future<void> updateCrashFeedbackDuration(int seconds) =>
      _writeSettings(
          GameSettingsCompanion(crashFeedbackDurationSeconds: Value(seconds)));

  /// Update trail system enabled
  Future<void> updateTrailSystemEnabled(bool enabled) =>
      _writeSettings(
          GameSettingsCompanion(trailSystemEnabled: Value(enabled)));

  /// Update screen shake enabled
  Future<void> updateScreenShakeEnabled(bool enabled) =>
      _writeSettings(
          GameSettingsCompanion(screenShakeEnabled: Value(enabled)));

  /// Update selected skin
  Future<void> updateSelectedSkin(String? skinId) =>
      _writeSettings(GameSettingsCompanion(selectedSkinId: Value(skinId)));

  /// Update selected trail
  Future<void> updateSelectedTrail(String? trailId) =>
      _writeSettings(GameSettingsCompanion(selectedTrailId: Value(trailId)));

  /// Cloud-snapshot apply path. Writes the singleton settings row
  /// without enqueueing an outbox marker so a first-sign-in restore
  /// doesn't echo the data back as a push. Skips the timestamp bump
  /// — the patch carries the cloud's UpdatedAt verbatim.
  Future<void> applySettingsSnapshot(GameSettingsCompanion patch) async {
    await into(gameSettings).insertOnConflictUpdate(
      patch.copyWith(id: const Value(1)),
    );
  }

  /// Reset settings to defaults. Outbox row queues a fresh sync so
  /// the backend picks up the reset.
  Future<void> resetSettings() async {
    await transaction(() async {
      await delete(gameSettings).go();
      await into(gameSettings).insert(GameSettingsCompanion.insert());
      await attachedDatabase.enqueueSyncOutbox(
        dataType: SyncDataType.settings,
        entityKey: 'settings:1',
      );
    });
  }
}
