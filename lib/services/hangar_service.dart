import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/di/injection.dart';
import '../data/database/app_database.dart';
import '../game/hangar.dart';
import '../models/ship_coins.dart';
import '../presentation/bloc/coins/coins_cubit.dart';
import '../utils/logger.dart';
import 'achievement_service.dart';
import 'storage_service.dart';

/// Offline-first Hangar state.
///
/// - Upgrade levels are owned items (`UnlockedItems`, type "hangar",
///   id `hangar_<stat>_<level>`): written to Drift and synced through the
///   existing unlocked-item outbox — no new backend endpoint.
/// - Ship frames unlock from campaign clears (Drift stage progress), so they
///   need no storage; the selected frame is a device preference.
class HangarService extends ChangeNotifier {
  HangarService._();
  static final HangarService instance = HangarService._();

  static const String itemType = 'hangar';
  static const String _shipPrefKey = 'hangar_selected_ship';

  Map<HangarStat, int> _levels = {};
  int _highestCleared = 0;
  String _selected = ShipFrame.striker.id;
  bool _loaded = false;

  bool get loaded => _loaded;
  int level(HangarStat s) => _levels[s] ?? 0;
  int get highestCleared => _highestCleared;
  ShipFrame get selectedFrame {
    final f = ShipFrame.byId(_selected);
    return f.ownedWith(_highestCleared) ? f : ShipFrame.striker;
  }

  /// What the next run applies.
  HangarLoadout get loadout => HangarLoadout(levels: Map.of(_levels), frame: selectedFrame);

  Future<void> load() async {
    try {
      final storage = StorageService();
      if (storage.isInitialized) {
        _levels = HangarCatalog.levelsFrom(await storage.storeDao.getUnlockedItemsByType(itemType));
      }
      final stages = await getIt<AppDatabase>().stageProgressDao.getAll();
      _highestCleared = stages.where((s) => s.cleared).fold<int>(0, (m, s) => s.stageId > m ? s.stageId : m);
      final prefs = await SharedPreferences.getInstance();
      _selected = prefs.getString(_shipPrefKey) ?? ShipFrame.striker.id;
      _loaded = true;
      notifyListeners();
    } catch (e) {
      AppLogger.error('Hangar load failed', e);
    }
  }

  /// Buy the next level of [stat]. Coins are spent first (offline-first via
  /// CoinsCubit); the level is granted only if the spend succeeded.
  Future<bool> buyNext(HangarStat stat) async {
    final current = level(stat);
    if (current >= HangarCatalog.maxLevel) return false;
    final cost = HangarCatalog.costForNext(current);
    final coins = getIt<CoinsCubit>();
    if (!coins.canAfford(cost)) return false;
    final ok = await coins.spendCoins(
      cost,
      CoinSpendingCategory.boosts,
      itemName: '${HangarCatalog.byStat(stat).name} L${current + 1}',
      metadata: {'hangar_stat': stat.name, 'level': current + 1},
    );
    if (!ok) return false;
    await StorageService().storeDao.unlockItem(
      HangarCatalog.itemId(stat, current + 1),
      itemType,
      unlockedBy: 'coins',
    );
    _levels = {..._levels, stat: current + 1};
    notifyListeners();
    // Hangar commendations (Retrofit / Fully Refit) — read-only hook.
    unawaited(AchievementService().evaluateStanding().then<void>((_) {}, onError: (Object _) {}));
    return true;
  }

  Future<void> selectFrame(ShipFrame frame) async {
    if (!frame.ownedWith(_highestCleared)) return;
    _selected = frame.id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_shipPrefKey, frame.id);
  }
}
