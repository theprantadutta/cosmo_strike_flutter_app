import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';

class PremiumBenefitsScreen extends StatefulWidget {
  const PremiumBenefitsScreen({super.key});

  @override
  State<PremiumBenefitsScreen> createState() => _PremiumBenefitsScreenState();
}

class _PremiumBenefitsScreenState extends State<PremiumBenefitsScreen> {
  bool _isYearly = true;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PremiumCubit, PremiumState>(
      builder: (context, premiumState) {
        return BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, themeState) {
            final theme = themeState.currentTheme;

            return CommandScaffold(
              theme: theme,
              title: 'Cosmo Strike Pro',
              bodyPadding: EdgeInsets.zero,
              // Landscape command deck: LEFT = the complete purchase column
              // (identity, plan toggle, price, CTAs), RIGHT = the feature
              // list. Everything floats borderless on the starfield per the
              // clean design; the old bottom-docked subscribe bar is gone.
              body: premiumState.hasPremium
                  ? Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _buildPremiumActiveBlock(theme),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 4,
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SizedBox(
                                  width: 280,
                                  child: _buildPurchasePanel(
                                    theme,
                                    premiumState,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 6,
                            child: _buildFeaturesList(theme),
                          ),
                        ],
                      ),
                    ),
            );
          },
        );
      },
    );
  }

  /// Shown when the user already owns Pro — a borderless centered block.
  Widget _buildPremiumActiveBlock(GameTheme theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.green, Colors.teal],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.4),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.verified, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 16),
        Text(
          'Premium Active!',
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You have access to all premium features',
          style: TextStyle(color: theme.textMuted, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// LEFT column: Pro identity, plan toggle, live price readout, and the
  /// purchase CTAs — fully borderless; only the diamond disc and the
  /// subscribe pill carry color.
  Widget _buildPurchasePanel(GameTheme theme, PremiumState premiumState) {
    final productId =
        _isYearly ? ProductIds.proYearly : ProductIds.proMonthly;
    final price = PurchaseService().getStorePriceOrDefault(
      productId,
      _isYearly ? 39.99 : 4.99,
    );
    final period = _isYearly ? '/year' : '/month';
    final String? badge = _isYearly ? 'Save 33%' : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Identity — gradient diamond disc + wordmark, no boxed background.
        Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade400, Colors.indigo.shade400],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.shade400.withValues(alpha: 0.4),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.diamond, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            'Cosmo Strike Pro',
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Unlock everything the game has to offer',
            style: TextStyle(color: theme.textMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 14),

        // Monthly / Yearly toggle — borderless; selection reads via bright
        // text and a glowing underline.
        Row(
          children: [
            Expanded(child: _buildToggleOption('Monthly', false, theme)),
            Expanded(child: _buildToggleOption('Yearly', true, theme)),
          ],
        ),
        const SizedBox(height: 12),

        // Live price readout for the selected plan.
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 2),
                child: Text(
                  period,
                  style: TextStyle(color: theme.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        if (badge != null) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(
              badge,
              style: TextStyle(
                color: Colors.green.shade400,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),

        // Primary CTA — same gradient subscribe pill as the store: amber for
        // the featured yearly plan, the neon ramp for monthly. Glow only.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _subscribe,
          child: Container(
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isYearly
                    ? [Colors.amber, Colors.orange.shade400]
                    : [theme.neonPrimary, theme.neonSecondary],
              ),
              borderRadius: BorderRadius.circular(23),
              boxShadow: [
                BoxShadow(
                  color: (_isYearly ? Colors.amber : theme.neonPrimary)
                      .withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Text(
              'SUBSCRIBE',
              style: TextStyle(
                color: Color(0xFF03040A),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'No commitment • Cancel anytime • Secure payment',
            style: TextStyle(color: theme.textMuted, fontSize: 10.5),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleOption(String label, bool isYearly, GameTheme theme) {
    final isSelected = _isYearly == isYearly;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _isYearly = isYearly),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? theme.textPrimary : theme.textMuted,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 5),
            // Glowing underline marks the selected plan — no box, no border.
            Container(
              width: 28,
              height: 2.5,
              decoration: BoxDecoration(
                color:
                    isSelected ? theme.neonPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: theme.neonPrimary.withValues(alpha: 0.7),
                          blurRadius: 8,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// RIGHT column: the entitlement list as transparent rows.
  Widget _buildFeaturesList(GameTheme theme) {
    // Honest list — every entry maps to an entitlement the server actually
    // grants on Pro verify (VerifyPurchaseCommandHandler). The previous
    // 'Exclusive Game Modes' line was a false promise (modes are uniformly
    // free per project rules) and 'Premium Power-ups' / 'VIP Tournaments'
    // were unimplemented — those are now real recurring bundles.
    final features = [
      _FeatureItem(
        Icons.block,
        'Remove All Ads',
        'No banners, no interstitials — play completely ad-free, forever',
      ),
      _FeatureItem(
        Icons.palette,
        'All Premium Themes',
        'Crystal, Cyberpunk, Space, Ocean, Desert, Forest',
      ),
      _FeatureItem(
        Icons.rocket_launch,
        'All Premium Ship Skins',
        'Golden, Galaxy, Dragon, Electric, Fire, Ice & 5 more',
      ),
      _FeatureItem(
        Icons.gradient,
        'All Premium Trail Effects',
        'Particle, Glow, Rainbow, Fire, Cosmic, Crystal & 5 more',
      ),
      _FeatureItem(
        Icons.monetization_on,
        '2x Coin Rewards',
        'Double Star Coins from every run',
      ),
      // In-game spawn boosts implemented in food.dart (Food.generateRandom
      // isPremium param) and game_cubit.dart (_trySpawnPowerUp). Backed by
      // the snapshot of PremiumCubit.hasPremium at game start.
      _FeatureItem(
        Icons.auto_awesome,
        'Lucky Magnet — More Power-Ups',
        '+50% chance to spawn the rare 50-point power-up in every run',
      ),
      _FeatureItem(
        Icons.bolt,
        'More In-Game Power-ups',
        '+30% spawn rate for in-game power-ups during gameplay',
      ),
      _FeatureItem(
        Icons.flash_on,
        'Premium Power-up Bundle',
        '5× Warp Escape, Ghost Mode, Orb Magnet, Last Stand & Invincibility every billing cycle',
      ),
      _FeatureItem(
        Icons.emoji_events,
        'Tournament Entries',
        '1× Bronze + 1× Silver + 1× Gold tournament entry every billing cycle',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Text(
          'PREMIUM INCLUDES',
          style: TextStyle(
            color: theme.accentColor,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 12),
        ...features.map((feature) => _buildFeatureRow(feature, theme)),
      ],
    );
  }

  Widget _buildFeatureRow(_FeatureItem feature, GameTheme theme) {
    // Fully transparent row per the clean design.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(feature.icon, color: theme.accentColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  feature.description,
                  style: TextStyle(color: theme.textMuted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Real subscription purchase — opens the Google Play sheet.
  ///
  /// When the product can't be purchased we no longer show a single opaque
  /// "not available" toast. We distinguish the actual cause so the user knows
  /// what to do, and offer a Retry when the store query simply hasn't
  /// completed.
  Future<void> _subscribe() async {
    final purchaseService = PurchaseService();
    final productId = _isYearly
        ? ProductIds.proYearly
        : ProductIds.proMonthly;
    final product = purchaseService.getProduct(productId);

    if (product != null) {
      await purchaseService.buyProduct(product);
      return;
    }

    // Device has no billing support at all (no Play services, emulator, etc.).
    if (!purchaseService.isAvailable) {
      _showSubscribeIssue(
        "In-app purchases aren't available on this device.",
      );
      return;
    }

    // Store query hasn't returned products yet, or it errored — this is a
    // transient/recoverable state, so offer a Retry that re-runs the query.
    if (!purchaseService.hasLoadedProducts ||
        purchaseService.queryProductError != null) {
      _showSubscribeIssue(
        'The store is still loading. Please check your connection and retry.',
        actionLabel: 'RETRY',
        onAction: () async {
          await purchaseService.retryLoadProducts();
          if (mounted) setState(() {});
        },
      );
      return;
    }

    // Billing works and products loaded, but this specific subscription isn't
    // configured/active on the store yet.
    _showSubscribeIssue(
      "Pro subscriptions aren't available right now. Please try again later.",
    );
  }

  /// Shows a subscription problem as a snackbar, optionally with a single
  /// recovery action (e.g. Retry). Uses the muted neutral surface rather than
  /// an alarming red — these are recoverable states, not crashes.
  void _showSubscribeIssue(
    String message, {
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                onPressed: () => onAction(),
              )
            : null,
      ),
    );
  }

}

class _FeatureItem {
  final IconData icon;
  final String title;
  final String description;

  _FeatureItem(this.icon, this.title, this.description);
}
