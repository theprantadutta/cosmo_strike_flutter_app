import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// "Watch an ad for coins" card. Self-hides for Pro users / when ads are
/// unavailable, and disables itself once the daily cap is hit or no ad is
/// loaded. Credits coins offline-first via [CoinsCubit.earnCoins].
class RewardedCoinsButton extends StatefulWidget {
  final GameTheme theme;
  const RewardedCoinsButton({super.key, required this.theme});

  @override
  State<RewardedCoinsButton> createState() => _RewardedCoinsButtonState();
}

class _RewardedCoinsButtonState extends State<RewardedCoinsButton> {
  AdService? get _ads =>
      GetIt.I.isRegistered<AdService>() ? GetIt.I<AdService>() : null;

  @override
  void initState() {
    super.initState();
    _ads?.preloadRewarded();
  }

  Future<void> _watch() async {
    final ads = _ads;
    if (ads == null) return;
    final coins = context.read<CoinsCubit>();
    await ads.showRewardedForCoins(
      onCoins: (amount) {
        coins.earnCoins(
          CoinEarningSource.watchedAd,
          customAmount: amount,
          itemName: 'Watched ad',
          metadata: const {'placement': 'store_free_coins'},
        );
      },
    );
    if (mounted) setState(() {}); // refresh "N left today"
  }

  @override
  Widget build(BuildContext context) {
    final ads = _ads;
    if (ads == null || !ads.adsEnabled) return const SizedBox.shrink();

    final theme = widget.theme;
    final remaining = ads.freeCoinAdsRemainingToday;
    final enabled = ads.canShowFreeCoinAd;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? _watch : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.amber.withValues(alpha: 0.18),
                Colors.orange.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.play_circle_fill, color: Colors.amber, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Watch an ad — +${AdService.freeCoinsPerAd} coins',
                      style: TextStyle(
                        color: theme.accentColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? '$remaining left today'
                          : (remaining == 0
                              ? 'Come back tomorrow for more'
                              : 'No ad available right now'),
                      style: TextStyle(
                        color: theme.accentColor.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.monetization_on,
                  color: Colors.amber.withValues(alpha: 0.9), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
