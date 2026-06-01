import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/models/multiplayer_game.dart';
import 'package:cosmo_strike_flutter_app/models/position.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/multiplayer/multiplayer_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/utils/direction.dart';
import 'package:cosmo_strike_flutter_app/widgets/multiplayer_game_adapter.dart';
import 'package:cosmo_strike_flutter_app/widgets/swipe_detector.dart';
import 'package:cosmo_strike_flutter_app/widgets/screen_shake.dart';
import 'package:cosmo_strike_flutter_app/widgets/crash_feedback_overlay.dart';
import 'package:cosmo_strike_flutter_app/models/game_state.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

class MultiplayerGameScreen extends StatefulWidget {
  const MultiplayerGameScreen({super.key});

  @override
  State<MultiplayerGameScreen> createState() => _MultiplayerGameScreenState();
}

class _MultiplayerGameScreenState extends State<MultiplayerGameScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  Timer? _gameTimer;
  late FocusNode _keyboardFocusNode;

  // Juice effects controller (like single-player)
  late GameJuiceController _juiceController;

  // Animation controllers for UI polish
  late AnimationController _gestureIndicatorController;
  Direction? _lastSwipeDirection;

  // Local game state for smooth gameplay
  List<Position> _mySnake = [];
  Direction _currentDirection = Direction.right;
  Direction _nextDirection = Direction.right;
  int _myScore = 0;
  bool _isAlive = true;

  // Crash state
  bool _showCrashOverlay = false;
  CrashReason? _crashReason;

  // Game settings
  int _boardSize = 20;
  int _gameSpeed = 200;

  // Track initialization
  bool _isGameInitialized = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Note: the status bar is hidden app-wide via WindowInsetsController in
    // MainActivity.kt — no per-screen tweak needed. The nav bar stays
    // visible for back-gesture access.

    _keyboardFocusNode = FocusNode();

    // Initialize juice controller for screen shake and effects
    _juiceController = GameJuiceController();

    // Gesture indicator animation
    _gestureIndicatorController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Initialize after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocusNode.requestFocus();
      _tryInitializeGame();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gameTimer?.cancel();
    _keyboardFocusNode.dispose();
    _juiceController.dispose();
    _gestureIndicatorController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Don't cancel timer in multiplayer - game continues on server
    }
  }

  void _tryInitializeGame() {
    if (_isGameInitialized) return;

    final multiplayerCubit = context.read<MultiplayerCubit>();
    final game = multiplayerCubit.state.currentGame;
    if (game == null) return;

    // Wait for game to be in "playing" status
    if (game.status != MultiplayerGameStatus.playing) return;

    final authState = context.read<AuthCubit>().state;
    _currentUserId = authState.userId;
    if (_currentUserId == null) return;

    final myPlayer = game.getPlayer(_currentUserId!);
    if (myPlayer == null || myPlayer.snake.isEmpty) return;

    // Initialize local state from server data
    _boardSize = game.gameSettings['boardSize'] ?? 20;
    _gameSpeed = game.gameSettings['initialSpeed'] ?? 200;
    _mySnake = List.from(myPlayer.snake);
    _currentDirection = myPlayer.currentDirection;
    _nextDirection = myPlayer.currentDirection;
    _myScore = myPlayer.score;
    _isAlive = myPlayer.status == PlayerStatus.playing;
    _isGameInitialized = true;

    debugPrint(
      '[MultiplayerGameScreen] Game initialized! Snake: ${_mySnake.length} segments',
    );
    _startGameLoop();
    setState(() {});
  }

  void _startGameLoop() {
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(Duration(milliseconds: _gameSpeed), (_) {
      if (_isAlive && _isGameInitialized) {
        _updateGame();
      }
    });
  }

  void _updateGame() {
    if (_mySnake.isEmpty || !_isAlive) return;

    // Update direction
    _currentDirection = _nextDirection;

    // Calculate new head position
    final head = _mySnake.first;
    final newHead = head.move(_currentDirection);

    // Check wall collision
    if (newHead.x < 0 ||
        newHead.x >= _boardSize ||
        newHead.y < 0 ||
        newHead.y >= _boardSize) {
      _handleCrash(CrashReason.wallCollision);
      return;
    }

    // Check self collision
    if (_mySnake.any((pos) => pos == newHead)) {
      _handleCrash(CrashReason.selfCollision);
      return;
    }

    // Check collision with other players
    final multiplayerCubit = context.read<MultiplayerCubit>();
    final game = multiplayerCubit.state.currentGame;
    if (game != null) {
      for (final player in game.players) {
        if (player.userId != _currentUserId && player.isAlive) {
          if (player.snake.any((pos) => pos == newHead)) {
            _handleCrash(CrashReason.selfCollision); // Player collision
            return;
          }
        }
      }
    }

    // Move snake
    _mySnake.insert(0, newHead);

    // Check food collision
    bool ateFood = false;
    if (game?.foodPosition == newHead) {
      ateFood = true;
      _myScore += 10;
      multiplayerCubit.onFoodEaten(10);
      _juiceController.foodEaten(); // Trigger juice effect
    } else if (game?.bonusFoodPosition == newHead) {
      ateFood = true;
      _myScore += 25;
      multiplayerCubit.onFoodEaten(25);
      _juiceController.bonusFoodEaten();
    } else if (game?.specialFoodPosition == newHead) {
      ateFood = true;
      _myScore += 50;
      multiplayerCubit.onFoodEaten(50);
      _juiceController.specialFoodEaten();
    }

    if (!ateFood) {
      _mySnake.removeLast();
    }

    // Send update to server
    multiplayerCubit.updateGameState(
      snake: _mySnake,
      score: _myScore,
      status: PlayerStatus.playing,
    );

    setState(() {});
  }

  void _handleCrash(CrashReason reason) {
    _isAlive = false;
    _gameTimer?.cancel();
    _crashReason = reason;
    _showCrashOverlay = true;

    final multiplayerCubit = context.read<MultiplayerCubit>();
    multiplayerCubit.onPlayerCrash();
    multiplayerCubit.checkGameEnd();

    // Trigger crash juice effects
    if (reason == CrashReason.wallCollision) {
      _juiceController.wallHit();
    } else {
      _juiceController.selfCollision();
    }

    // Play crash haptic
    HapticFeedback.heavyImpact();

    setState(() {});

    // Auto-dismiss crash overlay after delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showCrashOverlay = false;
        });
        _showGameOverDialog();
      }
    });
  }

  void _handleSwipe(Direction direction) {
    // Prevent 180-degree turns
    if ((_currentDirection == Direction.up && direction == Direction.down) ||
        (_currentDirection == Direction.down && direction == Direction.up) ||
        (_currentDirection == Direction.left && direction == Direction.right) ||
        (_currentDirection == Direction.right && direction == Direction.left)) {
      return;
    }

    _nextDirection = direction;
    _lastSwipeDirection = direction;
    context.read<MultiplayerCubit>().changeDirection(direction);
    HapticFeedback.selectionClick();

    // Animate gesture indicator
    _gestureIndicatorController.forward().then((_) {
      _gestureIndicatorController.reverse();
    });
  }

  void _handleKeyPress(KeyEvent event) {
    if (event is KeyDownEvent) {
      Direction? direction;

      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
        case LogicalKeyboardKey.keyW:
          direction = Direction.up;
          break;
        case LogicalKeyboardKey.arrowDown:
        case LogicalKeyboardKey.keyS:
          direction = Direction.down;
          break;
        case LogicalKeyboardKey.arrowLeft:
        case LogicalKeyboardKey.keyA:
          direction = Direction.left;
          break;
        case LogicalKeyboardKey.arrowRight:
        case LogicalKeyboardKey.keyD:
          direction = Direction.right;
          break;
        case LogicalKeyboardKey.escape:
          _showExitDialog();
          break;
      }

      if (direction != null) {
        _handleSwipe(direction);
      }
    }
  }

  void _showGameOverDialog() {
    final theme = context.read<ThemeCubit>().state.currentTheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.accentColor.withValues(alpha: 0.5)),
        ),
        title: Row(
          children: [
            Icon(Icons.sports_score, color: theme.accentColor, size: 32),
            const SizedBox(width: 12),
            Text(
              'Game Over',
              style: TextStyle(
                color: theme.accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You finished the game!',
              style: TextStyle(color: theme.accentColor, fontSize: 16),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.accentColor.withValues(alpha: 0.1),
                    theme.accentColor.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.accentColor.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Your Score',
                    style: TextStyle(
                      color: theme.accentColor.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_myScore',
                    style: TextStyle(
                      color: theme.accentColor,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Length: ${_mySnake.length}',
                    style: TextStyle(
                      color: theme.accentColor.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              dialogContext.pop();
              _navigateToLobby();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Back to Lobby',
                style: TextStyle(
                  color: theme.accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToLobby() {
    context.read<MultiplayerCubit>().leaveGame();
    context.pushReplacement(AppRoutes.multiplayerLobby);
  }

  void _showExitDialog() {
    final theme = context.read<ThemeCubit>().state.currentTheme;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Leave Game?',
          style: TextStyle(
            color: theme.accentColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to leave the multiplayer game?',
          style: TextStyle(color: theme.accentColor),
        ),
        actions: [
          TextButton(
            onPressed: () => dialogContext.pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: theme.accentColor.withValues(alpha: 0.7)),
            ),
          ),
          TextButton(
            onPressed: () {
              dialogContext.pop();
              _navigateToLobby();
            },
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;

        return BlocListener<MultiplayerCubit, MultiplayerState>(
          listenWhen: (prev, curr) {
            // Trigger when game starts playing or when player data arrives
            if (!_isGameInitialized) {
              final prevPlaying =
                  prev.currentGame?.status == MultiplayerGameStatus.playing;
              final currPlaying =
                  curr.currentGame?.status == MultiplayerGameStatus.playing;

              // Trigger when status changes to playing
              if (!prevPlaying && currPlaying) return true;

              // Trigger when snakes appear
              final hadSnakes =
                  prev.currentGame?.players.any((p) => p.snake.isNotEmpty) ??
                  false;
              final hasSnakes =
                  curr.currentGame?.players.any((p) => p.snake.isNotEmpty) ??
                  false;
              return !hadSnakes && hasSnakes;
            }
            return false;
          },
          listener: (context, state) {
            _tryInitializeGame();
          },
          child: BlocBuilder<MultiplayerCubit, MultiplayerState>(
            builder: (context, multiplayerState) {
              return BlocBuilder<AuthCubit, AuthState>(
                builder: (context, authState) {
                  final game = multiplayerState.currentGame;

                  // Loading state
                  if (game == null || !multiplayerState.isGameActive) {
                    return Scaffold(
                      backgroundColor: theme.backgroundColor,
                      body: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.accentColor,
                          ),
                        ),
                      ),
                    );
                  }

                  // Waiting for snake data / game to start
                  if (!_isGameInitialized) {
                    return Scaffold(
                      backgroundColor: theme.backgroundColor,
                      body: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                theme.accentColor,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Starting game...',
                              style: TextStyle(
                                color: theme.accentColor,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return PopScope(
                    canPop: false,
                    onPopInvokedWithResult: (didPop, result) {
                      if (!didPop) {
                        _showExitDialog();
                      }
                    },
                    child: KeyboardListener(
                      focusNode: _keyboardFocusNode,
                      onKeyEvent: _handleKeyPress,
                      child: GameJuiceWidget(
                        controller: _juiceController,
                        applyShake: true,
                        applyScale: false,
                        child: Scaffold(
                          body: Container(
                            decoration: BoxDecoration(
                              // Use theme colors, matching single-player
                              gradient: RadialGradient(
                                center: Alignment.topRight,
                                radius: 1.5,
                                colors: [
                                  theme.accentColor.withValues(alpha: 0.15),
                                  theme.backgroundColor,
                                  theme.backgroundColor.withValues(alpha: 0.9),
                                  Colors.black.withValues(alpha: 0.1),
                                ],
                                stops: const [0.0, 0.4, 0.8, 1.0],
                              ),
                            ),
                            child: SafeArea(
                              child: Stack(
                                children: [
                                  // Background pattern
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _GameBackgroundPainter(theme),
                                    ),
                                  ),

                                  // Main game content
                                  SwipeDetector(
                                    onSwipe: _handleSwipe,
                                    showFeedback: false,
                                    child: Column(
                                      children: [
                                        // Multiplayer HUD
                                        _buildMultiplayerHUD(
                                          theme,
                                          game,
                                          authState,
                                        ),

                                        // Game hint row
                                        _buildGameHintRow(theme),

                                        // Game Board using adapter
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: MultiplayerGameAdapter(
                                              game: game,
                                              currentUserId:
                                                  _currentUserId ?? '',
                                              localSnake: _mySnake,
                                              localDirection: _currentDirection,
                                              localScore: _myScore,
                                              localIsAlive: _isAlive,
                                            ),
                                          ),
                                        ),

                                        // Bottom info bar
                                        _buildBottomInfoBar(theme, game),
                                      ],
                                    ),
                                  ),

                                  // Crash feedback overlay
                                  if (_showCrashOverlay && _crashReason != null)
                                    CrashFeedbackOverlay(
                                      crashReason: _crashReason!,
                                      theme: theme,
                                      onSkip: () {
                                        setState(() {
                                          _showCrashOverlay = false;
                                        });
                                        _showGameOverDialog();
                                      },
                                      duration: const Duration(seconds: 2),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildGameHintRow(GameTheme theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Game hint
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.backgroundColor.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.foodColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: theme.foodColor.withValues(alpha: 0.7),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Avoid walls, yourself & others!',
                  style: TextStyle(
                    color: theme.foodColor.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Gesture indicator
          AnimatedBuilder(
            animation: _gestureIndicatorController,
            builder: (context, child) {
              final isActive =
                  _lastSwipeDirection != null &&
                  _gestureIndicatorController.isAnimating;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.backgroundColor.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.accentColor.withValues(
                      alpha: isActive ? 0.7 : 0.3,
                    ),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedRotation(
                      turns: _getDirectionRotation(_lastSwipeDirection),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.arrow_upward_rounded,
                        color: theme.accentColor.withValues(
                          alpha: isActive ? 1.0 : 0.6,
                        ),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Swipe',
                      style: TextStyle(
                        color: theme.accentColor.withValues(
                          alpha: isActive ? 0.9 : 0.6,
                        ),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  double _getDirectionRotation(Direction? direction) {
    if (direction == null) return 0.0;
    switch (direction) {
      case Direction.up:
        return 0.0;
      case Direction.right:
        return 0.25;
      case Direction.down:
        return 0.5;
      case Direction.left:
        return 0.75;
    }
  }

  Widget _buildMultiplayerHUD(
    GameTheme theme,
    MultiplayerGame game,
    AuthState authState,
  ) {
    final playerCount = game.players.length;
    final alivePlayers = game.players.where((p) => p.isAlive).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: _showExitDialog,
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: theme.accentColor,
              size: 22,
            ),
          ),

          const SizedBox(width: 8),

          // Mode indicator with theme-based styling
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.purple.withValues(alpha: 0.3),
                  Colors.amber.withValues(alpha: 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sports_esports, color: Colors.amber, size: 16),
                const SizedBox(width: 6),
                Text(
                  playerCount == 2 ? 'VS' : 'BATTLE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Your score
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Text(
                  '$_myScore',
                  style: TextStyle(
                    color: theme.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Alive count (for 4+ players)
          if (playerCount > 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$alivePlayers/$playerCount',
                style: const TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomInfoBar(GameTheme theme, MultiplayerGame game) {
    // Sort players by score (descending)
    final sortedPlayers = List<MultiplayerPlayer>.from(game.players)
      ..sort((a, b) => b.score.compareTo(a.score));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.8),
        border: Border(
          top: BorderSide(color: theme.accentColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          // Leaderboard
          Expanded(
            child: SizedBox(
              height: 50,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sortedPlayers.length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final player = sortedPlayers[index];
                  final isMe = player.userId == _currentUserId;
                  final playerColor =
                      multiplayerColors[player.rank % multiplayerColors.length];

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? playerColor.withValues(alpha: 0.2)
                          : theme.backgroundColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: player.isAlive
                            ? playerColor.withValues(alpha: 0.5)
                            : Colors.grey.withValues(alpha: 0.3),
                        width: isMe ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Rank indicator
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: index == 0
                                ? Colors.amber
                                : index == 1
                                ? Colors.grey.shade400
                                : index == 2
                                ? Colors.brown.shade400
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: index < 3 ? Colors.white : playerColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Player color dot
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: player.isAlive ? playerColor : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Name and score
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMe
                                  ? 'You'
                                  : (player.publicLabel.length > 8
                                        ? '${player.publicLabel.substring(0, 8)}...'
                                        : player.publicLabel),
                              style: TextStyle(
                                color: player.isAlive
                                    ? theme.accentColor
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                decoration: player.isAlive
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            Text(
                              '${isMe ? _myScore : player.score} pts',
                              style: TextStyle(
                                color: player.isAlive
                                    ? theme.accentColor.withValues(alpha: 0.7)
                                    : Colors.grey,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Snake length indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.straighten,
                  color: theme.accentColor.withValues(alpha: 0.7),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_mySnake.length}',
                  style: TextStyle(
                    color: theme.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Background pattern painter (matching single-player)
class _GameBackgroundPainter extends CustomPainter {
  final GameTheme theme;

  _GameBackgroundPainter(this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = theme.accentColor.withValues(alpha: 0.05);

    // Draw subtle grid pattern
    const gridSize = 30.0;

    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Draw decorative shapes
    final shapePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = theme.foodColor.withValues(alpha: 0.02);

    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.25),
      50,
      shapePaint,
    );

    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.75),
      70,
      shapePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! _GameBackgroundPainter || oldDelegate.theme != theme;
  }
}
