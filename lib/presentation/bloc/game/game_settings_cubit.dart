import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

import 'game_settings_state.dart';

export 'game_settings_state.dart';

/// Cubit for managing game settings (D-pad, board size, etc.)
class GameSettingsCubit extends Cubit<GameSettingsState> {
  final StorageService _storageService;
  final StatisticsService _statisticsService = StatisticsService();
  final ApiService _apiService = ApiService();
  // Drift stream subscription that keeps state.highScore in lock-step with
  // the settings table. Without this the cubit reads the DB once at init
  // and goes blind to subsequent writes — most importantly, the writes
  // that StatisticsService._syncWithCloud does after pulling the server's
  // aggregated high score. Online that staleness was masked by AuthState
  // (which refreshes from the backend on every launch); offline both
  // sources go stale and the home screen showed a fixed lower number.
  StreamSubscription<GameSetting?>? _settingsSubscription;

  /// Coalesces concurrent initialize() calls onto a shared completion
  /// future. Matches the pattern in [CoinsCubit] — AuthCubit fires
  /// syncWithBackend before main.dart's BlocProvider has finished
  /// loading from Drift, and we cannot let the sync read state.highScore
  /// while it's still the default 0.
  Completer<void>? _initCompleter;

  GameSettingsCubit(this._storageService) : super(GameSettingsState.initial());

  /// Initialize settings from storage
  Future<void> initialize() async {
    if (state.status == GameSettingsStatus.ready) return;
    final inFlight = _initCompleter;
    if (inFlight != null) return inFlight.future;
    final completer = Completer<void>();
    _initCompleter = completer;

    emit(state.copyWith(status: GameSettingsStatus.loading));

    try {
      // Initialize StatisticsService first to sync high scores between
      // the statistics object and the separate highScore key.
      //
      // After the cloud-sync-on-init fix in StatisticsService.initialize
      // this call is local-only and returns in tens of ms. The 3-second
      // safety net is defense in depth: if the underlying disk I/O ever
      // stalls (low-storage Android device, locked DB file, etc.) we
      // swallow the timeout and fall through to the storage reads below
      // — the user's local settings are still loadable directly from
      // StorageService even if the StatisticsService prep step hangs.
      try {
        await _statisticsService
            .initialize()
            .timeout(const Duration(seconds: 3));
      } on TimeoutException catch (e) {
        AppLogger.error(
          'StatisticsService.initialize timed out — continuing with '
          'direct storage reads',
          e,
        );
      }

      // Load saved settings (now synced)
      final highScore = await _storageService.getHighScore();
      final savedBoardSize = await _storageService.getBoardSize();
      final crashFeedbackDuration = await _storageService
          .getCrashFeedbackDuration();
      final dPadEnabled = await _storageService.isDPadEnabled();
      final dPadPosition = await _storageService.getDPadPosition();
      final screenShakeEnabled = await _storageService.isScreenShakeEnabled();
      final gameMode = await _storageService.getGameMode();
      final gameModePrompted = await _storageService.hasGameModeBeenPrompted();

      // Convert saved board size to BoardSize object
      final boardSize = _convertToBoardSize(savedBoardSize);

      emit(
        state.copyWith(
          status: GameSettingsStatus.ready,
          highScore: highScore,
          boardSize: boardSize,
          crashFeedbackDuration: crashFeedbackDuration,
          dPadEnabled: dPadEnabled,
          dPadPosition: dPadPosition,
          screenShakeEnabled: screenShakeEnabled,
          gameMode: gameMode,
          gameModeFirstLaunchPrompted: gameModePrompted,
        ),
      );

      AppLogger.info('GameSettingsCubit initialized. High score: $highScore');

      // Subscribe to settings-table changes so the cubit stays in sync
      // with any DB write — local saveHighScore calls AND background
      // writes from StatisticsService.syncWithCloud both flow through
      // here, so state.highScore is always at least as fresh as disk.
      _settingsSubscription = _storageService.watchSettings().listen((row) {
        if (row == null) return;
        if (row.highScore != state.highScore) {
          emit(state.copyWith(highScore: row.highScore));
        }
      });

      // Backend reconcile is no longer fired here — AuthCubit triggers
      // syncWithBackend after the user is authenticated (see
      // AuthCubit._firePostAuthSyncs). Firing here would race with auth
      // and 401 on first launch.
      completer.complete();
    } catch (e) {
      AppLogger.error('Error initializing GameSettingsCubit', e);
      emit(state.copyWith(status: GameSettingsStatus.ready));
      completer.complete();
    }
  }

