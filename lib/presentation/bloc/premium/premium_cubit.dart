import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart' as db;
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_settings_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/power_up/power_up_cubit.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/api_service.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/models/premium_cosmetics.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

import 'premium_state.dart';

export 'premium_state.dart';

/// Cubit for managing premium subscription and owned content
class PremiumCubit extends Cubit<PremiumState> {
  final PurchaseService _purchaseService;
  final StorageService _storageService;
  final CoinsCubit? _coinsCubit;
  final AnalyticsFacade _analytics;
  StreamSubscription<String>? _purchaseStatusSubscription;

  /// Drift watch on the `premium_status` singleton. Keeps the Pro
  /// entitlement state in lock-step with writes from elsewhere —
  /// most importantly the first-sign-in snapshot apply, which lands
  /// the cloud's IsPremiumActive / expiry AFTER initialize() ran.
  /// Without the watch, a returning Pro user briefly sees free-tier
  /// UI on a fresh install (until something else triggers a reload).
  StreamSubscription<db.PremiumStatusData?>? _premiumStatusWatch;
  bool _reloadingFromDrift = false;

  PremiumCubit({
    required PurchaseService purchaseService,
    required StorageService storageService,
    CoinsCubit? coinsCubit,
    required AnalyticsFacade analytics,
  }) : _purchaseService = purchaseService,
       _storageService = storageService,
       _coinsCubit = coinsCubit,
       _analytics = analytics,
       super(PremiumState.initial());

  /// Initialize premium status
  Future<void> initialize() async {
    if (state.status == PremiumStatus.ready) return;

    emit(state.copyWith(status: PremiumStatus.loading));

    try {
      await _purchaseService.initialize();

      // Load saved premium state
      final isPremiumActive = await _storageService.isPremiumActive();
      final expiryDateStr = await _storageService.getPremiumExpirationDate();
      // Every persisted cosmetic ID is parsed through the catalog's legacy
      // aliases, so pre-3.2 rows (skin 'golden', trail 'trail_fire',
      // theme 'space') read as their new equivalents even before the
      // one-time legacy_catalog_migration rewrites them on disk.
      final selectedSkinId =
          LiveryType.fromId(await _storageService.getSelectedSkinId()).id;
      final selectedTrailId =
          ExhaustType.fromId(await _storageService.getSelectedTrailId()).id;
      final ownedThemes = await _storageService.getUnlockedThemes();
      final ownedSkins = await _storageService.getUnlockedSkins();
      final ownedTrails = await _storageService.getUnlockedTrails();
      final ownedPowerUps = await _storageService.getUnlockedPowerUps();
      final ownedBundles = await _storageService.getUnlockedBundles();
      final tournamentEntries = await _storageService.getTournamentEntries();

      DateTime? expiryDate;
      if (expiryDateStr != null) {
        expiryDate = DateTime.tryParse(expiryDateStr);
      }

      emit(
        state.copyWith(
          status: PremiumStatus.ready,
          tier: isPremiumActive ? PremiumTier.pro : PremiumTier.free,
          subscriptionExpiry: expiryDate,
          selectedSkinId: selectedSkinId,
          selectedTrailId: selectedTrailId,
          ownedThemes: _parseThemes(ownedThemes),
          ownedSkins: _parseLiveries(ownedSkins),
          ownedTrails: _parseExhausts(ownedTrails),
          ownedPowerUps: ownedPowerUps.toSet(),
          ownedBundles: _parseBundles(ownedBundles),
          bronzeTournamentEntries: tournamentEntries['bronze'] ?? 0,
          silverTournamentEntries: tournamentEntries['silver'] ?? 0,
          goldTournamentEntries: tournamentEntries['gold'] ?? 0,
        ),
      );

      // Reconcile bundle contents for existing bundle owners
      for (final bundleId in state.ownedBundles) {
        // Fleet Kits — liveries + exhausts
        final kit = FleetKit.byId(bundleId);
        if (kit != null) {
          for (final livery in kit.liveries) {
            if (!state.ownedSkins.contains(livery.id)) {
              await unlockSkin(livery.id);
            }
          }
          for (final exhaust in kit.exhausts) {
            if (!state.ownedTrails.contains(exhaust.id)) {
              await unlockTrail(exhaust.id);
            }
          }
        }
        // Star Atlas — every premium sector.
        if (bundleId == FleetKit.sectorAtlasId) {
          for (final sector in PremiumContent.premiumThemes) {
            if (!state.ownedThemes.contains(sector)) await unlockTheme(sector);
          }
        }

        // Gear bundles are CONSUMABLE count packs (PowerUpCubit
        // inventory), not permanent unlocks — nothing to re-derive here.
      }

      // Listen to purchase updates
      _setupPurchaseListener();

      // Subscribe to PremiumStatus Drift writes so a cloud-restore /
      // server reconcile that lands AFTER this init flips the local
      // entitlement state without a screen rebuild.
      _wireDriftWatch();

      // Backend reconcile (which is what catches server-side Pro
      // revocations) is no longer fired here — AuthCubit triggers it
      // after the user is authenticated (see
      // AuthCubit._firePostAuthSyncs). Firing here raced auth: on a
      // cold start the JWT often wasn't ready yet, syncWithBackend
      // early-returned, and a stale tier=pro would persist locally
      // even though the backend had revoked.

      AppLogger.info('PremiumCubit initialized. Premium: ${state.hasPremium}');
    } catch (e) {
      AppLogger.error('Error initializing PremiumCubit', e);
      emit(
        state.copyWith(status: PremiumStatus.error, errorMessage: e.toString()),
      );
    }
  }

