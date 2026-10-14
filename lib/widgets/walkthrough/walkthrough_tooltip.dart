import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/walkthrough_step.dart';

/// Walkthrough step card (Prism Noir).
///
/// A raised #141419 card with a subtle border — the same surface as
/// [CsDialog]: mono step counter ("1/7") + icon, Syne title, body copy,
/// progress as short hairline bars (current = ink), SKIP text button and a
/// white NEXT pill. [theme] is kept for API compatibility only; menus are
/// always Prism Noir.
class WalkthroughTooltip extends StatelessWidget {
  /// The current walkthrough step
  final WalkthroughStep step;

  /// Kept for API compatibility (unused — menus are always Prism Noir).
  final GameTheme theme;

  /// Callback when Next is tapped
  final VoidCallback onNext;

  /// Callback when Skip is tapped
  final VoidCallback onSkip;

  /// Current step index (0-based)
  final int currentStepIndex;

  /// Total number of steps
  final int totalSteps;

  /// Whether this is the last step
  final bool isLastStep;

  /// Whether this step is waiting for user input
  final bool isAwaitingInput;

  const WalkthroughTooltip({
    super.key,
    required this.step,
    required this.theme,
    required this.onNext,
    required this.onSkip,
    required this.currentStepIndex,
    required this.totalSteps,
    this.isLastStep = false,
    this.isAwaitingInput = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CsColors.raised,
        borderRadius: BorderRadius.circular(CsRadius.card),
        border: Border.all(color: CsColors.lineSubtle),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(cs(20), cs(18), cs(16), cs(14)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Eyebrow: step counter + icon.
            Row(
              children: [
                Text(
                  '${currentStepIndex + 1}/$totalSteps',
                  style: t.mono(11, color: CsColors.ink45, em: 0.16),
                ),
                const Spacer(),
                if (step.icon != null) Icon(step.icon, size: cs(20), color: CsColors.ink70),
              ],
            ),
            SizedBox(height: cs(8)),
            Text(
              step.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.display(20, em: -0.02, height: 1.1),
            ),
            SizedBox(height: cs(8)),
            Text(step.message, style: t.body),
            SizedBox(height: cs(14)),
            _ProgressBars(current: currentStepIndex, total: totalSteps),
            SizedBox(height: cs(10)),
            Row(
              children: [
                if (step.canSkip)
                  Transform.translate(
                    offset: Offset(-cs(16), 0),
                    child: CsButton.text(
                      label: 'Skip',
                      size: CsButtonSize.small,
                      onPressed: onSkip,
                    ),
                  ),
                const Spacer(),
                _buildPrimary(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimary(BuildContext context) {
    final cs = context.cs;
    if (isAwaitingInput) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: cs(14),
            child: const CircularProgressIndicator(strokeWidth: 2, color: CsColors.cyan),
          ),
          SizedBox(width: cs(8)),
          CsLabel('Waiting', color: CsColors.cyan),
        ],
      );
    }
    final label = step.actionLabel ?? (isLastStep ? 'Got it!' : 'Next');
    return CsButton.primary(
      label: label,
      size: CsButtonSize.small,
      trailingIcon: (!isLastStep && step.actionLabel == null) ? Symbols.arrow_forward_rounded : null,
      onPressed: onNext,
    );
  }
}

/// Short square-ended bars: past = ink45, current = ink (wider), future = hairline.
class _ProgressBars extends StatelessWidget {
  const _ProgressBars({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) SizedBox(width: cs(4)),
          AnimatedContainer(
            duration: CsMotion.base,
            curve: CsMotion.standard,
            width: cs(i == current ? 22 : 10),
            height: 2,
            color: i == current
                ? CsColors.ink
                : i < current
                    ? CsColors.ink45
                    : CsColors.track,
          ),
        ],
      ],
    );
  }
}
