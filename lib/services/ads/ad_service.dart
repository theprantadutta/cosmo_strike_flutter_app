import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_config.dart';
import 'package:cosmo_strike_flutter_app/services/connectivity_service.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central AdMob wrapper: owns the SDK init + consent, preloads interstitial /
/// rewarded ads, enforces the **Pro gate** (Pro/trial users never see ads),
/// the **connectivity gate**, and an interstitial **frequency cap**.
///
/// Mobile-only: no-ops on web/desktop. Reward grants happen in the calling
/// code (placement-specific), not here — see the rewarded placements.
class AdService {
  // ---- tunables ----
  static const int _interstitialEveryNGames = 3;
  static const Duration _interstitialMinGap = Duration(minutes: 3);

  // SharedPreferences keys (device-only, never synced).
  static const _kGamesSinceInterstitial = 'ads_games_since_interstitial';
  static const _kLastInterstitialMs = 'ads_last_interstitial_ms';
  static const _kSessionIsFirst = 'ads_first_session_done';

  bool _initialized = false;
  bool _sdkReady = false;
  bool _consentGathered = false;
  // Whether UMP says a privacy-options entry point should be offered. Only
  // true when a consent form is actually available + required for this user —
  // so we never surface a "Privacy & ad choices" button that opens nothing
  // (e.g. when no form is configured in the AdMob console, or consent isn't
  // required in the user's region).
  bool _privacyOptionsRequired = false;

  InterstitialAd? _interstitial;
  bool _interstitialLoading = false;
  RewardedAd? _rewarded;
  bool _rewardedLoading = false;

  SharedPreferences? _prefs;

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _isPro {
    if (!GetIt.I.isRegistered<PremiumCubit>()) return false;
    return GetIt.I<PremiumCubit>().state.hasPremium;
  }

  bool get _isOnline {
    if (!GetIt.I.isRegistered<ConnectivityService>()) return true;
    return GetIt.I<ConnectivityService>().isOnline;
  }

  /// The single master switch. Everything checks this.
  bool get adsEnabled => _sdkReady && _isMobile && !_isPro;

  /// Whether banner placements should reserve their fixed height up front.
  /// True for any non-Pro mobile user — deliberately independent of SDK
  /// readiness, network state, and whether an ad actually filled — so the
  /// reserved space never collapses. That's what prevents the layout from
  /// shifting when a banner loads late, fails, or the device is offline.
  /// Pro users and non-mobile platforms reserve nothing (full-screen content).
  bool get shouldReserveBannerSpace => _isMobile && !_isPro;

  /// A rewarded ad is loaded and ready to show right now.
  bool get isRewardedReady => adsEnabled && _rewarded != null;

  // ==================== Init + consent ====================

