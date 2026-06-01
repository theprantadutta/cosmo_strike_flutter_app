import 'package:equatable/equatable.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

// Re-export DPadPosition, BoardSize, and GameMode from constants
export 'package:cosmo_strike_flutter_app/utils/constants.dart'
    show DPadPosition, BoardSize, GameMode;

/// Status of the game settings cubit
enum GameSettingsStatus { initial, loading, ready }

/// State class for GameSettingsCubit
class GameSettingsState extends Equatable {
  final GameSettingsStatus status;
  final bool dPadEnabled;
  final DPadPosition dPadPosition;
  final BoardSize boardSize;
  final GameMode gameMode;
  final bool gameModeFirstLaunchPrompted;
  final Duration crashFeedbackDuration;
  final int highScore;
  final bool screenShakeEnabled;

  const GameSettingsState({
    this.status = GameSettingsStatus.initial,
    this.dPadEnabled = false,
    this.dPadPosition = DPadPosition.bottomCenter,
    this.boardSize = BoardSize.classic,
    this.gameMode = GameMode.classic,
    this.gameModeFirstLaunchPrompted = false,
    this.crashFeedbackDuration = GameConstants.defaultCrashFeedbackDuration,
    this.highScore = 0,
    this.screenShakeEnabled = false, // Disabled by default
  });

  /// Initial state
  factory GameSettingsState.initial() => const GameSettingsState();

  /// Create a copy with updated values
  GameSettingsState copyWith({
    GameSettingsStatus? status,
    bool? dPadEnabled,
    DPadPosition? dPadPosition,
    BoardSize? boardSize,
    GameMode? gameMode,
    bool? gameModeFirstLaunchPrompted,
    Duration? crashFeedbackDuration,
    int? highScore,
    bool? screenShakeEnabled,
  }) {
    return GameSettingsState(
      status: status ?? this.status,
      dPadEnabled: dPadEnabled ?? this.dPadEnabled,
      dPadPosition: dPadPosition ?? this.dPadPosition,
      boardSize: boardSize ?? this.boardSize,
      gameMode: gameMode ?? this.gameMode,
      gameModeFirstLaunchPrompted:
          gameModeFirstLaunchPrompted ?? this.gameModeFirstLaunchPrompted,
      crashFeedbackDuration:
          crashFeedbackDuration ?? this.crashFeedbackDuration,
      highScore: highScore ?? this.highScore,
      screenShakeEnabled: screenShakeEnabled ?? this.screenShakeEnabled,
    );
  }

  /// Whether settings are loaded and ready
  bool get isReady => status == GameSettingsStatus.ready;

  @override
  List<Object?> get props => [
    status,
    dPadEnabled,
    dPadPosition,
    boardSize,
    gameMode,
    gameModeFirstLaunchPrompted,
    crashFeedbackDuration,
    highScore,
    screenShakeEnabled,
  ];
}