  /// Persisted / server sector IDs (current or pre-3.2) → sectors.
  static Set<GameTheme> _parseThemes(Iterable<String> ids) =>
      ids.map(GameTheme.fromId).whereType<GameTheme>().toSet();

  /// Persisted / server livery IDs → canonical IDs. The free livery and
  /// unknown junk are dropped (several legacy skins fold onto one livery).
  static Set<String> _parseLiveries(Iterable<String> ids) => ids
      .map(LiveryType.tryParse)
      .whereType<LiveryType>()
      .where((l) => l.isPremium)
      .map((l) => l.id)
      .toSet();

  /// Persisted / server exhaust IDs → canonical IDs (see [_parseLiveries]).
  static Set<String> _parseExhausts(Iterable<String> ids) => ids
      .map(ExhaustType.tryParse)
      .whereType<ExhaustType>()
      .where((e) => e.isPremium)
      .map((e) => e.id)
      .toSet();

  /// Persisted / server bundle IDs → current Fleet Kit / Star Atlas IDs.
  static Set<String> _parseBundles(Iterable<String> ids) =>
      ids.map(FleetKit.normalizeBundleId).whereType<String>().toSet();

  void _setupPurchaseListener() {
    _purchaseStatusSubscription = _purchaseService.purchaseStatusStream.listen((
      status,
    ) {
      if (status == 'premium_purchased' || status == 'premium_restored') {
        _handlePremiumPurchased();
      } else if (status.startsWith('purchase_completed:')) {
        final productId = status.substring('purchase_completed:'.length);
        _handlePurchaseCompleted(productId);
      }
    });
  }

  Future<void> _handlePurchaseCompleted(String productId) async {
    AppLogger.info('Handling purchase completion: $productId');

    // Strip store prefix — all comparisons below use internal IDs
    final internalId = ProductIds.stripPrefix(productId);

    // Strike Command — route monthly vs annual for correct expiry
    if (internalId == ProductIds.stripPrefix(ProductIds.commandMonthly)) {
      _handlePremiumPurchased(isYearly: false);
      return;
    }
    if (internalId == ProductIds.stripPrefix(ProductIds.commandAnnual)) {
      _handlePremiumPurchased(isYearly: true);
      return;
    }

    // Credit Caches — credit via CoinsCubit
    final option = CoinPurchaseOption.availableOptions
        .where((o) => o.id == internalId)
        .firstOrNull;
    if (option != null) {
      if (_coinsCubit != null) {
        await _coinsCubit.purchaseCoins(option, productId);
        AppLogger.info(
          'Credit cache delivered: ${option.totalCoins} credits for $internalId',
        );
        // Pull the authoritative balance from the server. Backend's
        // VerifyPurchaseCommandHandler increments User.Coins on a successful
        // verify; this sync keeps local in step with the server-side total
        // (and is a no-op if local is already ahead).
        unawaited(_coinsCubit.syncWithBackend());
      } else {
        AppLogger.error(
          'Failed to deliver credit cache $internalId: no CoinsCubit',
        );
      }
      return;
    }

    // Star Atlas — every premium sector
    if (internalId == FleetKit.sectorAtlasId) {
      for (final sector in PremiumContent.premiumThemes) {
        await unlockTheme(sector);
      }
      await unlockBundle(FleetKit.sectorAtlasId);
      return;
    }

    // Single sectors
    final sector = GameTheme.fromId(internalId);
    if (sector != null && sector.productId == internalId) {
      await unlockTheme(sector);
      return;
    }

    // Liveries
    final livery = LiveryType.tryParse(internalId);
    if (livery != null && livery.isPremium && livery.id == internalId) {
      await unlockSkin(livery.id);
      return;
    }

    // Exhausts
    final exhaust = ExhaustType.tryParse(internalId);
    if (exhaust != null && exhaust.isPremium && exhaust.id == internalId) {
      await unlockTrail(exhaust.id);
      return;
    }

    // Fleet Kits
    if (FleetKit.byId(internalId) != null) {
      await unlockBundle(internalId);
      return;
    }

    // Cup Passes — keep in sync with the backend's TournamentEntryGrants.
    final cupGrants = ProductIds.cupPassGrants[internalId];
    if (cupGrants != null) {
      for (final grant in cupGrants.entries) {
        await addTournamentEntry(grant.key, count: grant.value);
      }
      return;
    }

    AppLogger.warning('Unhandled purchase product: $internalId');
  }

