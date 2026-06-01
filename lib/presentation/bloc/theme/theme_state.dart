import 'package:equatable/equatable.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// Status of the theme cubit
enum ThemeStatus { initial, loading, ready }

/// State class for ThemeCubit
class ThemeState extends Equatable {
  final ThemeStatus status;
  final GameTheme currentTheme;
  final bool trailSystemEnabled;

  const ThemeState({
    this.status = ThemeStatus.initial,
    this.currentTheme = GameTheme.classic,
    this.trailSystemEnabled = false,
  });

  /// Initial state
  factory ThemeState.initial() => const ThemeState();

  /// Create a copy with updated values
  ThemeState copyWith({
    ThemeStatus? status,
    GameTheme? currentTheme,
    bool? trailSystemEnabled,
  }) {
    return ThemeState(
      status: status ?? this.status,
      currentTheme: currentTheme ?? this.currentTheme,
      trailSystemEnabled: trailSystemEnabled ?? this.trailSystemEnabled,
    );
  }

  /// Whether the theme system is ready
  bool get isReady => status == ThemeStatus.ready;

  /// Alias for trailSystemEnabled for compatibility
  bool get isTrailSystemEnabled => trailSystemEnabled;

  @override
  List<Object?> get props => [status, currentTheme, trailSystemEnabled];
}
