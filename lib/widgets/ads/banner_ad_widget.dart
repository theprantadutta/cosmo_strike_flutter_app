import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_config.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';

/// A self-contained anchored banner.
///
/// For Pro users and non-mobile platforms it renders nothing (takes zero
/// space). For everyone else it **always reserves the banner height up
/// front** — even while the ad is still loading, after it fails, or when the
/// device is offline — and the ad simply fills that reserved box once it
/// arrives. Reserving the space up front is what prevents the layout shift
/// users would otherwise see when a banner pops in a moment after the screen
/// renders.
///
/// Uses the anchored ADAPTIVE size for the current orientation (better fill +
/// eCPM than the fixed 320×50 banner, especially in landscape where the fixed
/// banner floats in a much wider slot), falling back to [AdSize.banner] when
/// the adaptive lookup fails. Failed loads retry with exponential backoff so
/// a flaky first request doesn't leave the reserved space empty forever.
class ShipBannerAd extends StatefulWidget {
  const ShipBannerAd({super.key, this.top = false});

  /// Anchor the banner to the TOP edge instead of the bottom. Used by the
  /// gameplay overlays (pause / level-clear / game-over), where the bottom
  /// edge is crowded. Defaults to bottom so menu placements are unaffected.
  final bool top;

  @override
  State<ShipBannerAd> createState() => _ShipBannerAdState();
}

class _ShipBannerAdState extends State<ShipBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;

  /// Resolved anchored-adaptive size (null until looked up). The reserved box
  /// uses its height so the reservation matches what will actually render.
  AdSize? _adSize;
  bool _sizeRequested = false;

  Timer? _retryTimer;
  int _retryAttempt = 0;
  static const _maxRetryDelay = Duration(seconds: 60);

  /// Premium flips must take effect on ALREADY-MOUNTED banners immediately.
  /// This widget reads premium state via GetIt (not the widget tree), so
  /// without a listener a loaded banner kept showing until its screen was
  /// rebuilt — subscribers saw ads for a while after buying Pro.
  StreamSubscription<PremiumState>? _premiumSub;
  bool _wasPremium = false;

  @override
  void initState() {
    super.initState();
    if (GetIt.I.isRegistered<PremiumCubit>()) {
      final premium = GetIt.I<PremiumCubit>();
      _wasPremium = premium.state.hasPremium;
      _premiumSub = premium.stream.listen((s) {
        if (!mounted || s.hasPremium == _wasPremium) return;
        _wasPremium = s.hasPremium;
        setState(() {
          if (s.hasPremium) {
            // Pro just activated: drop the ad + stop retries NOW. The build
            // below collapses to zero space via shouldReserveBannerSpace.
            _retryTimer?.cancel();
            _ad?.dispose();
            _ad = null;
            _loaded = false;
          } else if (_ad == null) {
            // Pro lapsed while this banner is mounted — start loading again.
            _retryAttempt = 0;
            _load();
          }
        });
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sizeRequested) return;
    _sizeRequested = true;
    // Resolve the adaptive size for the available width BEFORE the first
    // load, so the reserved height is right from the first frame the size is
    // known. MediaQuery is available here (not in initState).
    final width = MediaQuery.sizeOf(context).width.truncate();
    unawaited(_resolveSizeAndLoad(width));
  }

  Future<void> _resolveSizeAndLoad(int width) async {
    AdSize? size;
    try {
      // The app is landscape-locked, so the orientation is static. Height is
      // Google-optimized: capped at 15% of the screen height, min 50px.
      size = await AdSize.getLargeAnchoredAdaptiveBannerAdSizeWithOrientation(
        Orientation.landscape,
        width,
      );
    } catch (_) {
      size = null;
    }
    if (!mounted) return;
    setState(() => _adSize = size ?? AdSize.banner);
    _load();
  }

  void _load() {
    if (!mounted) return;
    if (!GetIt.I.isRegistered<AdService>()) return;
    if (!GetIt.I<AdService>().adsEnabled) return;
    final size = _adSize ?? AdSize.banner;
    final ad = BannerAd(
      adUnitId: AdConfig.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          _retryAttempt = 0;
          setState(() {
            _ad = ad as BannerAd;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _scheduleRetry();
        },
      ),
    );
    ad.load();
  }

  /// Exponential backoff: 5s, 10s, 20s, 40s, then capped at 60s while the
  /// widget stays mounted. Without this, one flaky request at screen-open
  /// left the reserved space empty until the user navigated away and back.
  void _scheduleRetry() {
    if (!mounted) return;
    final delay = Duration(
      milliseconds: math.min(
        (const Duration(seconds: 5).inMilliseconds) << _retryAttempt,
        _maxRetryDelay.inMilliseconds,
      ),
    );
    _retryAttempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, _load);
  }

  @override
  void dispose() {
    _premiumSub?.cancel();
    _retryTimer?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pro / non-mobile / no AdService → take no space at all.
    if (!GetIt.I.isRegistered<AdService>() ||
        !GetIt.I<AdService>().shouldReserveBannerSpace) {
      return const SizedBox.shrink();
    }

    // Non-Pro mobile users: reserve the banner height NOW and keep it
    // reserved regardless of load/fill/offline state. The reserved box uses
    // the resolved adaptive height once known (standard height until then),
    // so the ad fills it without shifting surrounding layout.
    final ad = _ad;
    final reservedHeight = (_adSize ?? AdSize.banner).height.toDouble();
    return SafeArea(
      // Hug the anchored edge: a bottom banner ignores the bottom inset, a top
      // banner ignores the top inset (so it sits flush under the status bar).
      top: widget.top,
      bottom: !widget.top,
      child: SizedBox(
        width: double.infinity,
        height: reservedHeight,
        child: (_loaded && ad != null)
            ? Center(
                child: SizedBox(
                  width: ad.size.width.toDouble(),
                  height: ad.size.height.toDouble(),
                  child: AdWidget(ad: ad),
                ),
              )
            : const SizedBox.shrink(), // reserved but empty until an ad loads
      ),
    );
  }
}
