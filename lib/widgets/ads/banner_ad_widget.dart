import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_config.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';

/// A self-contained anchored banner.
///
/// For Pro users and non-mobile platforms it renders nothing (takes zero
/// space). For everyone else it **always reserves the fixed banner height up
/// front** — even while the ad is still loading, after it fails, or when the
/// device is offline — and the ad simply fills that reserved box once it
/// arrives. Reserving the space up front is what prevents the layout shift
/// users would otherwise see when a banner pops in a moment after the screen
/// renders.
class ShipBannerAd extends StatefulWidget {
  const ShipBannerAd({super.key});

  @override
  State<ShipBannerAd> createState() => _ShipBannerAdState();
}

class _ShipBannerAdState extends State<ShipBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (!GetIt.I.isRegistered<AdService>()) return;
    if (!GetIt.I<AdService>().adsEnabled) return;
    final ad = BannerAd(
      adUnitId: AdConfig.bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = ad as BannerAd;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    );
    ad.load();
  }

  @override
  void dispose() {
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

    // Non-Pro mobile users: reserve the standard banner height NOW and keep it
    // reserved regardless of load/fill/offline state. The reserved box never
    // changes size, so the ad fills it without shifting surrounding layout.
    final ad = _ad;
    return SafeArea(
      top: false,
      child: SizedBox(
        width: double.infinity,
        height: AdSize.banner.height.toDouble(),
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
