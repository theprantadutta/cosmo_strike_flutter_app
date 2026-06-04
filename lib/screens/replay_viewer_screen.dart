import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/models/game_replay.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';

class ReplayViewerScreen extends StatefulWidget {
  /// The replay ID for deep link support.
  final String replayId;

  /// Optional replay object (for instant display when navigating with object).
  final GameReplay? replay;

  const ReplayViewerScreen({
    super.key,
    required this.replayId,
    this.replay,
  });

  @override
  State<ReplayViewerScreen> createState() => _ReplayViewerScreenState();
}

class _ReplayViewerScreenState extends State<ReplayViewerScreen> {
  final StorageService _storageService = StorageService();

  GameReplay? _replay;
  int _currentFrameIndex = 0;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  Timer? _playbackTimer;
  bool _isLoadingReplay = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _replay = widget.replay;

    if (_replay == null) {
      // Deep link: need to load replay from storage
      _loadReplayFromId();
    }
  }

  Future<void> _loadReplayFromId() async {
    setState(() {
      _isLoadingReplay = true;
      _loadError = null;
    });

    try {
      final replayJson = await _storageService.getReplay(widget.replayId);
      if (mounted) {
        if (replayJson != null) {
          final data = json.decode(replayJson) as Map<String, dynamic>;
          setState(() {
            _replay = GameReplay.fromJson(data);
            _isLoadingReplay = false;
          });
        } else {
          setState(() {
            _loadError = 'Replay not found';
            _isLoadingReplay = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = 'Failed to load replay';
          _isLoadingReplay = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  GameFrame? get _currentFrame {
    final replay = _replay;
    if (replay == null) return null;
    return replay.frames.isNotEmpty && _currentFrameIndex < replay.frames.length
        ? replay.frames[_currentFrameIndex]
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final theme = themeState.currentTheme;

    return CommandScaffold(
      theme: theme,
      title: _replay != null
          ? 'Replay: ${_replay!.playerName}'
          : 'Loading Replay...',
      bottomBar: const ShipBannerAd(),
      bodyPadding: EdgeInsets.zero,
      body: _buildContent(theme),
    );
  }

  Widget _buildContent(GameTheme theme) {
    // Show loading state when fetching replay from deep link
    if (_isLoadingReplay) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(theme.accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading replay...',
              style: TextStyle(
                color: theme.accentColor.withValues(alpha: 0.8),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    // Show error state
    if (_loadError != null || _replay == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.accentColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _loadError ?? 'Replay not found',
              style: TextStyle(
                color: theme.accentColor.withValues(alpha: 0.8),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            NeonButton(
              onPressed: () => Navigator.of(context).pop(),
              label: 'Go Back',
              icon: Icons.arrow_back,
              theme: theme,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Game info header
        _buildGameInfo(theme),

        const SizedBox(height: 16),

        // Game board
        Expanded(child: Center(child: _buildGameBoard(theme))),

        const SizedBox(height: 16),

        // Playback controls
        _buildPlaybackControls(theme),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildGameInfo(GameTheme theme) {
    final replay = _replay!;
    final frame = _currentFrame;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassPanel(
      theme: theme,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildInfoItem(
                'Score',
                frame?.score.toString() ?? '0',
                Icons.star,
              ),
              _buildInfoItem(
                'Level',
                frame?.level.toString() ?? '1',
                Icons.trending_up,
              ),
              _buildInfoItem(
                'Frame',
                '${_currentFrameIndex + 1}/${replay.totalFrames}',
                Icons.movie,
              ),
              _buildInfoItem(
                'Time',
                replay.formattedDuration,
                Icons.timer,
              ),
            ],
          ),

          // Reserve a fixed slot for the event chip so the surrounding
          // card doesn't grow/shrink each time a frame has (or stops
          // having) a `gameEvent`. AnimatedSwitcher fades the chip in
          // and out within the fixed slot. Height = 12 (gap) + ~28
          // (chip with v6 padding around a 12-px text line).
          const SizedBox(height: 12),
          SizedBox(
            height: 28,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: frame?.gameEvent != null
                  ? Container(
                      key: ValueKey('event-${frame!.frameNumber}'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formatGameEvent(frame.gameEvent!),
                        style: TextStyle(
                          color: theme.accentColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('event-empty')),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.7)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildGameBoard(GameTheme theme) {
    final frame = _currentFrame;
    if (frame == null) {
      return Container(
        width: 300,
        height: 300,
        decoration: BoxDecoration(
          color: theme.backgroundColor.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3)),
        ),
        child: const Center(
          child: Text('No frame data', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    const boardWidth = 20;
    const boardHeight = 20;
    const cellSize = 12.0;

    return Container(
      width: boardWidth * cellSize + 2,
      height: boardHeight * cellSize + 2,
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      child: CustomPaint(
        painter: ReplayBoardPainter(
          frame: frame,
          theme: theme,
          cellSize: cellSize,
        ),
      ),
    );
  }

  Widget _buildPlaybackControls(GameTheme theme) {
    final replay = _replay!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassPanel(
      theme: theme,
      child: Column(
        children: [
          // Progress slider
          Row(
            children: [
              Text(
                '${_currentFrameIndex + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  value: _currentFrameIndex.toDouble(),
                  min: 0,
                  max: (replay.totalFrames - 1).toDouble(),
                  onChanged: (value) {
                    setState(() {
                      _currentFrameIndex = value.round();
                    });
                  },
                  activeColor: theme.accentColor,
                  inactiveColor: theme.primaryColor.withValues(alpha: 0.3),
                ),
              ),
              Text(
                replay.totalFrames.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Previous frame
              IconButton(
                onPressed: _currentFrameIndex > 0 ? _previousFrame : null,
                icon: const Icon(Icons.skip_previous),
                color: theme.accentColor,
              ),

              // Step backward
              IconButton(
                onPressed: _currentFrameIndex > 0
                    ? () => _seekFrames(-1)
                    : null,
                icon: const Icon(Icons.keyboard_arrow_left),
                color: theme.primaryColor,
              ),

              // Play/Pause
              IconButton(
                onPressed: _togglePlayback,
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                color: theme.accentColor,
                iconSize: 32,
              ),

              // Step forward
              IconButton(
                onPressed: _currentFrameIndex < replay.totalFrames - 1
                    ? () => _seekFrames(1)
                    : null,
                icon: const Icon(Icons.keyboard_arrow_right),
                color: theme.primaryColor,
              ),

              // Next frame
              IconButton(
                onPressed: _currentFrameIndex < replay.totalFrames - 1
                    ? _nextFrame
                    : null,
                icon: const Icon(Icons.skip_next),
                color: theme.accentColor,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Speed control
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Speed: ',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (double speed in [0.25, 0.5, 1.0, 2.0, 4.0])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text('${speed}x'),
                            selected: _playbackSpeed == speed,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _playbackSpeed = speed;
                                });
                                if (_isPlaying) {
                                  _startPlayback();
                                }
                              }
                            },
                            selectedColor: theme.accentColor.withValues(
                              alpha: 0.3,
                            ),
                            backgroundColor: theme.primaryColor.withValues(
                              alpha: 0.1,
                            ),
                            labelStyle: TextStyle(
                              color: _playbackSpeed == speed
                                  ? theme.accentColor
                                  : Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _pausePlayback();
    } else {
      _startPlayback();
    }
  }

  void _startPlayback() {
    final replay = _replay;
    if (replay == null) return;

    if (_currentFrameIndex >= replay.totalFrames - 1) {
      _currentFrameIndex = 0;
    }

    setState(() {
      _isPlaying = true;
    });

    _playbackTimer?.cancel();
    final interval = (100 / _playbackSpeed).round(); // Base 100ms interval

    _playbackTimer = Timer.periodic(Duration(milliseconds: interval), (_) {
      if (_currentFrameIndex < replay.totalFrames - 1) {
        setState(() {
          _currentFrameIndex++;
        });
      } else {
        _pausePlayback();
      }
    });
  }

  void _pausePlayback() {
    _playbackTimer?.cancel();
    setState(() {
      _isPlaying = false;
    });
  }

  void _previousFrame() {
    if (_currentFrameIndex > 0) {
      setState(() {
        _currentFrameIndex--;
      });
    }
  }

  void _nextFrame() {
    final replay = _replay;
    if (replay == null) return;

    if (_currentFrameIndex < replay.totalFrames - 1) {
      setState(() {
        _currentFrameIndex++;
      });
    }
  }

  void _seekFrames(int delta) {
    final replay = _replay;
    if (replay == null) return;

    final newIndex = (_currentFrameIndex + delta).clamp(
      0,
      replay.totalFrames - 1,
    );
    setState(() {
      _currentFrameIndex = newIndex;
    });
  }

  String _formatGameEvent(Map<String, dynamic> event) {
    final type = event['type'] as String;
    switch (type) {
      case 'food_consumed':
        return '💥 Destroyed ${event['foodType']} enemy';
      case 'power_up_collected':
        return '⚡ Collected ${event['powerUpType']} power-up';
      default:
        return event.toString();
    }
  }
}

class ReplayBoardPainter extends CustomPainter {
  final GameFrame frame;
  final GameTheme theme;
  final double cellSize;

  ReplayBoardPainter({
    required this.frame,
    required this.theme,
    required this.cellSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Draw ship
    if (frame.shipPositions.isNotEmpty) {
      for (int i = 0; i < frame.shipPositions.length; i++) {
        final pos = frame.shipPositions[i];
        final isHead = i == 0;

        paint.color = isHead
            ? theme.shipColor
            : theme.shipColor.withValues(alpha: 0.8);

        final rect = Rect.fromLTWH(
          pos[0] * cellSize + 1,
          pos[1] * cellSize + 1,
          cellSize - 2,
          cellSize - 2,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          paint,
        );

        if (isHead) {
          // Draw eyes
          paint.color = Colors.white;
          final eyeSize = cellSize * 0.15;
          canvas.drawCircle(
            Offset(
              pos[0] * cellSize + cellSize * 0.3,
              pos[1] * cellSize + cellSize * 0.3,
            ),
            eyeSize,
            paint,
          );
          canvas.drawCircle(
            Offset(
              pos[0] * cellSize + cellSize * 0.7,
              pos[1] * cellSize + cellSize * 0.3,
            ),
            eyeSize,
            paint,
          );
        }
      }
    }

    // Draw food
    if (frame.foodPosition != null) {
      paint.color = theme.foodColor;
      final pos = frame.foodPosition!;
      final rect = Rect.fromLTWH(
        pos[0] * cellSize + 1,
        pos[1] * cellSize + 1,
        cellSize - 2,
        cellSize - 2,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.3)),
        paint,
      );
    }

    // Draw power-up
    if (frame.powerUpPosition != null) {
      paint.color = theme.accentColor;
      final pos = frame.powerUpPosition!;
      final center = Offset(
        pos[0] * cellSize + cellSize / 2,
        pos[1] * cellSize + cellSize / 2,
      );

      // Draw star shape for power-up
      final path = Path();
      final radius = cellSize * 0.4;
      for (int i = 0; i < 5; i++) {
        final angle = (i * 2 * 3.14159) / 5 - 3.14159 / 2;
        final x =
            center.dx + radius * 0.6 * (i % 2 == 0 ? 1 : 0.5) * math.cos(angle);
        final y =
            center.dy + radius * 0.6 * (i % 2 == 0 ? 1 : 0.5) * math.sin(angle);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
