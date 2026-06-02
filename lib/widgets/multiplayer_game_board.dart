import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/models/multiplayer_game.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/direction.dart';

/// A beautiful game board for multiplayer ship games.
/// Renders multiple ships with different colors, food, and effects.
class MultiplayerGameBoard extends StatefulWidget {
  final MultiplayerGame game;
  final String currentUserId;
  final double cellSize;

  /// Ship colors for different players
  static const List<Color> playerColors = [
    Color(0xFF4CAF50), // Green
    Color(0xFFF44336), // Red
    Color(0xFF2196F3), // Blue
    Color(0xFFFF9800), // Orange
    Color(0xFF9C27B0), // Purple
    Color(0xFF00BCD4), // Cyan
    Color(0xFFFFEB3B), // Yellow
    Color(0xFFE91E63), // Pink
  ];

  const MultiplayerGameBoard({
    super.key,
    required this.game,
    required this.currentUserId,
    this.cellSize = GameConstants.cellSize,
  });

  @override
  State<MultiplayerGameBoard> createState() => _MultiplayerGameBoardState();
}

class _MultiplayerGameBoardState extends State<MultiplayerGameBoard>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _moveController;

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

    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _moveController.dispose();
    super.dispose();
  }

  int get boardSize => widget.game.gameSettings['boardSize'] ?? 20;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;

        return RepaintBoundary(
          child: Container(
            margin: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              // Enhanced gradient background
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
                        painter: _GridPainter(theme, boardSize),
                      ),
                    ),
                    // Game content
                    AspectRatio(
                      aspectRatio: 1.0,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: _MultiplayerBoardPainter(
                              game: widget.game,
                              currentUserId: widget.currentUserId,
                              theme: theme,
                              pulseAnimation: _pulseAnimation,
                              boardSize: boardSize,
                            ),
                            size: Size.infinite,
                          );
                        },
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
  }
}

/// Draws the grid background
class _GridPainter extends CustomPainter {
  final GameTheme theme;
  final int boardSize;

  _GridPainter(this.theme, this.boardSize);

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
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.theme != theme || oldDelegate.boardSize != boardSize;
}

/// Main painter for multiplayer game content
class _MultiplayerBoardPainter extends CustomPainter {
  final MultiplayerGame game;
  final String currentUserId;
  final GameTheme theme;
  final Animation<double> pulseAnimation;
  final int boardSize;

  _MultiplayerBoardPainter({
    required this.game,
    required this.currentUserId,
    required this.theme,
    required this.pulseAnimation,
    required this.boardSize,
  }) : super(repaint: pulseAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    final cellWidth = size.width / boardSize;
    final cellHeight = size.height / boardSize;

    // Draw food
    _drawFood(canvas, cellWidth, cellHeight);

    // Draw all ships
    for (var player in game.players) {
      if (player.ship.isNotEmpty) {
        final color =
            MultiplayerGameBoard.playerColors[player.rank %
                MultiplayerGameBoard.playerColors.length];
        final isCurrentPlayer = player.userId == currentUserId;
        _drawShip(
          canvas,
          player,
          color,
          cellWidth,
          cellHeight,
          isCurrentPlayer,
        );
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

    // Main food circle
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

  void _drawShip(
    Canvas canvas,
    MultiplayerPlayer player,
    Color color,
    double cellWidth,
    double cellHeight,
    bool isCurrentPlayer,
  ) {
    final ship = player.ship;
    if (ship.isEmpty) return;

    final isDead = player.status == PlayerStatus.crashed;
    final baseColor = isDead ? Colors.grey : color;

    // Draw body segments (from tail to head)
    for (int i = ship.length - 1; i >= 0; i--) {
      final segment = ship[i];
      final isHead = i == 0;

      final centerX = segment.x * cellWidth + cellWidth / 2;
      final centerY = segment.y * cellHeight + cellHeight / 2;

      // Calculate segment size (head is larger)
      final segmentSize = isHead
          ? math.min(cellWidth, cellHeight) * 0.45
          : math.min(cellWidth, cellHeight) * 0.38;

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
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
        canvas.drawCircle(
          Offset(centerX, centerY),
          segmentSize * 1.3,
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
          player.currentDirection,
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
    if (ship.isNotEmpty) {
      final head = ship.first;
      final headX = head.x * cellWidth + cellWidth / 2;
      final headY = head.y * cellHeight - 8;

      final textPainter = TextPainter(
        text: TextSpan(
          text: isCurrentPlayer ? 'You' : player.publicLabel,
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
    Color shipColor,
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

    // Pupils (X for dead ship)
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
        oldDelegate.theme != theme ||
        oldDelegate.currentUserId != currentUserId;
  }
}
