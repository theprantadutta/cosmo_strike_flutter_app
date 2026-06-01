import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:get_it/get_it.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';
import 'analytics/analytics_facade.dart';
import 'api_service.dart';

// Product IDs for different categories
// Store IDs use the com.pranta.snakeclassic. prefix for Google Play / App Store.
// Internal IDs (SharedPreferences, database) stay unprefixed for backward compat.
class ProductIds {
  // Store product ID prefix
  static const String prefix = 'com.pranta.snakeclassic.';

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

  // Snake Coins (Consumable)
  static const String coinPackSmall = '${prefix}coin_pack_small';
  static const String coinPackMedium = '${prefix}coin_pack_medium';
  static const String coinPackLarge = '${prefix}coin_pack_large';
  static const String coinPackMega = '${prefix}coin_pack_mega';

  // Snake Skins (store IDs use skin_ category prefix)
  static const String goldenSnake = '${prefix}skin_golden';
  static const String rainbowSnake = '${prefix}skin_rainbow';
  static const String galaxySnake = '${prefix}skin_galaxy';
  static const String dragonSnake = '${prefix}skin_dragon';
  static const String electricSnake = '${prefix}skin_electric';
  static const String fireSnake = '${prefix}skin_fire';
  static const String iceSnake = '${prefix}skin_ice';
  static const String shadowSnake = '${prefix}skin_shadow';
  static const String neonSnake = '${prefix}skin_neon';
  static const String crystalSnake = '${prefix}skin_crystal';
  static const String cosmicSnake = '${prefix}skin_cosmic';

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
  static const String snakeClassicProMonthly = '${prefix}pro_monthly';
  static const String snakeClassicProYearly = '${prefix}pro_yearly';

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
    // Snake skins (11)
    goldenSnake, rainbowSnake, galaxySnake, dragonSnake, electricSnake,
    fireSnake, iceSnake, shadowSnake, neonSnake, crystalSnake, cosmicSnake,
    // Trail effects (11)
    particleTrail, glowTrail, rainbowTrail, fireTrail, electricTrail, starTrail,
    cosmicTrail, neonTrail, shadowTrail, crystalTrail, dragonTrail,
    // Bundles (4)
    starterCosmetics, elementalCosmetics, cosmicCosmetics, ultimateCosmetics,
    // Subscriptions (2)
    snakeClassicProMonthly, snakeClassicProYearly,
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

  static List<String> get subscriptionIds => [
    snakeClassicProMonthly,
    snakeClassicProYearly,
  ];
}

class PurchaseService {
  static final PurchaseService _instance = PurchaseService._internal();
  factory PurchaseService() => _instance;
  PurchaseService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _isAvailable = false;
  bool _isInitialized = false;
  List<ProductDetails> _products = [];
  final List<PurchaseDetails> _purchases = [];
  bool _purchasePending = false;
  String? _queryProductError;

  /// SharedPreferences key for persisted pending verifications.
  static const String _pendingVerificationsKey = 'pending_purchase_verifications';

  /// SharedPreferences key for delivered purchase IDs (deduplication).
  /// Prevents double-delivery if the app crashes between coin delivery
  /// and completePurchase().
  static const String _deliveredPurchaseIdsKey = 'delivered_purchase_ids';

  /// In-memory set of already-delivered purchase IDs.
  final Set<String> _deliveredPurchaseIds = {};

  // Getters
  bool get isAvailable => _isAvailable;
  List<ProductDetails> get products => _products;
  List<PurchaseDetails> get purchases => _purchases;
  bool get purchasePending => _purchasePending;
  String? get queryProductError => _queryProductError;

  // Stream controllers for UI updates
  final StreamController<bool> _purchasePendingController =
      StreamController<bool>.broadcast();
  final StreamController<List<ProductDetails>> _productsController =
      StreamController<List<ProductDetails>>.broadcast();
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
  Stream<List<ProductDetails>> get productsStream => _productsController.stream;
  Stream<String> get purchaseStatusStream => _purchaseStatusController.stream;

