import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/walkthrough_step.dart';

/// Styled tooltip widget for walkthrough steps.
///
/// Clean Command-HUD styling: a borderless dark surface framed purely by the
/// skin's neon glow, a tinted icon disc + title + step counter, muted body
/// text, neon progress dots, a prominent SKIP TOUR ghost action, and a
/// neon-ramp NEXT pill (same CTA language as the rest of the app).
class WalkthroughTooltip extends StatelessWidget {
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
    return Container(
      // Borderless per the clean design — the skin's glow frames the sheet.
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          theme.primaryColor.withValues(alpha: 0.06),
          theme.backgroundColor,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.glow.withValues(alpha: 0.3),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: tinted icon disc + title + step counter.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                if (step.icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.neonPrimary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      step.icon,
                      color: theme.neonPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    step.title,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${currentStepIndex + 1}/$totalSteps',
                  style: TextStyle(
                    color: theme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),

          // Message content
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Text(
              step.message,
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),

          // Progress dots
          _buildProgressDots(),

          const SizedBox(height: 10),

          // Action buttons
          _buildButtons(),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildProgressDots() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(totalSteps, (index) {
          final isActive = index == currentStepIndex;
          final isPast = index < currentStepIndex;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: isActive ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: isActive
                  ? theme.neonPrimary
                  : isPast
                      ? theme.neonPrimary.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: theme.neonPrimary.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Skip — prominent ghost action, always reachable.
          if (step.canSkip)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSkip,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  'SKIP TOUR',
                  style: TextStyle(
                    color: theme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

          const Spacer(),

          // Next/Done/Wait button
          _buildPrimaryButton(),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton() {
    // If awaiting input, show a "waiting" state — borderless neon tint.
    if (isAwaitingInput) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: theme.neonSecondary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(theme.neonSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Waiting...',
              style: TextStyle(
                color: theme.neonSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Normal next/done pill — the skin's neon ramp, dark lettering, glow only.
    final buttonText =
        (step.actionLabel ?? (isLastStep ? 'Got it!' : 'Next')).toUpperCase();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onNext,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.neonPrimary, theme.neonSecondary],
          ),
          borderRadius: BorderRadius.circular(19),
          boxShadow: [
            BoxShadow(
              color: theme.neonPrimary.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              buttonText,
              style: const TextStyle(
                color: Color(0xFF03040A),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            if (!isLastStep && step.actionLabel == null) ...[
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward,
                color: Color(0xFF03040A),
                size: 15,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
