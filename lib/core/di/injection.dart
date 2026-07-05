import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';

// Database
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';

// Services
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/firebase_analytics_client.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/logger_analytics_client.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/offline_cache_service.dart';
import 'package:cosmo_strike_flutter_app/services/connectivity_service.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/haptic_service.dart';
import 'package:cosmo_strike_flutter_app/services/preferences_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/unified_user_service.dart';
import 'package:cosmo_strike_flutter_app/services/achievement_service.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/services/progression_service.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/services/review_service.dart';
import 'package:cosmo_strike_flutter_app/services/sync/sync_engine.dart';

// Core
import 'package:cosmo_strike_flutter_app/core/network/network_info.dart';

// Data Sources
import 'package:cosmo_strike_flutter_app/data/datasources/local/cache_datasource.dart';
import 'package:cosmo_strike_flutter_app/data/datasources/remote/api_datasource.dart';

// Cubits
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_settings_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/tournament/tournament_context_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/battle_pass_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/power_up/power_up_cubit.dart';

/// Global GetIt instance for dependency injection
final getIt = GetIt.instance;

/// Initialize all dependencies
/// Call this in main() before runApp()
Future<void> configureDependencies() async {
  // ==================== Database ====================
  // Register AppDatabase as a singleton (created once, used everywhere)
  final database = AppDatabase();
  getIt.registerSingleton<AppDatabase>(database);

  // Initialize database defaults
  await database.initializeDefaults();

  // ==================== External Services ====================
  // These are services that already exist and have their own singleton patterns
  // We register them so other dependencies can use DI

  getIt.registerLazySingleton<ApiService>(() => ApiService());

  // OfflineCacheService needs database initialization
  getIt.registerLazySingleton<OfflineCacheService>(() {
    final service = OfflineCacheService();
    service.initializeWithDatabase(getIt<AppDatabase>());
    return service;
  });

  getIt.registerLazySingleton<ConnectivityService>(() => ConnectivityService());
  getIt.registerLazySingleton<AudioService>(() => AudioService());
  getIt.registerLazySingleton<HapticService>(() => HapticService());
  getIt.registerLazySingleton<PreferencesService>(() => PreferencesService());

  // StorageService needs database initialization
  getIt.registerLazySingleton<StorageService>(() {
    final service = StorageService();
    service.initialize(getIt<AppDatabase>());
    return service;
  });

  getIt.registerLazySingleton<UnifiedUserService>(() => UnifiedUserService());
  getIt.registerLazySingleton<AchievementService>(() => AchievementService());
  getIt.registerLazySingleton<StatisticsService>(() => StatisticsService());
  getIt.registerLazySingleton<ProgressionService>(() => ProgressionService());
  getIt.registerLazySingleton<AdService>(() => AdService());
  getIt.registerLazySingleton<PurchaseService>(() => PurchaseService());
  getIt.registerLazySingleton<AppDataCache>(() => AppDataCache());
  getIt.registerLazySingleton<ReviewService>(
    () => ReviewService(
      statisticsService: getIt<StatisticsService>(),
      analytics: getIt<AnalyticsFacade>(),
    ),
  );

  // ==================== Analytics ====================
  // Debug builds never hit production Firebase Analytics — they log locally only.
  getIt.registerLazySingleton<AnalyticsFacade>(() {
    return AnalyticsFacade([
      if (kDebugMode) LoggerAnalyticsClient() else FirebaseAnalyticsClient(),
    ]);
  });

  // ==================== Core ====================

  getIt.registerLazySingleton<NetworkInfo>(
    () => NetworkInfoImpl(getIt<ConnectivityService>()),
  );

  // ==================== Data Sources ====================

  getIt.registerLazySingleton<CacheDataSource>(
    () => CacheDataSource(getIt<OfflineCacheService>()),
  );

  getIt.registerLazySingleton<ApiDataSource>(
    () => ApiDataSource(getIt<ApiService>()),
  );

  // ==================== Cubits ====================
  // Cubits are registered as factories (new instance each time)
  // This ensures fresh state when navigating to new screens

  getIt.registerLazySingleton<ThemeCubit>(
    () => ThemeCubit(
      getIt<PreferencesService>(),
      getIt<StorageService>(),
      getIt<AnalyticsFacade>(),
    ),
  );

  getIt.registerFactory<AuthCubit>(
    () => AuthCubit(getIt<UnifiedUserService>(), getIt<AnalyticsFacade>()),
  );

  getIt.registerLazySingleton<GameSettingsCubit>(
    () => GameSettingsCubit(getIt<StorageService>()),
  );

  // Register CoinsCubit as singleton so it can be shared across game sessions
  getIt.registerLazySingleton<CoinsCubit>(() => CoinsCubit());

  // Cross-screen tournament context for Flame runs (set by the tournament
  // detail screen, consumed by pre-game loading + gameplay).
  getIt.registerLazySingleton<TournamentContextCubit>(
    () => TournamentContextCubit(),
  );

  getIt.registerLazySingleton<PremiumCubit>(
    () => PremiumCubit(
      purchaseService: getIt<PurchaseService>(),
      storageService: getIt<StorageService>(),
      coinsCubit: getIt<CoinsCubit>(),
      analytics: getIt<AnalyticsFacade>(),
    ),
  );

  getIt.registerLazySingleton<BattlePassCubit>(
    () => BattlePassCubit(
      storageService: getIt<StorageService>(),
      premiumCubit: getIt<PremiumCubit>(),
      analytics: getIt<AnalyticsFacade>(),
      progressionService: getIt<ProgressionService>(),
    ),
  );

  getIt.registerLazySingleton<PowerUpCubit>(() => PowerUpCubit());

  // ==================== Sync ====================
  // SyncEngine owns the outbox drain (Drift SyncQueue → backend
  // batch endpoints). Registered as a lazy singleton; `initialize`
  // is kicked off from main.dart after the DB is ready.
  getIt.registerLazySingleton<SyncEngine>(() => SyncEngine());
}

/// Reset all dependencies (useful for testing)
Future<void> resetDependencies() async {
  await getIt.reset();
}

/// Check if dependencies are registered
bool get dependenciesRegistered => getIt.isRegistered<ApiService>();
