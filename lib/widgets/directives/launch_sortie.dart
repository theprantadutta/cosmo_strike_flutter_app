import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';

/// Starts a sortie exactly like Home's LAUNCH: straight into the furthest
/// unlocked campaign level through the pre-game loader (which
/// pushReplacements to /game, so back from the game returns here).
Future<void> launchNextSortie(BuildContext context) async {
  final startLevel = await getIt<AppDatabase>().stageProgressDao.getFurthestUnlocked();
  if (!context.mounted) return;
  context.push(AppRoutes.playLoading, extra: startLevel);
}