  Future<void> initialize() async {
    if (_initialized || !_isMobile) return;
    _initialized = true;
    try {
      _prefs = await SharedPreferences.getInstance();
      await _gatherConsentAndAtt();
      await MobileAds.instance.initialize();
      if (kDebugMode) {
        // Emulators/sim are test devices automatically; this covers physical
        // dev phones too so we never serve real impressions in debug.
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: const []),
        );
      }
      _sdkReady = true;
      AppLogger.success('AdService initialized (ads ${adsEnabled ? 'on' : 'off'})');
      if (adsEnabled) {
        _loadInterstitial();
        _loadRewarded();
      }
    } catch (e) {
      AppLogger.error('AdService init failed', e);
    }
  }

  /// UMP (GDPR) consent + iOS ATT. Never throws — ads just stay off on failure.
  Future<void> _gatherConsentAndAtt() async {
    try {
      final params = ConsentRequestParameters();
      final completer = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
          } catch (_) {}
          if (!completer.isCompleted) completer.complete();
        },
        (FormError error) {
          AppLogger.warning('UMP consent update failed: ${error.message}');
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future;
      _consentGathered = true;
      // Cache whether a privacy-options form should be offered, so the
      // Settings entry point can gate on it synchronously.
      try {
        final status = await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus();
        _privacyOptionsRequired =
            status == PrivacyOptionsRequirementStatus.required;
      } catch (_) {
        _privacyOptionsRequired = false;
      }
    } catch (e) {
      AppLogger.warning('Consent gathering errored: $e');
    }

    // iOS App Tracking Transparency — request once if undetermined.
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final status =
            await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          await AppTrackingTransparency.requestTrackingAuthorization();
        }
      }
    } catch (_) {/* ATT optional — ignore */}
  }

  /// Whether a "Privacy & ad choices" entry point should be shown. False when
  /// no consent form is available/required (so we don't show a dead button).
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  /// Re-show the consent form so users can change their choice (Settings).
  /// Returns true if the form was shown, false if it failed (e.g. no form is
  /// configured for this app ID in the AdMob console).
  Future<bool> showPrivacyOptions() async {
    final completer = Completer<bool>();
    try {
      await ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (!completer.isCompleted) completer.complete(error == null);
      });
    } catch (e) {
      AppLogger.warning('Privacy options form failed: $e');
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future;
  }

  bool get consentGathered => _consentGathered;

  // ==================== Interstitial ====================

  void _loadInterstitial() {
    if (!adsEnabled || _interstitial != null || _interstitialLoading) return;
    if (!_isOnline) return;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _interstitialLoading = false;
        },
        onAdFailedToLoad: (error) {
          _interstitial = null;
          _interstitialLoading = false;
          AppLogger.warning('Interstitial failed to load: ${error.message}');
        },
      ),
    );
  }

  /// Show an interstitial if the frequency cap allows. Call this on game-over.
  /// Returns true if an ad was shown. Counts the game regardless.
  Future<bool> maybeShowInterstitialOnGameOver() async {
    if (!adsEnabled) return false;
    final prefs = _prefs;
    if (prefs == null) return false;

    // First session ever → never interrupt; just mark it done.
    if (!(prefs.getBool(_kSessionIsFirst) ?? false)) {
      await prefs.setBool(_kSessionIsFirst, true);
      return false;
    }

    final games = (prefs.getInt(_kGamesSinceInterstitial) ?? 0) + 1;
    final lastMs = prefs.getInt(_kLastInterstitialMs) ?? 0;
    final gapOk = DateTime.now().millisecondsSinceEpoch - lastMs >=
        _interstitialMinGap.inMilliseconds;

    if (games < _interstitialEveryNGames || !gapOk || _interstitial == null) {
      await prefs.setInt(_kGamesSinceInterstitial, games);
      _loadInterstitial();
      return false;
    }

    final ad = _interstitial!;
    final shown = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitial = null;
        if (!shown.isCompleted) shown.complete(true);
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitial = null;
        if (!shown.isCompleted) shown.complete(false);
        _loadInterstitial();
      },
    );
    await ad.show();
    await prefs.setInt(_kGamesSinceInterstitial, 0);
    await prefs.setInt(
        _kLastInterstitialMs, DateTime.now().millisecondsSinceEpoch);
    return shown.future;
  }

  // ==================== Rewarded ====================

  void _loadRewarded() {
    if (!adsEnabled || _rewarded != null || _rewardedLoading) return;
    if (!_isOnline) return;
    _rewardedLoading = true;
    RewardedAd.load(
      adUnitId: AdConfig.rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _rewardedLoading = false;
        },
        onAdFailedToLoad: (error) {
          _rewarded = null;
          _rewardedLoading = false;
          AppLogger.warning('Rewarded failed to load: ${error.message}');
        },
      ),
    );
  }

  /// Eagerly (re)load a rewarded ad — call when entering a screen that offers
  /// one, so it's ready by the time the user taps.
  void preloadRewarded() => _loadRewarded();

  /// Show the rewarded ad. [onReward] fires only if the user earned the reward
  /// (watched to completion) AND **after the ad is dismissed** — never while
  /// it's still on screen. This matters for the revive placement: granting on
  /// the earn callback resumed the game loop behind the ad, so the ship moved
  /// (and re-crashed) before the player closed it. Granting on dismiss means
  /// the player is back in the app when the reward applies.
  Future<bool> showRewarded({required VoidCallback onReward}) async {
    if (!adsEnabled || _rewarded == null) {
      _loadRewarded();
      return false;
    }
    final ad = _rewarded!;
    _rewarded = null;
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (earned) onReward();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewarded();
      },
    );
    await ad.show(
      onUserEarnedReward: (_, _) => earned = true,
    );
    return earned;
  }

  // ==================== Daily-capped rewarded helpers ====================
  //
  // Per-placement, per-day caps stored device-only (SharedPreferences). These
  // bound how much free currency/XP ad-grinding can produce — it must never be
  // cheaper to grind ads than to buy IAP, so keep the caps modest.

  /// Cap keys + their per-day limits (used by the rewarded placements).
  static const String capFreeCoins = 'free_coins';
  static const String capFreePowerUp = 'free_powerup';
  static const String capBattlePassXp = 'bp_xp';
  static const Map<String, int> dailyCaps = {
    capFreeCoins: 5,
    capFreePowerUp: 3,
    capBattlePassXp: 3,
  };

  /// Coins granted per "watch for coins" ad.
  static const int freeCoinsPerAd = 30;

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  int _dailyUsed(String capKey) {
    final prefs = _prefs;
    // Unknown prefs → treat as maxed so we never over-grant before init.
    if (prefs == null) return 1 << 30;
    final usedToday = prefs.getString('ads_cap_${capKey}_date') == _todayKey();
    return usedToday ? (prefs.getInt('ads_cap_${capKey}_count') ?? 0) : 0;
  }

  /// How many of [capKey] ads the user can still watch today.
  int dailyRemaining(String capKey) {
    final max = dailyCaps[capKey] ?? 0;
    return (max - _dailyUsed(capKey)).clamp(0, max);
  }

  /// True when a rewarded ad for [capKey] can be shown now (loaded + under cap).
  bool canShowCapped(String capKey) =>
      isRewardedReady && dailyRemaining(capKey) > 0;

  Future<void> _recordDaily(String capKey) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final used = _dailyUsed(capKey);
    await prefs.setString('ads_cap_${capKey}_date', _todayKey());
    await prefs.setInt('ads_cap_${capKey}_count', used + 1);
  }

  /// Show a rewarded ad for a daily-capped placement. [onReward] fires (on ad
  /// dismiss, via [showRewarded]) only if earned; the cap is then recorded.
  Future<bool> showRewardedCapped({
    required String capKey,
    required VoidCallback onReward,
  }) async {
    if (!canShowCapped(capKey)) return false;
    return showRewarded(onReward: () {
      onReward();
      _recordDaily(capKey);
    });
  }

  /// Convenience wrapper for the free-coins placement.
  Future<bool> showRewardedForCoins({
    required void Function(int coins) onCoins,
  }) =>
      showRewardedCapped(
        capKey: capFreeCoins,
        onReward: () => onCoins(freeCoinsPerAd),
      );

  // Back-compat getters used by RewardedCoinsButton.
  int get freeCoinAdsRemainingToday => dailyRemaining(capFreeCoins);
  bool get canShowFreeCoinAd => canShowCapped(capFreeCoins);

  void dispose() {
    _interstitial?.dispose();
    _rewarded?.dispose();
    _interstitial = null;
    _rewarded = null;
  }
}
