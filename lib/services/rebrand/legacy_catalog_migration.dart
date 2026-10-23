import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database/app_database.dart';
import '../../models/premium_cosmetics.dart';
import '../../models/premium_power_up.dart';
import '../../utils/constants.dart' show GameConstants, GameTheme;
import '../../utils/logger.dart';

/// One-time rewrite of persisted catalog IDs to the 3.2 Armory catalog
/// (REBRAND_SPEC §2.8 / §5): skins → liveries, trails → exhausts, themes →
/// sectors, cosmetic bundles → Fleet Kits, power-up keys → `gear_*`.
///
/// Reads are already tolerant (`LiveryType.fromId`, `ExhaustType.fromId`,
/// `GameTheme.fromId` / `fromIndex`, `PremiumPowerUpType.normalizeKey`), so
/// this is storage hygiene — EXCEPT for the theme index, where the old
/// `modern` slot (index 1) is indistinguishable from the new High Contrast
/// slot and must be rewritten here, before the first post-upgrade read.
///
/// Nothing is enqueued for push: the backend runs the same remap in its own
/// data migration, so echoing the rewritten rows back would only add load.
///
/// Idempotent: guarded by a SharedPreferences flag; every step is a no-op
/// on already-migrated data, so a crash mid-way simply re-runs.
///
/// Covers:
/// - `UnlockedItems` rows of type skin / trail / theme / bundle (provenance
///   kept; legacy IDs folding onto the same new ID collapse to one row; the
///   free items and dropped bundles are removed)
/// - `GameSettings.selectedSkinId` / `selectedTrailId` / `themeIndex`
/// - `PowerUpInventory.inventoryJson` keys (counts merged)
/// - pending `SyncQueue` unlocked-item payloads
/// - SharedPreferences `selected_theme` index
const String kLegacyCatalogMigrationFlag = 'rebrand_v32_catalog_migrated';

Future<void> migrateLegacyCatalog(AppDatabase db) async {
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    AppLogger.warning('LegacyCatalogMigration: prefs unavailable, skipping: $e');
    return;
  }
  if (prefs.getBool(kLegacyCatalogMigrationFlag) ?? false) return;

  var rewritten = 0;
  try {
    rewritten += await _migrateUnlockedItems(db);
    rewritten += await _migrateSettings(db);
    rewritten += await _migratePowerUpInventory(db);
    rewritten += await _migrateSyncQueue(db);
    rewritten += await _migratePrefs(prefs);
  } catch (e, st) {
    // Leave the flag unset so the next launch retries; reads stay tolerant
    // in the meantime.
    AppLogger.error('LegacyCatalogMigration failed', e, st);
    return;
  }

  await prefs.setBool(kLegacyCatalogMigrationFlag, true);
  AppLogger.info('LegacyCatalogMigration: done ($rewritten rows rewritten)');
}

/// Canonical ID for an `UnlockedItems` row (or an unlocked-item sync
/// payload). Returns the input unchanged for item types this catalog doesn't
/// own (hangar, board_size, game_mode, …) and null when the row should be
/// dropped (free items, retired bundles, unknown junk).
String? normalizeUnlockedItemId(String itemType, String itemId) {
  switch (itemType) {
    case 'skin':
      final l = LiveryType.tryParse(itemId);
      return (l == null || !l.isPremium) ? null : l.id;
    case 'trail':
      final e = ExhaustType.tryParse(itemId);
      return (e == null || !e.isPremium) ? null : e.id;
    case 'theme':
      final t = GameTheme.fromId(itemId);
      return (t == null || !t.isPremium) ? null : t.id;
    case 'bundle':
      return FleetKit.normalizeBundleId(itemId);
    case 'powerup':
      return PremiumPowerUpType.normalizeKey(itemId);
    default:
      return itemId;
  }
}

const Set<String> _catalogTypes = {'skin', 'trail', 'theme', 'bundle', 'powerup'};

