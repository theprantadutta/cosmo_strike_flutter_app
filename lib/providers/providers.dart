import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/connectivity_service.dart';

// Export all providers
export 'daily_challenges_provider.dart';
export 'tournaments_provider.dart';
export 'friends_provider.dart';
export 'leaderboard_provider.dart';

// ==================== Base Providers ====================

/// Provider for ConnectivityService singleton
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return getIt<ConnectivityService>();
});

/// Stream provider for online status changes
/// Use this to trigger auto-refresh when coming online
final isOnlineProvider = StreamProvider<bool>((ref) {
  final connectivityService = ref.watch(connectivityServiceProvider);
  return connectivityService.onlineStatusStream;
});

/// Simple provider for current online status (synchronous)
final isOnlineSyncProvider = Provider<bool>((ref) {
  final connectivityService = ref.watch(connectivityServiceProvider);
  return connectivityService.isOnline;
});
