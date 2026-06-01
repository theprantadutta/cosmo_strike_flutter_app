import 'package:flutter/foundation.dart';

/// AdMob ad unit IDs. These are **not secrets** — they ship in the app binary
/// and are safe to hardcode, so they live here rather than in `.env`.
///
/// Debug builds always use Google's official **test** unit ids: serving (or
/// clicking) your own real ads during development is a policy violation that
/// can get the AdMob account banned. Release builds use the real ids from
/// `admob_ad_list.md`.
///
/// App IDs are NOT here — the SDK reads those from the native manifests
/// (`AndroidManifest.xml` / iOS `Info.plist`).
///
/// Uses [defaultTargetPlatform] (not `dart:io`) so the file stays web-safe.
class AdConfig {
  AdConfig._();

  static bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  // ---- Google official TEST ad unit ids (debug only) ----
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  // ---- Real PRODUCTION ad unit ids (from admob_ad_list.md) ----
  static const _bannerAndroid = 'ca-app-pub-9242904787767394/3016639636';
  static const _bannerIos = 'ca-app-pub-9242904787767394/3952271184';
  static const _interstitialAndroid = 'ca-app-pub-9242904787767394/6572741266';
  static const _interstitialIos = 'ca-app-pub-9242904787767394/9378033857';
  static const _rewardedAndroid = 'ca-app-pub-9242904787767394/7829982619';
  static const _rewardedIos = 'ca-app-pub-9242904787767394/3896430862';

  static String get bannerUnitId => kDebugMode
      ? (_isIos ? _testBannerIos : _testBannerAndroid)
      : (_isIos ? _bannerIos : _bannerAndroid);

  static String get interstitialUnitId => kDebugMode
      ? (_isIos ? _testInterstitialIos : _testInterstitialAndroid)
      : (_isIos ? _interstitialIos : _interstitialAndroid);

  static String get rewardedUnitId => kDebugMode
      ? (_isIos ? _testRewardedIos : _testRewardedAndroid)
      : (_isIos ? _rewardedIos : _rewardedAndroid);
}
