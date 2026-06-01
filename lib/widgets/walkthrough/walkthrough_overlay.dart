import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/walkthrough_step.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/walkthrough_tooltip.dart';

/// Full-screen overlay with spotlight effect for walkthroughs
class WalkthroughOverlay extends StatefulWidget {
  /// The current walkthrough step
  final WalkthroughStep step;

  /// Current theme for styling
  final GameTheme theme;

  /// Callback when Next is tapped
  final VoidCallback onNext;

  /// Callback when Skip is tapped
  final VoidCallback onSkip;

  /// Current step index (0-based)
  final int currentStepIndex;

  /// Total number of steps
  final int totalSteps;

  /// Whether this is an interactive step awaiting user input
  final bool isAwaitingInput;

  const WalkthroughOverlay({
    super.key,
    required this.step,
    required this.theme,
    required this.onNext,
    required this.onSkip,
    required this.currentStepIndex,
    required this.totalSteps,
    this.isAwaitingInput = false,
  });

  @override
  State<WalkthroughOverlay> createState() => _WalkthroughOverlayState();
}

class _WalkthroughOverlayState extends State<WalkthroughOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();

    // Calculate target rect after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTargetRect();
    });
  }

  @override
  void didUpdateWidget(WalkthroughOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step.id != widget.step.id) {
      // Animate transition to new step
      _animationController.reset();
      _animationController.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateTargetRect();
      });
    }
  }

  void _updateTargetRect() {
    if (!mounted) return;

    final targetKey = widget.step.targetKey;
    if (targetKey?.currentContext != null) {
      final box = targetKey!.currentContext!.findRenderObject() as RenderBox?;
      if (box != null) {
        final position = box.localToGlobal(Offset.zero);
        setState(() {
          _targetRect = Rect.fromLTWH(
            position.dx - widget.step.spotlightPadding,
            position.dy - widget.step.spotlightPadding,
            box.size.width + widget.step.spotlightPadding * 2,
            box.size.height + widget.step.spotlightPadding * 2,
          );
        });
      }
    } else {
      setState(() {
        _targetRect = null;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // Semi-transparent overlay with spotlight cutout
            CustomPaint(
              size: screenSize,
              painter: _SpotlightPainter(
                targetRect: _targetRect,
                overlayColor: Colors.black.withValues(alpha: 0.85),
                glowColor: widget.theme.accentColor,
                borderRadius: widget.step.spotlightBorderRadius,
              ),
            ),

            // Positioned tooltip
            _buildTooltip(screenSize),
          ],
        ),
      ),
    );
  }

  Widget _buildTooltip(Size screenSize) {
    final tooltipWidget = WalkthroughTooltip(
      step: widget.step,
      theme: widget.theme,
      onNext: widget.onNext,
      onSkip: widget.onSkip,
      currentStepIndex: widget.currentStepIndex,
      totalSteps: widget.totalSteps,
      isLastStep: widget.currentStepIndex == widget.totalSteps - 1,
      isAwaitingInput: widget.isAwaitingInput,
    ).animate().scale(
          begin: const Offset(0.8, 0.8),
          end: const Offset(1.0, 1.0),
          duration: 300.ms,
          curve: Curves.easeOutBack,
        );

    // If no target, center the tooltip
    if (_targetRect == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: tooltipWidget,
        ),
      );
    }

    // Calculate tooltip position based on step position preference
    return _positionTooltip(screenSize, tooltipWidget);
  }

  Widget _positionTooltip(Size screenSize, Widget tooltip) {
    final rect = _targetRect!;
    const tooltipMargin = 16.0;
    const tooltipMaxWidth = 320.0;

    // Calculate available space in each direction
    final spaceAbove = rect.top;
    final spaceBelow = screenSize.height - rect.bottom;
    // Reserved for future left/right position auto-adjustment
    // final spaceLeft = rect.left;
    // final spaceRight = screenSize.width - rect.right;

    // Determine best position
    TooltipPosition effectivePosition = widget.step.position;

    // If preferred position doesn't have enough space, try alternatives
    const minSpace = 150.0;
    if (effectivePosition == TooltipPosition.below && spaceBelow < minSpace) {
      effectivePosition = TooltipPosition.above;
    } else if (effectivePosition == TooltipPosition.above &&
        spaceAbove < minSpace) {
      effectivePosition = TooltipPosition.below;
    }

    double? top, bottom, left, right;

    switch (effectivePosition) {
      case TooltipPosition.above:
        bottom = screenSize.height - rect.top + tooltipMargin;
        left = _calculateHorizontalPosition(rect, screenSize, tooltipMaxWidth);
        break;
      case TooltipPosition.below:
        top = rect.bottom + tooltipMargin;
        left = _calculateHorizontalPosition(rect, screenSize, tooltipMaxWidth);
        break;
      case TooltipPosition.left:
        right = screenSize.width - rect.left + tooltipMargin;
        top = _calculateVerticalPosition(rect, screenSize);
        break;
      case TooltipPosition.right:
        left = rect.right + tooltipMargin;
        top = _calculateVerticalPosition(rect, screenSize);
        break;
      case TooltipPosition.center:
        // Center on screen
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: tooltip,
          ),
        );
    }

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: tooltipMaxWidth),
        child: tooltip,
      ),
    );
  }

  double _calculateHorizontalPosition(
      Rect rect, Size screenSize, double tooltipMaxWidth) {
    // Try to center tooltip under/over target
    final targetCenter = rect.left + rect.width / 2;
    final tooltipHalf = tooltipMaxWidth / 2;

    // Clamp to screen bounds with padding
    final minLeft = 16.0;
    final maxLeft = screenSize.width - tooltipMaxWidth - 16;

    return (targetCenter - tooltipHalf).clamp(minLeft, maxLeft);
  }

  double _calculateVerticalPosition(Rect rect, Size screenSize) {
    // Try to vertically center tooltip with target
    final targetCenter = rect.top + rect.height / 2;
    const estimatedTooltipHeight = 150.0;

    // Clamp to screen bounds with padding
    const minTop = 100.0; // Leave room for status bar
    final maxTop = screenSize.height - estimatedTooltipHeight - 50;

    return (targetCenter - estimatedTooltipHeight / 2).clamp(minTop, maxTop);
  }
}

/// Custom painter for the spotlight effect
class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final Color overlayColor;
  final Color glowColor;
  final double borderRadius;

  _SpotlightPainter({
    this.targetRect,
    required this.overlayColor,
    required this.glowColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;

    // Create the full screen path
    final fullScreen = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (targetRect != null) {
      // Create the cutout path
      final cutout = Path()
        ..addRRect(
          RRect.fromRectAndRadius(targetRect!, Radius.circular(borderRadius)),
        );

      // Combine paths to create spotlight effect
      final combinedPath = Path.combine(
        PathOperation.difference,
        fullScreen,
        cutout,
      );

      canvas.drawPath(combinedPath, paint);

      // Draw glow around spotlight
      final glowPaint = Paint()
        ..color = glowColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8);

      canvas.drawRRect(
        RRect.fromRectAndRadius(targetRect!, Radius.circular(borderRadius)),
        glowPaint,
      );

      // Draw inner border
      final borderPaint = Paint()
        ..color = glowColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(targetRect!, Radius.circular(borderRadius)),
        borderPaint,
      );
    } else {
      // No target - just draw the overlay
      canvas.drawPath(fullScreen, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.borderRadius != borderRadius;
  }
}
