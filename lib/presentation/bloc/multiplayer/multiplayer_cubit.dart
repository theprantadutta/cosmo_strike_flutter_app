import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/models/multiplayer_game.dart';
import 'package:cosmo_strike_flutter_app/models/position.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/haptic_service.dart';
import 'package:cosmo_strike_flutter_app/services/multiplayer_service.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';
import 'package:cosmo_strike_flutter_app/utils/direction.dart';

import 'multiplayer_state.dart';

export 'multiplayer_state.dart';

/// Cubit for managing multiplayer game state
class MultiplayerCubit extends Cubit<MultiplayerState> {
  final MultiplayerService _multiplayerService;
  final UnifiedUserService _userService;
  final AudioService _audioService;
  final HapticService _hapticService;
  final AnalyticsFacade _analytics;

  // Stream subscriptions
  StreamSubscription? _gameSubscription;
  StreamSubscription? _actionsSubscription;
  StreamSubscription? _matchmakingSubscription;
  StreamSubscription? _errorSubscription;

  // Matchmaking timer
  Timer? _matchmakingTimer;
  static const int matchmakingTimeoutSeconds = 60;

  // Start game timeout
  Timer? _startGameTimeoutTimer;

  // Per-match stat tracking. Multiplayer doesn't have per-tick food/power-up
  // counts available to the client (server-authoritative), so the minimum
  // we record is game duration + final score + whether the player was
  // eliminated by a crash. Better than the previous total miss.
  final Stopwatch _matchTimer = Stopwatch();
  bool _matchStatsRecorded = false;
  final StatisticsService _statisticsService = StatisticsService();

  MultiplayerCubit({
    required MultiplayerService multiplayerService,
    required UnifiedUserService userService,
    required AudioService audioService,
    required HapticService hapticService,
    required AnalyticsFacade analytics,
  }) : _multiplayerService = multiplayerService,
       _userService = userService,
       _audioService = audioService,
       _hapticService = hapticService,
       _analytics = analytics,
       super(MultiplayerState.initial()) {
    // Start listening to matchmaking stream
    _startMatchmakingListener();
    // Start listening to error stream
    _startErrorListener();
  }

  void _startErrorListener() {
    _errorSubscription = _multiplayerService.errorStream.listen((error) {
      _hapticService.heavyImpact();
      _startGameTimeoutTimer?.cancel();
      emit(state.copyWith(errorMessage: error, isLoading: false));
    });
  }

  void _startMatchmakingListener() {
    _matchmakingSubscription = _multiplayerService.matchmakingStream.listen(
      (status) {
        if (status.matchFound && status.gameId != null) {
          // Match found! Stop timer and transition to lobby
          _stopMatchmakingTimer();
          _audioService.playSound('high_score');
          _hapticService.mediumImpact();

          // First emit the status change with clear matchmaking
          // Don't set currentGame here - let the stream listener handle it
          emit(
            state.copyWith(
              status: MultiplayerStatus.inLobby,
              clearMatchmaking: true,
            ),
          );

          // Start listening to game updates
          _startListening();
        } else if (status.error != null) {
          _stopMatchmakingTimer();
          _audioService.playSound('game_over');
          emit(
            state.copyWith(
              status: MultiplayerStatus.error,
              errorMessage: status.error,
              clearMatchmaking: true,
            ),
          );
        } else if (status.isSearching) {
          emit(
            state.copyWith(
              status: MultiplayerStatus.inMatchmaking,
              isMatchmaking: true,
              matchmakingQueuePosition: status.queuePosition,
              matchmakingEstimatedWait: status.estimatedWaitSeconds,
              matchmakingMode: status.mode,
              matchmakingPlayerCount: status.playerCount,
            ),
          );
        }
      },
      onError: (error) {
        _stopMatchmakingTimer();
        emit(
          state.copyWith(
            errorMessage: 'Matchmaking error: $error',
            clearMatchmaking: true,
          ),
        );
      },
    );
  }