  void _handlePremiumPurchased({bool isYearly = false}) {
    final duration = isYearly
        ? const Duration(days: 365)
        : const Duration(days: 30);
    final expiry = DateTime.now().add(duration);
    emit(state.copyWith(tier: PremiumTier.pro, subscriptionExpiry: expiry));
    _storageService.setPremiumActive(true);
    _storageService.setPremiumExpirationDate(expiry.toIso8601String());
    _coinsCubit?.updatePremiumMultiplier(true, state.hasBattlePass);
    _analytics.trackPremiumSubscriptionStarted();
    _analytics.setUserProperties(isPremium: true);

    // The Pro purchase server-side now grants a premium power-up bundle
    // + free tournament tier entries (VerifyPurchaseCommandHandler). Kick
    // off a sync so those grants land in local state immediately rather
    // than waiting for the next manual refresh. Fire-and-forget — the
    // user-visible status flip already happened above.
    unawaited(syncWithBackend());
    unawaited(getIt<PowerUpCubit>().loadInventory());
  }

  /// Purchase Strike Command (monthly)
  /// Note: actual unlock happens via purchase stream in _handlePurchaseCompleted
  Future<bool> purchasePremium() async {
    try {
      final result = await _purchaseService.purchaseProduct(
        ProductIds.commandMonthly,
      );
      // Do NOT call _handlePremiumPurchased() here — purchaseProduct() only
      // initiates the billing flow. The actual completion arrives asynchronously
      // via the purchase stream and is handled in _handlePurchaseCompleted().
      return result;
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Purchase failed: $e'));
      return false;
    }
  }

  /// Restore purchases
  Future<void> restorePurchases() async {
    try {
      await _purchaseService.restorePurchases();
      // The purchase stream will handle updating state if purchases are found
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Restore failed: $e'));
    }
  }

  /// Sync battle pass status from BattlePassCubit
  void syncBattlePassStatus({required bool isActive, required int tier}) {
    if (state.hasBattlePass == isActive && state.battlePassTier == tier) return;
    emit(state.copyWith(hasBattlePass: isActive, battlePassTier: tier));
    _coinsCubit?.updatePremiumMultiplier(state.hasPremium, isActive);
  }

  /// Equip a livery (validates it's unlocked — owned, kit, or Strike
  /// Command; the free livery is always allowed). Accepts legacy IDs.
  /// Pushes the choice to the backend so it survives reinstall/device-switch.
  Future<void> selectSkin(String id) async {
    final livery = LiveryType.fromId(id);
    final skinId = livery.id;
    if (state.selectedSkinId == skinId) return;
    if (!state.isLiveryUnlocked(livery)) {
      AppLogger.warning('Attempted to equip locked livery: $skinId');
      return;
    }

    emit(state.copyWith(selectedSkinId: skinId));
    await _storageService.setSelectedSkinId(skinId);
    _analytics.trackCosmeticEquipped(cosmeticType: 'livery', cosmeticId: skinId);
    unawaited(ApiService().setEquippedCosmetics(skinId: skinId));
  }

  /// Equip an exhaust (validates it's unlocked — the stock thruster is
  /// always allowed). Accepts legacy IDs.
  /// Pushes the choice to the backend so it survives reinstall/device-switch.
  Future<void> selectTrail(String id) async {
    final exhaust = ExhaustType.fromId(id);
    final trailId = exhaust.id;
    if (state.selectedTrailId == trailId) return;
    if (!state.isExhaustUnlocked(exhaust)) {
      AppLogger.warning('Attempted to equip locked exhaust: $trailId');
      return;
    }

    emit(state.copyWith(selectedTrailId: trailId));
    await _storageService.setSelectedTrailId(trailId);
    _analytics.trackCosmeticEquipped(cosmeticType: 'exhaust', cosmeticId: trailId);
    unawaited(ApiService().setEquippedCosmetics(trailId: trailId));

    // Equipping a real exhaust flips the engine-effects master gate on —
    // it defaults to off, and a buyer who equips an exhaust expects to SEE
    // it in-game, not to hunt down a second toggle.
    if (exhaust != ExhaustType.stock) {
      try {
        unawaited(getIt<ThemeCubit>().setTrailSystemEnabled(true));
      } catch (e) {
        AppLogger.warning('Could not auto-enable exhaust effects: $e');
      }
    }
  }

