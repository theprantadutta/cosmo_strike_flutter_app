import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// A theme-aware loading widget: a centered spinner over a label.
///
/// Use this anywhere a screen is waiting on a network fetch instead of a
/// bare `CircularProgressIndicator()`. The labeled spinner reads as
/// "loading" rather than the context-less "maybe empty / maybe broken"
/// feel of a naked spinner, and the accent color ties the loading state
/// to whatever theme the player is using.
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(theme.accentColor),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              color: theme.accentColor.withValues(alpha: 0.8),
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
