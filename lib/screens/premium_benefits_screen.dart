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

class _PremiumBenefitsScreenState extends State<PremiumBenefitsScreen>
    with SingleTickerProviderStateMixin {
  // Trial lengths mirror the Play Console base-plan offers (monthly: 3-day,
  // yearly: 7-day). Used to render trial copy in the pricing cards, trial
  // info card, and Subscribe-button subtitle. Update here AND in Play
  // Console together if the offer ever changes.
  static const int _monthlyTrialDays = 3;
  static const int _yearlyTrialDays = 7;

  late TabController _tabController;
  bool _isYearly = true;

  int get _selectedTrialDays =>
      _isYearly ? _yearlyTrialDays : _monthlyTrialDays;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
              bottomBar: premiumState.hasPremium
                  ? null
                  : _buildBottomButton(theme, premiumState),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (premiumState.hasPremium) ...[
                      _buildPremiumActiveCard(theme),
                    ] else ...[
                      _buildPremiumHeaderCard(theme),
                      const SizedBox(height: 20),
                      _buildPricingToggle(theme),
                      const SizedBox(height: 16),
                      _buildPricingCards(theme),
                      const SizedBox(height: 20),
                      _buildFeaturesList(theme),
                      const SizedBox(height: 20),
                      _buildTrialInfo(theme),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPremiumActiveCard(GameTheme theme) {
    return SizedBox(
      width: double.infinity,
      child: GlassPanel(
      theme: theme,
      padding: const EdgeInsets.all(20),
      borderColor: Colors.green.withValues(alpha: 0.4),
      fillColor: Colors.green.withValues(alpha: 0.10),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.green, Colors.teal]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.verified, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            'Premium Active!',
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You have access to all premium features',
            style: TextStyle(
              color: theme.accentColor.withValues(alpha: 0.7),
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildPremiumHeaderCard(GameTheme theme) {
    return SizedBox(
      width: double.infinity,
      child: GlassPanel(
      theme: theme,
      glow: true,
      padding: const EdgeInsets.all(20),
      borderColor: Colors.purple.shade400.withValues(alpha: 0.4),
      fillColor: Colors.purple.shade400.withValues(alpha: 0.10),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade400, Colors.indigo.shade400],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.shade400.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.diamond, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            'Cosmo Strike Pro',
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Unlock everything the game has to offer',
            style: TextStyle(
              color: theme.accentColor.withValues(alpha: 0.7),
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildPricingToggle(GameTheme theme) {
    return GlassPanel(
      theme: theme,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(child: _buildToggleOption('Monthly', false, theme)),
          Expanded(child: _buildToggleOption('Yearly', true, theme)),
        ],
      ),
    );
  }


  Widget _buildToggleOption(String label, bool isYearly, GameTheme theme) {
    final isSelected = _isYearly == isYearly;

    return GestureDetector(
      onTap: () {
        setState(() {
          _isYearly = isYearly;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.accentColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(
                  color: theme.accentColor.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected
                ? theme.accentColor
                : theme.accentColor.withValues(alpha: 0.6),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildPricingCards(GameTheme theme) {
    return Column(
      children: [
        _buildPricingCard(
          title: 'Monthly Plan',
          price: PurchaseService().getStorePriceOrDefault(
              ProductIds.proMonthly, 4.99),
          period: '/month',
          badge: '$_monthlyTrialDays-day free trial',
          accentColor: Colors.blue,
          isPopular: false,
          theme: theme,
        ),
        const SizedBox(height: 12),
        _buildPricingCard(
          title: 'Yearly Plan',
          price: _isYearly
              ? PurchaseService().getStorePriceOrDefault(
                  ProductIds.proYearly, 39.99)
              : PurchaseService().getStorePriceOrDefault(
                  ProductIds.proMonthly, 4.99),
          period: _isYearly ? '/year' : '/month',
          badge: _isYearly
              ? 'Save 33% • $_yearlyTrialDays-day free trial'
              : '$_monthlyTrialDays-day free trial',
          accentColor: Colors.green,
          isPopular: _isYearly,
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildPricingCard({
    required String title,
    required String price,
    required String period,
    required String badge,
    required Color accentColor,
    required bool isPopular,
    required GameTheme theme,
  }) {
    return SizedBox(
      width: double.infinity,
      child: GlassPanel(
      theme: theme,
      glow: isPopular,
      padding: const EdgeInsets.all(20),
      borderColor: accentColor.withValues(alpha: isPopular ? 0.5 : 0.35),
      fillColor: accentColor.withValues(alpha: 0.10),
      child: Column(
        children: [
          if (isPopular)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.amber, Colors.orange]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'MOST POPULAR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (isPopular) const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: theme.accentColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      badge,
                      style: TextStyle(
                        color: theme.accentColor.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    period,
                    style: TextStyle(
                      color: accentColor.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

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
        Icons.pets,
        'All Premium Ship Skins',
        'Golden, Galaxy, Dragon, Electric, Fire, Ice & 5 more',
      ),
      _FeatureItem(
        Icons.gradient,
        'All Premium Trail Effects',
        'Particle, Glow, Rainbow, Fire, Cosmic, Crystal & 5 more',
      ),
      _FeatureItem(
        Icons.grid_on,
        'Large Game Boards',
        'Play on 35x35, 40x40 & 50x50 boards',
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
        '+30% spawn rate for on-board power-ups during gameplay',
      ),
      _FeatureItem(
        Icons.flash_on,
        'Premium Power-up Bundle',
        '5× Teleport, Ghost Mode, Magnetic Pickup, Score Shield & Mega Invincibility every billing cycle',
      ),
      _FeatureItem(
        Icons.emoji_events,
        'Tournament Entries',
        '1× Bronze + 1× Silver + 1× Gold tournament entry every billing cycle',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Premium Includes:',
          style: TextStyle(
            color: theme.accentColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...features.map((feature) => _buildFeatureCard(feature, theme)),
      ],
    );
  }

  Widget _buildFeatureCard(_FeatureItem feature, GameTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HoloCard(
      theme: theme,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(feature.icon, color: theme.accentColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: TextStyle(
                    color: theme.accentColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  feature.description,
                  style: TextStyle(
                    color: theme.accentColor.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTrialInfo(GameTheme theme) {
    return SizedBox(
      width: double.infinity,
      child: GlassPanel(
      theme: theme,
      borderColor: Colors.green.withValues(alpha: 0.4),
      fillColor: Colors.green.withValues(alpha: 0.10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.green, Colors.teal]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.card_giftcard,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_selectedTrialDays-Day Free Trial',
                  style: TextStyle(
                    color: theme.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Try all premium features risk-free',
                  style: TextStyle(
                    color: theme.accentColor.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildBottomButton(GameTheme theme, PremiumState premiumState) {
    final productId = _isYearly
        ? ProductIds.proYearly
        : ProductIds.proMonthly;
    final price = PurchaseService().getStorePriceOrDefault(
      productId,
      _isYearly ? 39.99 : 4.99,
    );
    final period = _isYearly ? '/year' : '/month';
    final canStartInAppTrial =
        !premiumState.hasUsedTrial && !premiumState.isOnTrial;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(
            color: theme.accentColor.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Primary CTA — honest about payment
            NeonButton(
              onPressed: _subscribe,
              label: 'Subscribe — $price$period',
              theme: theme,
              expand: true,
              height: 52,
            ),
            const SizedBox(height: 6),
            Text(
              '$_selectedTrialDays-day free trial via Google Play',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: theme.accentColor.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            // Secondary CTA — in-app trial, no payment. Hidden once trial used.
            if (canStartInAppTrial) ...[
              const SizedBox(height: 10),
              NeonButton(
                onPressed: _startInAppTrial,
                label: 'Try 3 days free',
                theme: theme,
                variant: NeonButtonVariant.outline,
                expand: true,
                height: 48,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'No commitment • Cancel anytime • Secure payment',
              style: TextStyle(
                color: theme.accentColor.withValues(alpha: 0.6),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// Real subscription purchase — opens the Google Play sheet.
  void _subscribe() {
    final purchaseService = PurchaseService();
    final productId = _isYearly
        ? ProductIds.proYearly
        : ProductIds.proMonthly;
    final product = purchaseService.getProduct(productId);

    if (product != null) {
      purchaseService.buyProduct(product);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium subscription not available'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// In-app 3-day trial — no payment, no Google Play sheet. One-shot per user
  /// (PremiumCubit.startFreeTrial enforces single-use via state.hasUsedTrial).
  void _startInAppTrial() {
    final messenger = ScaffoldMessenger.of(context);
    context.read<PremiumCubit>().startFreeTrial();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('3-day free trial started — enjoy premium!'),
        backgroundColor: Colors.green,
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