  /// Push the currently-applied theme to the backend so it survives
  /// reinstall/device-switch. The actual local theme state lives in
  /// ThemeCubit — this is a fire-and-forget passthrough for sync.
  Future<void> syncSelectedTheme(String themeName) async {
    unawaited(ApiService().setEquippedCosmetics(themeId: themeName));
  }

  /// Unlock a sector
  Future<void> unlockTheme(GameTheme theme) async {
    final updatedThemes = {...state.ownedThemes, theme};
    emit(state.copyWith(ownedThemes: updatedThemes));
    // Single-item write: only the new theme goes into the outbox,
    // not every theme the user already owns.
    await _storageService.unlockItem(theme.name, 'theme');
  }

  /// Unlock a livery (legacy IDs are folded onto the new catalog).
  Future<void> unlockSkin(String id) async {
    final skinId = LiveryType.normalizeId(id);
    if (skinId == null) {
      AppLogger.warning('Ignoring unknown livery unlock: $id');
      return;
    }
    final updatedSkins = {...state.ownedSkins, skinId};
    emit(state.copyWith(ownedSkins: updatedSkins));
    await _storageService.unlockItem(skinId, 'skin');
  }

  /// Unlock an exhaust (legacy IDs are folded onto the new catalog).
  Future<void> unlockTrail(String id) async {
    final trailId = ExhaustType.normalizeId(id);
    if (trailId == null) {
      AppLogger.warning('Ignoring unknown exhaust unlock: $id');
      return;
    }
    final updatedTrails = {...state.ownedTrails, trailId};
    emit(state.copyWith(ownedTrails: updatedTrails));
    await _storageService.unlockItem(trailId, 'trail');
  }

  /// Unlock a power-up
  Future<void> unlockPowerUp(String powerUpId) async {
    final updatedPowerUps = {...state.ownedPowerUps, powerUpId};
    emit(state.copyWith(ownedPowerUps: updatedPowerUps));
    await _storageService.unlockItem(powerUpId, 'powerup');
    AppLogger.info('Power-up unlocked: $powerUpId');
  }

  /// Unlock a bundle (and all its contents — Fleet Kit cosmetics)
  Future<void> unlockBundle(String id) async {
    final bundleId = FleetKit.normalizeBundleId(id) ?? id;
    if (state.ownedBundles.contains(bundleId)) return;

    final updatedBundles = {...state.ownedBundles, bundleId};
    emit(state.copyWith(ownedBundles: updatedBundles));
    await _storageService.unlockItem(bundleId, 'bundle');

    // Unlock Fleet Kit contents (liveries + exhausts)
    final kit = FleetKit.byId(bundleId);
    if (kit != null) {
      for (final livery in kit.liveries) {
        await unlockSkin(livery.id);
      }
      for (final exhaust in kit.exhausts) {
        await unlockTrail(exhaust.id);
      }
    }

    // Gear bundles are consumable count packs (PowerUpCubit grants the
    // uses at purchase time) — no permanent unlock rows.

    AppLogger.info('Bundle unlocked: $bundleId');
  }

  /// Add Cup Passes of a wire tier (bronze = Scout, silver = Strike,
  /// gold = Ace)
  Future<void> addTournamentEntry(
    String tournamentType, {
    int count = 1,
  }) async {
    switch (tournamentType.toLowerCase()) {
      case 'bronze':
        emit(
          state.copyWith(
            bronzeTournamentEntries: state.bronzeTournamentEntries + count,
          ),
        );
        break;
      case 'silver':
        emit(
          state.copyWith(
            silverTournamentEntries: state.silverTournamentEntries + count,
          ),
        );
        break;
      case 'gold':
        emit(
          state.copyWith(
            goldTournamentEntries: state.goldTournamentEntries + count,
          ),
        );
        break;
    }
    await _saveTournamentEntries();
    AppLogger.info('Tournament entry added: $tournamentType x$count');
  }

