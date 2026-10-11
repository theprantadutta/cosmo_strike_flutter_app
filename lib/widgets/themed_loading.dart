import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// Labeled loading state for screens waiting on a fetch.
///
/// Renders the Prism Noir [CsLoadingState] (2px sweeping prism line + mono
/// caption). [theme] is kept for API compatibility — menus are always
/// Prism Noir, so the purchased colour theme no longer tints this.
class ThemedLoading extends StatelessWidget {
  final GameTheme theme;
  final String label;

  const ThemedLoading({
    super.key,
    required this.theme,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    // Drop a trailing ellipsis — the mono caption reads cleaner without it.
    final clean = label.replaceAll(RegExp(r'(\.\.\.|…)$'), '');
    return CsLoadingState(label: clean);
  }
}
