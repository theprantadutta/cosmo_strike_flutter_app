import 'package:equatable/equatable.dart';
import 'package:cosmo_strike_flutter_app/models/food.dart';
import 'package:cosmo_strike_flutter_app/models/game_state.dart' as model;
import 'package:cosmo_strike_flutter_app/models/power_up.dart';
import 'package:cosmo_strike_flutter_app/models/position.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/utils/direction.dart';

/// Game play status
enum GamePlayStatus { initial, ready, playing, paused, crashed, gameOver }

/// State class for GameCubit
/// This is a simplified view of the game state for UI consumption
class GameCubitState extends Equatable {
  final GamePlayStatus status;
  final model.GameState? gameState;
  final String? tournamentId;
  final TournamentGameMode? tournamentMode;
  final double moveProgress;
  final model.GameState? previousGameState;
  /// Timestamp of the last rejected direction input (reverse-into-self or
  /// already-queued). Input widgets watch this to flash a red "denied" cue
  /// when fresh (within ~250ms). Cleared back to null by a Timer in the
  /// cubit so the flash doesn't linger.
  final DateTime? lastRejectedInputAt;
  /// Timestamp + direction of the last accepted direction input. Drives the
  /// edge-bloom pulse (250ms) and the ship-head intent shimmer (~100ms)
  /// so the player gets a glance-level "did it register?" answer before
  /// the next tick actually turns the ship. Cleared by a Timer in the
  /// cubit so neither layer lingers.
  final DateTime? lastAcceptedInputAt;
  final Direction? lastAcceptedDirection;
  /// Total coins credited to the user during the current (or just-ended)
  /// game session — sum of game_completed, perfect_game, long_survival,
  /// and level_up grants reflected after Pro multipliers and daily cap.
  /// Reset to 0 on each new game start; read by the game-over screen.
  final int coinsEarnedThisGame;

  /// True while the post-crash "Continue / revive" offer is on screen (the
  /// game has crashed but we're waiting on the player to revive or decline
  /// before transitioning to game-over). Drives [ReviveOverlay].
  final bool offeringRevive;

  /// True while the Time-Attack "+30s / watch ad" offer is on screen (the
  /// timer hit zero but the run is frozen awaiting the player's choice before
  /// transitioning to game-over). Drives [TimeBonusOverlay].
  final bool offeringTimeBonus;

  const GameCubitState({
    this.status = GamePlayStatus.initial,
    this.gameState,
    this.tournamentId,
    this.tournamentMode,
    this.moveProgress = 0.0,
    this.previousGameState,
    this.lastRejectedInputAt,
    this.lastAcceptedInputAt,
    this.lastAcceptedDirection,
    this.coinsEarnedThisGame = 0,
    this.offeringRevive = false,
    this.offeringTimeBonus = false,
  });

  /// Initial state
  factory GameCubitState.initial() => const GameCubitState();

  /// Create a copy with updated values
  GameCubitState copyWith({
    GamePlayStatus? status,
    model.GameState? gameState,
    String? tournamentId,
    TournamentGameMode? tournamentMode,
    double? moveProgress,
    model.GameState? previousGameState,
    DateTime? lastRejectedInputAt,
    DateTime? lastAcceptedInputAt,
    Direction? lastAcceptedDirection,
    int? coinsEarnedThisGame,
    bool? offeringRevive,
    bool? offeringTimeBonus,
    bool clearTournament = false,
    bool clearPreviousGameState = false,
    bool clearRejectedInput = false,
    bool clearAcceptedInput = false,
  }) {
    return GameCubitState(
      status: status ?? this.status,
      gameState: gameState ?? this.gameState,
      tournamentId: clearTournament
          ? null
          : (tournamentId ?? this.tournamentId),
      tournamentMode: clearTournament
          ? null
          : (tournamentMode ?? this.tournamentMode),
      moveProgress: moveProgress ?? this.moveProgress,
      previousGameState: clearPreviousGameState
          ? null
          : (previousGameState ?? this.previousGameState),
      lastRejectedInputAt: clearRejectedInput
          ? null
          : (lastRejectedInputAt ?? this.lastRejectedInputAt),
      lastAcceptedInputAt: clearAcceptedInput
          ? null
          : (lastAcceptedInputAt ?? this.lastAcceptedInputAt),
      lastAcceptedDirection: clearAcceptedInput
          ? null
          : (lastAcceptedDirection ?? this.lastAcceptedDirection),
      coinsEarnedThisGame: coinsEarnedThisGame ?? this.coinsEarnedThisGame,
      offeringRevive: offeringRevive ?? this.offeringRevive,
      offeringTimeBonus: offeringTimeBonus ?? this.offeringTimeBonus,
    );
  }

  /// Whether game is playing
  bool get isPlaying => status == GamePlayStatus.playing;

  /// Whether game is paused
  bool get isPaused => status == GamePlayStatus.paused;

  /// Whether game is over
  bool get isGameOver => status == GamePlayStatus.gameOver;

  /// Whether game is in crash feedback state
  bool get isCrashed => status == GamePlayStatus.crashed;

  /// Whether in tournament mode
  bool get isTournamentMode => tournamentId != null;

  /// Current score
  int get score => gameState?.score ?? 0;

  /// Current level
  int get level => gameState?.level ?? 1;

  /// Ship body positions
  List<Position> get shipBody => gameState?.ship.body ?? [];

  /// Ship head position
  Position? get shipHead => gameState?.ship.head;

  /// Current food
  Food? get food => gameState?.food;

  /// Current power-up on field
  PowerUp? get powerUp => gameState?.powerUp;

  /// Active power-ups
  List<ActivePowerUp> get activePowerUps => gameState?.activePowerUps ?? [];

  /// Current combo
  int get currentCombo => gameState?.currentCombo ?? 0;

  /// Combo multiplier
  double get comboMultiplier => gameState?.comboMultiplier ?? 1.0;

  /// Board width
  int get boardWidth => gameState?.boardWidth ?? 20;

  /// Board height
  int get boardHeight => gameState?.boardHeight ?? 20;

  /// High score
  int get highScore => gameState?.highScore ?? 0;

  /// Crash reason (if game over)
  model.CrashReason? get crashReason => gameState?.crashReason;

  /// Crash position (if game over)
  Position? get crashPosition => gameState?.crashPosition;

  @override
  List<Object?> get props => [
    status,
    gameState,
    tournamentId,
    tournamentMode,
    moveProgress,
    previousGameState,
    lastRejectedInputAt,
    lastAcceptedInputAt,
    lastAcceptedDirection,
    coinsEarnedThisGame,
    offeringRevive,
    offeringTimeBonus,
  ];
}
