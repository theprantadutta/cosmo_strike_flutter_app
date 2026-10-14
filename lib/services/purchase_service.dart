import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_inapp_purchase/flutter_inapp_purchase.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';
import 'analytics/analytics_facade.dart';
import 'api_service.dart';
import 'data_sync_service.dart';
import 'storage_service.dart';

// Product IDs for different categories
// Store IDs use the com.pranta.cosmostrike. prefix for Google Play / App Store.
// Internal IDs (SharedPreferences, database) stay unprefixed for backward compat.
class ProductIds {
  // Store product ID prefix
  static const String prefix = 'com.pranta.cosmostrike.';

  /// Strip the store prefix to get the internal ID.
  static String stripPrefix(String id) {
    if (id.startsWith(prefix)) return id.substring(prefix.length);
    return id;
  }

  /// Add the store prefix to an internal ID.
  static String withPrefix(String id) {
    if (id.startsWith(prefix)) return id;
    return '$prefix$id';
  }

  /// Convert a bare skin name (e.g. 'golden') to its store product ID.
  static String skinStoreId(String skinId) => '${prefix}skin_$skinId';

  // Premium Themes
  static const String crystalTheme = '${prefix}crystal_theme';
  static const String cyberpunkTheme = '${prefix}cyberpunk_theme';
  static const String spaceTheme = '${prefix}space_theme';
  static const String oceanTheme = '${prefix}ocean_theme';
  static const String desertTheme = '${prefix}desert_theme';
  static const String forestTheme = '${prefix}forest_theme';
  static const String themesBundle = '${prefix}premium_themes_bundle';

  // Ship Coins (Consumable)
  static const String coinPackSmall = '${prefix}coin_pack_small';
  static const String coinPackMedium = '${prefix}coin_pack_medium';
  static const String coinPackLarge = '${prefix}coin_pack_large';
  static const String coinPackMega = '${prefix}coin_pack_mega';

  // Ship Skins (store IDs use skin_ category prefix)
  static const String goldenShip = '${prefix}skin_golden';
  static const String rainbowShip = '${prefix}skin_rainbow';
  static const String galaxyShip = '${prefix}skin_galaxy';
  static const String dragonShip = '${prefix}skin_dragon';
  static const String electricShip = '${prefix}skin_electric';
  static const String fireShip = '${prefix}skin_fire';
  static const String iceShip = '${prefix}skin_ice';
  static const String shadowShip = '${prefix}skin_shadow';
  static const String neonShip = '${prefix}skin_neon';
  static const String crystalShip = '${prefix}skin_crystal';
  static const String cosmicShip = '${prefix}skin_cosmic';

  // Trail Effects
  static const String particleTrail = '${prefix}trail_particle';
  static const String glowTrail = '${prefix}trail_glow';
  static const String rainbowTrail = '${prefix}trail_rainbow';
  static const String fireTrail = '${prefix}trail_fire';
  static const String electricTrail = '${prefix}trail_electric';
  static const String starTrail = '${prefix}trail_star';
  static const String cosmicTrail = '${prefix}trail_cosmic';
  static const String neonTrail = '${prefix}trail_neon';
  static const String shadowTrail = '${prefix}trail_shadow';
  static const String crystalTrail = '${prefix}trail_crystal';
  static const String dragonTrail = '${prefix}trail_dragon';

  // Cosmetic Bundles
  static const String starterCosmetics = '${prefix}starter_pack';
  static const String elementalCosmetics = '${prefix}elemental_pack';
  static const String cosmicCosmetics = '${prefix}cosmic_collection';
  static const String ultimateCosmetics = '${prefix}ultimate_collection';

  // Subscriptions
  static const String proMonthly = '${prefix}pro_monthly';
  static const String proYearly = '${prefix}pro_yearly';

  // Battle Pass — Coming Soon (not registered on stores yet)
  static const String battlePass = '${prefix}battle_pass_season';

  // Tournament Entries (Consumable)
  static const String tournamentBronze = '${prefix}tournament_bronze';
  static const String tournamentSilver = '${prefix}tournament_silver';
  static const String tournamentGold = '${prefix}tournament_gold';
  static const String championshipEntry = '${prefix}championship_entry';
  static const String tournamentVipEntry = '${prefix}tournament_vip_entry';

  /// All active store product IDs (44 products).
  /// Battle Pass and power-up IAPs are excluded.
  static List<String> get allProductIds => [
    // Themes (7)
    crystalTheme, cyberpunkTheme, spaceTheme,
    oceanTheme, desertTheme, forestTheme, themesBundle,
    // Coins (4)
    coinPackSmall, coinPackMedium, coinPackLarge, coinPackMega,
    // Ship skins (11)
    goldenShip, rainbowShip, galaxyShip, dragonShip, electricShip,
    fireShip, iceShip, shadowShip, neonShip, crystalShip, cosmicShip,
    // Trail effects (11)
    particleTrail, glowTrail, rainbowTrail, fireTrail, electricTrail, starTrail,
    cosmicTrail, neonTrail, shadowTrail, crystalTrail, dragonTrail,
    // Bundles (4)
    starterCosmetics, elementalCosmetics, cosmicCosmetics, ultimateCosmetics,
    // Subscriptions (2)
    proMonthly, proYearly,
    // Tournament entries (5)
    tournamentBronze, tournamentSilver, tournamentGold,
    championshipEntry, tournamentVipEntry,
  ];

  static List<String> get consumableIds => [
    // Coins
    coinPackSmall, coinPackMedium, coinPackLarge, coinPackMega,
    // Tournament entries
    tournamentBronze, tournamentSilver, tournamentGold,
    championshipEntry, tournamentVipEntry,
  ];

