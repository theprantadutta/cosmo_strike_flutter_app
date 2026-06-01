import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/models/player_level.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Owns the player's **lifetime** XP + level progression — persistent across
/// seasons and independent of the battle pass.
///
/// Offline-first: XP is buffered during gameplay then flushed to Drift via
/// [GameDao.addPlayerXp], which enqueues a `player_progress` sync outbox row in
/// the same transaction. The SyncEngine pushes the snapshot to the backend's
/// `User.Experience`/`Level`; a cloud restore writes straight to Drift and the
/// Drift watch keeps this service's in-memory state in lock-step.
///
/// Every XP source in the app funnels through [BattlePassCubit.bufferXP] /
/// [BattlePassCubit.flushXP], which forward here — so this service sees the
/// same events the battle pass does, and keeps accruing past the battle-pass
/// max tier.
class ProgressionService extends ChangeNotifier {
  static final ProgressionService _instance = ProgressionService._internal();
  factory ProgressionService() => _instance;
  ProgressionService._internal();

  final StorageService _storageService = StorageService();

  PlayerProgress _progress = PlayerProgress.initial;
  bool _initialized = false;
  StreamSubscription<PlayerProgressRow?>? _watch;

  // XP buffered during a play session, flushed once at game end (mirrors the
  // battle-pass buffer so a burst of mid-game grants collapses to one write).
  int _bufferedXp = 0;

  /// Fires the new level whenever a flush crosses a level threshold. The UI
  /// listens to show the level-up celebration. Cloud-restore level jumps do
  /// NOT fire here (only real gameplay grants), so reinstalling doesn't pop a
  /// spurious celebration.
  final StreamController<int> _levelUps = StreamController<int>.broadcast();
  Stream<int> get levelUps => _levelUps.stream;

  // A level-up celebration that hasn't been shown yet. Set on flush, drained
  // by the home screen — survives the game-over → home navigation so a
  // late listener (the home screen mounting after the level-up fired during
  // post-game sync) still gets to show the popup.
  int? _pendingLevelUp;
  int? get pendingLevelUp => _pendingLevelUp;
  void clearPendingLevelUp() => _pendingLevelUp = null;

  PlayerProgress get progress => _progress;
  int get level => _progress.level;
  int get totalXp => _progress.totalXp;
  int get xpIntoLevel => _progress.xpIntoLevel;
  int get xpForNextLevel => _progress.xpForNextLevel;
  double get levelProgress => _progress.levelProgress;

  /// Idempotent. Hydrates from Drift (cold-start, non-blocking) and wires the
  /// reactive watch. Safe to call from build().
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final row = await _storageService.gameDao.getPlayerProgress();
      if (row != null) {
        _progress = PlayerProgress(totalXp: row.totalXp, level: row.level);
      }
    } catch (e) {
      AppLogger.error('ProgressionService: hydrate from Drift failed', e);
    }
    _wireDriftWatch();
    notifyListeners();
  }

  /// Keep [_progress] in lock-step with the Drift singleton so a cloud-snapshot
  /// restore (which writes Drift directly) refreshes the UI. Does not emit
  /// level-ups — those come only from [flushXp].
  void _wireDriftWatch() {
    _watch?.cancel();
    _watch = _storageService.gameDao.watchPlayerProgress().listen((row) {
      if (row == null) return;
      if (row.totalXp == _progress.totalXp && row.level == _progress.level) {
        return;
      }
      _progress = PlayerProgress(totalXp: row.totalXp, level: row.level);
      notifyListeners();
    });
  }

  /// Buffer XP locally without touching Drift. Call [flushXp] at game end.
  void bufferXp(int xp, {String source = 'gameplay'}) {
    if (xp <= 0) return;
    _bufferedXp += xp;
  }

  /// Persist all buffered XP in one Drift write (+ sync outbox row) and fire a
  /// level-up event if the player crossed a threshold.
  Future<void> flushXp() async {
    if (_bufferedXp <= 0) return;
    final total = _bufferedXp;
    _bufferedXp = 0;

    final oldLevel = _progress.level;
    try {
      final row = await _storageService.gameDao.addPlayerXp(total);
      _progress = PlayerProgress(totalXp: row.totalXp, level: row.level);
      notifyListeners();
      if (_progress.level > oldLevel) {
        _pendingLevelUp = _progress.level;
        _levelUps.add(_progress.level);
        AppLogger.info(
          'Player leveled up: $oldLevel -> ${_progress.level} '
          '(total XP ${_progress.totalXp})',
        );
      }
    } catch (e) {
      AppLogger.error('ProgressionService: flush failed', e);
      _bufferedXp += total; // don't drop the XP — retry on the next flush
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    _watch = null;
    _levelUps.close();
    super.dispose();
  }
}