  /// Use Cup Passes of a wire tier
  Future<void> useTournamentEntry(String tournamentType, {int count = 1}) async {
    switch (tournamentType.toLowerCase()) {
      case 'bronze':
        if (state.bronzeTournamentEntries >= count) {
          emit(
            state.copyWith(
              bronzeTournamentEntries: state.bronzeTournamentEntries - count,
            ),
          );
        }
        break;
      case 'silver':
        if (state.silverTournamentEntries >= count) {
          emit(
            state.copyWith(
              silverTournamentEntries: state.silverTournamentEntries - count,
            ),
          );
        }
        break;
      case 'gold':
        if (state.goldTournamentEntries >= count) {
          emit(
            state.copyWith(
              goldTournamentEntries: state.goldTournamentEntries - count,
            ),
          );
        }
        break;
    }
    await _saveTournamentEntries();
    AppLogger.info('Tournament entry used: $tournamentType x$count');
  }

  Future<void> _saveTournamentEntries() async {
    await _storageService.setTournamentEntries(
      bronze: state.bronzeTournamentEntries,
      silver: state.silverTournamentEntries,
      gold: state.goldTournamentEntries,
    );
  }

  // Convenience checker methods (delegate to state)
  bool isThemeUnlocked(GameTheme theme) => state.isThemeUnlocked(theme);
  bool isSkinUnlocked(String liveryId) => state.isSkinOwned(liveryId);
  bool isTrailUnlocked(String exhaustId) => state.isTrailOwned(exhaustId);
  bool isPowerUpUnlocked(String powerUpId) =>
      state.isPowerUpUnlocked(powerUpId);
  bool isBundleOwned(String bundleId) => state.isBundleOwned(bundleId);
  bool hasTournamentEntry(String type) => state.hasTournamentEntry(type);

  /// Sync premium entitlements from backend.
  /// Merges server-side entitlements into local state so purchases made on
  /// other devices or granted server-side are reflected.
  Future<void> syncWithBackend() async {
    try {
      final apiService = ApiService();
      if (!apiService.isAuthenticated) return;

      // Wait for the cubit to finish hydrating before applying backend
      // state. _applyBackendEntitlements gates several branches on the
      // current in-memory state — most importantly the revocation block
      // (`is_premium == false && state.tier == PremiumTier.pro`). If the
      // sync fires before initialize() reads `isPremiumActive=true` from
      // disk, `state.tier` is still the default `free` and the gate
      // misses, leaving the revocation unpersisted. AuthCubit only fires
      // the post-auth sync once per UID (`_lastSyncedUid` guard), so a
      // missed downgrade then persists until the user signs out/in.
      if (state.status != PremiumStatus.ready) {
        try {
          await stream
              .firstWhere((s) => s.status == PremiumStatus.ready)
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          AppLogger.warning(
            'PremiumCubit not ready within 10s — skipping backend sync; '
            'will retry on next launch',
          );
          return;
        }
      }

      final data = await apiService.getPremiumContent();
      if (data == null) return;

      await _applyBackendEntitlements(data);
      AppLogger.info(
        'Premium state synced with backend (is_premium=${data['is_premium']}, '
        'local_tier=${state.tier.name})',
      );
    } catch (e) {
      AppLogger.error('Error syncing premium state with backend', e);
    }
  }

  /// Re-evaluate the LOCAL Pro entitlement against its stored expiry,
  /// with NO network call. This complements [syncWithBackend], which can
  /// only downgrade when online AND the server says is_premium=false.
  ///
  /// The gap it closes: a subscription that lapses while the device is
  /// offline (or while the app sits foregrounded for a long time). Once
  /// the stored — now server-authoritative, see [_applyBackendEntitlements]
  /// — expiry passes, this drops the user to free on the next resume even
  /// with no connectivity. Reading [StorageService.isPremiumActive] flips
  /// the persisted flag + enqueues a sync_outbox row when the expiry is in
  /// the past; the Drift watch then re-projects tier=free into state, and
  /// the explicit emit below makes the downgrade take effect immediately.
  Future<void> recheckLocalExpiry() async {
    if (state.status != PremiumStatus.ready) return;
    if (state.tier != PremiumTier.pro) return;
    final stillActive = await _storageService.isPremiumActive();
    if (!stillActive && state.tier == PremiumTier.pro) {
      AppLogger.info(
        'Local Pro expiry passed (${state.subscriptionExpiry}) — '
        'downgrading to free without waiting for the backend',
      );
      emit(state.copyWith(tier: PremiumTier.free));
      _coinsCubit?.updatePremiumMultiplier(false, state.hasBattlePass);
    }
  }