  static List<String> get subscriptionIds => [proMonthly, proYearly];

  /// Every one-time product (consumable or not) — queried separately from
  /// subscriptions, which the store fetches with a different product type.
  static List<String> get inAppIds => allProductIds
      .where((id) => !subscriptionIds.contains(id))
      .toList();
}

/// In-app purchases over OpenIAP (`flutter_inapp_purchase`).
///
/// Replaces `in_app_purchase` + `in_app_purchase_android`. OpenIAP ships Play
/// Billing 9.1.0 (required by Play from 2026-11-01) and StoreKit 2 on iOS.
/// The client-side delivery model is unchanged — verify with the backend,
/// deliver locally (optimistically on a transient failure, with an offline
/// retry queue), dedupe by store transaction id — but OpenIAP differs from the
/// old plugin in three ways this class has to absorb:
///
/// * **A purchase's result never comes back from the call.** It arrives on
///   [FlutterInappPurchase.purchaseUpdatedListener], or as a failure (including
///   a user cancel) on [FlutterInappPurchase.purchaseErrorListener]. Both are
///   attached *before* `initConnection` so the first event of a session — a
///   purchase completed while the app was dead — is not missed.
/// * **Restore no longer replays onto the stream.** `restorePurchases` syncs and
///   returns nothing; owned items are read back with `getAvailablePurchases`
///   and fed through the same handler (see [restorePurchases]).
/// * **An Android subscription purchase must name an offer token** — sending
///   none is a developer error on the native side. See [_selectOffer].
class PurchaseService {
  static final PurchaseService _instance = PurchaseService._internal();
  factory PurchaseService() => _instance;
  PurchaseService._internal();

  final FlutterInappPurchase _iap = FlutterInappPurchase.instance;
  StreamSubscription<Purchase>? _purchaseSubscription;
  StreamSubscription<PurchaseError>? _errorSubscription;

  bool _isAvailable = false;
  bool _isInitialized = false;
  List<ProductCommon> _products = [];
  final List<Purchase> _purchases = [];
  bool _purchasePending = false;
  String? _queryProductError;

  /// Transactions currently being verified. The store re-delivers a purchase
  /// until it is finished, and finishing waits on a backend round trip, so the
  /// same transaction can arrive twice (stream + restore) while the first is
  /// still in flight. Without this both would verify and deliver.
  final Set<String> _inFlight = {};

  /// SharedPreferences key for persisted pending verifications.
  static const String _pendingVerificationsKey =
      'pending_purchase_verifications';

  /// SharedPreferences key for delivered purchase IDs (deduplication).
  /// Prevents double-delivery if the app crashes between coin delivery
  /// and finishTransaction().
  static const String _deliveredPurchaseIdsKey = 'delivered_purchase_ids';

  /// In-memory set of already-delivered purchase IDs.
  final Set<String> _deliveredPurchaseIds = {};

  // Getters
  bool get isAvailable => _isAvailable;
  List<ProductCommon> get products => _products;
  List<Purchase> get purchases => _purchases;
  bool get purchasePending => _purchasePending;
  String? get queryProductError => _queryProductError;

  /// Whether any store products have been loaded yet. False means the store
  /// query hasn't completed (or returned nothing) — distinct from a specific
  /// product simply not being configured.
  bool get hasLoadedProducts => _products.isNotEmpty;

  /// Re-run the store product query on demand (e.g. a "Retry" button after a
  /// transient load failure). Re-checks billing availability first so a device
  /// that came online / installed Play services since boot can recover.
  /// Clears the previous error so the UI reflects the fresh attempt.
  Future<void> retryLoadProducts() async {
    _queryProductError = null;
    if (!_isAvailable) {
      _isAvailable = await _openConnection();
    }
    if (!_isAvailable) {
      _queryProductError = 'In-app purchases are not available on this device.';
      return;
    }
    await loadProducts();
  }

  // Stream controllers for UI updates
  final StreamController<bool> _purchasePendingController =
      StreamController<bool>.broadcast();
  final StreamController<List<ProductCommon>> _productsController =
      StreamController<List<ProductCommon>>.broadcast();
  final StreamController<String> _purchaseStatusController =
      StreamController<String>.broadcast();

  /// Lazily resolve [AnalyticsFacade] from GetIt — null-safe so the service
  /// stays usable in tests / before DI bootstrap completes.
  AnalyticsFacade? get _analytics {
    if (!GetIt.I.isRegistered<AnalyticsFacade>()) return null;
    return GetIt.I<AnalyticsFacade>();
  }

  /// Categorise a product ID for analytics. Falls back to "other" so we never
  /// drop an event because of a product ID we forgot to map.
  String _productTypeFor(String productId) {
    final id = ProductIds.stripPrefix(productId);
    if (ProductIds.subscriptionIds.any(
      (s) => ProductIds.stripPrefix(s) == id,
    )) {
      return 'subscription';
    }
    if (id.startsWith('coin_pack_')) return 'coins';
    if (id.startsWith('skin_')) return 'skin';
    if (id.startsWith('trail_')) return 'trail';
    if (id.endsWith('_theme') || id == 'premium_themes_bundle') return 'theme';
    if (id.contains('tournament') || id.contains('championship')) {
      return 'tournament_entry';
    }
    if (id.endsWith('_pack') || id.endsWith('_collection')) return 'bundle';
    return 'other';
  }

  Stream<bool> get purchasePendingStream => _purchasePendingController.stream;
  Stream<List<ProductCommon>> get productsStream => _productsController.stream;
  Stream<String> get purchaseStatusStream => _purchaseStatusController.stream;

