import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/models/food.dart';
import 'package:cosmo_strike_flutter_app/models/game_state.dart';
import 'package:cosmo_strike_flutter_app/models/multiplayer_game.dart';
import 'package:cosmo_strike_flutter_app/models/position.dart';
import 'package:cosmo_strike_flutter_app/models/snake.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/utils/direction.dart';
import 'package:cosmo_strike_flutter_app/widgets/advanced_particle_system.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// Player colors for multi-player games (matches backend)
const List<Color> multiplayerColors = [
  Color(0xFF4CAF50), // Green
  Color(0xFFF44336), // Red
  Color(0xFF2196F3), // Blue
  Color(0xFFFF9800), // Orange
  Color(0xFF9C27B0), // Purple
  Color(0xFF00BCD4), // Cyan
  Color(0xFFFFEB3B), // Yellow
  Color(0xFFE91E63), // Pink
];

/// Adapter widget that converts MultiplayerGame to work with the existing
/// single-player GameBoard widget. This allows us to reuse all the beautiful
/// rendering, animations, and effects from single-player.
class MultiplayerGameAdapter extends StatefulWidget {
  final MultiplayerGame game;
  final String currentUserId;
  final List<Position> localSnake;
  final Direction localDirection;
  final int localScore;
  final bool localIsAlive;

  const MultiplayerGameAdapter({
    super.key,
    required this.game,
    required this.currentUserId,
    required this.localSnake,
    required this.localDirection,
    required this.localScore,
    required this.localIsAlive,
  });

  @override
  State<MultiplayerGameAdapter> createState() => _MultiplayerGameAdapterState();
}