  /// Apply entitlements returned by the backend to local state.
  ///
  /// AUTHORITATIVE sync: the server is the source of truth for ownership.
  /// If a refund/chargeback/revocation removes an item server-side, the
  /// local owned-set is pruned to match, and any currently-equipped item
  /// that's no longer owned falls back to the default (Standard Issue
  /// livery / Stock Thruster / Prism Noir sector). Without this, a user whose payment
  /// was reversed would keep using premium cosmetics indefinitely.
  ///
  /// Defensive: only prune a list if the server actually sent it. A
  /// missing key (network error reading one section) leaves the local
  /// set alone rather than wiping everything.
  Future<void> _applyBackendEntitlements(Map<String, dynamic> data) async {
    // ---- Owned themes ----
    if (data['owned_themes'] is List) {
      final serverThemes =
          _parseThemes((data['owned_themes'] as List).whereType<String>());
      if (serverThemes != state.ownedThemes) {
        emit(state.copyWith(ownedThemes: serverThemes));
        // Merge-only: locally-owned themes the server doesn't know
        // about (e.g., achievement rewards that bypass /premium-content)
        // are preserved, and we don't echo the server's data back.
        await _storageService.applyUnlockedThemesFromServer(
          serverThemes.map((t) => t.name).toList(),
        );
      }
    }

    // ---- Owned skins ----
    if (data['owned_skins'] is List) {
      final serverSkins =
          _parseLiveries((data['owned_skins'] as List).whereType<String>());
      if (serverSkins != state.ownedSkins) {
        emit(state.copyWith(ownedSkins: serverSkins));
        await _storageService.applyUnlockedSkinsFromServer(
          serverSkins.toList(),
        );
      }
    }

    // ---- Owned trails ----
    if (data['owned_trails'] is List) {
      final serverTrails =
          _parseExhausts((data['owned_trails'] as List).whereType<String>());
      if (serverTrails != state.ownedTrails) {
        emit(state.copyWith(ownedTrails: serverTrails));
        await _storageService.applyUnlockedTrailsFromServer(
          serverTrails.toList(),
        );
      }
    }

    // ---- Owned bundles ----
    if (data['owned_bundles'] is List) {
      final serverBundles =
          _parseBundles((data['owned_bundles'] as List).whereType<String>());
      if (serverBundles != state.ownedBundles) {
        emit(state.copyWith(ownedBundles: serverBundles));
        await _storageService.applyUnlockedBundlesFromServer(
          serverBundles.toList(),
        );
      }
    }

    // ---- Tournament entries (additive — counts can't be "revoked" in
    // the same sense, they're consumed) ----
    if (data['tournament_entries'] is Map) {
      final entries = data['tournament_entries'] as Map<String, dynamic>;
      for (final tier in ['bronze', 'silver', 'gold']) {
        final backendCount = (entries[tier] ?? 0) as int;
        final localCount = state.getTournamentEntryCount(tier);
        if (backendCount > localCount) {
          await addTournamentEntry(tier, count: backendCount - localCount);
        }
      }
    }

    // ---- Strike Command gear perk (per-subscription-period grant) ----
    // The backend delivers the grant with a deterministic id derived from
    // the subscription expiry; PowerUpCubit applies it exactly once per
    // id, so repeated syncs are no-ops and each renewal delivers fresh.
    final grantId = data['power_up_grant_id'] as String?;
    final grantMap = data['power_up_grant'];
    if (grantId != null && grantId.isNotEmpty && grantMap is Map) {
      final grant = <String, int>{
        for (final entry in grantMap.entries)
          if (entry.value is int && (entry.value as int) > 0)
            entry.key as String: entry.value as int,
      };
      final applied =
          await getIt<PowerUpCubit>().applyServerGrant(grantId, grant);
      if (applied) {
        AppLogger.info('Applied Strike Command gear grant $grantId: $grant');
      }
    }

    // ---- Promo state (read first so the tier block can layer on top) ----
    // is_promo true => the user is on a server-granted Pro promo giveaway.
    // The backend already merges promo + paid into a single is_premium /
    // subscription_expiry pair, so the tier-handling below works the same
    // for both — promo just adds the TRIAL badge + revocation timing.
    final isPromo = data['is_promo'] == true;
    final promoExpiresStr = data['promo_expires_at'] as String?;
    final promoExpires =
        promoExpiresStr != null ? DateTime.tryParse(promoExpiresStr) : null;
    final promoSource = data['promo_source'] as String?;
    if (isPromo != state.isOnPromo ||
        promoExpires != state.promoExpiresAt ||
        promoSource != state.promoSource) {
      if (isPromo) {
        emit(state.copyWith(
          isOnPromo: true,
          promoExpiresAt: promoExpires,
          promoSource: promoSource,
        ));
      } else {
        emit(state.copyWith(clearPromo: true));
      }
    }

    // ---- Subscription tier ----
    if (data['is_premium'] == true) {
      final expiryStr = data['subscription_expiry'] as String?;
      final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
      // The server is authoritative for the REAL subscription end date.
      // Adopt whatever it sends — EARLIER or later — rather than the old
      // max-merge that only ever extended the local expiry. The previous
      // behaviour let the optimistic +30d/+365d guess from
      // _handlePremiumPurchased outlive the true subscription: a cancelled
      // or short (test) sub kept Pro alive locally until an explicit
      // is_premium=false arrived, and OFFLINE it never expired at all.
      // Storing the true expiry lets the local self-expiry
      // (StoreDao.isPremiumActive / PremiumState.isSubscriptionExpired)
      // drop the user to free at the correct moment, even with no network.
      if (expiry != null && expiry.isAfter(DateTime.now())) {
        if (state.tier != PremiumTier.pro ||
            state.subscriptionExpiry != expiry) {
          emit(state.copyWith(
            tier: PremiumTier.pro,
            subscriptionExpiry: expiry,
          ));
          // Atomic write: setPremiumExpirationDate derives the active flag
          // from expiry-vs-now and persists BOTH fields in one transaction.
          // A bare setPremiumActive(true) would null the expiry column.
          await _storageService.setPremiumExpirationDate(
            expiry.toIso8601String(),
          );
        }
      }
      // is_premium=true with an absent/already-past expiry is a backend
      // contract violation (GetPremiumContent only reports true when the
      // expiry is in the future). Don't grant Pro off it here — the local
      // self-expiry and the is_premium==false branch settle that case.
    } else if (data['is_premium'] == false && state.tier == PremiumTier.pro) {
      // Subscription was revoked. Downgrade tier locally so paywall gating
      // reactivates immediately, then also revert the per-feature state
      // that depended on Pro. The backend EntitlementRecomputer already
      // pruned OwnedThemes / OwnedCosmetics / PowerUpInventory /
      // TournamentEntries on the server — the sections above have already
      // mirrored those down. What remains here is the client-only
      // bookkeeping that nothing else touches.
      emit(state.copyWith(tier: PremiumTier.free));
      _storageService.setPremiumActive(false);

      // Coin multiplier: drop from 1.5x / 1.75x back to 1.0x. Without this
      // the player keeps earning at Pro rate until the next app start.
      _coinsCubit?.updatePremiumMultiplier(false, state.hasBattlePass);

      // Board size: if a premium board (35/40/50) was selected, fall back
      // to the classic 20x20 free default so the next game doesn't start
      // on a premium-only surface.
      try {
        final settingsCubit = getIt<GameSettingsCubit>();
        if (settingsCubit.state.boardSize.isPremium) {
          unawaited(settingsCubit.setBoardSize(BoardSize.classic));
        }
      } catch (_) {
        // GameSettingsCubit not registered (shouldn't happen at runtime)
        // — silent fallback rather than crashing the sync.
      }

      // Tournament entries: the server-side recomputer cleared them all.
      // Force-set local counts to match (the regular sync block above is
      // additive-only and wouldn't zero them out).
      if (state.bronzeTournamentEntries != 0 ||
          state.silverTournamentEntries != 0 ||
          state.goldTournamentEntries != 0) {
        emit(state.copyWith(
          bronzeTournamentEntries: 0,
          silverTournamentEntries: 0,
          goldTournamentEntries: 0,
        ));
        await _storageService.setTournamentEntries(
          bronze: 0,
          silver: 0,
          gold: 0,
        );
      }

      // Power-up inventory: pull fresh from the server so the wiped Pro
      // power-up charges land locally without waiting for the next
      // PowerUpCubit refresh trigger.
      unawaited(getIt<PowerUpCubit>().loadInventory());
    }

    // ---- Equipped-cosmetic restore (reinstall / device-switch) ----
    // Same rules as before: only adopt backend's selection if the local
    // choice is still at the default.
    final backendLivery =
        LiveryType.tryParse(data['selected_skin_id'] as String?);
    if (backendLivery != null &&
        state.selectedSkinId == LiveryType.standard.id &&
        backendLivery != LiveryType.standard) {
      await selectSkin(backendLivery.id);
    }
    final backendExhaust =
        ExhaustType.tryParse(data['selected_trail_id'] as String?);
    if (backendExhaust != null &&
        state.selectedTrailId == ExhaustType.stock.id &&
        backendExhaust != ExhaustType.stock) {
      await selectTrail(backendExhaust.id);
    }
    final backendThemeId = data['selected_theme_id'] as String?;
    if (backendThemeId != null && backendThemeId.isNotEmpty) {
      try {
        await getIt<ThemeCubit>().applyEquippedThemeFromBackend(backendThemeId);
      } catch (e) {
        AppLogger.warning('Failed to apply backend theme: $e');
      }
    }

    // ---- Revocation fallback ----
    // If the user was equipped on a cosmetic they no longer own (refund,
    // chargeback, etc.), drop back to the default so the game doesn't
    // keep rendering a paid item they shouldn't have. Strike Command
    // implicitly includes every premium cosmetic, so the fallback only
    // applies to free-tier users.
    if (!state.isLiveryUnlocked(LiveryType.fromId(state.selectedSkinId))) {
      AppLogger.info(
          'Equipped livery "${state.selectedSkinId}" no longer owned — falling back to standard');
      await selectSkin(LiveryType.standard.id);
    }
    if (!state.isExhaustUnlocked(ExhaustType.fromId(state.selectedTrailId))) {
      AppLogger.info(
          'Equipped exhaust "${state.selectedTrailId}" no longer owned — falling back to stock');
      await selectTrail(ExhaustType.stock.id);
    }
    try {
      await getIt<ThemeCubit>().applyFallbackIfThemeRevoked(state);
    } catch (e) {
      AppLogger.warning('Failed to evaluate theme revocation fallback: $e');
    }
  }

