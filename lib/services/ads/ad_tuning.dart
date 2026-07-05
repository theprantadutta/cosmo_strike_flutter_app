import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';

/// Remote-tunable ad cadence knobs (Firebase Remote Config).
///
/// The in-code defaults below are the live values until a fetch succeeds, so
/// ads behave correctly offline, on first launch, and if Remote Config is
/// never configured in the console. Tuning a value in the Firebase console
/// changes the cadence on the next fetch (≤1h) — no app release needed.
///
/// Keep this static + synchronous on the read side: AdService consults these
/// getters on every interstitial decision.
abstract final class AdTuning {
  static const _kEveryNGames = 'ads_interstitial_every_n_games';
  static const _kEveryNLevels = 'ads_interstitial_every_n_levels';
  static const _kMinGapSeconds = 'ads_interstitial_min_gap_seconds';
  static const _kOverlayBanners = 'ads_overlay_banners_enabled';

  static const _defaults = <String, dynamic>{
    _kEveryNGames: 3,
    // Level-clear softened from every 2 to every 3: mid-run interruptions in
    // a momentum game are the biggest churn lever; game-over interstitials
    // (run already ended) are the cheaper placement.
    _kEveryNLevels: 3,
    _kMinGapSeconds: 180,
    _kOverlayBanners: true,
  };

  static FirebaseRemoteConfig? _rc;

  /// Non-blocking init — call after Firebase.initializeApp. Ads run on the
  /// defaults if this never completes (offline / console unconfigured).
  static Future<void> init() async {
    try {
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await rc.setDefaults(_defaults);
      _rc = rc; // defaults are readable even if the fetch below fails
      await rc.fetchAndActivate();
      AppLogger.success(
        'AdTuning: remote config active '
        '(games=$interstitialEveryNGames levels=$interstitialEveryNLevels '
        'gap=${interstitialMinGap.inSeconds}s overlayBanners=$overlayBannersEnabled)',
      );
    } catch (e) {
      AppLogger.warning('AdTuning: remote fetch failed, using defaults ($e)');
    }
  }

  static int _int(String key) => _rc?.getInt(key) ?? _defaults[key] as int;
  static bool _bool(String key) => _rc?.getBool(key) ?? _defaults[key] as bool;

  /// Show a game-over interstitial every Nth game.
  static int get interstitialEveryNGames => _int(_kEveryNGames);

  /// Show a level-clear interstitial every Nth cleared level.
  static int get interstitialEveryNLevels => _int(_kEveryNLevels);

  /// Minimum wall-clock gap shared by ALL interstitial placements.
  static Duration get interstitialMinGap =>
      Duration(seconds: _int(_kMinGapSeconds));

  /// Kill switch for the banners floated on the pause / level-clear /
  /// game-over overlays.
  static bool get overlayBannersEnabled => _bool(_kOverlayBanners);
}
