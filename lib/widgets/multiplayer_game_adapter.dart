import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/models/food.dart';
import 'package:cosmo_strike_flutter_app/models/game_state.dart';
import 'package:cosmo_strike_flutter_app/models/multiplayer_game.dart';
import 'package:cosmo_strike_flutter_app/models/position.dart';
import 'package:cosmo_strike_flutter_app/models/ship.dart';
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
  final List<Position> localShip;
  final Direction localDirection;
  final int localScore;
  final bool localIsAlive;

  const MultiplayerGameAdapter({
    super.key,
    required this.game,
    required this.currentUserId,
    required this.localShip,
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
    final ship = Ship.fromPositions(widget.localShip, widget.localDirection);

    // Convert food position
    Food? food;
    if (widget.game.foodPosition != null) {
      food = Food(position: widget.game.foodPosition!, type: FoodType.normal);
    }

    return GameState(
      ship: ship,
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

    // Track when ship changes for smooth animation
    if (oldWidget.localShip.length != widget.localShip.length ||
        (oldWidget.localShip.isNotEmpty &&
            widget.localShip.isNotEmpty &&
            oldWidget.localShip.first != widget.localShip.first)) {
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
                        // No grid — ships leave neon light-trails on the
                        // deep-space backdrop (the container gradient above).

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
                                  localShip: widget.localShip,
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

/// Main painter for all game content — ships (neon light-trails), food, effects
class _MultiplayerBoardPainter extends CustomPainter {
  final MultiplayerGame game;
  final String currentUserId;
  final List<Position> localShip;
  final Direction localDirection;
  final bool localIsAlive;
  final GameTheme theme;
  final Animation<double> pulseAnimation;
  final double moveProgress;
  final int boardSize;

  _MultiplayerBoardPainter({
    required this.game,
    required this.currentUserId,
    required this.localShip,
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

    // Draw food first (below ships)
    _drawFood(canvas, cellWidth, cellHeight);

    // Draw all ships - current player uses local state for smooth rendering
    for (var player in game.players) {
      final isCurrentPlayer = player.userId == currentUserId;

      if (isCurrentPlayer) {
        // Use local ship state for smooth rendering
        if (localShip.isNotEmpty) {
          final color =
              multiplayerColors[player.rank % multiplayerColors.length];
          _drawShip(
            canvas,
            localShip,
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
        if (player.ship.isNotEmpty) {
          final color =
              multiplayerColors[player.rank % multiplayerColors.length];
          _drawShip(
            canvas,
            player.ship,
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
    final center = Offset(
      foodPos.x * cellWidth + cellWidth / 2,
      foodPos.y * cellHeight + cellHeight / 2,
    );
    final baseRadius = math.min(cellWidth, cellHeight) * 0.34;
    final radius = baseRadius * pulseAnimation.value;
    final node = theme.neonSecondary;

    // Neon energy node: soft halo + solid core + bright ring (no apple dot).
    canvas.drawCircle(
      center,
      radius * 1.8,
      Paint()
        ..color = node.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(center, radius, Paint()..color = node);
    canvas.drawCircle(
      center,
      radius * 1.3,
      Paint()
        ..color = node.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawShip(
    Canvas canvas,
    List<Position> ship,
    Direction direction,
    bool isAlive,
    Color color,
    double cellWidth,
    double cellHeight, {
    required bool isCurrentPlayer,
    required String playerName,
  }) {
    if (ship.isEmpty) return;

    final isDead = !isAlive;
    final trailColor = isDead ? const Color(0xFF6B7280) : color;
    final lineW = math.min(cellWidth, cellHeight);

    // Segment centers (head -> tail).
    final pts = <Offset>[
      for (final s in ship)
        Offset(
          s.x * cellWidth + cellWidth / 2,
          s.y * cellHeight + cellHeight / 2,
        ),
    ];

    // Wide blurred glow underlay for the whole trail.
    if (!isDead && pts.length > 1) {
      final glowPath = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        glowPath.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        glowPath,
        Paint()
          ..color = trailColor.withValues(alpha: 0.30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineW * 0.9
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // Light-trail: bright at the head, fading + thinning toward the tail.
    for (int i = 0; i < pts.length - 1; i++) {
      final f = (1.0 - i / pts.length).clamp(0.12, 1.0);
      canvas.drawLine(
        pts[i],
        pts[i + 1],
        Paint()
          ..color = trailColor.withValues(alpha: (isDead ? 0.28 : 0.95) * f)
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineW * (0.30 + 0.30 * f)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // Directional chevron head (no eyes).
    final head = pts.first;
    final hs = lineW * 0.7;
    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(_directionAngle(direction));
    final chevron = Path()
      ..moveTo(hs * 0.6, 0)
      ..lineTo(-hs * 0.5, -hs * 0.46)
      ..lineTo(-hs * 0.2, 0)
      ..lineTo(-hs * 0.5, hs * 0.46)
      ..close();
    if (isCurrentPlayer && !isDead) {
      canvas.drawPath(
        chevron,
        Paint()
          ..color = trailColor.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawPath(
      chevron,
      Paint()..color = isDead ? trailColor : _lighten(trailColor, 0.18),
    );
    canvas.drawPath(
      chevron,
      Paint()
        ..color = Colors.white.withValues(alpha: isDead ? 0.3 : 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.restore();

    // Player name label above the head.
    final headCell = ship.first;
    final headX = headCell.x * cellWidth + cellWidth / 2;
    final headY = headCell.y * cellHeight - 8;
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

  /// Rotation for the head chevron (drawn pointing +x = right by default).
  double _directionAngle(Direction direction) {
    switch (direction) {
      case Direction.up:
        return -math.pi / 2;
      case Direction.down:
        return math.pi / 2;
      case Direction.left:
        return math.pi;
      case Direction.right:
        return 0;
    }
  }

  Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  bool shouldRepaint(covariant _MultiplayerBoardPainter oldDelegate) {
    return oldDelegate.game != game ||
        oldDelegate.localShip != localShip ||
        oldDelegate.localDirection != localDirection ||
        oldDelegate.localIsAlive != localIsAlive ||
        oldDelegate.theme != theme ||
        oldDelegate.currentUserId != currentUserId;
  }
}