  /// Clear error
  void clearError() {
    emit(state.copyWith(clearError: true));
  }

  /// Get purchase history
  Future<List<Map<String, dynamic>>> getPurchaseHistory() async {
    // Return purchase history from storage or service
    final purchases = _purchaseService.purchases;
    return purchases
        .map(
          (p) => {
            'productId': p.productId,
            'purchaseId': p.id,
            'transactionDate': p.transactionDate.toInt().toString(),
            'status': p.purchaseState.toString(),
          },
        )
        .toList();
  }

  @override
  Future<void> close() {
    _purchaseStatusSubscription?.cancel();
    _premiumStatusWatch?.cancel();
    return super.close();
  }

  /// Subscribe to the `premium_status` Drift singleton so any later
  /// write (snapshot apply on first sign-in, purchase echo, server
  /// reconcile) reactively re-projects into [state]. Emits immediately
  /// with the current row on subscribe, which is fine — that's the
  /// same data initialize() just loaded synchronously.
  void _wireDriftWatch() {
    _premiumStatusWatch?.cancel();
    _premiumStatusWatch =
        _storageService.storeDao.watchPremiumStatus().listen((_) {
      if (_reloadingFromDrift) return;
      _reloadingFromDrift = true;
      _reloadEntitlementFromDrift()
          .catchError((Object e) {
            AppLogger.error('PremiumStatus Drift-watch reload failed', e);
          })
          .whenComplete(() => _reloadingFromDrift = false);
    });
  }

