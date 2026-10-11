import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_config.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/theme/cosmo_theme.dart';

/// An inline banner that lives INSIDE one column of a two-column layout
/// (typically the bottom of the left summary column) — never a full-width
/// strip. Full-width anchored banners were removed app-wide: on wide, short
/// landscape screens they ate a large slice of the viewport.
///
/// Sized with an inline-adaptive banner for the column's width, capped at
/// [maxHeight]. It takes **no space** until an ad has actually loaded (and
/// never for Pro users, non-mobile platforms, or columns too narrow for a
/// banner), so an empty slot is never shown. Failed loads retry with
/// exponential backoff while mounted; a Pro purchase drops it immediately.
class ColumnBannerAd extends StatefulWidget {
  const ColumnBannerAd({super.key, this.maxHeight = 60, this.minWidth = 240});

  /// Tallest banner allowed (logical px). Keep small on phones.
  final double maxHeight;

  /// Below this column width no banner is requested.
  final double minWidth;

  @override
  State<ColumnBannerAd> createState() => _ColumnBannerAdState();
}

class _ColumnBannerAdState extends State<ColumnBannerAd> {
  BannerAd? _ad;
  AdSize? _size;
  bool _loaded = false;
  int? _requestedWidth;

  Timer? _retryTimer;
  int _retryAttempt = 0;
  static const _maxRetryDelay = Duration(seconds: 60);

  StreamSubscription<PremiumState>? _premiumSub;
  bool _wasPremium = false;

  AdService? get _ads => GetIt.I.isRegistered<AdService>() ? GetIt.I<AdService>() : null;

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
            _retryTimer?.cancel();
            _ad?.dispose();
            _ad = null;
            _loaded = false;
          } else if (_ad == null && _requestedWidth != null) {
            _retryAttempt = 0;
            _load(_requestedWidth!);
          }
        });
      });
    }
  }

  void _ensureLoaded(int width) {
    if (_requestedWidth == width) return;
    _requestedWidth = width;
    // Defer out of layout.
    scheduleMicrotask(() => _load(width));
  }

  void _load(int width) {
    if (!mounted) return;
    final ads = _ads;
    if (ads == null || !ads.adsEnabled) return;
    final size = AdSize.getInlineAdaptiveBannerAdSize(width, widget.maxHeight.truncate());
    final ad = BannerAd(
      adUnitId: AdConfig.bannerUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loaded) async {
          final banner = loaded as BannerAd;
          // Inline adaptive ads report their real height after load.
          final platform = await banner.getPlatformAdSize();
          if (!mounted) {
            banner.dispose();
            return;
          }
          _retryAttempt = 0;
          setState(() {
            _ad?.dispose();
            _ad = banner;
            _size = platform ?? size;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (failed, error) {
          failed.dispose();
          _scheduleRetry(width);
        },
      ),
    );
    ad.load();
  }

  void _scheduleRetry(int width) {
    if (!mounted) return;
    final delay = Duration(
      milliseconds: math.min(
        (const Duration(seconds: 5).inMilliseconds) << _retryAttempt,
        _maxRetryDelay.inMilliseconds,
      ),
    );
    _retryAttempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => _load(width));
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
    final ads = _ads;
    if (ads == null || !ads.shouldReserveBannerSpace) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < widget.minWidth) return const SizedBox.shrink();
      _ensureLoaded(c.maxWidth.truncate());
      final ad = _ad;
      final size = _size;
      if (!_loaded || ad == null || size == null) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(top: context.cs(12)),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(CsRadius.tile),
            child: SizedBox(
              width: size.width.toDouble(),
              height: size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        ),
      );
    });
  }
}