Future<int> _migrateUnlockedItems(AppDatabase db) async {
  var n = 0;
  final rows = await (db.select(db.unlockedItems)
        ..where((t) => t.itemType.isIn(_catalogTypes)))
      .get();
  // (type, id) pairs that already exist in canonical form, so a remapped
  // legacy row folding onto one is simply deleted.
  final present = <String>{
    for (final r in rows)
      if (normalizeUnlockedItemId(r.itemType, r.itemId) == r.itemId)
        '${r.itemType}:${r.itemId}',
  };
  await db.transaction(() async {
    for (final row in rows) {
      final next = normalizeUnlockedItemId(row.itemType, row.itemId);
      if (next == row.itemId) continue;
      final key = '${row.itemType}:$next';
      if (next == null || present.contains(key)) {
        await (db.delete(db.unlockedItems)..where((t) => t.id.equals(row.id)))
            .go();
      } else {
        await (db.update(db.unlockedItems)..where((t) => t.id.equals(row.id)))
            .write(UnlockedItemsCompanion(itemId: Value(next)));
        present.add(key);
      }
      n++;
    }
  });
  return n;
}

Future<int> _migrateSettings(AppDatabase db) async {
  final row = await db.settingsDao.getSettings();
  if (row == null) return 0;
  final skin = row.selectedSkinId == null
      ? null
      : LiveryType.fromId(row.selectedSkinId).id;
  final trail = row.selectedTrailId == null
      ? null
      : ExhaustType.fromId(row.selectedTrailId).id;
  // Stored index is pre-3.2 (old 11-theme order) by definition here.
  final themeIndex = GameTheme.fromLegacyIndex(row.themeIndex).index;
  if (skin == row.selectedSkinId &&
      trail == row.selectedTrailId &&
      themeIndex == row.themeIndex) {
    return 0;
  }
  // Snapshot path: writes the singleton without enqueueing an outbox push
  // and without bumping updatedAt (the server migrates its copy itself).
  await db.settingsDao.applySettingsSnapshot(GameSettingsCompanion(
    selectedSkinId: Value(skin),
    selectedTrailId: Value(trail),
    themeIndex: Value(themeIndex),
  ));
  return 1;
}

Future<int> _migratePowerUpInventory(AppDatabase db) async {
  final row = await db.storeDao.getPowerUpInventoryRow();
  if (row == null) return 0;
  final current = await db.storeDao.getPowerUpInventory();
  final next = PremiumPowerUpType.normalizeInventory(current);
  if (_sameMap(current, next)) return 0;
  await db.storeDao.savePowerUpInventory(
    next,
    enqueueSync: false,
    updatedAt: row.updatedAt,
  );
  return 1;
}

bool _sameMap(Map<String, int> a, Map<String, int> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// Pending unlocked-item pushes queued by the old build carry legacy IDs in
/// both the entity key and the payload; rewrite them (or drop them when the
/// item no longer exists) so nothing legacy reaches the backend.
Future<int> _migrateSyncQueue(AppDatabase db) async {
  var n = 0;
  final rows = await (db.select(db.syncQueue)
        ..where((t) =>
            t.status.isNotIn(const [3]) &
            t.dataType.equals(SyncDataType.unlockedItem)))
      .get();
  for (final row in rows) {
    final Object? decoded;
    try {
      decoded = jsonDecode(row.data);
    } catch (_) {
      continue;
    }
    if (decoded is! Map) continue;
    final payload = decoded['payload'];
    if (payload is! Map) continue;
    final type = payload['item_type'];
    final id = payload['item_id'];
    if (type is! String || id is! String || !_catalogTypes.contains(type)) {
      continue;
    }
    final next = normalizeUnlockedItemId(type, id);
    if (next == id) continue;
    if (next == null) {
      await (db.delete(db.syncQueue)..where((t) => t.id.equals(row.id))).go();
    } else {
      final data = Map<String, Object?>.from(decoded)
        ..['entityKey'] = 'unlocked_item:$type:$next'
        ..['payload'] = (Map<String, Object?>.from(payload)..['item_id'] = next);
      await (db.update(db.syncQueue)..where((t) => t.id.equals(row.id)))
          .write(SyncQueueCompanion(data: Value(jsonEncode(data))));
    }
    n++;
  }
  return n;
}

/// PreferencesService mirrors the theme as an INDEX under
/// `selected_theme`; remap it from the old 11-theme order.
Future<int> _migratePrefs(SharedPreferences prefs) async {
  const key = GameConstants.selectedThemeKey;
  final raw = prefs.getInt(key);
  if (raw == null) return 0;
  final next = GameTheme.fromLegacyIndex(raw).index;
  if (next == raw) return 0;
  await prefs.setInt(key, next);
  return 1;
}
