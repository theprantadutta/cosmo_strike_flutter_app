import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/walkthrough_step.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/walkthrough_tooltip.dart';

/// Full-screen walkthrough overlay: the Prism Noir scrim with a rounded
/// cut-out around the target (outlined by a single hairline) and the step
/// card positioned next to it.
class WalkthroughOverlay extends StatefulWidget {
  /// The current walkthrough step
  final WalkthroughStep step;

  /// Kept for API compatibility (menus are always Prism Noir).
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
      duration: CsMotion.slow,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: CsMotion.standard,
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
            // Scrim with spotlight cut-out
            CustomPaint(
              size: screenSize,
              painter: _SpotlightPainter(
                targetRect: _targetRect,
                overlayColor: CsColors.scrim,
                ringColor: CsColors.lineStrong,
                borderRadius: widget.step.spotlightBorderRadius,
              ),
            ),

            // Positioned tooltip
            _buildTooltip(context, screenSize),
          ],
        ),
      ),
    );
  }

  Widget _buildTooltip(BuildContext context, Size screenSize) {
    final cs = context.cs;
    final tooltipWidget = ScaleTransition(
      scale: Tween(begin: .97, end: 1.0).animate(_fadeAnimation),
      child: WalkthroughTooltip(
        step: widget.step,
        theme: widget.theme,
        onNext: widget.onNext,
        onSkip: widget.onSkip,
        currentStepIndex: widget.currentStepIndex,
        totalSteps: widget.totalSteps,
        isLastStep: widget.currentStepIndex == widget.totalSteps - 1,
        isAwaitingInput: widget.isAwaitingInput,
      ),
    );

    final maxWidth = cs(320);

    // If no target, center the tooltip
    if (_targetRect == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(cs(24)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: tooltipWidget,
          ),
        ),
      );
    }

    // Calculate tooltip position based on step position preference
    return _positionTooltip(context, screenSize, tooltipWidget, maxWidth);
  }

  Widget _positionTooltip(
      BuildContext context, Size screenSize, Widget tooltip, double tooltipMaxWidth) {
    final cs = context.cs;
    final rect = _targetRect!;
    final tooltipMargin = cs(16);

    // Calculate available space in each direction
    final spaceAbove = rect.top;
    final spaceBelow = screenSize.height - rect.bottom;
    final spaceLeft = rect.left;
    final spaceRight = screenSize.width - rect.right;

    // Determine best position
    TooltipPosition effectivePosition = widget.step.position;

    // If the preferred position doesn't have enough space, try alternatives.
    // In the short landscape viewport a tall target (e.g. the launch bay)
    // can have NO room above or below — fall through to the sides, then
    // centre, so the tooltip never renders clipped offscreen.
    final minSpace = cs(190);
    final minSideSpace = tooltipMaxWidth + tooltipMargin * 2;
    if (effectivePosition == TooltipPosition.below && spaceBelow < minSpace) {
      effectivePosition = TooltipPosition.above;
    }
    if (effectivePosition == TooltipPosition.above && spaceAbove < minSpace) {
      effectivePosition =
          spaceBelow >= minSpace ? TooltipPosition.below : TooltipPosition.left;
    }
    if (effectivePosition == TooltipPosition.left && spaceLeft < minSideSpace) {
      effectivePosition = spaceRight >= minSideSpace
          ? TooltipPosition.right
          : TooltipPosition.center;
    }
    if (effectivePosition == TooltipPosition.right &&
        spaceRight < minSideSpace) {
      effectivePosition = spaceLeft >= minSideSpace
          ? TooltipPosition.left
          : TooltipPosition.center;
    }

    double? top, bottom, left, right;

    switch (effectivePosition) {
      case TooltipPosition.above:
        bottom = screenSize.height - rect.top + tooltipMargin;
        left = _calculateHorizontalPosition(context, rect, screenSize, tooltipMaxWidth);
        break;
      case TooltipPosition.below:
        top = rect.bottom + tooltipMargin;
        left = _calculateHorizontalPosition(context, rect, screenSize, tooltipMaxWidth);
        break;
      case TooltipPosition.left:
        right = screenSize.width - rect.left + tooltipMargin;
        top = _calculateVerticalPosition(context, rect, screenSize);
        break;
      case TooltipPosition.right:
        left = rect.right + tooltipMargin;
        top = _calculateVerticalPosition(context, rect, screenSize);
        break;
      case TooltipPosition.center:
        return Center(
          child: Padding(
            padding: EdgeInsets.all(cs(24)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: tooltipMaxWidth),
              child: tooltip,
            ),
          ),
        );
    }

    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: tooltipMaxWidth),
        child: tooltip,
      ),
    );
  }

  double _calculateHorizontalPosition(
      BuildContext context, Rect rect, Size screenSize, double tooltipMaxWidth) {
    final edge = context.cs(16);
    final targetCenter = rect.left + rect.width / 2;
    final minLeft = edge;
    final maxLeft = (screenSize.width - tooltipMaxWidth - edge).clamp(minLeft, double.infinity);
    return (targetCenter - tooltipMaxWidth / 2).clamp(minLeft, maxLeft);
  }

  double _calculateVerticalPosition(BuildContext context, Rect rect, Size screenSize) {
    final cs = context.cs;
    final targetCenter = rect.top + rect.height / 2;
    final estimatedTooltipHeight = cs(200);

    // Fullscreen-immersive landscape — no status bar to dodge.
    final minTop = cs(16);
    final maxTop =
        (screenSize.height - estimatedTooltipHeight - minTop).clamp(minTop, double.infinity);

    return (targetCenter - estimatedTooltipHeight / 2).clamp(minTop, maxTop);
  }
}

/// Scrim with a rounded cut-out and a 1px hairline ring around it.
class _SpotlightPainter extends CustomPainter {
  final Rect? targetRect;
  final Color overlayColor;
  final Color ringColor;
  final double borderRadius;

  _SpotlightPainter({
    this.targetRect,
    required this.overlayColor,
    required this.ringColor,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;
    final fullScreen = Path()..addRect(Offset.zero & size);

    if (targetRect != null) {
      final rrect = RRect.fromRectAndRadius(targetRect!, Radius.circular(borderRadius));
      final cutout = Path()..addRRect(rrect);
      canvas.drawPath(Path.combine(PathOperation.difference, fullScreen, cutout), paint);
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = ringColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else {
      canvas.drawPath(fullScreen, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.overlayColor != overlayColor ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.borderRadius != borderRadius;
  }
}
