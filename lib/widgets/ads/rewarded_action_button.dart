import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// Generic "watch an ad for X" card used by the rewarded placements (free
/// power-up, bonus XP, …). Self-hides for Pro / when ads are disabled, disables
/// itself when no ad is loaded or the daily cap is hit, and re-checks readiness
/// live (1s ticker) so it enables the moment the rewarded ad finishes loading.
///
/// [onWatch] performs the actual ad show + grant (typically
/// `AdService.showRewardedCapped(...)`); the button just handles gating + UI.
class RewardedActionButton extends StatefulWidget {
  final GameTheme theme;
  final IconData icon;
  final String label;

  /// AdService cap key (e.g. [AdService.capFreePowerUp]). When set, the button
  /// gates on the daily cap and shows "N left today". Null → gate only on a
  /// loaded ad.
  final String? capKey;

  /// Does the ad + grant. Should call AdService.showRewarded(Capped). Awaited so
  /// the button can refresh its "N left" after.
  final Future<void> Function() onWatch;

  const RewardedActionButton({
    super.key,
    required this.theme,
    required this.icon,
    required this.label,
    required this.onWatch,
    this.capKey,
  });

  @override
  State<RewardedActionButton> createState() => _RewardedActionButtonState();
}

class _RewardedActionButtonState extends State<RewardedActionButton> {
  Timer? _ticker;

  AdService? get _ads =>
      GetIt.I.isRegistered<AdService>() ? GetIt.I<AdService>() : null;

  @override
  void initState() {
    super.initState();
    _ads?.preloadRewarded();
    // Re-evaluate readiness/cap periodically so the button enables when the ad
    // loads and the "N left today" updates after a watch.
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool _enabled(AdService ads) => widget.capKey != null
      ? ads.canShowCapped(widget.capKey!)
      : ads.isRewardedReady;

  Future<void> _onTap() async {
    await widget.onWatch();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ads = _ads;
    if (ads == null || !ads.adsEnabled) return const SizedBox.shrink();

    final theme = widget.theme;
    final enabled = _enabled(ads);
    final remaining =
        widget.capKey != null ? ads.dailyRemaining(widget.capKey!) : null;
    final subtitle = enabled
        ? (remaining != null ? '$remaining left today' : 'Opt-in — watch to earn')
        : (remaining == 0
            ? 'Come back tomorrow for more'
            : 'No ad available right now');

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? _onTap : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.accentColor.withValues(alpha: 0.18),
                theme.foodColor.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.accentColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.play_circle_fill, color: theme.accentColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: theme.accentColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: theme.accentColor.withValues(alpha: 0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(widget.icon,
                  color: theme.accentColor.withValues(alpha: 0.9), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