  /// Set user ID getter. Previously used for BackendService verification.
  /// Now purchase verification uses ApiService which carries the user identity
  /// via JWT token, so this is retained only for backward compatibility.
  void setUserIdGetter(String? Function() getUserId) {
    // No-op: ApiService.verifyPurchase uses JWT for user identification
  }

  /// Open (or re-check) the billing connection. Bounded: a store that never
  /// answers must not hold startup, and the game is fully usable without it.
  Future<bool> _openConnection() async {
    try {
      return await _iap.initConnection().timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLogger.error('Failed to open a billing connection', e);
      return false;
    }
  }

  Future<void> initialize() async {
    // Idempotency guard — prevent double initialization when called from
    // both main.dart and PremiumCubit.initialize().
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      AppLogger.info('Initializing Purchase Service...');

      // Load previously delivered purchase IDs for deduplication
      await _loadDeliveredPurchaseIds();

      // Listeners go on BEFORE initConnection: a purchase completed in a
      // previous session can be delivered as soon as the connection opens.
      _purchaseSubscription = _iap.purchaseUpdatedListener.listen(
        (purchase) => unawaited(_handlePurchase(purchase)),
        onError: (error) => AppLogger.error('Purchase stream error', error),
      );
      _errorSubscription = _iap.purchaseErrorListener.listen(
        _handlePurchaseError,
      );

      _isAvailable = await _openConnection();
      if (!_isAvailable) {
        AppLogger.error('In-app purchases not available on this device');
        return;
      }

      await loadProducts().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AppLogger.warning(
            'loadProducts timed out — continuing without product data',
          );
        },
      );
      // restorePurchases() intentionally NOT called here. Restoring at boot
      // pushes every existing store purchase through _handlePurchase, which
      // then tries to verify each one against OUR backend — and the user
      // isn't authenticated yet, so every verify call 401s and the purchases
      // pile up in the pending-verification queue. Restore + pending-retry
      // are triggered by AuthCubit once it transitions to authenticated
      // (see PurchaseService.runPostAuthRestore below).

      AppLogger.info(
        'Purchase Service initialized successfully (post-auth restore pending)',
      );
    } catch (e) {
      AppLogger.error('Error initializing Purchase Service', e);
    }
  }

  Future<void> loadProducts() async {
    try {
      AppLogger.info('Loading products...');

      // One-time products and subscriptions are separate store queries.
      final inApp = await _iap.fetchProducts<Product>(
        skus: ProductIds.inAppIds,
        type: ProductQueryType.InApp,
      );
      final subs = await _iap.fetchProducts<ProductSubscription>(
        skus: ProductIds.subscriptionIds,
        type: ProductQueryType.Subs,
      );

      _products = [...inApp, ...subs];
      _queryProductError = null;

      final notFound = ProductIds.allProductIds
          .where((id) => !_products.any((p) => p.id == id))
          .toList();
      if (notFound.isNotEmpty) {
        AppLogger.warning('Products not found: $notFound');
      }

      _productsController.add(_products);

      AppLogger.info('Loaded ${_products.length} products successfully');
    } catch (e) {
      AppLogger.error('Error loading products', e);
      _queryProductError = e is PurchaseError ? e.message : e.toString();
    }
  }

  /// Ask the store to open its purchase sheet. A `true` return means the sheet
  /// was requested, nothing more — the outcome arrives on the listeners.
  Future<bool> buyProduct(ProductCommon product) async {
    if (!_isAvailable) {
      _purchaseStatusController.add('In-app purchases not available');
      return false;
    }

    try {
      AppLogger.info('Initiating purchase for: ${product.id}');
      _purchasePending = true;
      _purchasePendingController.add(true);

      // Funnel event — fired BEFORE the IAP sheet opens. Combined with
      // item_purchased / purchase_cancelled / purchase_failed, this gives
      // us the IAP-sheet abandonment rate.
      _analytics?.trackPurchaseInitiated(
        productId: product.id,
        productType: _productTypeFor(product.id),
      );

      final request = product is ProductSubscription
          ? _buildSubscriptionRequest(product)
          : RequestPurchaseProps.inApp((
              apple: Platform.isIOS
                  ? RequestPurchaseIosProps(sku: product.id)
                  : null,
              google: Platform.isAndroid
                  ? RequestPurchaseAndroidProps(skus: [product.id])
                  : null,
            ));

      if (request == null) {
        _failInitiation(product.id, 'no_offer');
        return false;
      }

      await _iap.requestPurchase(request);
      return true;
    } catch (e) {
      AppLogger.error('Error buying product', e);
      _purchasePending = false;
      _purchasePendingController.add(false);
      _purchaseStatusController.add('Purchase failed: ${e.toString()}');
      _analytics?.trackPurchaseFailed(
        productId: product.id,
        errorCode: 'exception',
      );
      return false;
    }
  }

  void _failInitiation(String productId, String errorCode) {
    _purchasePending = false;
    _purchasePendingController.add(false);
    _purchaseStatusController.add('Failed to initiate purchase');
    _analytics?.trackPurchaseFailed(productId: productId, errorCode: errorCode);
  }

  /// Build the subscription request. On Android this checks whether the user
  /// already holds the OTHER Pro SKU (from this session's purchase/restore
  /// results) and, if so, buys via Google's subscription-replacement flow with
  /// time proration — the old sub is upgraded/downgraded instead of a SECOND
  /// concurrent subscription being created (Google only blocks re-buying the
  /// SAME product, so a plain request here double-bills). Plan cards are
  /// hidden for subscribers, but stale local state (fresh reinstall pre-sync)
  /// can expose them.
  ///
  /// Returns null when an Android product has no purchasable offer.
  RequestPurchaseProps? _buildSubscriptionRequest(ProductSubscription product) {
    if (!Platform.isAndroid) {
      return RequestPurchaseProps.subs((
        apple: RequestSubscriptionIosProps(sku: product.id),
        google: null,
      ));
    }

    final offerToken = _selectOffer(
      _subscriptionOffersOf(product),
    )?.offerTokenAndroid;
    if (offerToken == null) {
      AppLogger.error('No purchasable offer for ${product.id}');
      return null;
    }

    final otherProId = product.id == ProductIds.proMonthly
        ? ProductIds.proYearly
        : ProductIds.proMonthly;
    PurchaseAndroid? oldSub;
    for (final p in _purchases) {
      if (p is PurchaseAndroid &&
          p.productId == otherProId &&
          p.purchaseToken != null) {
        oldSub = p;
      }
    }
    if (oldSub != null) {
      AppLogger.info(
        'Buying ${product.id} as a REPLACEMENT of $otherProId '
        '(time-prorated) instead of a second concurrent subscription',
      );
    }

    return RequestPurchaseProps.subs((
      apple: null,
      google: RequestSubscriptionAndroidProps(
        skus: [product.id],
        subscriptionOffers: [
          AndroidSubscriptionOfferInput(sku: product.id, offerToken: offerToken),
        ],
        // A replacement needs both: the token names the purchase being
        // replaced, the params name its product and the proration mode.
        purchaseToken: oldSub?.purchaseToken,
        subscriptionProductReplacementParams: oldSub == null
            ? null
            : SubscriptionProductReplacementParamsAndroid(
                oldProductId: oldSub.productId,
                replacementMode:
                    SubscriptionReplacementModeAndroid.WithTimeProration,
              ),
      ),
    ));
  }

  /// A store failure — a cancel, a network problem, an ineligible product.
  /// Never a backend verdict.
  void _handlePurchaseError(PurchaseError error) {
    final productId = error.productId ?? 'unknown';
    if (error.code == ErrorCode.UserCancelled) {
      AppLogger.info('Purchase canceled by user: $productId');
      _analytics?.trackPurchaseCancelled(productId: productId);
    } else {
      AppLogger.error('Purchase error: ${error.code}: ${error.message}');
      _purchaseStatusController.add('Purchase failed');
      _analytics?.trackPurchaseFailed(
        productId: productId,
        errorCode: error.code?.name ?? 'unknown',
      );
    }
    _purchasePending = false;
    _purchasePendingController.add(false);
  }

  /// A purchase arrived — from the stream, or from a restore.
  Future<void> _handlePurchase(Purchase purchase) async {
    switch (purchase.purchaseState) {
      case PurchaseState.Pending:
        // Deferred payment: nothing is delivered or finished until it clears.
        _purchaseStatusController.add('Purchase pending...');
        return;

      case PurchaseState.Unknown:
        AppLogger.error('Purchase in an unknown state: ${purchase.productId}');
        _purchaseStatusController.add('Purchase failed');
        _analytics?.trackPurchaseFailed(
          productId: purchase.productId,
          errorCode: 'unknown_state',
        );
        _purchasePending = false;
        _purchasePendingController.add(false);
        return;

      case PurchaseState.Purchased:
        break;
    }

    final purchaseId = _purchaseIdOf(purchase);
    if (!_inFlight.add(purchaseId)) {
      AppLogger.info('Ignoring duplicate purchase update for $purchaseId');
      return;
    }

    try {
      // Deduplication: skip delivery if this purchase was already delivered
      // (protects against double-credit if the app crashes between delivery
      // and finishTransaction)
      if (_deliveredPurchaseIds.contains(purchaseId)) {
        AppLogger.info(
          'Skipping already-delivered purchase: $purchaseId '
          '(${purchase.productId})',
        );
        _rememberOwned(purchase);
      } else {
        // Verify purchase with backend (via ApiService with JWT auth).
        // Three outcomes — "couldn't reach the server" and "the server
        // definitively said NO" must not be conflated:
        //  * valid      → deliver.
        //  * transient  → deliver optimistically + queue an offline
        //                 retry (the purchase is real per the store's own
        //                 client-side flow; only our backend is unsure).
        //  * rejected   → do NOT deliver and do NOT queue. The store's
        //                 server API says this purchase isn't valid.
        //                 Not marked delivered either, so a later
        //                 restore re-verifies in case the state heals.
        final outcome = await _verifyWithBackend(purchase);
        if (outcome == _VerifyOutcome.rejected) {
          AppLogger.warning(
            'Purchase definitively rejected by backend: '
            '${purchase.productId} — not delivering',
          );
          _purchaseStatusController.add(
            'Purchase could not be verified — contact support if you were charged',
          );
        } else {
          if (outcome == _VerifyOutcome.valid) {
            _rememberOwned(purchase);
            // Broadcast for PremiumCubit to handle content delivery
            _purchaseStatusController.add(
              'purchase_completed:${purchase.productId}',
            );
            _purchaseStatusController.add('Purchase successful!');
          } else {
            // Transient — queue for offline retry
            await _queuePendingVerification(purchase);
            // Still deliver locally so the user isn't stuck
            _rememberOwned(purchase);
            _purchaseStatusController.add(
              'purchase_completed:${purchase.productId}',
            );
            _purchaseStatusController.add(
              'Purchase delivered (backend sync pending)',
            );
          }

          // Mark as delivered AFTER broadcasting so PremiumCubit
          // processes it
          await _markAsDelivered(purchaseId);

          // Funnel terminal event — fires once per fulfilled purchase
          // (already-delivered re-emissions are skipped above).
          final product = getProduct(purchase.productId);
          _analytics?.trackItemPurchased(
            itemId: purchase.productId,
            itemType: _productTypeFor(purchase.productId),
            price: product?.displayPrice ?? 'unknown',
          );
        }
      }

      await _finishPurchase(purchase);
    } finally {
      _inFlight.remove(purchaseId);
    }

    _purchasePending = false;
    _purchasePendingController.add(false);
  }

  /// Track an owned purchase, replacing any earlier record of the same
  /// product so a re-delivery does not duplicate it.
  void _rememberOwned(Purchase purchase) {
    _purchases.removeWhere((p) => _purchaseIdOf(p) == _purchaseIdOf(purchase));
    _purchases.add(purchase);
  }

  /// Finish the transaction so the store stops re-delivering it: consumes
  /// coin packs / tournament entries (making them re-buyable), acknowledges
  /// everything else.
  Future<void> _finishPurchase(Purchase purchase) async {
    final consumable = ProductIds.consumableIds.contains(purchase.productId);
    if (!consumable &&
        purchase is PurchaseAndroid &&
        purchase.isAcknowledgedAndroid == true) {
      return;
    }
    try {
      await _iap.finishTransaction(
        purchase: purchase,
        isConsumable: consumable,
      );
    } catch (e) {
      // Unfinished purchases are re-delivered, and the delivered-set keeps a
      // re-delivery from crediting twice, so this is safe to just log.
      AppLogger.error('Failed to finish transaction', e);
    }
  }

  // ==================== Backend Verification (via ApiService) ====================

  Future<_VerifyOutcome> _verifyWithBackend(Purchase purchase) async {
    try {
      final apiService = ApiService();
      final payload = _verificationPayloadOf(purchase);

      // Use ApiService (authenticated with JWT) instead of BackendService
      final result = await apiService.verifyPurchase(
        platform: payload.platform,
        receiptData: payload.receiptData,
        productId: purchase.productId,
        transactionId: payload.transactionId,
        purchaseToken: payload.purchaseToken,
      );

      if (result != null && result['is_valid'] == true) {
        AppLogger.info('Purchase verified via ApiService (JWT-authenticated)');
        return _VerifyOutcome.valid;
      }

      if (result != null) {
        // HTTP 200 with is_valid=false — the server reached the store and
        // the store says this purchase is not valid. Definitive.
        AppLogger.error(
          'Backend definitively rejected purchase: ${result['message']}',
        );
        return _VerifyOutcome.rejected;
      }

      // null = non-2xx or empty: network failure, 401 (pre-auth), 5xx, or
      // the server's retryable PURCHASE_VERIFICATION_UNAVAILABLE 400.
      AppLogger.error('Backend verification unavailable (null response)');
      return _VerifyOutcome.transient;
    } catch (e) {
      AppLogger.error('Error verifying purchase with backend', e);
      return _VerifyOutcome.transient;
    }
  }

  // ==================== Offline Retry Queue ====================

  /// Persist a failed verification so it can be retried later.
  Future<void> _queuePendingVerification(Purchase purchase) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_pendingVerificationsKey) ?? [];
      final payload = _verificationPayloadOf(purchase);

      final entry = jsonEncode({
        'product_id': purchase.productId,
        'transaction_id': payload.transactionId,
        'platform': payload.platform,
        'receipt_data': payload.receiptData,
        'purchase_token': payload.purchaseToken,
        'queued_at': DateTime.now().toIso8601String(),
      });

      existing.add(entry);
      await prefs.setStringList(_pendingVerificationsKey, existing);
      AppLogger.info('Queued pending verification for ${purchase.productId}');
    } catch (e) {
      AppLogger.error('Error queuing pending verification', e);
    }
  }

  /// Retry all pending verifications. Called on app resume and connectivity restore.
  /// Uses batch endpoint when multiple verifications are pending.
  /// True while the offline verification queue is non-empty. CoinsCubit
  /// uses this to HOLD adopting a server-ahead coin balance — a queued
  /// coin-pack verify can transiently double-count server-side (the
  /// absolute balance push already included the pack, then the first
  /// verify adds it again).
  Future<bool> get hasPendingVerifications async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_pendingVerificationsKey) ?? []).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// After queued COIN-PACK verifications finally land server-side, the
  /// server's users.Coins is double-counted (resume order: absolute
  /// balance push B+N first, then the verify adds +N → B+2N). Re-assert
  /// the client truth with a fresh absolute push so the server settles
  /// back to the real balance.
  Future<void> _reassertCoinBalanceAfterVerify() async {
    try {
      await StorageService().storeDao.enqueueCoinBalanceSync();
      unawaited(DataSyncService().forceSyncNow());
      AppLogger.info(
        'Re-asserted client coin balance after queued coin-pack verify',
      );
    } catch (e) {
      AppLogger.error('Failed to re-assert coin balance after verify', e);
    }
  }

  static bool _isCoinPack(Object? productId) =>
      productId is String && productId.contains('coin_pack');

  /// Batch-verify items surface transient server states as `is_valid=false`
  /// with a recognizable message prefix (the single-verify endpoint returns
  /// non-2xx for the same states). These must stay in the retry queue;
  /// anything else with `is_valid=false` is a definitive store rejection.
  /// The anonymous block is retryable too — it heals once the user signs in.
  static bool _isTransientVerifyMessage(Object? message) =>
      message is String &&
      (message.startsWith('PURCHASE_VERIFICATION_UNAVAILABLE') ||
          message.startsWith('ANONYMOUS_ACCOUNT_PURCHASE_BLOCKED'));

  /// Entries older than this are dropped from the retry queue — by then the
  /// user has either re-triggered the purchase via restore (fresh verify) or
  /// the purchase was refunded by Google's 3-day unacknowledged window. The
  /// cap guarantees a poisoned entry can never block coin-balance adoption
  /// (see [hasPendingVerifications]) forever.
  static const Duration _pendingVerificationMaxAge = Duration(days: 14);

  Future<void> retryPendingVerifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var pending = prefs.getStringList(_pendingVerificationsKey) ?? [];
      if (pending.isEmpty) return;

      // Age cap: silently drop expired entries before retrying.
      final fresh = <String>[];
      for (final entryJson in pending) {
        try {
          final entry = jsonDecode(entryJson) as Map<String, dynamic>;
          final queuedAt = DateTime.tryParse(
            entry['queued_at'] as String? ?? '',
          );
          if (queuedAt != null &&
              DateTime.now().difference(queuedAt) >
                  _pendingVerificationMaxAge) {
            AppLogger.warning(
              'Dropping expired pending verification: ${entry['product_id']} '
              '(queued ${queuedAt.toIso8601String()})',
            );
            continue;
          }
          fresh.add(entryJson);
        } catch (_) {
          // Unparseable entry — drop it rather than retry forever.
        }
      }
      if (fresh.length != pending.length) {
        await prefs.setStringList(_pendingVerificationsKey, fresh);
        pending = fresh;
      }
      if (pending.isEmpty) return;

      AppLogger.info(
        'Retrying ${pending.length} pending purchase verifications',
      );
      final apiService = ApiService();
      if (!apiService.isAuthenticated) return;

      // Parse all pending entries
      final entries = <Map<String, dynamic>>[];
      for (final entryJson in pending) {
        try {
          entries.add(jsonDecode(entryJson) as Map<String, dynamic>);
        } catch (_) {}
      }

      if (entries.isEmpty) return;

      // Use batch endpoint if multiple pending, individual for single
      if (entries.length >= 2) {
        final batchPayload = entries
            .map(
              (entry) => <String, dynamic>{
                'purchase_data': {
                  'product_id': entry['product_id'],
                  'transaction_id': entry['transaction_id'],
                  'receipt_data': entry['receipt_data'],
                  'purchase_token': entry['purchase_token'],
                },
                'platform': entry['platform'],
              },
            )
            .toList();

        final result = await apiService.batchVerifyPurchases(batchPayload);

        if (result != null && result['results'] != null) {
          final results = result['results'] as List;
          final remaining = <String>[];

          var coinPackVerified = false;
          for (int i = 0; i < entries.length; i++) {
            if (i < results.length) {
              final r = results[i] as Map<String, dynamic>;
              if (r['is_valid'] == true) {
                AppLogger.info(
                  'Pending verification succeeded: ${entries[i]['product_id']}',
                );
                if (_isCoinPack(entries[i]['product_id'])) {
                  coinPackVerified = true;
                }
              } else if (_isTransientVerifyMessage(r['message'])) {
                // Server couldn't reach the store / payment pending — keep
                // retrying.
                remaining.add(pending[i]);
              } else {
                // Definitive rejection — drop the poisoned entry so it can't
                // block coin-balance adoption forever.
                AppLogger.warning(
                  'Pending verification definitively rejected, dropping: '
                  '${entries[i]['product_id']} (${r['message']})',
                );
              }
            } else {
              remaining.add(pending[i]);
            }
          }

          await prefs.setStringList(_pendingVerificationsKey, remaining);
          if (coinPackVerified) await _reassertCoinBalanceAfterVerify();
          if (remaining.isEmpty) {
            AppLogger.info('All pending verifications completed (batch)');
          } else {
            AppLogger.warning(
              '${remaining.length} verifications still pending',
            );
          }
          return;
        }
      }

      // Fallback: individual verification (single pending or batch failed)
      final remaining = <String>[];
      var coinPackVerified = false;
      for (int i = 0; i < entries.length; i++) {
        try {
          final entry = entries[i];
          final result = await apiService.verifyPurchase(
            platform: entry['platform'] as String,
            receiptData: entry['receipt_data'] as String,
            productId: entry['product_id'] as String,
            transactionId: entry['transaction_id'] as String,
            purchaseToken: entry['purchase_token'] as String?,
          );

          if (result != null && result['is_valid'] == true) {
            AppLogger.info(
              'Pending verification succeeded: ${entry['product_id']}',
            );
            if (_isCoinPack(entry['product_id'])) coinPackVerified = true;
          } else if (result != null) {
            // HTTP 200 with is_valid=false — the store definitively rejected
            // this purchase. Drop it instead of retrying forever. (Transient
            // server states come back as non-2xx → null → kept below.)
            AppLogger.warning(
              'Pending verification definitively rejected, dropping: '
              '${entry['product_id']} (${result['message']})',
            );
          } else {
            remaining.add(pending[i]);
          }
        } catch (e) {
          remaining.add(pending[i]);
        }
      }

      await prefs.setStringList(_pendingVerificationsKey, remaining);
      if (coinPackVerified) await _reassertCoinBalanceAfterVerify();
      if (remaining.isEmpty) {
        AppLogger.info('All pending verifications completed');
      } else {
        AppLogger.warning('${remaining.length} verifications still pending');
      }
    } catch (e) {
      AppLogger.error('Error retrying pending verifications', e);
    }
  }

  // ==================== Deduplication ====================

  /// Load previously delivered purchase IDs from SharedPreferences.
  Future<void> _loadDeliveredPurchaseIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_deliveredPurchaseIdsKey) ?? [];
      _deliveredPurchaseIds.addAll(ids);
      if (ids.isNotEmpty) {
        AppLogger.info('Loaded ${ids.length} delivered purchase IDs for dedup');
      }
    } catch (e) {
      AppLogger.error('Error loading delivered purchase IDs', e);
    }
  }

  /// Record a purchase ID as delivered so it won't be double-credited
  /// if the store re-delivers it (e.g. after a crash).
  Future<void> _markAsDelivered(String purchaseId) async {
    _deliveredPurchaseIds.add(purchaseId);
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep only the last 500 IDs to avoid unbounded growth
      final ids = _deliveredPurchaseIds.toList();
      if (ids.length > 500) {
        final trimmed = ids.sublist(ids.length - 500);
        _deliveredPurchaseIds
          ..clear()
          ..addAll(trimmed);
      }
      await prefs.setStringList(
        _deliveredPurchaseIdsKey,
        _deliveredPurchaseIds.toList(),
      );
    } catch (e) {
      AppLogger.error('Error persisting delivered purchase ID', e);
    }
  }

  // ==================== Restore & Product Queries ====================

  /// Sync with the store and run everything the user owns back through
  /// [_handlePurchase]. Under the old plugin a restore re-emitted onto the
  /// purchase stream; OpenIAP's restore returns nothing, so owned items are
  /// read back explicitly. The delivered-set makes re-handling them a no-op
  /// for anything already credited.
  Future<void> restorePurchases() async {
    try {
      AppLogger.info('Restoring purchases...');
      if (!_isAvailable) {
        _isAvailable = await _openConnection();
        if (!_isAvailable) {
          _purchaseStatusController.add('Failed to restore purchases');
          return;
        }
      }
      await _iap.restorePurchases();
      final owned = await _iap.getAvailablePurchases();
      for (final purchase in owned) {
        await _handlePurchase(purchase);
      }
      AppLogger.info('Purchases restored successfully (${owned.length} owned)');
    } catch (e) {
      AppLogger.error('Error restoring purchases', e);
      _purchaseStatusController.add('Failed to restore purchases');
    }
  }

  /// One-shot post-authentication setup. Triggered from AuthCubit when it
  /// transitions to authenticated. Re-runs the user's store purchases through
  /// the handler (which now has a valid JWT for backend verify) AND drains any
  /// purchases that 401'd in a previous unauth session.
  /// Idempotent and safe to call multiple times.
  bool _postAuthRestoreDone = false;
  Future<void> runPostAuthRestore() async {
    if (_postAuthRestoreDone) {
      // Subsequent re-auths just drain the pending queue; no need to
      // re-process the whole store inventory.
      await retryPendingVerifications();
      return;
    }
    _postAuthRestoreDone = true;
    try {
      AppLogger.info('Running post-auth purchase restore + verification drain');
      await restorePurchases().timeout(
        const Duration(seconds: 15),
        onTimeout: () =>
            AppLogger.warning('Post-auth restorePurchases timed out'),
      );
      await retryPendingVerifications();
    } catch (e) {
      AppLogger.error('Error during post-auth purchase restore', e);
    }
  }

  ProductCommon? getProduct(String productId) {
    for (final product in _products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  /// Display price for a product, handling the Google Play **subscription**
  /// quirk: a subscription's `displayPrice` comes from its first pricing
  /// phase, which reads as "Free" / $0 whenever a base plan or free-trial
  /// phase is zero-priced — even though the real recurring price exists in a
  /// later pricing phase. For Android subs we dig out the recurring (non-zero)
  /// phase's formatted price; otherwise we use `displayPrice` (correct for
  /// one-time products and iOS subs).
  String? _displayPrice(ProductCommon? product) {
    if (product == null) return null;
    if (product is ProductSubscriptionAndroid) {
      final recurring = _androidSubscriptionRecurringPrice(product);
      if (recurring != null && recurring.isNotEmpty) return recurring;
    }
    final price = product.displayPrice;
    if (price.isEmpty) return null;
    return price;
  }

  /// The formatted price of the recurring (non-zero) pricing phase of an
  /// Android subscription, or null if not found.
  String? _androidSubscriptionRecurringPrice(
    ProductSubscriptionAndroid product,
  ) {
    // Skip free-trial / intro phases (priceAmountMicros == 0); the perpetual
    // recurring price is the last non-zero phase. Take it from the first offer
    // that has one (typically the base plan).
    for (final offer in product.subscriptionOffers) {
      final phases = offer.pricingPhasesAndroid?.pricingPhaseList;
      if (phases == null) continue;
      String? recurring;
      for (final phase in phases) {
        if ((int.tryParse(phase.priceAmountMicros) ?? 0) > 0) {
          recurring = phase.formattedPrice;
        }
      }
      if (recurring != null) return recurring;
    }
    return null;
  }

  /// Get the store-formatted price for a product (e.g. "$1.99").
  /// Returns null if the product hasn't been loaded from the store.
  String? getStorePrice(String productId) =>
      _displayPrice(getProduct(productId));

  /// Numeric store price (in the store's currency) for a product, or null
  /// if it hasn't loaded. Android subscriptions use the recurring (non-zero)
  /// pricing phase, matching [getStorePrice].
  double? getStorePriceValue(String productId) {
    final product = getProduct(productId);
    if (product == null) return null;
    if (product is ProductSubscriptionAndroid) {
      for (final offer in product.subscriptionOffers) {
        final phases = offer.pricingPhasesAndroid?.pricingPhaseList;
        if (phases == null) continue;
        int? micros;
        for (final phase in phases) {
          final m = int.tryParse(phase.priceAmountMicros) ?? 0;
          if (m > 0) micros = m;
        }
        if (micros != null) return micros / 1e6;
      }
    }
    final price = product.price;
    return (price != null && price > 0) ? price : null;
  }

  /// Store currency code for a loaded product (e.g. "BDT"), or null.
  String? getStoreCurrency(String productId) => getProduct(productId)?.currency;

  /// Whole-percent saving of paying [actual] instead of [full], or null when
  /// either is unknown or there's no real saving. Rounded down so a badge
  /// never overstates the discount.
  static int? savingsPercent({required double? full, required double? actual}) {
    if (full == null || actual == null || full <= 0 || actual <= 0) return null;
    final pct = ((1 - actual / full) * 100).floor();
    return pct >= 1 ? pct : null;
  }

  /// Yearly-vs-12×monthly saving from live store prices, or null if either
  /// plan hasn't loaded or the currencies differ.
  int? yearlySavingsPercent(String monthlyId, String yearlyId) {
    final monthly = getStorePriceValue(monthlyId);
    final yearly = getStorePriceValue(yearlyId);
    if (getStoreCurrency(monthlyId) != getStoreCurrency(yearlyId)) return null;
    return savingsPercent(full: monthly == null ? null : monthly * 12, actual: yearly);
  }

  /// Get the store price, falling back to a formatted default.
  String getStorePriceOrDefault(String productId, double fallbackPrice) {
    return _displayPrice(getProduct(productId)) ??
        '\$${fallbackPrice.toStringAsFixed(2)}';
  }

  Future<bool> purchaseProduct(String productId) async {
    final product = getProduct(productId);
    if (product == null) {
      throw Exception('Product $productId not found');
    }
    return await buyProduct(product);
  }

  bool isPurchased(String productId) {
    return _purchases.any(
      (purchase) =>
          purchase.productId == productId &&
          purchase.purchaseState == PurchaseState.Purchased,
    );
  }

  bool hasActiveSubscription(String subscriptionId) {
    final purchase = _purchases
        .where((p) => p.productId == subscriptionId)
        .firstOrNull;
    if (purchase == null) return false;

    return purchase.purchaseState == PurchaseState.Purchased;
  }

  void dispose() {
    _purchaseSubscription?.cancel();
    _errorSubscription?.cancel();
    _purchasePendingController.close();
    _productsController.close();
    _purchaseStatusController.close();
    unawaited(_iap.endConnection().catchError((_) => false));
  }
}

/// The store transaction id used for delivery dedup and as the backend's
/// `transaction_id`. Matches what the old plugin's `purchaseID` held — the
/// Play order id / StoreKit transaction id — so delivered-ids persisted by
/// earlier app versions still dedupe after the migration. Falls back to the
/// purchase token, because a Play order id can be null (pending purchases).
String _purchaseIdOf(Purchase purchase) {
  final transactionId = switch (purchase) {
    PurchaseAndroid(:final transactionId) => transactionId,
    PurchaseIOS(:final transactionId) => transactionId,
  };
  if (transactionId != null && transactionId.isNotEmpty) return transactionId;
  final token = purchase.purchaseToken;
  if (token != null && token.isNotEmpty) return token;
  return purchase.id;
}

/// The wire fields `/purchases/verify` has always taken. `purchaseToken` is
/// the Play purchase token on Android and the StoreKit 2 signed transaction
/// (JWS) on iOS — the same values the old plugin put in
/// `serverVerificationData`, so the backend contract is unchanged.
({
  String platform,
  String receiptData,
  String? purchaseToken,
  String transactionId,
})
_verificationPayloadOf(Purchase purchase) {
  final token = purchase.purchaseToken ?? '';
  final transactionId = switch (purchase) {
    PurchaseAndroid(:final transactionId) => transactionId,
    PurchaseIOS(:final transactionId) => transactionId,
  };
  return switch (purchase) {
    PurchaseAndroid() => (
      platform: 'android',
      receiptData: token,
      purchaseToken: token.isEmpty ? null : token,
      transactionId: transactionId ?? '',
    ),
    PurchaseIOS() => (
      platform: 'ios',
      receiptData: token,
      purchaseToken: null,
      transactionId: transactionId ?? '',
    ),
  };
}

/// The offers on a subscription product, whichever platform it came from.
List<SubscriptionOffer> _subscriptionOffersOf(ProductSubscription product) =>
    switch (product) {
      ProductSubscriptionAndroid(:final subscriptionOffers) =>
        subscriptionOffers,
      ProductSubscriptionIOS(:final subscriptionOffers) =>
        subscriptionOffers ?? const [],
    };

/// Picks the Play offer to buy: an introductory (free/discounted-trial) offer
/// if the user is eligible — Play only returns offers they are eligible for —
/// otherwise the base plan, otherwise whatever is first.
SubscriptionOffer? _selectOffer(List<SubscriptionOffer> offers) {
  if (offers.isEmpty) return null;

  for (final offer in offers) {
    final phases = offer.pricingPhasesAndroid?.pricingPhaseList ?? const [];
    // recurrenceMode 1 = infinite recurring, i.e. a base plan, not an intro.
    if (phases.any(
      (p) => (int.tryParse(p.priceAmountMicros) ?? -1) == 0 &&
          p.recurrenceMode != 1,
    )) {
      return offer;
    }
  }

  for (final offer in offers) {
    final basePlanId = offer.basePlanIdAndroid;
    if (basePlanId != null && basePlanId == offer.id) return offer;
  }

  return offers.first;
}

/// Outcome of a backend purchase verification. [transient] means the answer
/// is unknown (network / server unreachable / payment pending / not signed
/// in) — deliver optimistically and retry. [rejected] means the server
/// reached the store and the store says the purchase is invalid — never
/// deliver.
enum _VerifyOutcome { valid, rejected, transient }