  /// Get current player from the game
  MultiplayerPlayer? get currentPlayer {
    if (state.currentGame == null) return null;
    final currentUserId = _userService.currentUser?.uid;
    if (currentUserId == null) return null;

    return state.currentGame!.getPlayer(currentUserId);
  }

  /// Check if current player is host
  /// Host is determined by playerIndex (rank) == 0, not by list order
  bool get isHost {
    if (state.currentGame == null) return false;
    final currentUserId = _userService.currentUser?.uid;
    if (currentUserId == null) return false;

    final currentPlayer = state.currentGame!.getPlayer(currentUserId);
    return currentPlayer?.rank == 0;
  }

  /// Get opponent player
  MultiplayerPlayer? getOpponent() {
    if (state.currentGame == null) return null;
    final currentUserId = _userService.currentUser?.uid;
    if (currentUserId == null) return null;

    final opponents = state.currentGame!.players
        .where((player) => player.userId != currentUserId)
        .toList();

    return opponents.isNotEmpty ? opponents.first : null;
  }

  /// Create a new multiplayer game
  Future<bool> createGame({
    required MultiplayerGameMode mode,
    bool isPrivate = false,
    int maxPlayers = 2,
  }) async {
    emit(state.copyWith(isLoading: true, clearError: true));

    try {
      _audioService.playSound('button_click');
      _hapticService.lightImpact();

      final gameId = await _multiplayerService.createGame(
        mode: mode,
        isPrivate: isPrivate,
        maxPlayers: maxPlayers,
      );

      if (gameId != null) {
        await _startListening();

        _audioService.playSound('high_score');
        _hapticService.mediumImpact();

        emit(
          state.copyWith(status: MultiplayerStatus.inLobby, isLoading: false),
        );
        return true;
      } else {
        _audioService.playSound('game_over');
        _hapticService.heavyImpact();
        emit(
          state.copyWith(
            isLoading: false,
            errorMessage: 'Failed to create game',
          ),
        );
        return false;
      }
    } catch (e) {
      _audioService.playSound('game_over');
      _hapticService.heavyImpact();
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Error creating game: $e',
        ),
      );
      return false;
    }
  }

  /// Join a game by ID or room code
  Future<bool> joinGame(String gameIdOrRoomCode) async {
    emit(state.copyWith(isLoading: true, clearError: true));

    try {
      _audioService.playSound('button_click');
      _hapticService.lightImpact();

      final success = await _multiplayerService.joinGame(gameIdOrRoomCode);

      if (success) {
        await _startListening();

        _audioService.playSound('high_score');
        _hapticService.mediumImpact();

        emit(
          state.copyWith(status: MultiplayerStatus.inLobby, isLoading: false),
        );
        return true;
      } else {
        _audioService.playSound('game_over');
        _hapticService.heavyImpact();
        emit(
          state.copyWith(
            isLoading: false,
            errorMessage:
                'Failed to join game. Game might be full or not exist.',
          ),
        );
        return false;
      }
    } catch (e) {
      _audioService.playSound('game_over');
      _hapticService.heavyImpact();
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Error joining game: $e',
        ),
      );
      return false;
    }
  }

  /// Leave current game
  Future<void> leaveGame() async {
    try {
      await _multiplayerService.leaveGame();
      _stopListening();
      emit(
        state.copyWith(
          status: MultiplayerStatus.idle,
          clearGame: true,
          clearError: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error leaving game: $e'));
    }
  }

  /// Mark current player as ready
  Future<bool> markPlayerReady() async {
    try {
      _audioService.playSound('button_click');
      _hapticService.lightImpact();

      final success = await _multiplayerService.markPlayerReady();
      if (success) {
        _audioService.playSound('high_score');
        _hapticService.mediumImpact();
      } else {
        _audioService.playSound('game_over');
        emit(state.copyWith(errorMessage: 'Failed to mark player as ready'));
      }
      return success;
    } catch (e) {
      _audioService.playSound('game_over');
      emit(state.copyWith(errorMessage: 'Error marking player ready: $e'));
      return false;
    }
  }

  /// Send direction change
  Future<void> changeDirection(Direction direction) async {
    if (state.currentGame?.status != MultiplayerGameStatus.playing) return;

    try {
      final currentUserId = _userService.currentUser?.uid;
      if (currentUserId == null) return;

      _audioService.playSound('button_click');
      _hapticService.lightImpact();

      final action = MultiplayerGameAction.changeDirection(
        currentUserId,
        direction,
      );
      await _multiplayerService.sendPlayerAction(action);
    } catch (e) {
      if (kDebugMode) {
        print('Error changing direction: $e');
      }
    }
  }

  /// Update player's game state (position, score, status)
  Future<void> updateGameState({
    required List<Position> snake,
    required int score,
    required PlayerStatus status,
  }) async {
    try {
      await _multiplayerService.updatePlayerGameState(
        snake: snake,
        score: score,
        status: status,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error updating game state: $e');
      }
    }
  }

  /// Load available games
  Future<void> loadAvailableGames() async {
    try {
      final games = await _multiplayerService.getAvailableGames();
      emit(
        state.copyWith(status: MultiplayerStatus.idle, availableGames: games),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error loading available games: $e'));
    }
  }

  /// Quick match using matchmaking system
  Future<bool> quickMatch(
    MultiplayerGameMode mode, {
    int playerCount = 2,
  }) async {
    emit(
      state.copyWith(isLoading: true, clearError: true, clearMatchmaking: true),
    );

    try {
      _audioService.playSound('button_click');
      _hapticService.lightImpact();

      await _multiplayerService.joinMatchmaking(
        mode: mode,
        playerCount: playerCount,
      );

      emit(
        state.copyWith(
          status: MultiplayerStatus.inMatchmaking,
          isLoading: false,
          isMatchmaking: true,
          matchmakingMode: mode,
          matchmakingPlayerCount: playerCount,
          matchmakingElapsedSeconds: 0,
          matchmakingTimedOut: false,
        ),
      );

      _analytics.trackMultiplayerQueueJoined();

      // Start the matchmaking timer
      _startMatchmakingTimer();

      return true;
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Error starting matchmaking: $e',
        ),
      );
      return false;
    }
  }

  /// Start matchmaking countdown timer
  void _startMatchmakingTimer() {
    _stopMatchmakingTimer();

    _matchmakingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final elapsed = timer.tick;

      if (elapsed >= matchmakingTimeoutSeconds) {
        // Timeout reached
        _onMatchmakingTimeout();
      } else {
        // Update elapsed time
        emit(state.copyWith(matchmakingElapsedSeconds: elapsed));
      }
    });
  }

  /// Stop matchmaking timer
  void _stopMatchmakingTimer() {
    _matchmakingTimer?.cancel();
    _matchmakingTimer = null;
  }

  /// Handle matchmaking timeout
  Future<void> _onMatchmakingTimeout() async {
    _stopMatchmakingTimer();

    _audioService.playSound('game_over');
    _hapticService.mediumImpact();

    // Cancel matchmaking on the server
    try {
      await _multiplayerService.leaveMatchmaking();
    } catch (e) {
      if (kDebugMode) {
        print('Error leaving matchmaking after timeout: $e');
      }
    }

    emit(
      state.copyWith(
        status: MultiplayerStatus.idle,
        isMatchmaking: false,
        matchmakingTimedOut: true,
        matchmakingElapsedSeconds: matchmakingTimeoutSeconds,
      ),
    );
  }

  /// Cancel matchmaking
  Future<void> cancelMatchmaking() async {
    _stopMatchmakingTimer();

    try {
      _audioService.playSound('button_click');
      await _multiplayerService.leaveMatchmaking();

      emit(
        state.copyWith(status: MultiplayerStatus.idle, clearMatchmaking: true),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Error canceling matchmaking: $e'));
    }
  }

  /// Clear matchmaking timeout state (to dismiss the timeout message)
  void clearMatchmakingTimeout() {
    emit(state.copyWith(matchmakingTimedOut: false, clearMatchmaking: true));
  }

  /// Attempt to reconnect to a game after disconnect
  Future<bool> attemptReconnect() async {
    emit(
      state.copyWith(status: MultiplayerStatus.reconnecting, isLoading: true),
    );

    try {
      final success = await _multiplayerService.attemptReconnect();

      if (success) {
        _audioService.playSound('high_score');
        _hapticService.mediumImpact();

        await _startListening();

        emit(
          state.copyWith(status: MultiplayerStatus.playing, isLoading: false),
        );
        return true;
      } else {
        _audioService.playSound('game_over');
        emit(
          state.copyWith(
            status: MultiplayerStatus.idle,
            isLoading: false,
            errorMessage: 'Could not reconnect to game',
          ),
        );
        return false;
      }
    } catch (e) {
      emit(
        state.copyWith(
          status: MultiplayerStatus.idle,
          isLoading: false,
          errorMessage: 'Reconnection failed: $e',
        ),
      );
      return false;
    }
  }

  /// Generate new food when eaten
  Future<void> generateNewFood() async {
    await _multiplayerService.generateNewFood();
  }

  /// Check if game should end
  Future<void> checkGameEnd() async {
    await _multiplayerService.checkGameEnd();
  }

  /// Handle food consumption
  Future<void> onFoodEaten(int points) async {
    try {
      _audioService.playSound('eat');
      _hapticService.lightImpact();
    } catch (e) {
      if (kDebugMode) {
        print('Error handling food eaten: $e');
      }
    }
  }

  /// Handle player crash
  Future<void> onPlayerCrash() async {
    try {
      _audioService.playSound('game_over');
      _hapticService.heavyImpact();
    } catch (e) {
      if (kDebugMode) {
        print('Error handling player crash: $e');
      }
    }
  }

  /// Handle game victory
  Future<void> onGameWon(int finalScore) async {
    try {
      _audioService.playSound('level_up');
      _hapticService.heavyImpact();
      _analytics.trackMultiplayerGameEnded(score: finalScore, result: 'win');
    } catch (e) {
      if (kDebugMode) {
        print('Error handling game victory: $e');
      }
    }
  }

  /// Handle game loss
  Future<void> onGameLost(int finalScore) async {
    try {
      _audioService.playSound('game_over');
      _hapticService.mediumImpact();
      _analytics.trackMultiplayerGameEnded(score: finalScore, result: 'loss');
    } catch (e) {
      if (kDebugMode) {
        print('Error handling game loss: $e');
      }
    }
  }

  /// Utility methods for UI
  String getPlayerDisplayName(String userId) {
    final player = state.currentGame?.players
        .where((p) => p.userId == userId)
        .toList()
        .firstOrNull;
    return player?.displayName ?? 'Unknown Player';
  }

  PlayerStatus getPlayerStatus(String userId) {
    final player = state.currentGame?.players
        .where((p) => p.userId == userId)
        .toList()
        .firstOrNull;
    return player?.status ?? PlayerStatus.waiting;
  }

  int getPlayerScore(String userId) {
    final player = state.currentGame?.players
        .where((p) => p.userId == userId)
        .toList()
        .firstOrNull;
    return player?.score ?? 0;
  }

  List<Position> getPlayerSnake(String userId) {
    final player = state.currentGame?.players
        .where((p) => p.userId == userId)
        .toList()
        .firstOrNull;
    return player?.snake ?? [];
  }

  /// Winner display name
  String? get winner {
    if (state.currentGame?.winnerId == null) return null;
    return getPlayerDisplayName(state.currentGame!.winnerId!);
  }

  /// Check if game is ready to start (all players ready)
  bool get isReadyToStart => state.currentGame?.canStart ?? false;

  /// Check if game is actively playing
  bool get isGameActive =>
      state.currentGame?.status == MultiplayerGameStatus.playing;

  /// Check if game is finished
  bool get isGameFinished => state.currentGame?.isFinished ?? false;

  /// Get formatted room code for display (XXX-XXX format)
  String? get formattedRoomCode {
    final code = _multiplayerService.currentRoomCode;
    if (code == null) return null;

    // Format as XXX-XXX
    if (code.length == 6) {
      return '${code.substring(0, 3)}-${code.substring(3)}';
    }
    return code;
  }

  /// Get raw room code
  String? get roomCode => _multiplayerService.currentRoomCode;

  /// Get game duration since start
  Duration? get gameDuration {
    if (state.currentGame?.startedAt == null) return null;
    return DateTime.now().difference(state.currentGame!.startedAt!);
  }

  /// Start the game (host only)
  Future<bool> startGame() async {
    if (!isHost) return false;

    // Show loading state
    emit(state.copyWith(isLoading: true));

    try {
      _audioService.playSound('game_start');
      _hapticService.mediumImpact();

      final success = await _multiplayerService.startGame();
      if (success) {
        _analytics.trackMultiplayerGameStarted();
      }
      if (!success) {
        emit(
          state.copyWith(
            errorMessage: 'Failed to start game',
            isLoading: false,
          ),
        );
        return false;
      }

      // Set timeout - if no GameStarting received in 5 seconds, show error
      _startGameTimeoutTimer?.cancel();
      _startGameTimeoutTimer = Timer(const Duration(seconds: 5), () {
        if (state.isLoading && state.status != MultiplayerStatus.playing) {
          emit(
            state.copyWith(
              errorMessage: 'Start game timed out. Please try again.',
              isLoading: false,
            ),
          );
        }
      });

      return success;
    } catch (e) {
      emit(
        state.copyWith(
          errorMessage: 'Error starting game: $e',
          isLoading: false,
        ),
      );
      return false;
    }
  }

  /// Notify that current player died
  Future<void> notifyPlayerDied() async {
    try {
      await _multiplayerService.notifyPlayerDied();
    } catch (e) {
      if (kDebugMode) {
        print('Error notifying player died: $e');
      }
    }
  }

  /// Notify game over with final score
  Future<void> notifyGameOver(int finalScore) async {
    try {
      await _multiplayerService.notifyGameOver(finalScore);
    } catch (e) {
      if (kDebugMode) {
        print('Error notifying game over: $e');
      }
    }
  }

  /// Clear error message
  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  /// Private helper methods
  Future<void> _startListening() async {
    _stopListening();

    // Listen to game updates
    _gameSubscription = _multiplayerService.gameStream.listen(
      (game) {
        if (game == null) return;

        MultiplayerStatus newStatus = state.status;
        bool shouldClearLoading = false;

        if (game.status == MultiplayerGameStatus.starting) {
          // Game is starting (countdown) - clear loading state
          shouldClearLoading = true;
          _startGameTimeoutTimer?.cancel();
        } else if (game.status == MultiplayerGameStatus.playing) {
          newStatus = MultiplayerStatus.playing;
          shouldClearLoading = true;
          _startGameTimeoutTimer?.cancel();
          // Start the per-match stat timer on the playing transition.
          if (!_matchTimer.isRunning) {
            _matchTimer
              ..reset()
              ..start();
            _matchStatsRecorded = false;
          }
        } else if (game.isFinished) {
          newStatus = MultiplayerStatus.finished;
          shouldClearLoading = true;
          _recordMatchStats(game);
        } else if (game.status == MultiplayerGameStatus.waiting) {
          newStatus = MultiplayerStatus.inLobby;
        }

        emit(
          state.copyWith(
            status: newStatus,
            currentGame: game,
            isLoading: shouldClearLoading ? false : null,
          ),
        );
      },
      onError: (error) {
        emit(state.copyWith(errorMessage: 'Game stream error: $error'));
      },
    );

    // Listen to game actions
    _actionsSubscription = _multiplayerService.gameActionsStream.listen(
      (action) {
        _handleGameAction(action);
      },
      onError: (error) {
        if (kDebugMode) {
          print('Game actions stream error: $error');
        }
      },
    );

    // Immediately emit the current game state (since broadcast streams don't replay)
    final currentGame = _multiplayerService.currentGame;
    if (currentGame != null) {
      MultiplayerStatus newStatus = state.status;
      if (currentGame.status == MultiplayerGameStatus.playing) {
        newStatus = MultiplayerStatus.playing;
        if (!_matchTimer.isRunning) {
          _matchTimer
            ..reset()
            ..start();
          _matchStatsRecorded = false;
        }
      } else if (currentGame.isFinished) {
        newStatus = MultiplayerStatus.finished;
        _recordMatchStats(currentGame);
      } else if (currentGame.status == MultiplayerGameStatus.waiting) {
        newStatus = MultiplayerStatus.inLobby;
      }

      emit(state.copyWith(status: newStatus, currentGame: currentGame));
    }
  }

  /// Record a finished multiplayer match into the per-user statistics.
  /// Multiplayer doesn't expose per-tick food/power-up counts on the
  /// client side, so this records the minimum that the screen actually
  /// surfaces: score, game duration, and a wall/self-hit flag derived
  /// from the player's elimination state. Idempotent within a single
  /// match — `_matchStatsRecorded` guards against the multiple
  /// game-state-finished events the SignalR stream can emit.
  void _recordMatchStats(MultiplayerGame game) {
    if (_matchStatsRecorded) return;
    final userId = _userService.currentUser?.uid;
    if (userId == null) return;

    MultiplayerPlayer? me;
    for (final p in game.players) {
      if (p.userId == userId) {
        me = p;
        break;
      }
    }
    if (me == null) return;

    if (_matchTimer.isRunning) _matchTimer.stop();
    final gameTimeSeconds = _matchTimer.elapsed.inSeconds;
    _matchStatsRecorded = true;

    // Treat any non-null eliminationRank as "the player crashed at some
    // point". We can't differentiate wall vs self from this info; bucket
    // into selfHits since multiplayer modes rarely have walls.
    final eliminated = me.eliminationRank != null;
    final selfHits = eliminated ? 1 : 0;

    _statisticsService.recordGameResult(
      score: me.score,
      gameTime: gameTimeSeconds,
      level: 1,
      foodConsumed: 0,
      foodTypes: const <String, int>{},
      foodPoints: 0,
      powerUpsCollected: 0,
      powerUpTypes: const <String, int>{},
      powerUpTime: 0,
      wallHits: 0,
      selfHits: selfHits,
      isPerfectGame: !eliminated && gameTimeSeconds >= 30,
      unlockedAchievements: const [],
    );
  }

  void _stopListening() {
    _gameSubscription?.cancel();
    _actionsSubscription?.cancel();
    _gameSubscription = null;
    _actionsSubscription = null;
  }

  void _stopMatchmakingListener() {
    _matchmakingSubscription?.cancel();
    _matchmakingSubscription = null;
  }

  void _handleGameAction(MultiplayerGameAction action) {
    if (kDebugMode) {
      print('Received action: ${action.actionType} from ${action.playerId}');
    }
    // Actions are already reflected in the game state
  }

  @override
  Future<void> close() {
    _stopListening();
    _stopMatchmakingListener();
    _stopMatchmakingTimer();
    _startGameTimeoutTimer?.cancel();
    _errorSubscription?.cancel();
    _multiplayerService.dispose();
    return super.close();
  }
}
