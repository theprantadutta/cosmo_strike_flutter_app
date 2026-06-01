import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:cosmo_strike_flutter_app/services/walkthrough_service.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/walkthrough_step.dart';

/// State for walkthrough management
class WalkthroughState {
  /// Whether a walkthrough is currently active
  final bool isActive;

  /// The ID of the current walkthrough (e.g., 'home', 'game_tutorial')
  final String? walkthroughId;

  /// Current step index
  final int currentStepIndex;

  /// List of steps for the current walkthrough
  final List<WalkthroughStep> steps;

  /// Whether the walkthrough is in an interactive practice mode
  final bool isAwaitingInput;

  const WalkthroughState({
    this.isActive = false,
    this.walkthroughId,
    this.currentStepIndex = 0,
    this.steps = const [],
    this.isAwaitingInput = false,
  });

  /// Get the current step, or null if no walkthrough is active
  WalkthroughStep? get currentStep {
    if (!isActive || currentStepIndex >= steps.length) return null;
    return steps[currentStepIndex];
  }

  /// Whether there are more steps after the current one
  bool get hasNextStep => currentStepIndex < steps.length - 1;

  /// Whether this is the last step
  bool get isLastStep => currentStepIndex == steps.length - 1;

  /// Progress as a value between 0.0 and 1.0
  double get progress {
    if (steps.isEmpty) return 0.0;
    return (currentStepIndex + 1) / steps.length;
  }

  WalkthroughState copyWith({
    bool? isActive,
    String? walkthroughId,
    int? currentStepIndex,
    List<WalkthroughStep>? steps,
    bool? isAwaitingInput,
  }) {
    return WalkthroughState(
      isActive: isActive ?? this.isActive,
      walkthroughId: walkthroughId ?? this.walkthroughId,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      steps: steps ?? this.steps,
      isAwaitingInput: isAwaitingInput ?? this.isAwaitingInput,
    );
  }
}

/// Notifier for managing walkthrough state
class WalkthroughNotifier extends StateNotifier<WalkthroughState> {
  final WalkthroughService _service;
  VoidCallback? _onComplete;

  WalkthroughNotifier()
      : _service = WalkthroughService(),
        super(const WalkthroughState());

  /// Start a walkthrough with the given steps
  Future<void> start({
    required String walkthroughId,
    required List<WalkthroughStep> steps,
    VoidCallback? onComplete,
  }) async {
    // Ensure service is initialized
    if (!_service.isInitialized) {
      await _service.initialize();
    }

    // Check if already completed
    if (_service.isComplete(walkthroughId)) {
      return;
    }

    _onComplete = onComplete;

    state = WalkthroughState(
      isActive: true,
      walkthroughId: walkthroughId,
      currentStepIndex: 0,
      steps: steps,
      isAwaitingInput: steps.isNotEmpty && steps.first.isInteractive,
    );
  }

  /// Move to the next step
  void next() {
    if (!state.isActive) return;

    if (state.hasNextStep) {
      final nextIndex = state.currentStepIndex + 1;
      final nextStep = state.steps[nextIndex];

      state = state.copyWith(
        currentStepIndex: nextIndex,
        isAwaitingInput: nextStep.isInteractive,
      );
    } else {
      // Complete the walkthrough
      complete();
    }
  }

  /// Skip the current walkthrough
  Future<void> skip() async {
    if (!state.isActive || state.walkthroughId == null) return;

    await _service.markComplete(state.walkthroughId!);
    _onComplete?.call();

    state = const WalkthroughState();
  }

  /// Complete the walkthrough
  Future<void> complete() async {
    if (!state.isActive || state.walkthroughId == null) return;

    await _service.markComplete(state.walkthroughId!);
    _onComplete?.call();

    state = const WalkthroughState();
  }

  /// Set the awaiting input state (for interactive steps)
  void setAwaitingInput(bool awaiting) {
    state = state.copyWith(isAwaitingInput: awaiting);
  }

  /// Reset a specific walkthrough to allow it to be shown again
  Future<void> resetWalkthrough(String walkthroughId) async {
    if (!_service.isInitialized) {
      await _service.initialize();
    }
    await _service.reset(walkthroughId);
  }

  /// Check if a walkthrough has been completed
  Future<bool> isWalkthroughComplete(String walkthroughId) async {
    if (!_service.isInitialized) {
      await _service.initialize();
    }
    return _service.isComplete(walkthroughId);
  }
}

/// Provider for walkthrough state
final walkthroughProvider =
    StateNotifierProvider<WalkthroughNotifier, WalkthroughState>((ref) {
  return WalkthroughNotifier();
});

/// Convenience provider for checking if walkthrough is active
final isWalkthroughActiveProvider = Provider<bool>((ref) {
  return ref.watch(walkthroughProvider).isActive;
});

/// Convenience provider for current step
final currentWalkthroughStepProvider = Provider<WalkthroughStep?>((ref) {
  return ref.watch(walkthroughProvider).currentStep;
});

/// Convenience provider for walkthrough progress
final walkthroughProgressProvider = Provider<double>((ref) {
  return ref.watch(walkthroughProvider).progress;
});
