import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cosmo_strike_flutter_app/models/game_state.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

class CrashFeedbackOverlay extends StatefulWidget {
  final CrashReason crashReason;
  final GameTheme theme;
  final VoidCallback onSkip;
  final Duration duration;

  const CrashFeedbackOverlay({
    super.key,
    required this.crashReason,
    required this.theme,
    required this.onSkip,
    required this.duration,
  });

  @override
  State<CrashFeedbackOverlay> createState() => _CrashFeedbackOverlayState();
}

class _CrashFeedbackOverlayState extends State<CrashFeedbackOverlay>
    with TickerProviderStateMixin {
  late AnimationController _shakeController;
  late AnimationController _pulseController;
  bool _animationsStarted = false;

  @override
  void initState() {
    super.initState();

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Defer animation start until the first didChangeDependencies tick so
    // the modal route's ~300ms transition doesn't consume half the shake.
    // The player should see the shake play out from the moment the overlay
    // is on screen, not catch the tail end.
    if (!_animationsStarted) {
      _animationsStarted = true;
      _shakeController.forward();
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onSkip,
      behavior: HitTestBehavior.opaque,
      child: Material(
        color: Colors.black.withValues(alpha: 0.8),
        child: Center(
        child:
            Container(
              margin: const EdgeInsets.all(40),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: widget.theme.backgroundColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: widget.theme.foodColor, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: widget.theme.foodColor.withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Crash icon with shake animation
                  AnimatedBuilder(
                    animation: _shakeController,
                    builder: (context, child) {
                      final shakeValue = _shakeController.value;
                      final offset = Offset(
                        (shakeValue < 0.5
                                ? shakeValue * 2
                                : (1 - shakeValue) * 2) *
                            10 *
                            (shakeValue < 0.25 || shakeValue > 0.75 ? -1 : 1),
                        0,
                      );

                      return Transform.translate(
                        offset: offset,
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: 1.0 + _pulseController.value * 0.2,
                              child: Text(
                                widget.crashReason.icon,
                                style: const TextStyle(fontSize: 80),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // "OOPS!" text
                  Text(
                    'OOPS!',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: widget.theme.foodColor,
                      letterSpacing: 4,
                      shadows: [
                        Shadow(
                          offset: const Offset(2, 2),
                          blurRadius: 4,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.5),

                  const SizedBox(height: 16),

                  // Crash reason message
                  Text(
                    widget.crashReason.message,
                    style: TextStyle(
                      fontSize: 20,
                      color: widget.theme.accentColor,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

                  const SizedBox(height: 24),

                  // Progress indicator showing auto-continue (or wait for tap)
                  Column(
                    children: [
                      // "Until Tap" mode shows waiting message, others show countdown
                      if (widget.duration.inSeconds ==
                          GameConstants.crashFeedbackUntilTap) ...[
                        // Until Tap mode - no countdown, just waiting
                        Text(
                          'Ready when you are...',
                          style: TextStyle(
                            fontSize: 14,
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        // Normal mode - show countdown
                        Text(
                          'Game Over in...',
                          style: TextStyle(
                            fontSize: 14,
                            color: widget.theme.accentColor.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // Countdown timer
                        _buildCountdownTimer(),

                        const SizedBox(height: 16),
                      ],

                      // Skip/Continue button
                      GestureDetector(
                            onTap: widget.onSkip,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    widget.duration.inSeconds ==
                                        GameConstants.crashFeedbackUntilTap
                                    ? widget.theme.accentColor.withValues(
                                        alpha: 0.2,
                                      )
                                    : Colors.transparent,
                                border: Border.all(
                                  color: widget.theme.accentColor.withValues(
                                    alpha:
                                        widget.duration.inSeconds ==
                                            GameConstants.crashFeedbackUntilTap
                                        ? 0.8
                                        : 0.5,
                                  ),
                                  width:
                                      widget.duration.inSeconds ==
                                          GameConstants.crashFeedbackUntilTap
                                      ? 2
                                      : 1,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'TAP TO CONTINUE',
                                style: TextStyle(
                                  fontSize:
                                      widget.duration.inSeconds ==
                                          GameConstants.crashFeedbackUntilTap
                                      ? 14
                                      : 12,
                                  fontWeight:
                                      widget.duration.inSeconds ==
                                          GameConstants.crashFeedbackUntilTap
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: widget.theme.accentColor.withValues(
                                    alpha:
                                        widget.duration.inSeconds ==
                                            GameConstants.crashFeedbackUntilTap
                                        ? 1.0
                                        : 0.8,
                                  ),
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(delay: 800.ms)
                          .then()
                          .shimmer(delay: 500.ms),
                    ],
                  ).animate().fadeIn(delay: 600.ms),
                ],
              ),
            ).animate().scale(
              begin: const Offset(0.5, 0.5),
              duration: 400.ms,
              curve: Curves.elasticOut,
            ),
        ),
      ),
    );
  }

  Widget _buildCountdownTimer() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: widget.duration.inSeconds.toDouble(), end: 0.0),
      duration: widget.duration,
      builder: (context, value, child) {
        return Column(
          children: [
            Text(
              '${value.ceil()}',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: widget.theme.foodColor,
              ),
            ),

            const SizedBox(height: 8),

            // Progress bar
            Container(
              width: 100,
              height: 6,
              decoration: BoxDecoration(
                color: widget.theme.backgroundColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 1 - (value / widget.duration.inSeconds),
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.theme.foodColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