  /// Set user ID getter. Previously used for BackendService verification.
  /// Now purchase verification uses ApiService which carries the user identity
  /// via JWT token, so this is retained only for backward compatibility.
  void setUserIdGetter(String? Function() getUserId) {
    // No-op: ApiService.verifyPurchase uses JWT for user identification
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

      _isAvailable = await _inAppPurchase.isAvailable();
      if (!_isAvailable) {
        AppLogger.error('In-app purchases not available on this device');
        return;
      }

      // Listen to purchase updates
      _subscription = _inAppPurchase.purchaseStream.listen(
        _listenToPurchaseUpdated,
        onDone: () => _subscription?.cancel(),
        onError: (error) => AppLogger.error('Purchase stream error', error),
      );

      await loadProducts().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AppLogger.warning('loadProducts timed out — continuing without product data');
        },
      );
      // restorePurchases() intentionally NOT called here. Calling it at
      // boot re-emits every existing Play Store purchase through the
      // _listenToPurchaseUpdated listener, which then tries to verify
      // each one against OUR backend — and the user isn't authenticated
      // yet, so every verify call 401s and the purchases pile up in the
      // pending-verification queue. Restore + pending-retry are now
      // triggered by AuthCubit once it transitions to authenticated
      // (see PurchaseService.runPostAuthRestore below).

      AppLogger.info('Purchase Service initialized successfully (post-auth restore pending)');
    } catch (e) {
      AppLogger.error('Error initializing Purchase Service', e);
    }
  }

  Future<void> loadProducts() async {
    try {
      AppLogger.info('Loading products...');

      final ProductDetailsResponse response = await _inAppPurchase
          .queryProductDetails(ProductIds.allProductIds.toSet());

      if (response.notFoundIDs.isNotEmpty) {
        AppLogger.warning('Products not found: ${response.notFoundIDs}');
      }

      if (response.error != null) {
        _queryProductError = response.error!.message;
        AppLogger.error('Error loading products: ${response.error!.message}');
        return;
      }

      _products = response.productDetails;
      _productsController.add(_products);

      AppLogger.info('Loaded ${_products.length} products successfully');
    } catch (e) {
      AppLogger.error('Error loading products', e);
      _queryProductError = e.toString();
    }
  }

  Future<bool> buyProduct(ProductDetails productDetails) async {
    if (!_isAvailable) {
      _purchaseStatusController.add('In-app purchases not available');
      return false;
    }

    try {
      AppLogger.info('Initiating purchase for: ${productDetails.id}');
      _purchasePending = true;
      _purchasePendingController.add(true);

      // Funnel event — fired BEFORE the IAP sheet opens. Combined with
      // item_purchased / purchase_cancelled / purchase_failed, this gives
      // us the IAP-sheet abandonment rate.
      _analytics?.trackPurchaseInitiated(
        productId: productDetails.id,
        productType: _productTypeFor(productDetails.id),
      );

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      bool success;
      if (ProductIds.consumableIds.contains(productDetails.id)) {
        success = await _inAppPurchase.buyConsumable(
          purchaseParam: purchaseParam,
        );
      } else {
        success = await _inAppPurchase.buyNonConsumable(
          purchaseParam: purchaseParam,
        );
      }

      if (!success) {
        _purchasePending = false;
        _purchasePendingController.add(false);
        _purchaseStatusController.add('Failed to initiate purchase');
        _analytics?.trackPurchaseFailed(
          productId: productDetails.id,
          errorCode: 'init_returned_false',
        );
      }

      return success;
    } catch (e) {
      AppLogger.error('Error buying product', e);
      _purchasePending = false;
      _purchasePendingController.add(false);
      _purchaseStatusController.add('Purchase failed: ${e.toString()}');
      _analytics?.trackPurchaseFailed(
        productId: productDetails.id,
        errorCode: 'exception',
      );
      return false;
    }
  }

  Future<void> _listenToPurchaseUpdated(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchaseStatusController.add('Purchase pending...');
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          AppLogger.error('Purchase error: ${purchaseDetails.error}');
          _purchaseStatusController.add('Purchase failed');
          _analytics?.trackPurchaseFailed(
            productId: purchaseDetails.productID,
            errorCode: purchaseDetails.error?.code,
          );
        } else if (purchaseDetails.status == PurchaseStatus.canceled) {
          AppLogger.info(
            'Purchase canceled by user: ${purchaseDetails.productID}',
          );
          _analytics?.trackPurchaseCancelled(
            productId: purchaseDetails.productID,
          );
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          // Deduplication: skip delivery if this purchase was already delivered
          // (protects against double-credit if app crashes between delivery
          // and completePurchase)
          final purchaseId = purchaseDetails.purchaseID;
          if (purchaseId != null &&
              _deliveredPurchaseIds.contains(purchaseId)) {
            AppLogger.info(
              'Skipping already-delivered purchase: $purchaseId '
              '(${purchaseDetails.productID})',
            );
          } else {
            // Verify purchase with backend (via ApiService with JWT auth)
            bool valid = await _verifyWithBackend(purchaseDetails);
            if (valid) {
              _purchases.add(purchaseDetails);
              // Broadcast for PremiumCubit to handle content delivery
              _purchaseStatusController.add(
                'purchase_completed:${purchaseDetails.productID}',
              );
              _purchaseStatusController.add('Purchase successful!');
            } else {
              // Backend verification failed — queue for offline retry
              await _queuePendingVerification(purchaseDetails);
              // Still deliver locally so the user isn't stuck
              _purchases.add(purchaseDetails);
              _purchaseStatusController.add(
                'purchase_completed:${purchaseDetails.productID}',
              );
              _purchaseStatusController.add(
                'Purchase delivered (backend sync pending)',
              );
            }

            // Mark as delivered AFTER broadcasting so PremiumCubit processes it
            if (purchaseId != null) {
              await _markAsDelivered(purchaseId);
            }

            // Funnel terminal event — fires once per fulfilled purchase
            // (restored re-emissions are skipped above).
            // Restore events also fire here on the first delivery; subsequent
            // restores hit the dedup branch and don't double-log.
            final productDetails = getProduct(purchaseDetails.productID);
            _analytics?.trackItemPurchased(
              itemId: purchaseDetails.productID,
              itemType: _productTypeFor(purchaseDetails.productID),
              price: productDetails?.price ?? 'unknown',
            );
          }
        }

        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }

        _purchasePending = false;
        _purchasePendingController.add(false);
      }
    }
  }

  // ==================== Backend Verification (via ApiService) ====================

  Future<bool> _verifyWithBackend(PurchaseDetails purchaseDetails) async {
    try {
      final apiService = ApiService();

      // Extract platform-specific data
      String platform = 'unknown';
      String receiptData = '';
      String? purchaseToken;

      if (purchaseDetails.verificationData.source == 'app_store') {
        platform = 'ios';
        receiptData = purchaseDetails.verificationData.serverVerificationData;
      } else if (purchaseDetails.verificationData.source == 'google_play') {
        platform = 'android';
        receiptData = purchaseDetails.verificationData.serverVerificationData;
        if (Platform.isAndroid && purchaseDetails is GooglePlayPurchaseDetails) {
          purchaseToken =
              purchaseDetails.billingClientPurchase.purchaseToken;
        } else {
          purchaseToken = purchaseDetails.purchaseID;
        }
      }

      // Use ApiService (authenticated with JWT) instead of BackendService
      final result = await apiService.verifyPurchase(
        platform: platform,
        receiptData: receiptData,
        productId: purchaseDetails.productID,
        transactionId: purchaseDetails.purchaseID ?? '',
        purchaseToken: purchaseToken,
      );

      if (result != null && result['is_valid'] == true) {
        AppLogger.info('Purchase verified via ApiService (JWT-authenticated)');
        return true;
      }

      AppLogger.error(
        'Backend verification failed: ${result?['message'] ?? 'null response'}',
      );
      return false;
    } catch (e) {
      AppLogger.error('Error verifying purchase with backend', e);
      return false;
    }
  }

  // ==================== Offline Retry Queue ====================

  /// Persist a failed verification so it can be retried later.
  Future<void> _queuePendingVerification(PurchaseDetails details) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_pendingVerificationsKey) ?? [];

      String? purchaseToken;
      String platform = 'unknown';
      String receiptData = '';

      if (details.verificationData.source == 'app_store') {
        platform = 'ios';
        receiptData = details.verificationData.serverVerificationData;
      } else if (details.verificationData.source == 'google_play') {
        platform = 'android';
        receiptData = details.verificationData.serverVerificationData;
        if (Platform.isAndroid && details is GooglePlayPurchaseDetails) {
          purchaseToken = details.billingClientPurchase.purchaseToken;
        } else {
          purchaseToken = details.purchaseID;
        }
      }

      final entry = jsonEncode({
        'product_id': details.productID,
        'transaction_id': details.purchaseID ?? '',
        'platform': platform,
        'receipt_data': receiptData,
        'purchase_token': purchaseToken,
        'queued_at': DateTime.now().toIso8601String(),
      });

      existing.add(entry);
      await prefs.setStringList(_pendingVerificationsKey, existing);
      AppLogger.info('Queued pending verification for ${details.productID}');
    } catch (e) {
      AppLogger.error('Error queuing pending verification', e);
    }
  }

  /// Retry all pending verifications. Called on app resume and connectivity restore.
  /// Uses batch endpoint when multiple verifications are pending.
  Future<void> retryPendingVerifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(_pendingVerificationsKey) ?? [];
      if (pending.isEmpty) return;

      AppLogger.info('Retrying ${pending.length} pending purchase verifications');
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
            .map((entry) => <String, dynamic>{
                  'purchase_data': {
                    'product_id': entry['product_id'],
                    'transaction_id': entry['transaction_id'],
                    'receipt_data': entry['receipt_data'],
                    'purchase_token': entry['purchase_token'],
                  },
                  'platform': entry['platform'],
                })
            .toList();

        final result = await apiService.batchVerifyPurchases(batchPayload);

        if (result != null && result['results'] != null) {
          final results = result['results'] as List;
          final remaining = <String>[];

          for (int i = 0; i < entries.length; i++) {
            if (i < results.length) {
              final r = results[i] as Map<String, dynamic>;
              if (r['is_valid'] == true) {
                AppLogger.info(
                  'Pending verification succeeded: ${entries[i]['product_id']}',
                );
              } else {
                remaining.add(pending[i]);
              }
            } else {
              remaining.add(pending[i]);
            }
          }

          await prefs.setStringList(_pendingVerificationsKey, remaining);
          if (remaining.isEmpty) {
            AppLogger.info('All pending verifications completed (batch)');
          } else {
            AppLogger.warning('${remaining.length} verifications still pending');
          }
          return;
        }
      }

      // Fallback: individual verification (single pending or batch failed)
      final remaining = <String>[];
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
          } else {
            remaining.add(pending[i]);
          }
        } catch (e) {
          remaining.add(pending[i]);
        }
      }

      await prefs.setStringList(_pendingVerificationsKey, remaining);
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
  /// if the purchase stream re-emits it (e.g. after a crash).
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

  Future<void> restorePurchases() async {
    try {
      AppLogger.info('Restoring purchases...');
      await _inAppPurchase.restorePurchases();
      AppLogger.info('Purchases restored successfully');
    } catch (e) {
      AppLogger.error('Error restoring purchases', e);
      _purchaseStatusController.add('Failed to restore purchases');
    }
  }

  /// One-shot post-authentication setup. Triggered from AuthCubit when it
  /// transitions to authenticated. Re-emits the user's Play Store purchases
  /// through the listener (which now has a valid JWT for backend verify)
  /// AND drains any purchases that 401'd in a previous unauth session.
  /// Idempotent and safe to call multiple times.
  bool _postAuthRestoreDone = false;
  Future<void> runPostAuthRestore() async {
    if (_postAuthRestoreDone) {
      // Subsequent re-auths just drain the pending queue; no need to
      // re-emit the whole Play Store inventory.
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

  ProductDetails? getProduct(String productId) {
    try {
      return _products.firstWhere((product) => product.id == productId);
    } catch (e) {
      return null;
    }
  }

  /// Display price for a product, handling the Google Play **subscription**
  /// quirk: a subscription's `ProductDetails.price` is derived from its first
  /// base-plan / offer pricing phase, which reads as "Free" / $0 whenever a
  /// base plan or free-trial phase is zero-priced — even though the real
  /// recurring price exists in a later pricing phase. For Android subs we dig
  /// out the recurring (non-zero) phase's formatted price; otherwise we use the
  /// cross-platform `price` (correct for one-time products and iOS subs).
  String? _displayPrice(ProductDetails? product) {
    if (product == null) return null;
    final recurring = _androidSubscriptionRecurringPrice(product);
    if (recurring != null && recurring.isNotEmpty) return recurring;
    final price = product.price;
    if (price.isEmpty) return null;
    return price;
  }

  /// The formatted price of the recurring (non-zero) pricing phase of an
  /// Android subscription, or null if not applicable / not found.
  String? _androidSubscriptionRecurringPrice(ProductDetails product) {
    if (product is! GooglePlayProductDetails) return null;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (offers == null || offers.isEmpty) return null;
    // Skip free-trial / intro phases (priceAmountMicros == 0); the perpetual
    // recurring price is the last non-zero phase. Take it from the first offer
    // that has one (typically the base plan).
    for (final offer in offers) {
      PricingPhaseWrapper? recurring;
      for (final phase in offer.pricingPhases) {
        if (phase.priceAmountMicros > 0) recurring = phase;
      }
      if (recurring != null) return recurring.formattedPrice;
    }
    return null;
  }

  /// Get the store-formatted price for a product (e.g. "$1.99").
  /// Returns null if the product hasn't been loaded from the store.
  String? getStorePrice(String productId) => _displayPrice(getProduct(productId));

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
          purchase.productID == productId &&
          purchase.status == PurchaseStatus.purchased,
    );
  }

  bool hasActiveSubscription(String subscriptionId) {
    final purchase = _purchases
        .where((p) => p.productID == subscriptionId)
        .firstOrNull;
    if (purchase == null) return false;

    return purchase.status == PurchaseStatus.purchased;
  }

  void dispose() {
    _subscription?.cancel();
    _purchasePendingController.close();
    _productsController.close();
    _purchaseStatusController.close();
  }
}
