import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/models/game_replay.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

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
    return CsScaffold(
      title: _replay != null ? 'Replay · ${_replay!.playerName}' : 'Loading replay',
      trailing: [
        if (_replay != null) CsMeta(_replay!.formattedDuration, icon: Symbols.timer_rounded),
      ],
      body: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    // Show loading state when fetching replay from deep link
    if (_isLoadingReplay) {
      return const CsLoadingState(label: 'Loading replay');
    }

    // Show error state
    if (_loadError != null || _replay == null) {
      return CsEmptyState.error(
        title: _loadError ?? 'Replay not found',
        action: CsButton.secondary(
          label: 'Go back',
          icon: Symbols.arrow_back_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
      );
    }

    return CsSplit(
      leftFlex: 5,
      left: CsFitColumn(
        alignment: Alignment.centerLeft,
        children: [
          _buildGameInfo(context),
          SizedBox(height: context.cs(18)),
          _buildPlaybackControls(context),
        ],
      ),
      right: Center(child: AspectRatio(aspectRatio: 1, child: _buildGameBoard(context))),
    );
  }

  Widget _buildGameInfo(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final replay = _replay!;
    final frame = _currentFrame;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CsLabel('Score'),
        SizedBox(height: cs(6)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('${frame?.score ?? 0}', maxLines: 1, style: t.hudScore),
        ),
        SizedBox(height: cs(12)),
        CsStatGrid(
          columns: 3,
          valueSize: 18,
          cellPadding: 10,
          stats: [
            CsStat('${frame?.level ?? 1}', 'Level'),
            CsStat('${_currentFrameIndex + 1}/${replay.totalFrames}', 'Frame'),
            CsStat(replay.formattedDuration, 'Time'),
          ],
        ),
        // Reserve a fixed slot for the event chip so the column doesn't
        // grow/shrink each time a frame has (or stops having) a
        // `gameEvent`. AnimatedSwitcher fades the chip within the slot.
        SizedBox(height: cs(10)),
        SizedBox(
          height: cs(24),
          child: AnimatedSwitcher(
            duration: CsMotion.base,
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: frame?.gameEvent != null
                ? Align(
                    key: ValueKey('event-${frame!.frameNumber}'),
                    alignment: Alignment.centerLeft,
                    child: _eventChip(frame.gameEvent!),
                  )
                : const SizedBox.shrink(key: ValueKey('event-empty')),
          ),
        ),
      ],
    );
  }

  Widget _buildGameBoard(BuildContext context) {
    final cs = context.cs;
    final frame = _currentFrame;

    const boardWidth = 20;
    const boardHeight = 20;
    const cellSize = 12.0;
    const side = boardWidth * cellSize + 2;

    final Widget inner = frame == null
        ? Center(child: Text('NO FRAME DATA', style: cs.type.micro))
        : CustomPaint(
            size: const Size(boardWidth * cellSize, boardHeight * cellSize),
            painter: ReplayBoardPainter(frame: frame, cellSize: cellSize),
          );

    // Fill the available height; the board is painted at its native cell
    // size and scaled as one unit.
    return FittedBox(
      fit: BoxFit.contain,
      child: Container(
        width: side,
        height: side,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: CsColors.bgGame,
          borderRadius: BorderRadius.circular(CsRadius.tile / 2),
          border: Border.all(color: CsColors.lineSubtle),
        ),
        child: inner,
      ),
    );
  }

  Widget _buildPlaybackControls(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final replay = _replay!;
    final atStart = _currentFrameIndex <= 0;
    final atEnd = _currentFrameIndex >= replay.totalFrames - 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Scrubber (theme slider: 2px ink track, white thumb).
        Row(
          children: [
            Text('${_currentFrameIndex + 1}', style: t.micro),
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
              ),
            ),
            Text('${replay.totalFrames}', style: t.micro),
          ],
        ),
        SizedBox(height: cs(6)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CsIconButton(
              icon: Symbols.skip_previous_rounded,
              tooltip: 'Previous frame',
              bordered: false,
              onPressed: atStart ? null : _previousFrame,
            ),
            CsIconButton(
              icon: Symbols.chevron_left_rounded,
              tooltip: 'Step back',
              onPressed: atStart ? null : () => _seekFrames(-1),
            ),
            _PlayButton(playing: _isPlaying, onPressed: _togglePlayback),
            CsIconButton(
              icon: Symbols.chevron_right_rounded,
              tooltip: 'Step forward',
              onPressed: atEnd ? null : () => _seekFrames(1),
            ),
            CsIconButton(
              icon: Symbols.skip_next_rounded,
              tooltip: 'Next frame',
              bordered: false,
              onPressed: atEnd ? null : _nextFrame,
            ),
          ],
        ),
        SizedBox(height: cs(14)),
        Row(children: [
          const CsLabel('Speed', size: 10),
          SizedBox(width: cs(12)),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CsSegmented<double>(
                segments: {0.25: '0.25×', 0.5: '0.5×', 1.0: '1×', 2.0: '2×', 4.0: '4×'},
                selected: _playbackSpeed,
                onChanged: (speed) {
                  setState(() {
                    _playbackSpeed = speed;
                  });
                  if (_isPlaying) {
                    _startPlayback();
                  }
                },
              ),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _eventChip(Map<String, dynamic> event) {
    final type = event['type'] as String;
    final icon = switch (type) {
      'food_consumed' => Symbols.explosion_rounded,
      'power_up_collected' => Symbols.bolt_rounded,
      _ => Symbols.info_rounded,
    };
    return CsChip(_formatGameEvent(event), icon: icon);
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
        return 'Destroyed ${event['foodType']} enemy';
      case 'power_up_collected':
        return 'Collected ${event['powerUpType']} power-up';
      default:
        return event.toString();
    }
  }
}

