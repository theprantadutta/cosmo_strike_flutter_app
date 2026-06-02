import 'dart:async';
import 'package:cosmo_strike_flutter_app/models/multiplayer_game.dart';
import 'package:cosmo_strike_flutter_app/models/position.dart';

/// Matchmaking status snapshot consumed by the multiplayer cubit.
/// In the offline-first build this is only emitted with `isSearching:
/// false` (since matchmaking is disabled), but the type stays so
/// existing call sites compile.
class MatchmakingStatus {
  final bool isSearching;
  final int queuePosition;
  final int estimatedWaitSeconds;
  final MultiplayerGameMode? mode;
  final int? playerCount;
  final bool matchFound;
  final String? gameId;
  final String? error;

  const MatchmakingStatus({
    required this.isSearching,
    required this.queuePosition,
    required this.estimatedWaitSeconds,
    this.mode,
    this.playerCount,
    this.matchFound = false,
    this.gameId,
    this.error,
  });
}

/// Offline-first stub. Multiplayer requires both a live REST backend
/// (create/join/list rooms) and a SignalR hub for real-time game
/// state. Both are disabled in this build, so the service compiles
/// but every method is inert — create returns null, join returns
/// false, action methods are no-ops, streams are empty.
///
/// To revive: restore the prior implementation from git history and
/// re-add the multiplayer endpoints + SignalR hub URL to [ApiService].
class MultiplayerService {
  static MultiplayerService? _instance;

  MultiplayerGame? _currentGame;
  String? _currentGameId;
  String? _currentRoomCode;

  final _gameStreamController =
      StreamController<MultiplayerGame?>.broadcast();
  final _gameActionsController =
      StreamController<MultiplayerGameAction>.broadcast();
  final _matchmakingStreamController =
      StreamController<MatchmakingStatus>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  MultiplayerService._internal();

  factory MultiplayerService() {
    _instance ??= MultiplayerService._internal();
    return _instance!;
  }

  MultiplayerGame? get currentGame => _currentGame;
  String? get currentGameId => _currentGameId;
  String? get currentRoomCode => _currentRoomCode;
  bool get isInGame => false;
  bool get isConnected => false;

  bool get isInMatchmaking => false;
  int get matchmakingQueuePosition => 0;
  int get matchmakingEstimatedWait => 0;

  Stream<MultiplayerGame?> get gameStream => _gameStreamController.stream;
  Stream<MultiplayerGameAction> get gameActionsStream =>
      _gameActionsController.stream;
  Stream<MatchmakingStatus> get matchmakingStream =>
      _matchmakingStreamController.stream;
  Stream<String> get errorStream => _errorController.stream;

  Future<String?> createGame({
    required MultiplayerGameMode mode,
    bool isPrivate = false,
    int maxPlayers = 2,
  }) async => null;

  Future<bool> joinGame(String gameIdOrRoomCode) async => false;

  Future<void> leaveGame() async {}

  Future<bool> markPlayerReady({bool isReady = true}) async => false;

  Future<bool> startGame() async => false;

  Future<void> sendPlayerAction(MultiplayerGameAction action) async {}

  Future<void> updatePlayerGameState({
    required List<Position> ship,
    required int score,
    required PlayerStatus status,
  }) async {}

  Future<void> notifyPlayerDied() async {}

  Future<void> notifyGameOver(int finalScore) async {}

  Future<void> updateGameState({
    List<Position>? foodPositions,
    List<Map<String, dynamic>>? powerUps,
  }) async {}

  Future<List<MultiplayerGame>> getAvailableGames() async => const [];

  Future<bool> joinMatchmaking({
    required MultiplayerGameMode mode,
    required int playerCount,
  }) async => false;

  Future<void> leaveMatchmaking() async {}

  Future<bool> attemptReconnect() async => false;

  Future<void> generateNewFood() async {}

  Future<void> checkGameEnd() async {}

  /// Pre-game ship spawn — pure geometry, kept because the game
  /// engine may still call it. Doesn't touch the network.
  List<Position> generateInitialShipPosition(int playerIndex, int boardSize) {
    final centerY = boardSize ~/ 2;
    final spacingY = boardSize ~/ 4;
    final y = (centerY + (playerIndex - 1) * spacingY).clamp(2, boardSize - 3);
    return [
      Position(2, y),
      Position(1, y),
      Position(0, y),
    ];
  }

  void dispose() {
    _gameStreamController.close();
    _gameActionsController.close();
    _matchmakingStreamController.close();
    _errorController.close();
  }
}