  /// Pull `User.HighScore` from the backend and reconcile with local DB.
  ///
  /// Strategy: take max(local, server). Mirrors CoinsCubit.syncWithBackend
  /// exactly — once an online launch lands the server value into the local
  /// DB, every subsequent offline session shows the correct number because
  /// the local DB is the persistent source of truth (StorageService.saveHighScore
  /// never decreases). The watchSettings stream above picks up the write
  /// and emits new state, so the UI rebuilds without any further plumbing.
  Future<void> syncWithBackend() async {
    try {
      // Block on initialize() so state.highScore reflects the Drift
      // settings row, not the default 0. AuthCubit._firePostAuthSyncs
      // fires this on every successful authentication — well before
      // main.dart's BlocProvider.create has finished loading. Without
      // the await, local=0 races server=N and the sync log misreports
      // "local=0, server=2033 (synced)" while writing a value the
      // never-decrease saveHighScore guard might have suppressed.
      await initialize();
      if (state.status != GameSettingsStatus.ready) return;

      if (!_apiService.isAuthenticated) return;
      final data = await _apiService.getCurrentUser();
      if (data == null) return;

      final serverHighScore = (data['high_score'] as int?)
          ?? (data['highScore'] as int?)
          ?? 0;
      final localHighScore = state.highScore;

      if (serverHighScore == localHighScore) {
        AppLogger.info(
          'High score sync: local=$localHighScore, server=$serverHighScore (in sync)',
        );
        return;
      }
      if (serverHighScore < localHighScore) {
        // Local ahead — keep it. The score-submit / statistics sync
        // paths will push the higher local value up on the next tick.
        AppLogger.info(
          'High score sync: local=$localHighScore, server=$serverHighScore '
          '(kept local; server is behind by ${localHighScore - serverHighScore})',
        );
        return;
      }

      // saveHighScore enforces never-decrease; the stream subscription
      // above will emit the new state once the DB write commits.
      await _storageService.saveHighScore(serverHighScore);
      AppLogger.info(
        'High score sync: local=$localHighScore, server=$serverHighScore (synced)',
      );
    } catch (e) {
      AppLogger.error('Error syncing high score with backend', e);
    }
  }

  @override
  Future<void> close() {
    _settingsSubscription?.cancel();
    return super.close();
  }

  BoardSize _convertToBoardSize(dynamic savedSize) {
    if (savedSize == null) return BoardSize.classic;

    // Handle BoardSize object from storage
    if (savedSize is BoardSize) return savedSize;

    // Handle map from storage
    if (savedSize is Map || savedSize.width != null) {
      final width = savedSize.width ?? savedSize['width'] ?? 20;
      final height = savedSize.height ?? savedSize['height'] ?? 20;

      // Look up against the FULL list (availableBoardSizes), not BoardSize.all
      // (which only holds the 4 original sizes) — otherwise a larger size read
      // from a legacy map shape would silently fall back to Classic.
      return GameConstants.availableBoardSizes.firstWhere(
        (size) => size.width == width && size.height == height,
        orElse: () => BoardSize.classic,
      );
    }

    return BoardSize.classic;
  }

  /// Update D-Pad enabled setting
  Future<void> setDPadEnabled(bool enabled) async {
    if (state.dPadEnabled == enabled) return;

    emit(state.copyWith(dPadEnabled: enabled));
    await _storageService.setDPadEnabled(enabled);
  }

  /// Alias for setDPadEnabled
  Future<void> updateDPadEnabled(bool enabled) => setDPadEnabled(enabled);

  /// Toggle D-Pad
  Future<void> toggleDPad() async {
    await setDPadEnabled(!state.dPadEnabled);
  }

  /// Update D-Pad position
  Future<void> setDPadPosition(DPadPosition position) async {
    if (state.dPadPosition == position) return;

    emit(state.copyWith(dPadPosition: position));
    await _storageService.setDPadPosition(position);
  }

  /// Alias for setDPadPosition
  Future<void> updateDPadPosition(DPadPosition position) =>
      setDPadPosition(position);

  /// Update board size
  Future<void> setBoardSize(BoardSize size) async {
    if (state.boardSize == size) return;

    emit(state.copyWith(boardSize: size));
    await _storageService.saveBoardSize(size);
  }

  /// Alias for setBoardSize
  Future<void> updateBoardSize(BoardSize size) => setBoardSize(size);

  /// Update single-player game mode
  Future<void> setGameMode(GameMode mode) async {
    if (state.gameMode == mode) return;

    emit(state.copyWith(gameMode: mode));
    await _storageService.saveGameMode(mode);
  }

  /// Alias for setGameMode
  Future<void> updateGameMode(GameMode mode) => setGameMode(mode);

  /// Mark the first-launch game mode prompt as shown.
  Future<void> markGameModePrompted() async {
    if (state.gameModeFirstLaunchPrompted) return;
    emit(state.copyWith(gameModeFirstLaunchPrompted: true));
    await _storageService.markGameModePrompted();
  }

  /// Update crash feedback duration
  Future<void> setCrashFeedbackDuration(Duration duration) async {
    if (state.crashFeedbackDuration == duration) return;

    emit(state.copyWith(crashFeedbackDuration: duration));
    await _storageService.saveCrashFeedbackDuration(duration);
  }

  /// Alias for setCrashFeedbackDuration
  Future<void> updateCrashFeedbackDuration(Duration duration) =>
      setCrashFeedbackDuration(duration);

  /// Update high score if new score is higher
  Future<bool> updateHighScore(int newScore) async {
    if (newScore <= state.highScore) return false;

    emit(state.copyWith(highScore: newScore));
    await _storageService.saveHighScore(newScore);
    AppLogger.info('New high score: $newScore');
    return true;
  }

  /// Reset high score (for debugging)
  Future<void> resetHighScore() async {
    emit(state.copyWith(highScore: 0));
    await _storageService.saveHighScore(0);
  }

  /// Update screen shake setting
  Future<void> setScreenShakeEnabled(bool enabled) async {
    if (state.screenShakeEnabled == enabled) return;

    emit(state.copyWith(screenShakeEnabled: enabled));
    await _storageService.setScreenShakeEnabled(enabled);
  }

  /// Toggle screen shake
  Future<void> toggleScreenShake() async {
    await setScreenShakeEnabled(!state.screenShakeEnabled);
  }
}