/// White play / pause disc — the focal control of the viewer.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onPressed});
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final d = context.cs(56).clamp(48.0, 76.0);
    return CsPressable(
      onTap: onPressed,
      semanticLabel: playing ? 'Pause' : 'Play',
      child: Container(
        width: d,
        height: d,
        decoration: const BoxDecoration(color: CsColors.ink, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(
          playing ? Symbols.pause_rounded : Symbols.play_arrow_rounded,
          size: d * 0.5,
          color: CsColors.onLight,
        ),
      ),
    );
  }
}

/// Paints one recorded frame: the ship (ink, head with dark "eyes"), the
/// enemy target (pink — danger) and a power-up star (gold).
class ReplayBoardPainter extends CustomPainter {
  final GameFrame frame;
  final double cellSize;

  ReplayBoardPainter({
    required this.frame,
    required this.cellSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Faint cell grid so positions read on the black board.
    final grid = Paint()
      ..color = CsColors.fill04
      ..strokeWidth = 1;
    for (double x = cellSize; x < size.width; x += cellSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = cellSize; y < size.height; y += cellSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Draw ship
    if (frame.shipPositions.isNotEmpty) {
      for (int i = 0; i < frame.shipPositions.length; i++) {
        final pos = frame.shipPositions[i];
        final isHead = i == 0;

        paint.color = isHead ? CsColors.ink : CsColors.ink60;

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
          paint.color = CsColors.bg;
          final eyeSize = cellSize * 0.12;
          canvas.drawCircle(
            Offset(pos[0] * cellSize + cellSize * 0.3, pos[1] * cellSize + cellSize * 0.3),
            eyeSize,
            paint,
          );
          canvas.drawCircle(
            Offset(pos[0] * cellSize + cellSize * 0.7, pos[1] * cellSize + cellSize * 0.3),
            eyeSize,
            paint,
          );
        }
      }
    }

    // Draw enemy target
    if (frame.foodPosition != null) {
      paint.color = CsColors.pink;
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
      paint.color = CsColors.gold;
      final pos = frame.powerUpPosition!;
      final center = Offset(
        pos[0] * cellSize + cellSize / 2,
        pos[1] * cellSize + cellSize / 2,
      );

      // Draw star shape for power-up
      final path = Path();
      final radius = cellSize * 0.4;
      for (int i = 0; i < 5; i++) {
        final angle = (i * 2 * math.pi) / 5 - math.pi / 2;
        final x = center.dx + radius * 0.6 * (i % 2 == 0 ? 1 : 0.5) * math.cos(angle);
        final y = center.dy + radius * 0.6 * (i % 2 == 0 ? 1 : 0.5) * math.sin(angle);
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
  bool shouldRepaint(covariant ReplayBoardPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.cellSize != cellSize;
}