class _MultiplayerGameAdapterState extends State<MultiplayerGameAdapter>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _moveController;
  DateTime _lastGameStateChangeTime = DateTime.now();
  GameState? _lastGameState;

  // Particle manager for food/crash effects
  final ParticleManager _particleManager = ParticleManager();

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseController.repeat(reverse: true);

    // Smooth movement controller - drives 60fps animation
    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _moveController.dispose();
    _particleManager.clear();
    super.dispose();
  }

  int get boardSize => widget.game.gameSettings['boardSize'] ?? 20;
  int get gameSpeed => widget.game.gameSettings['initialSpeed'] ?? 200;

  /// Convert current player's multiplayer data to single-player GameState
  GameState _buildGameStateForCurrentPlayer() {
    final snake = Snake.fromPositions(widget.localSnake, widget.localDirection);

    // Convert food position
    Food? food;
    if (widget.game.foodPosition != null) {
      food = Food(position: widget.game.foodPosition!, type: FoodType.normal);
    }

    return GameState(
      snake: snake,
      food: food,
      score: widget.localScore,
      highScore: widget.localScore,
      boardWidth: boardSize,
      boardHeight: boardSize,
      status: widget.localIsAlive ? GameStatus.playing : GameStatus.crashed,
      level: 1,
      gameMode: GameMode.classic,
    );
  }

  /// Calculate move progress locally for smooth 60fps animation
  double _calculateMoveProgress() {
    final elapsed = DateTime.now()
        .difference(_lastGameStateChangeTime)
        .inMilliseconds;
    return (elapsed / gameSpeed).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(MultiplayerGameAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Track when snake changes for smooth animation
    if (oldWidget.localSnake.length != widget.localSnake.length ||
        (oldWidget.localSnake.isNotEmpty &&
            widget.localSnake.isNotEmpty &&
            oldWidget.localSnake.first != widget.localSnake.first)) {
      _lastGameStateChangeTime = DateTime.now();

      // Check for food consumption and add particle effect
      final oldGameState = _lastGameState;
      final newGameState = _buildGameStateForCurrentPlayer();
      if (oldGameState != null && newGameState.score > oldGameState.score) {
        _addFoodParticleEffect(oldGameState.food);
      }
      _lastGameState = newGameState;
    }
  }

  void _addFoodParticleEffect(Food? food) {
    if (food == null) return;

    final cellSize = 1.0; // Will be scaled by the CustomPaint
    final position = Offset(
      food.position.x * cellSize + cellSize / 2,
      food.position.y * cellSize + cellSize / 2,
    );

    _particleManager.emitAt(
      position,
      ParticleConfig.appleFoodExplosion,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;

        return BlocBuilder<PremiumCubit, PremiumState>(
          builder: (context, premiumState) {
            return RepaintBoundary(
              child: Container(
                margin: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  // Use theme colors with multiplayer purple accent
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.5,
                    colors: [
                      theme.accentColor.withValues(alpha: 0.12),
                      theme.backgroundColor.withValues(alpha: 0.98),
                      theme.backgroundColor,
                      Colors.black.withValues(alpha: 0.08),
                    ],
                    stops: const [0.0, 0.4, 0.8, 1.0],
                  ),
                  // Multiplayer uses purple/gold glow
                  border: Border.all(
                    color: Colors.purple.withValues(alpha: 0.7),
                    width: 4.0,
                  ),
                  borderRadius: BorderRadius.circular(0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.withValues(alpha: 0.35),
                      blurRadius: 20,
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.25),
                      blurRadius: 28,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 24,
                      spreadRadius: 1,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          theme.backgroundColor.withValues(alpha: 0.95),
                          theme.backgroundColor.withValues(alpha: 0.98),
                          theme.accentColor.withValues(alpha: 0.05),
                          theme.foodColor.withValues(alpha: 0.02),
                        ],
                        stops: const [0.0, 0.4, 0.8, 1.0],
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Grid pattern background
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GridBackgroundPainter(theme, boardSize),
                          ),
                        ),

                        // Main game content with all players
                        AspectRatio(
                          aspectRatio: 1.0,
                          child: AnimatedBuilder(
                            animation: _moveController,
                            builder: (context, child) {
                              final moveProgress = _calculateMoveProgress();

                              return CustomPaint(
                                painter: _MultiplayerBoardPainter(
                                  game: widget.game,
                                  currentUserId: widget.currentUserId,
                                  localSnake: widget.localSnake,
                                  localDirection: widget.localDirection,
                                  localIsAlive: widget.localIsAlive,
                                  theme: theme,
                                  pulseAnimation: _pulseAnimation,
                                  moveProgress: moveProgress,
                                  boardSize: boardSize,
                                ),
                                size: Size.infinite,
                              );
                            },
                          ),
                        ),

                        // Particle system
                        Positioned.fill(
                          child: AdvancedParticleSystem(
                            emissions: _particleManager.emissions,
                            autoRemoveEmissions: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Grid background painter
class _GridBackgroundPainter extends CustomPainter {
  final GameTheme theme;
  final int boardSize;

  _GridBackgroundPainter(this.theme, this.boardSize);

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / boardSize;
    final cellHeight = size.height / boardSize;

    final paint = Paint()
      ..color = theme.accentColor.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;

    // Draw vertical lines
    for (int x = 0; x <= boardSize; x++) {
      canvas.drawLine(
        Offset(x * cellWidth, 0),
        Offset(x * cellWidth, size.height),
        paint,
      );
    }

    // Draw horizontal lines
    for (int y = 0; y <= boardSize; y++) {
      canvas.drawLine(
        Offset(0, y * cellHeight),
        Offset(size.width, y * cellHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GridBackgroundPainter oldDelegate) =>
      oldDelegate.theme != theme || oldDelegate.boardSize != boardSize;
}

/// Main painter for all game content - snakes, food, effects
class _MultiplayerBoardPainter extends CustomPainter {
  final MultiplayerGame game;
  final String currentUserId;
  final List<Position> localSnake;
  final Direction localDirection;
  final bool localIsAlive;
  final GameTheme theme;
  final Animation<double> pulseAnimation;
  final double moveProgress;
  final int boardSize;

  _MultiplayerBoardPainter({
    required this.game,
    required this.currentUserId,
    required this.localSnake,
    required this.localDirection,
    required this.localIsAlive,
    required this.theme,
    required this.pulseAnimation,
    required this.moveProgress,
    required this.boardSize,
  }) : super(repaint: pulseAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / boardSize;
    final cellHeight = size.height / boardSize;

    // Draw food first (below snakes)
    _drawFood(canvas, cellWidth, cellHeight);

    // Draw all snakes - current player uses local state for smooth rendering
    for (var player in game.players) {
      final isCurrentPlayer = player.userId == currentUserId;

      if (isCurrentPlayer) {
        // Use local snake state for smooth rendering
        if (localSnake.isNotEmpty) {
          final color =
              multiplayerColors[player.rank % multiplayerColors.length];
          _drawSnake(
            canvas,
            localSnake,
            localDirection,
            localIsAlive,
            color,
            cellWidth,
            cellHeight,
            isCurrentPlayer: true,
            playerName: 'You',
          );
        }
      } else {
        // Use server state for other players
        if (player.snake.isNotEmpty) {
          final color =
              multiplayerColors[player.rank % multiplayerColors.length];
          _drawSnake(
            canvas,
            player.snake,
            player.currentDirection,
            player.isAlive,
            color,
            cellWidth,
            cellHeight,
            isCurrentPlayer: false,
            playerName: player.publicLabel,
          );
        }
      }
    }
  }

  void _drawFood(Canvas canvas, double cellWidth, double cellHeight) {
    if (game.foodPosition == null) return;

    final foodPos = game.foodPosition!;
    final centerX = foodPos.x * cellWidth + cellWidth / 2;
    final centerY = foodPos.y * cellHeight + cellHeight / 2;
    final baseRadius = math.min(cellWidth, cellHeight) * 0.35;
    final radius = baseRadius * pulseAnimation.value;

    // Glow effect
    final glowPaint = Paint()
      ..color = theme.foodColor.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset(centerX, centerY), radius * 1.5, glowPaint);

    // Main food circle with gradient
    final foodPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [theme.foodColor, theme.foodColor.withValues(alpha: 0.8)],
          ).createShader(
            Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
          );
    canvas.drawCircle(Offset(centerX, centerY), radius, foodPaint);

    // Highlight
    final highlightPaint = Paint()..color = Colors.white.withValues(alpha: 0.6);
    canvas.drawCircle(
      Offset(centerX - radius * 0.3, centerY - radius * 0.3),
      radius * 0.2,
      highlightPaint,
    );
  }

  void _drawSnake(
    Canvas canvas,
    List<Position> snake,
    Direction direction,
    bool isAlive,
    Color color,
    double cellWidth,
    double cellHeight, {
    required bool isCurrentPlayer,
    required String playerName,
  }) {
    if (snake.isEmpty) return;

    final isDead = !isAlive;
    final baseColor = isDead ? Colors.grey : color;

    // Draw body segments (from tail to head)
    for (int i = snake.length - 1; i >= 0; i--) {
      final segment = snake[i];
      final isHead = i == 0;

      final centerX = segment.x * cellWidth + cellWidth / 2;
      final centerY = segment.y * cellHeight + cellHeight / 2;

      // Calculate segment size (head is larger, tail tapers)
      double segmentSize;
      if (isHead) {
        segmentSize = math.min(cellWidth, cellHeight) * 0.45;
      } else {
        // Taper towards tail
        final taperFactor = 1.0 - (i / snake.length) * 0.3;
        segmentSize = math.min(cellWidth, cellHeight) * 0.38 * taperFactor;
      }

      // Gradient for 3D effect
      final segmentPaint = Paint()
        ..shader =
            RadialGradient(
              center: const Alignment(-0.3, -0.3),
              colors: [
                _lighten(baseColor, 0.3),
                baseColor,
                _darken(baseColor, 0.2),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(
              Rect.fromCircle(
                center: Offset(centerX, centerY),
                radius: segmentSize,
              ),
            );

      // Draw glow for current player's head
      if (isHead && isCurrentPlayer && !isDead) {
        final glowPaint = Paint()
          ..color = baseColor.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(
          Offset(centerX, centerY),
          segmentSize * 1.4,
          glowPaint,
        );
      }

      // Draw segment with rounded corners
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, centerY),
          width: segmentSize * 2,
          height: segmentSize * 2,
        ),
        Radius.circular(segmentSize * 0.4),
      );
      canvas.drawRRect(rect, segmentPaint);

      // Draw eyes on head
      if (isHead) {
        _drawEyes(
          canvas,
          Offset(centerX, centerY),
          direction,
          segmentSize,
          baseColor,
          isDead,
        );
      }

      // Draw border for visibility
      final borderPaint = Paint()
        ..color = _darken(baseColor, 0.4).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRRect(rect, borderPaint);
    }

    // Draw player name label above head
    if (snake.isNotEmpty) {
      final head = snake.first;
      final headX = head.x * cellWidth + cellWidth / 2;
      final headY = head.y * cellHeight - 8;

      final textPainter = TextPainter(
        text: TextSpan(
          text: playerName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.8),
                offset: const Offset(1, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(headX - textPainter.width / 2, headY - textPainter.height),
      );
    }
  }

  void _drawEyes(
    Canvas canvas,
    Offset center,
    Direction direction,
    double headSize,
    Color snakeColor,
    bool isDead,
  ) {
    final eyeRadius = headSize * 0.2;
    final eyeOffset = headSize * 0.35;

    Offset leftEyePos;
    Offset rightEyePos;

    switch (direction) {
      case Direction.up:
        leftEyePos = Offset(center.dx - eyeOffset, center.dy - eyeOffset * 0.5);
        rightEyePos = Offset(
          center.dx + eyeOffset,
          center.dy - eyeOffset * 0.5,
        );
        break;
      case Direction.down:
        leftEyePos = Offset(center.dx - eyeOffset, center.dy + eyeOffset * 0.5);
        rightEyePos = Offset(
          center.dx + eyeOffset,
          center.dy + eyeOffset * 0.5,
        );
        break;
      case Direction.left:
        leftEyePos = Offset(center.dx - eyeOffset * 0.5, center.dy - eyeOffset);
        rightEyePos = Offset(
          center.dx - eyeOffset * 0.5,
          center.dy + eyeOffset,
        );
        break;
      case Direction.right:
        leftEyePos = Offset(center.dx + eyeOffset * 0.5, center.dy - eyeOffset);
        rightEyePos = Offset(
          center.dx + eyeOffset * 0.5,
          center.dy + eyeOffset,
        );
        break;
    }

    // Eye whites
    final eyeWhitePaint = Paint()..color = Colors.white;
    canvas.drawCircle(leftEyePos, eyeRadius, eyeWhitePaint);
    canvas.drawCircle(rightEyePos, eyeRadius, eyeWhitePaint);

    // Pupils (X for dead snake)
    if (isDead) {
      final xPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      // Draw X on each eye
      for (final eyePos in [leftEyePos, rightEyePos]) {
        canvas.drawLine(
          Offset(eyePos.dx - eyeRadius * 0.5, eyePos.dy - eyeRadius * 0.5),
          Offset(eyePos.dx + eyeRadius * 0.5, eyePos.dy + eyeRadius * 0.5),
          xPaint,
        );
        canvas.drawLine(
          Offset(eyePos.dx + eyeRadius * 0.5, eyePos.dy - eyeRadius * 0.5),
          Offset(eyePos.dx - eyeRadius * 0.5, eyePos.dy + eyeRadius * 0.5),
          xPaint,
        );
      }
    } else {
      final pupilPaint = Paint()..color = Colors.black;
      final pupilRadius = eyeRadius * 0.5;
      canvas.drawCircle(leftEyePos, pupilRadius, pupilPaint);
      canvas.drawCircle(rightEyePos, pupilRadius, pupilPaint);
    }
  }

  Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color _darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  bool shouldRepaint(covariant _MultiplayerBoardPainter oldDelegate) {
    return oldDelegate.game != game ||
        oldDelegate.localSnake != localSnake ||
        oldDelegate.localDirection != localDirection ||
        oldDelegate.localIsAlive != localIsAlive ||
        oldDelegate.theme != theme ||
        oldDelegate.currentUserId != currentUserId;
  }
}
