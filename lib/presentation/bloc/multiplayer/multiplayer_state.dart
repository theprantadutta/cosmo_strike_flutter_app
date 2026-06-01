import 'package:equatable/equatable.dart';
import 'package:cosmo_strike_flutter_app/models/multiplayer_game.dart';

/// Status of the multiplayer cubit
enum MultiplayerStatus {
  initial,
  loading,
  idle,
  inMatchmaking, // Searching for opponents
  inLobby,
  playing,
  reconnecting, // Attempting to reconnect
  finished,
  error,
}

/// State class for MultiplayerCubit
class MultiplayerState extends Equatable {
  final MultiplayerStatus status;
  final MultiplayerGame? currentGame;
  final List<MultiplayerGame> availableGames;
  final String? errorMessage;
  final bool isLoading;

  // Matchmaking state
  final bool isMatchmaking;
  final int matchmakingQueuePosition;
  final int matchmakingEstimatedWait;
  final MultiplayerGameMode? matchmakingMode;
  final int? matchmakingPlayerCount;
  final int matchmakingElapsedSeconds;
  final bool matchmakingTimedOut;

  const MultiplayerState({
    this.status = MultiplayerStatus.initial,
    this.currentGame,
    this.availableGames = const [],
    this.errorMessage,
    this.isLoading = false,
    this.isMatchmaking = false,
    this.matchmakingQueuePosition = 0,
    this.matchmakingEstimatedWait = 0,
    this.matchmakingMode,
    this.matchmakingPlayerCount,
    this.matchmakingElapsedSeconds = 0,
    this.matchmakingTimedOut = false,
  });

  /// Initial state
  factory MultiplayerState.initial() => const MultiplayerState();

  /// Create a copy with updated values
  MultiplayerState copyWith({
    MultiplayerStatus? status,
    MultiplayerGame? currentGame,
    List<MultiplayerGame>? availableGames,
    String? errorMessage,
    bool? isLoading,
    bool clearGame = false,
    bool clearError = false,
    bool? isMatchmaking,
    int? matchmakingQueuePosition,
    int? matchmakingEstimatedWait,
    MultiplayerGameMode? matchmakingMode,
    int? matchmakingPlayerCount,
    int? matchmakingElapsedSeconds,
    bool? matchmakingTimedOut,
    bool clearMatchmaking = false,
  }) {
    return MultiplayerState(
      status: status ?? this.status,
      currentGame: clearGame ? null : (currentGame ?? this.currentGame),
      availableGames: availableGames ?? this.availableGames,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
      isMatchmaking: clearMatchmaking
          ? false
          : (isMatchmaking ?? this.isMatchmaking),
      matchmakingQueuePosition: clearMatchmaking
          ? 0
          : (matchmakingQueuePosition ?? this.matchmakingQueuePosition),
      matchmakingEstimatedWait: clearMatchmaking
          ? 0
          : (matchmakingEstimatedWait ?? this.matchmakingEstimatedWait),
      matchmakingMode: clearMatchmaking
          ? null
          : (matchmakingMode ?? this.matchmakingMode),
      matchmakingPlayerCount: clearMatchmaking
          ? null
          : (matchmakingPlayerCount ?? this.matchmakingPlayerCount),
      matchmakingElapsedSeconds: clearMatchmaking
          ? 0
          : (matchmakingElapsedSeconds ?? this.matchmakingElapsedSeconds),
      matchmakingTimedOut: clearMatchmaking
          ? false
          : (matchmakingTimedOut ?? this.matchmakingTimedOut),
    );
  }

  /// Whether user is currently in a game
  bool get isInGame => currentGame != null;

  /// Whether game can be started
  bool get canStartGame => currentGame?.canStart ?? false;

  /// Whether user is waiting for players
  bool get isWaitingForPlayers =>
      currentGame?.status == MultiplayerGameStatus.waiting &&
      !(currentGame?.isFull ?? true);

  /// Whether game is ready to start
  bool get isReadyToStart => currentGame?.canStart ?? false;

  /// Whether game is actively playing
  bool get isGameActive => currentGame?.status == MultiplayerGameStatus.playing;

  /// Whether game is finished
  bool get isGameFinished => currentGame?.isFinished ?? false;

  /// Game room code formatted for display
  String? get formattedRoomCode {
    final code = currentGame?.roomCode;
    if (code == null) return null;

    // Format as XXX-XXX
    if (code.length == 6) {
      return '${code.substring(0, 3)}-${code.substring(3)}';
    }
    return code;
  }

  /// Get game duration
  Duration? get gameDuration {
    if (currentGame?.startedAt == null) return null;
    return DateTime.now().difference(currentGame!.startedAt!);
  }

  @override
  List<Object?> get props => [
    status,
    currentGame,
    availableGames,
    errorMessage,
    isLoading,
    isMatchmaking,
    matchmakingQueuePosition,
    matchmakingEstimatedWait,
    matchmakingMode,
    matchmakingPlayerCount,
    matchmakingElapsedSeconds,
    matchmakingTimedOut,
  ];
}
