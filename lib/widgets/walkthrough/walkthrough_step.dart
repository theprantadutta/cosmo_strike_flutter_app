import 'package:flutter/material.dart';

/// Position of the tooltip relative to the target element
enum TooltipPosition {
  above,
  below,
  left,
  right,
  center,
}

/// Represents a single step in a walkthrough/tutorial
class WalkthroughStep {
  /// Unique identifier for this step
  final String id;

  /// Title displayed at the top of the tooltip
  final String title;

  /// Main message/description for this step
  final String message;

  /// GlobalKey for the target widget to spotlight
  /// If null, spotlight will be centered on screen
  final GlobalKey? targetKey;

  /// Position of the tooltip relative to the target
  final TooltipPosition position;

  /// Whether this step requires user interaction (e.g., swipe practice)
  final bool isInteractive;

  /// Optional icon to display in the tooltip
  final IconData? icon;

  /// Optional custom action label for the next button
  final String? actionLabel;

  /// Padding around the spotlight cutout
  final double spotlightPadding;

  /// Border radius for the spotlight cutout
  final double spotlightBorderRadius;

  /// Whether to show the skip button for this step
  final bool canSkip;

  const WalkthroughStep({
    required this.id,
    required this.title,
    required this.message,
    this.targetKey,
    this.position = TooltipPosition.below,
    this.isInteractive = false,
    this.icon,
    this.actionLabel,
    this.spotlightPadding = 8.0,
    this.spotlightBorderRadius = 12.0,
    this.canSkip = true,
  });

  /// Create a copy with modified properties
  WalkthroughStep copyWith({
    String? id,
    String? title,
    String? message,
    GlobalKey? targetKey,
    TooltipPosition? position,
    bool? isInteractive,
    IconData? icon,
    String? actionLabel,
    double? spotlightPadding,
    double? spotlightBorderRadius,
    bool? canSkip,
  }) {
    return WalkthroughStep(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      targetKey: targetKey ?? this.targetKey,
      position: position ?? this.position,
      isInteractive: isInteractive ?? this.isInteractive,
      icon: icon ?? this.icon,
      actionLabel: actionLabel ?? this.actionLabel,
      spotlightPadding: spotlightPadding ?? this.spotlightPadding,
      spotlightBorderRadius: spotlightBorderRadius ?? this.spotlightBorderRadius,
      canSkip: canSkip ?? this.canSkip,
    );
  }

  @override
  String toString() => 'WalkthroughStep(id: $id, title: $title)';
}