  /// Re-read the Pro entitlement fields from Drift and emit a new
  /// state. Owned-items lists are intentionally NOT re-read here —
  /// those land in the UnlockedItems table, not PremiumStatus, and
  /// the snapshot apply path already calls [_storageService.setX]
  /// helpers which trigger Drift writes the screens re-read on next
  /// navigation. Keeping this method tight to the fields the watch
  /// is actually firing for.
  Future<void> _reloadEntitlementFromDrift() async {
    final isPremiumActive = await _storageService.isPremiumActive();
    final expiryDateStr = await _storageService.getPremiumExpirationDate();
    final tournamentEntries = await _storageService.getTournamentEntries();

    DateTime? expiryDate;
    if (expiryDateStr != null) {
      expiryDate = DateTime.tryParse(expiryDateStr);
    }

    final newTier = isPremiumActive ? PremiumTier.pro : PremiumTier.free;
    final entitlementChanged =
        state.tier != newTier || state.subscriptionExpiry != expiryDate;

    if (!entitlementChanged &&
        state.bronzeTournamentEntries == (tournamentEntries['bronze'] ?? 0) &&
        state.silverTournamentEntries == (tournamentEntries['silver'] ?? 0) &&
        state.goldTournamentEntries == (tournamentEntries['gold'] ?? 0)) {
      // No-op emit — Drift wrote the same values back to disk (common
      // on echoed pushes / reseed flows).
      return;
    }

    emit(state.copyWith(
      tier: newTier,
      subscriptionExpiry: expiryDate,
      bronzeTournamentEntries: tournamentEntries['bronze'] ?? 0,
      silverTournamentEntries: tournamentEntries['silver'] ?? 0,
      goldTournamentEntries: tournamentEntries['gold'] ?? 0,
    ));
  }
}
