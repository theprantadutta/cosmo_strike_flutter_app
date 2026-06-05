import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/models/premium_cosmetics.dart';
import 'package:cosmo_strike_flutter_app/models/premium_power_up.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/rewarded_coins_button.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/power_up/power_up_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/account_upgrade_sheet.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';

class StoreScreen extends StatefulWidget {
  final int initialTab;

  const StoreScreen({super.key, this.initialTab = 0});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Tracks productIds whose purchase was just initiated but whose ownership
  // hasn't reflected back from the backend yet. The card switches from
  // "BUY" to a "Verifying..." spinner during this window (typically 2-15s
  // for Play Store → webhook → entitlement → cubit). Auto-cleared once
  // the PremiumCubit reports the item as owned, or after a safety timeout
  // so the spinner never spins forever if a webhook is genuinely lost.
  final Set<String> _pendingProductIds = {};

  // Tab order: Pro / Coins / Themes / Skins / Trails / Power-Ups.
  // Keeps Coins at index 1 so existing `?tab=1` deep links still land on
  // coins. Themes replaces the old Boards tab (boards aren't products).
  // Modes tab removed entirely — modes are uniformly free now.
  static const _tabNames = [
    'Pro',
    'Coins',
    'Themes',
    'Skins',
    'Trails',
    'Power-Ups',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabNames.length,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, _tabNames.length - 1),
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    getIt<AnalyticsFacade>().trackStoreTabViewed(_tabNames[_tabController.index]);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PremiumCubit, PremiumState>(
      builder: (context, premiumState) {
        return BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, themeState) {
            return BlocBuilder<CoinsCubit, CoinsState>(
              builder: (context, coinsState) {
                final theme = themeState.currentTheme;
                return CommandScaffold(
                  theme: theme,
                  title: 'Cosmo Store',
                  bottomBar: const ShipBannerAd(),
                  bodyPadding: EdgeInsets.zero,
                  body: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // LEFT — balance telemetry + section rail. Never
                        // scrolls: rendered at natural size and scaled down
                        // to fit the short landscape viewport.
                        Expanded(
                          flex: 3,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SizedBox(
                                width: 220,
                                child: _buildLeftPanel(theme, coinsState),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        // RIGHT — the selected section's content (swipeable).
                        Expanded(
                          flex: 7,
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildProTab(theme, premiumState),
                              _buildCoinsTab(theme, coinsState),
                              _buildThemesTab(theme, premiumState),
                              _buildSkinsTab(theme, premiumState),
                              _buildTrailsTab(theme, premiumState),
                              _buildPowerUpsTab(theme, premiumState, coinsState),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // Left panel — balance telemetry + borderless section rail
  // ===========================================================================

  /// Vertical left region: the Star Coins balance readout up top and a
  /// borderless nav rail below it. Driven by the existing [_tabController]
  /// so rail taps and TabBarView swipes stay in sync.
  Widget _buildLeftPanel(GameTheme theme, CoinsState coinsState) {
    const items = [
      (Icons.diamond, 'Pro'),
      (Icons.monetization_on, 'Coins'),
      (Icons.color_lens, 'Themes'),
      (Icons.rocket_launch, 'Skins'),
      (Icons.auto_awesome, 'Trails'),
      (Icons.flash_on, 'Power-Ups'),
    ];

    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Balance telemetry — floats straight on the starfield.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'BALANCE',
                    style: TextStyle(
                      color: theme.accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.monetization_on,
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${coinsState.balance.total}',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (coinsState.hasPremiumBonus) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.purple.shade400,
                                Colors.indigo.shade400,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${coinsState.earningMultiplier}x BONUS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < items.length; i++)
              _buildNavItem(theme, i, items[i].$1, items[i].$2),
          ],
        );
      },
    );
  }

  Widget _buildNavItem(GameTheme theme, int i, IconData icon, String label) {
    final selected = _tabController.index == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tabController.animateTo(i),
      // No background at all — selection reads purely through the neon icon,
      // brighter text, and a small glowing indicator dot.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? theme.neonPrimary : theme.textMuted,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? theme.textPrimary : theme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (selected)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.neonPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.neonPrimary.withValues(alpha: 0.7),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // PRO TAB
  // ===========================================================================

  Widget _buildProTab(GameTheme theme, PremiumState premiumState) {
    // Drops any Pro SKU from the pending set once PremiumCubit reports
    // hasPremium=true — the spinner on the plan cards stops the moment the
    // backend's VerifyPurchase response lands.
    _reconcilePendingPurchases(premiumState);

    // Paid Pro user — banner + feature grid only, no need to show plans.
    if (premiumState.hasPremium && !premiumState.isOnPromo) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildProActiveBanner(theme, premiumState),
            const SizedBox(height: 16),
            _buildProFeatureGrid(theme),
          ],
        ),
      );
    }

    // Trial user — banner with TRIAL badge + feature grid + plan picker
    // below so they can convert without leaving the tab. Banner's
    // "Keep Pro" CTA defaults to monthly; this section lets them choose.
    if (premiumState.hasPremium && premiumState.isOnPromo) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildProActiveBanner(theme, premiumState),
            const SizedBox(height: 20),
            _buildProFeatureGrid(theme),
            const SizedBox(height: 24),
            Text(
              'SUBSCRIBE BEFORE THE TRIAL ENDS',
              style: TextStyle(
                color: theme.accentColor,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildProPlanCard(
                    theme: theme,
                    title: 'Monthly',
                    productId: ProductIds.proMonthly,
                    fallbackPrice: 4.99,
                    cadence: '/month',
                    savingsLabel: null,
                    highlight: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildProPlanCard(
                    theme: theme,
                    title: 'Yearly',
                    productId: ProductIds.proYearly,
                    fallbackPrice: 49.99,
                    cadence: '/year',
                    savingsLabel: 'Save 17%',
                    highlight: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Plans lead the tab — price first, pitch after.
          Text(
            'CHOOSE YOUR PLAN',
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildProPlanCard(
                  theme: theme,
                  title: 'Monthly',
                  productId: ProductIds.proMonthly,
                  fallbackPrice: 4.99,
                  cadence: '/month',
                  savingsLabel: null,
                  highlight: false,
                  trialLabel: '3-day free trial',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildProPlanCard(
                  theme: theme,
                  title: 'Yearly',
                  productId: ProductIds.proYearly,
                  fallbackPrice: 49.99,
                  cadence: '/year',
                  savingsLabel: 'Save 17%',
                  highlight: true,
                  trialLabel: '7-day free trial',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildProHero(theme),
          const SizedBox(height: 20),
          Text(
            'WHAT YOU GET',
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 12),
          _buildProFeatureGrid(theme),
        ],
      ),
    );
  }

  Widget _buildProHero(GameTheme theme) {
    // Fully transparent per the clean design — the gradient diamond disc and
    // typography carry the hero; no boxed background.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade400, Colors.indigo.shade400],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.diamond, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            'Cosmo Strike Pro',
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'All premium themes, skins & trails · 2× coins · '
            'premium power-ups · tournament entries · Battle Pass Premium',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProPlanCard({
    required GameTheme theme,
    required String title,
    required String productId,
    required double fallbackPrice,
    required String cadence,
    required String? savingsLabel,
    required bool highlight,
    String? trialLabel,
  }) {
    final price =
        PurchaseService().getStorePriceOrDefault(productId, fallbackPrice);
    final isPending = _pendingProductIds.contains(productId);
    // While a sibling plan card is mid-verify we disable BOTH plan cards so
    // the user can't kick off a second purchase before the first one's
    // VerifyPurchase response lands — that would double-charge and bug out
    // the PremiumCubit's mid-flight state.
    final anyProPending = _pendingProductIds
            .contains(ProductIds.proMonthly) ||
        _pendingProductIds.contains(ProductIds.proYearly);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: anyProPending
          ? null
          : () => _purchaseSubscription(productId, '$title plan'),
      // Fully transparent card per the clean design — the price typography,
      // savings chip, and the gradient subscribe pill carry the plan.
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (savingsLabel != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      savingsLabel,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              price,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              cadence,
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 12,
              ),
            ),
            if (trialLabel != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.card_giftcard,
                      size: 12, color: Colors.green.shade400),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      trialLabel,
                      style: TextStyle(
                        color: Colors.green.shade400,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // Gradient subscribe pill — purely visual; the whole card is the
            // tap target (outer GestureDetector). Featured plan = amber,
            // sibling = the neon cyan→magenta ramp. No borders, glow only.
            Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: isPending
                    ? null
                    : LinearGradient(
                        colors: highlight
                            ? [Colors.amber, Colors.orange.shade400]
                            : [theme.neonPrimary, theme.neonSecondary],
                      ),
                color:
                    isPending ? Colors.white.withValues(alpha: 0.08) : null,
                borderRadius: BorderRadius.circular(21),
                boxShadow: isPending
                    ? null
                    : [
                        BoxShadow(
                          color:
                              (highlight ? Colors.amber : theme.neonPrimary)
                                  .withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: isPending
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(theme.textMuted),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Verifying…',
                          style: TextStyle(
                            color: theme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'SUBSCRIBE',
                      style: TextStyle(
                        color: Color(0xFF03040A),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProActiveBanner(GameTheme theme, PremiumState premiumState) {
    // Promo trials (welcome bonus / app-wide giveaway) get amber-orange
    // theming + a TRIAL chip + a convert CTA so the user knows this is a
    // limited window and there's an action they can take. Paid Pro keeps
    // the original green/teal "verified" treatment.
    final isPromo = premiumState.isOnPromo;
    final expiry = isPromo
        ? premiumState.promoExpiresAt
        : premiumState.subscriptionExpiry;
    final gradientColors = isPromo
        ? [
            Colors.amber.withValues(alpha: 0.22),
            Colors.orange.withValues(alpha: 0.12),
          ]
        : [
            Colors.green.withValues(alpha: 0.18),
            Colors.teal.withValues(alpha: 0.10),
          ];
    final iconGradient = isPromo
        ? const LinearGradient(colors: [Colors.amber, Colors.orange])
        : const LinearGradient(colors: [Colors.green, Colors.teal]);
    final icon = isPromo ? Icons.card_giftcard : Icons.verified;
    final title = isPromo ? "You're on a free Pro trial!" : "You're Pro!";
    final expiryLabel = isPromo
        ? (expiry != null ? _formatPromoCountdown(expiry) : 'Free 3-day trial')
        : (expiry != null ? 'Renews ${_formatDate(expiry)}' : null);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: iconGradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPromo) ...[
                          const SizedBox(width: 8),
                          _buildTrialBadge(),
                        ],
                      ],
                    ),
                    if (expiryLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        expiryLabel,
                        style: TextStyle(
                          color: theme.textMuted,
                          fontSize: 12,
                          fontWeight: isPromo ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (isPromo) ...[
            const SizedBox(height: 14),
            // Convert CTA — single tap straight into the plan picker. The
            // tab swap happens in-screen so the user doesn't lose context.
            NeonButton(
              expand: true,
              theme: theme,
              icon: Icons.workspace_premium,
              label: 'Keep Pro — Subscribe',
              onPressed: () {
                // Tap inside the Pro tab — toggle the "free trial active"
                // state away so the plan cards become visible (the Pro
                // tab's active-banner branch hides the plan cards).
                // Simplest: scroll the user's attention by showing a
                // dialog explaining their conversion options, OR just
                // route through the existing Pro plan purchase via the
                // monthly default. We'll fire the monthly purchase to
                // keep the path consistent with the Subscribe button.
                _purchaseSubscription(
                  ProductIds.proMonthly,
                  'Pro Monthly',
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrialBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.amber, Colors.orange],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.6),
            blurRadius: 6,
          ),
        ],
      ),
      child: const Text(
        'TRIAL',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  /// Human-friendly countdown for promo expiry — "Ends in 2d 5h" / "Ends in
  /// 14h 20m" / "Ends in 32m" / "Ending soon". Negative durations
  /// (race between sync + revoke job) fall back to "Ending soon".
  String _formatPromoCountdown(DateTime expiry) {
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative || remaining.inMinutes <= 0) {
      return 'Ending soon';
    }
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final minutes = remaining.inMinutes.remainder(60);
    if (days > 0) return 'Ends in ${days}d ${hours}h';
    if (hours > 0) return 'Ends in ${hours}h ${minutes}m';
    return 'Ends in ${minutes}m';
  }

  Widget _buildProFeatureGrid(GameTheme theme) {
    // Honest list — every line maps to an entitlement that's actually
    // granted. 'No ads' is now real: AdService is Pro-gated so Pro/trial
    // users never see banners, interstitials, or rewarded offers. (The old
    // 'Exclusive Game Modes' / vague 'Power-up perks' promises were removed
    // as unimplemented.)
    final features = const [
      (Icons.block, 'No ads — play completely ad-free'),
      (Icons.color_lens, 'All 6 premium themes'),
      (Icons.rocket_launch, 'All 11 premium ship skins'),
      (Icons.gradient, 'All 11 premium trail effects'),
      (Icons.monetization_on, '2× coin earnings'),
      (Icons.flash_on, '5× premium power-ups every cycle'),
      (Icons.emoji_events, 'Bronze + Silver + Gold tournament entries each cycle'),
      (Icons.workspace_premium, 'Battle Pass Premium track every season'),
    ];
    return Column(
      children: features
          .map(
            (f) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(f.$1, color: theme.accentColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f.$2,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.check_circle,
                    color: Colors.green.withValues(alpha: 0.8),
                    size: 18,
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Anonymous (guest) users can't make purchases — every paid path on this
  /// screen funnels through this check. On block we show the upgrade sheet;
  /// the caller bails so the user can re-tap Buy after they link an account.
  Future<bool> _ensurePurchasable() async {
    final user = context.read<AuthCubit>().state.user;
    if (user == null || !user.isAnonymous) return true;
    await showAccountUpgradeSheet(context);
    return false;
  }

  Future<void> _purchaseSubscription(String productId, String displayName) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    // Mark pending up-front so the plan cards swap to a "Verifying…" state
    // covering the ~2–15s window between Play Store confirmation and the
    // backend's VerifyPurchase response landing in PremiumCubit. Auto-cleared
    // by _reconcilePendingPurchases when hasPremium flips true, or by the
    // 45s safety timeout in _markPending if the webhook is genuinely lost.
    _markPending(productId);
    try {
      await PurchaseService().purchaseProduct(productId);
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Initiating $displayName purchase...'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      // Failure path — drop the pending state immediately so the user can
      // retry without waiting for the 45s safety timeout.
      if (mounted) {
        setState(() => _pendingProductIds.remove(productId));
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content:
                Text('Subscription not available. Please try again later.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // COINS TAB
  // ===========================================================================

  Widget _buildCoinsTab(GameTheme theme, CoinsState coinsState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BUY STAR COINS',
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 16),
          ...CoinPurchaseOption.availableOptions.map(
            (option) => _buildCoinPackCard(option, theme),
          ),
          const SizedBox(height: 24),
          Text(
            'EARN FREE COINS',
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 16),
          // Rewarded ad — self-hides for Pro / when no ad is available.
          RewardedCoinsButton(theme: theme),
          _buildEarnMethodCard(
            'Play Games',
            '5 coins per game',
            Icons.games,
            theme,
          ),
          _buildEarnMethodCard(
            'Daily Login',
            '10-50 coins daily',
            Icons.calendar_today,
            theme,
          ),
          _buildEarnMethodCard(
            'Achievements',
            '25-100 coins',
            Icons.emoji_events,
            theme,
          ),
          _buildEarnMethodCard(
            'Tournaments',
            '100+ coins',
            Icons.leaderboard,
            theme,
          ),
        ],
      ),
    );
  }

  Future<void> _purchaseCoinPack(
      CoinPurchaseOption option, GameTheme theme) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final price = PurchaseService().getStorePriceOrDefault(
        ProductIds.withPrefix(option.id), option.price);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Buy ${option.name}'),
        content: Text('Purchase ${option.displayCoins} for $price?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final navigator = Navigator.of(dialogContext);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              navigator.pop();
              try {
                await PurchaseService()
                    .purchaseProduct(ProductIds.withPrefix(option.id));
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content:
                          Text('Initiating purchase for ${option.name}...'),
                      backgroundColor: theme.accentColor,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Product not available. Please try again later.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text('Buy - $price'),
          ),
        ],
      ),
    );
  }

  Widget _buildCoinPackCard(CoinPurchaseOption option, GameTheme theme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _purchaseCoinPack(option, theme),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.amber.withValues(alpha: 0.15),
              Colors.orange.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber, Colors.orange],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.monetization_on,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        option.name,
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (option.isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'POPULAR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    option.displayCoins,
                    style: TextStyle(
                      color: theme.textMuted,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              PurchaseService().getStorePriceOrDefault(
                  ProductIds.withPrefix(option.id), option.price),
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEarnMethodCard(
    String title,
    String reward,
    IconData icon,
    GameTheme theme,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: theme.accentColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            reward,
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // THEMES TAB
  // ===========================================================================

  /// Banner atop the cosmetic tabs (themes / skins / trails) telling the user
  /// a Pro subscription unlocks everything in that tab. Tapping it (when not
  /// already Pro) jumps to the Pro tab. Power-Ups are intentionally excluded —
  /// Pro doesn't unlock the power-up catalog.
  Widget _buildProIncludedBanner(
    GameTheme theme,
    PremiumState premiumState,
    String itemNoun,
  ) {
    final isPro = premiumState.hasPremium;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isPro ? null : () => _tabController.animateTo(0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.purple.shade400.withValues(alpha: 0.22),
              Colors.indigo.shade400.withValues(alpha: 0.14),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(isPro ? Icons.check_circle : Icons.diamond,
                color: Colors.purple.shade200, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isPro
                        ? 'Unlocked with Pro'
                        : 'Included with Cosmo Strike Pro',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isPro
                        ? 'Every $itemNoun here is yours with your subscription.'
                        : 'Subscribe to Pro to unlock every $itemNoun here — no separate purchase needed.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (!isPro)
              Icon(Icons.chevron_right,
                  color: Colors.white.withValues(alpha: 0.7), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildThemesTab(GameTheme theme, PremiumState premiumState) {
    // Premium themes — listed as products in the Play Store catalog.
    const premiumThemes = [
      GameTheme.crystal,
      GameTheme.cyberpunk,
      GameTheme.space,
      GameTheme.ocean,
      GameTheme.desert,
      GameTheme.forest,
    ];
    // Free themes — included with every install. Surfaced here so the
    // user has an obvious way to switch back to their previous theme
    // after trying a premium one. The home/settings theme selector
    // still works, but this tab is the canonical store + switcher.
    const freeThemes = [
      GameTheme.classic,
      GameTheme.modern,
      GameTheme.neon,
      GameTheme.retro,
    ];

    // Once a pending purchase reflects as owned, drop it from the pending
    // set on the next frame so we don't trigger a build-during-build.
    _reconcilePendingPurchases(premiumState);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProIncludedBanner(theme, premiumState, 'theme'),
          const SizedBox(height: 16),
          _buildThemesBundleCard(theme, premiumState),
          const SizedBox(height: 20),
          Text(
            'PREMIUM THEMES',
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          // Horizontal-row list layout — replaces the grid that was
          // leaving dead space below each card. One row per theme is
          // more readable and packs more info per pixel of vertical
          // space.
          for (final t in premiumThemes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildThemeRow(t, theme, premiumState),
            ),
          const SizedBox(height: 18),
          Text(
            'FREE THEMES',
            style: TextStyle(
              color: theme.accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Always available — switch back any time.',
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          for (final t in freeThemes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildThemeRow(t, theme, premiumState),
            ),
        ],
      ),
    );
  }

  /// Drop any pendingProductIds that the backend now reports as owned.
  /// Scheduled post-frame to avoid setState-during-build crashes.
  void _reconcilePendingPurchases(PremiumState premiumState) {
    if (_pendingProductIds.isEmpty) return;
    final justOwned = <String>[];
    for (final productId in _pendingProductIds) {
      if (_isProductOwned(productId, premiumState)) {
        justOwned.add(productId);
      }
    }
    if (justOwned.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _pendingProductIds.removeAll(justOwned));
    });
  }

  /// Resolve "is this productId now owned" across themes / skins / trails /
  /// bundles so the pending spinner clears regardless of the cosmetic type.
  bool _isProductOwned(String productId, PremiumState premiumState) {
    // Pro subscription SKUs — once PremiumCubit flips to hasPremium=true the
    // Pro tab swaps to the "you are Pro" banner, but we also clear pending
    // so any leftover spinner state doesn't survive a tab switch.
    if (productId == ProductIds.proMonthly ||
        productId == ProductIds.proYearly) {
      return premiumState.hasPremium;
    }
    // Themes — including the all-themes bundle. Pro subscribers also have
    // all premium themes implicitly.
    if (productId == ProductIds.themesBundle) {
      return premiumState.isBundleOwned('premium_themes_bundle');
    }
    for (final t in GameTheme.values) {
      if (_productIdForTheme(t) == productId) {
        return premiumState.isThemeUnlocked(t);
      }
    }
    // Skins: store ID is `${prefix}skin_<id>`
    final stripped = productId.startsWith(ProductIds.prefix)
        ? productId.substring(ProductIds.prefix.length)
        : productId;
    if (stripped.startsWith('skin_')) {
      return premiumState.isSkinOwned(stripped.substring('skin_'.length));
    }
    // Trails: store ID is `${prefix}trail_<id>` — kept with the prefix in
    // PremiumState.ownedTrails per the existing convention.
    if (stripped.startsWith('trail_')) {
      return premiumState.isTrailOwned(stripped);
    }
    // Cosmetic bundles (starter_pack etc.) — owned set uses bare ID.
    return premiumState.isBundleOwned(stripped);
  }

  Widget _buildThemesBundleCard(GameTheme theme, PremiumState premiumState) {
    final bundleOwned = premiumState.isBundleOwned('premium_themes_bundle');
    final isPending = _pendingProductIds.contains(ProductIds.themesBundle);
    final price = PurchaseService().getStorePriceOrDefault(
      ProductIds.themesBundle,
      7.99,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: (bundleOwned || isPending)
          ? null
          : () => _purchaseThemeProduct(
                ProductIds.themesBundle,
                'All Themes Bundle',
              ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.purple.shade400.withValues(alpha: 0.18),
              Colors.indigo.shade400.withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade400, Colors.indigo.shade400],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  const Icon(Icons.card_giftcard, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All Themes Bundle',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'All 6 premium themes · save 33%',
                    style: TextStyle(
                      color: theme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _buildBundleStatusPill(
              isOwned: bundleOwned,
              isPending: isPending,
              priceLabel: price,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBundleStatusPill({
    required bool isOwned,
    required bool isPending,
    required String priceLabel,
  }) {
    if (isPending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blueGrey,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 6),
            Text(
              'VERIFYING',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isOwned ? Colors.green : Colors.amber,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        isOwned ? 'OWNED' : priceLabel,
        style: TextStyle(
          color: isOwned ? Colors.white : Colors.black,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildThemeRow(
    GameTheme target,
    GameTheme currentTheme,
    PremiumState premiumState,
  ) {
    final isOwned = premiumState.isThemeUnlocked(target);
    final isActive = currentTheme == target;
    final productId = _productIdForTheme(target);
    final isPending =
        productId != null && _pendingProductIds.contains(productId);
    final price = productId == null
        ? 'FREE'
        : PurchaseService().getStorePriceOrDefault(productId, 1.99);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isPending
          ? null
          : () {
              if (isOwned) {
                context.read<ThemeCubit>().setTheme(target);
              } else if (productId != null) {
                _purchaseThemeProduct(productId, target.name);
              }
            },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: currentTheme.accentColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          // Active theme reads through a soft accent glow (plus the
          // ACTIVE pill) instead of an outline.
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: currentTheme.accentColor.withValues(alpha: 0.25),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Preview swatch — fixed height row makes this a small
            // landscape rectangle, plenty of pixels for the painter
            // without a tall card.
            SizedBox(
              width: 84,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _ThemePreview(theme: target),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    target.name,
                    style: TextStyle(
                      color: currentTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _shortThemeDescription(target),
                    style: TextStyle(
                      color: currentTheme.textMuted,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _buildStatusPill(
              currentTheme: currentTheme,
              isActive: isActive,
              isOwned: isOwned,
              isPending: isPending,
              fallbackPriceLabel: price,
            ),
          ],
        ),
      ),
    );
  }

  String _shortThemeDescription(GameTheme target) {
    switch (target) {
      case GameTheme.classic:
        return 'The original look';
      case GameTheme.modern:
        return 'Clean and minimal';
      case GameTheme.neon:
        return 'Glowing neon nights';
      case GameTheme.retro:
        return '80s neon arcade';
      case GameTheme.space:
        return 'Cosmic starfield';
      case GameTheme.ocean:
        return 'Deep-sea blues';
      case GameTheme.cyberpunk:
        return 'Electric cyan & pink';
      case GameTheme.forest:
        return 'Vivid emerald jungle';
      case GameTheme.desert:
        return 'Canyon + cactus teal';
      case GameTheme.crystal:
        return 'Icy crystalline blue';
    }
  }

  /// The bottom-of-card pill that toggles between ACTIVE / APPLY / price /
  /// VERIFYING (with spinner). Centralized so the bundle card and theme
  /// cards stay visually consistent.
  Widget _buildStatusPill({
    required GameTheme currentTheme,
    required bool isActive,
    required bool isOwned,
    required bool isPending,
    required String fallbackPriceLabel,
  }) {
    final Color background;
    final Color foreground;
    Widget child;
    if (isPending) {
      background = Colors.blueGrey;
      foreground = Colors.white;
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(foreground),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'VERIFYING',
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    } else if (isActive) {
      background = currentTheme.accentColor;
      foreground = currentTheme.backgroundColor;
      child = Text(
        'ACTIVE',
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
    } else if (isOwned) {
      background = Colors.green;
      foreground = Colors.white;
      child = Text(
        'APPLY',
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
    } else {
      background = Colors.amber;
      foreground = Colors.black;
      child = Text(
        fallbackPriceLabel,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  String? _productIdForTheme(GameTheme target) {
    switch (target) {
      case GameTheme.crystal:
        return ProductIds.crystalTheme;
      case GameTheme.cyberpunk:
        return ProductIds.cyberpunkTheme;
      case GameTheme.space:
        return ProductIds.spaceTheme;
      case GameTheme.ocean:
        return ProductIds.oceanTheme;
      case GameTheme.desert:
        return ProductIds.desertTheme;
      case GameTheme.forest:
        return ProductIds.forestTheme;
      default:
        return null;
    }
  }

  Future<void> _purchaseThemeProduct(String productId, String displayName) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final theme = context.read<ThemeCubit>().state.currentTheme;
    final price = PurchaseService().getStorePriceOrDefault(productId, 1.99);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.color_lens, color: theme.accentColor),
            const SizedBox(width: 8),
            Text(displayName, style: TextStyle(color: theme.accentColor)),
          ],
        ),
        content: Text(
          'Unlock $displayName for $price?',
          style: TextStyle(color: theme.accentColor.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Buy - $price'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await PurchaseService().purchaseProduct(productId);
      if (!mounted) return;
      _markPending(productId);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Verifying $displayName purchase…'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Theme not available. Please try again later.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Mark a productId as "purchase pending" so its card shows the
  /// verifying spinner. Auto-cleared once ownership reflects in
  /// PremiumState (see _reconcilePendingPurchases), or after 45s as a
  /// safety net so a dropped Play Store callback doesn't leave the UI
  /// stuck in a verifying state forever.
  void _markPending(String productId) {
    setState(() => _pendingProductIds.add(productId));
    Future.delayed(const Duration(seconds: 45), () {
      if (!mounted) return;
      if (!_pendingProductIds.contains(productId)) return;
      setState(() => _pendingProductIds.remove(productId));
    });
  }

  // ===========================================================================
  // SKINS TAB
  // ===========================================================================

  Widget _buildSkinsTab(GameTheme theme, PremiumState premiumState) {
    _reconcilePendingPurchases(premiumState);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildProIncludedBanner(theme, premiumState, 'skin'),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              // Match the Trails tab aspect ratio so the painted preview
              // band has room to render the ship silhouette + signature.
              childAspectRatio: 0.78,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: ShipSkinType.values.length,
      itemBuilder: (context, index) {
        final skin = ShipSkinType.values[index];
        // Pro subscription unlocks all premium skins (mirrors theme bundling).
        final isUnlocked = premiumState.isSkinUnlocked(skin);
        final isSelected = premiumState.selectedSkinId == skin.id;
        final productId = ProductIds.skinStoreId(skin.id);
        return _buildSkinCard(
          skin: skin,
          isUnlocked: isUnlocked,
          isSelected: isSelected,
          isPending: _pendingProductIds.contains(productId),
          price: skin.isPremium
              ? PurchaseService()
                  .getStorePriceOrDefault(productId, skin.price)
              : 'FREE',
          theme: theme,
          onTap: () {
            if (isUnlocked) {
              context.read<PremiumCubit>().selectSkin(skin.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${skin.displayName} equipped'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 1),
                ),
              );
            } else {
              _purchaseCosmetic(
                productId: productId,
                displayName: skin.displayName,
                fallbackPrice: skin.price,
              );
            }
          },
        );
      },
          ),
        ),
      ],
    );
  }

  /// Modernized skin card — mirrors the Trails tab redesign. Each card
  /// paints a small ship-silhouette preview using the skin's actual
  /// colors and its per-skin signature (golden shimmer, fire embers,
  /// galaxy stars, etc.) so users see what the skin will look like
  /// in-game without leaving the store.
  Widget _buildSkinCard({
    required ShipSkinType skin,
    required bool isUnlocked,
    required bool isSelected,
    required bool isPending,
    required String price,
    required GameTheme theme,
    required VoidCallback onTap,
  }) {
    final palette = skin.colors.isNotEmpty
        ? skin.colors
        : [
            theme.shipColor,
            theme.shipColor.withValues(alpha: 0.6),
          ];
    final headerStart = palette.first.withValues(alpha: 0.85);
    final headerEnd = palette.last.withValues(alpha: 0.35);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isPending ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: theme.backgroundColor.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          // Selected skin reads through the accent glow alone — no outline.
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.accentColor.withValues(alpha: 0.30),
                    blurRadius: 14,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview band — painted ship silhouette with the skin's
            // own colors + a stylized signature so each skin reads
            // instantly distinct from its grid neighbors.
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [headerStart, headerEnd],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.6, -0.6),
                          radius: 1.0,
                          colors: [
                            Colors.white.withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    CustomPaint(
                      painter: _SkinPreviewPainter(
                        skin: skin,
                        accentColor: theme.accentColor,
                      ),
                    ),
                    if (!isUnlocked && skin.isPremium)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.lock,
                                  color: Colors.white, size: 11),
                              SizedBox(width: 4),
                              Text(
                                'PRO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    skin.displayName,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    skin.description,
                    style: TextStyle(
                      color: theme.textMuted,
                      fontSize: 10,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _buildCosmeticStatusPill(
                    theme: theme,
                    isSelected: isSelected,
                    isUnlocked: isUnlocked,
                    isPending: isPending,
                    priceLabel: price,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TRAILS TAB
  // ===========================================================================

  Widget _buildTrailsTab(GameTheme theme, PremiumState premiumState) {
    _reconcilePendingPurchases(premiumState);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildProIncludedBanner(theme, premiumState, 'trail'),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              // Slightly more vertical room than the skins tab so the painted
              // trail preview has space to breathe.
              childAspectRatio: 0.78,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: TrailEffectType.values.length,
      itemBuilder: (context, index) {
        final trail = TrailEffectType.values[index];
        // Pro subscription unlocks all premium trails (mirrors theme bundling).
        final isUnlocked = premiumState.isTrailUnlocked(trail);
        final isSelected = premiumState.selectedTrailId == trail.id;
        final productId = ProductIds.withPrefix(trail.id);
        return _buildTrailCard(
          trail: trail,
          isUnlocked: isUnlocked,
          isSelected: isSelected,
          isPending: _pendingProductIds.contains(productId),
          price: trail.isPremium
              ? PurchaseService()
                  .getStorePriceOrDefault(productId, trail.price)
              : 'FREE',
          theme: theme,
          onTap: () {
            if (isUnlocked) {
              context.read<PremiumCubit>().selectTrail(trail.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${trail.displayName} equipped'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 1),
                ),
              );
            } else {
              _purchaseCosmetic(
                productId: productId,
                displayName: trail.displayName,
                fallbackPrice: trail.price,
              );
            }
          },
        );
      },
          ),
        ),
      ],
    );
  }

  /// Modernized trail card — replaces the generic emoji-in-circle layout
  /// for the Trails tab. Each card paints a custom preview that uses the
  /// trail's actual colors and a type-specific signature (sparkles for
  /// particle, lightning for electric, flames for fire, etc.) so the
  /// twelve trails read as visually distinct at a glance rather than
  /// twelve near-identical chip variations.
  Widget _buildTrailCard({
    required TrailEffectType trail,
    required bool isUnlocked,
    required bool isSelected,
    required bool isPending,
    required String price,
    required GameTheme theme,
    required VoidCallback onTap,
  }) {
    // Header palette for the gradient backdrop. Use the trail's own
    // colors when it has them; fall back to theme accent for the
    // "No Trail" entry.
    final palette = trail.colors.isNotEmpty
        ? trail.colors
        : [
            theme.accentColor.withValues(alpha: 0.35),
            theme.backgroundColor.withValues(alpha: 0.6),
          ];
    final headerStart = palette.first.withValues(alpha: 0.85);
    final headerEnd = palette.last.withValues(alpha: 0.35);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isPending ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: theme.backgroundColor.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          // Soft outer glow for the active trail so the selection state
          // pops without an outline or flooding the surrounding grid.
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.accentColor.withValues(alpha: 0.30),
                    blurRadius: 14,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview band — custom-painted trail signature on a
            // gradient backdrop pulled from the trail's color palette.
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [headerStart, headerEnd],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Faint radial highlight that gives every card a
                    // shared "lit from upper-left" feel and prevents
                    // dark palettes (shadow) from looking flat.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-0.6, -0.6),
                          radius: 1.0,
                          colors: [
                            Colors.white.withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    CustomPaint(
                      painter: _TrailPreviewPainter(
                        trail: trail,
                        accentColor: theme.accentColor,
                      ),
                    ),
                    if (!isUnlocked && trail.isPremium)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.lock,
                                  color: Colors.white, size: 11),
                              SizedBox(width: 4),
                              Text(
                                'PRO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Info plate underneath — name, one-line description, status pill.
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    trail.displayName,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    trail.description,
                    style: TextStyle(
                      color: theme.textMuted,
                      fontSize: 10,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _buildCosmeticStatusPill(
                    theme: theme,
                    isSelected: isSelected,
                    isUnlocked: isUnlocked,
                    isPending: isPending,
                    priceLabel: price,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCosmeticStatusPill({
    required GameTheme theme,
    required bool isSelected,
    required bool isUnlocked,
    required bool isPending,
    required String priceLabel,
  }) {
    if (isPending) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.blueGrey,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(
                strokeWidth: 1.3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 4),
            Text(
              'VERIFYING',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.accentColor
            : isUnlocked
                ? Colors.green
                : Colors.amber,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isSelected
            ? 'EQUIPPED'
            : isUnlocked
                ? 'EQUIP'
                : priceLabel,
        style: TextStyle(
          color: isSelected
              ? theme.backgroundColor
              : isUnlocked
                  ? Colors.white
                  : Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _purchaseCosmetic({
    required String productId,
    required String displayName,
    required double fallbackPrice,
  }) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final theme = context.read<ThemeCubit>().state.currentTheme;
    final price =
        PurchaseService().getStorePriceOrDefault(productId, fallbackPrice);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(Icons.shopping_cart, color: theme.accentColor),
            const SizedBox(width: 8),
            Text(displayName, style: TextStyle(color: theme.accentColor)),
          ],
        ),
        content: Text(
          'Unlock $displayName for $price?',
          style: TextStyle(color: theme.accentColor.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Buy - $price'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await PurchaseService().purchaseProduct(productId);
      if (!mounted) return;
      _markPending(productId);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Verifying $displayName purchase…'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Item not available. Please try again later.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ===========================================================================
  // POWER-UPS TAB
  // ===========================================================================
  // Power-ups now have a real coin-purchased inventory backed by the
  // /api/v1/PowerUps/{inventory,purchase,consume} endpoints. The 4 types
  // here match the PowerUpType enum used by the gameplay engine, so each
  // purchase produces a usable stockpile entry (activation UI lands in a
  // follow-up — for now the inventory accrues server-side and the user
  // can see their count).

  /// Rewarded-ad card granting one free Speed Boost. Self-hides for Pro /
  /// web / when the SDK isn't ready; disables when no ad is loaded.
  Widget _buildFreePowerUpAdCard(BuildContext context, GameTheme theme) {
    final ads = getIt.isRegistered<AdService>() ? getIt<AdService>() : null;
    if (ads == null || !ads.adsEnabled) return const SizedBox.shrink();
    final ready = ads.isRewardedReady;
    return Opacity(
      opacity: ready ? 1 : 0.5,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ready
            ? () {
                final powerUps = context.read<PowerUpCubit>();
                ads.showRewarded(onReward: powerUps.grantFreePowerUp);
              }
            : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              theme.accentColor.withValues(alpha: 0.14),
              theme.foodColor.withValues(alpha: 0.08),
            ]),
            borderRadius: BorderRadius.circular(16),
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
                      'Watch an ad — free Speed Boost',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ready
                          ? 'Adds 1 Speed Boost to your loadout'
                          : 'No ad available right now',
                      style: TextStyle(
                        color: theme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.bolt,
                  color: theme.accentColor.withValues(alpha: 0.9), size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPowerUpsTab(
    GameTheme theme,
    PremiumState premiumState,
    CoinsState coinsState,
  ) {
    // Power-up types use snake_case to match the JSON dictionary keys
    // returned by the backend (ASP.NET applies DictionaryKeyPolicy =
    // SnakeCaseLower to outgoing dicts). Mapping back to PowerUpType for
    // activation lives in the game cubit (next commit).
    // Coin costs MUST match PurchasePowerUpWithCoinsCommandHandler.AllowedCosts
    // on the backend — server rejects request.CoinCost mismatches outright.
    final powerUps = const [
      _PowerUpCatalogItem(
        type: 'speed_boost',
        name: 'Speed Boost',
        description: "Boosts your ship's fire rate for 7 seconds.",
        icon: Icons.speed,
        coinCost: 500,
      ),
      _PowerUpCatalogItem(
        type: 'invincibility',
        name: 'Invincibility',
        description: 'Pass through walls and yourself for 6 seconds.',
        icon: Icons.shield,
        coinCost: 1000,
      ),
      _PowerUpCatalogItem(
        type: 'score_multiplier',
        name: 'Score Multiplier',
        description: 'Double points for 10 seconds.',
        icon: Icons.star,
        coinCost: 750,
      ),
      _PowerUpCatalogItem(
        type: 'slow_motion',
        name: 'Slow Motion',
        description: 'Slows the game for precision (8 seconds).',
        icon: Icons.slow_motion_video,
        coinCost: 500,
      ),
    ];

    return BlocBuilder<PowerUpCubit, PowerUpState>(
      builder: (context, powerUpState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: theme.accentColor, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Buy with coins, then arm one from the home screen '
                        'loadout chip — it activates 5s into your next game.',
                        style: TextStyle(
                          color: theme.textMuted,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Rewarded ad — free Speed Boost. Self-hides for Pro / no ad.
              _buildFreePowerUpAdCard(context, theme),
              Text(
                'POWER-UPS',
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 12),
              ...powerUps.map(
                (p) => _buildPowerUpCatalogCard(p, theme, powerUpState),
              ),
              const SizedBox(height: 24),
              Text(
                'POWER-UP BUNDLES',
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Unlock multiple power-up types at a discount.',
                style: TextStyle(
                  color: theme.textMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              ...PowerUpBundle.availableBundles.map(
                (bundle) => _buildPowerUpBundleCard(
                    bundle, theme, premiumState, coinsState),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPowerUpCatalogCard(
    _PowerUpCatalogItem item,
    GameTheme theme,
    PowerUpState powerUpState,
  ) {
    final owned = powerUpState.countFor(item.type);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: theme.accentColor, size: 22),
              ),
              if (owned > 0)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'x$owned',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: TextStyle(
                    color: theme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _purchasePowerUpWithCoins(item, theme),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor.withValues(alpha: 0.85),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monetization_on,
                    size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  '${item.coinCost}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _purchasePowerUpWithCoins(
      _PowerUpCatalogItem item, GameTheme theme) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final coinsCubit = context.read<CoinsCubit>();
    final powerUpCubit = context.read<PowerUpCubit>();
    final coinsBalance = coinsCubit.state.balance.total;
    if (coinsBalance < item.coinCost) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Insufficient coins!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(item.icon, color: theme.accentColor),
            const SizedBox(width: 8),
            Text(item.name, style: TextStyle(color: theme.accentColor)),
          ],
        ),
        content: Text(
          'Buy 1 ${item.name} for ${item.coinCost} coins?',
          style: TextStyle(color: theme.accentColor.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Buy - ${item.coinCost} coins'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final newBalance =
        await powerUpCubit.purchaseWithCoins(item.type, item.coinCost);
    if (!mounted) return;
    if (newBalance == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Purchase failed. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // Reflect the server-authoritative coin balance locally so the
    // CoinsCubit and any other UI stays in sync without an extra round-trip.
    await coinsCubit.setServerBalance(newBalance);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('${item.name} added to your loadout!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildPowerUpBundleCard(
    PowerUpBundle bundle,
    GameTheme theme,
    PremiumState premiumState,
    CoinsState coinsState,
  ) {
    final isOwned = premiumState.isBundleOwned(bundle.id);
    final canAfford = coinsState.balance.total >= bundle.bundlePrice;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.withValues(alpha: 0.14),
            Colors.indigo.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.purple, Colors.indigo],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(bundle.icon, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bundle.name,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bundle.description,
                      style: TextStyle(
                        color: theme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: bundle.powerUps
                .map(
                  (p) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${p.icon} ${p.displayName}',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (bundle.originalPrice > bundle.bundlePrice)
                Text(
                  '${bundle.originalPrice.toInt()} coins',
                  style: TextStyle(
                    color: theme.textMuted,
                    fontSize: 12,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                '${bundle.bundlePrice.toInt()} coins',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: isOwned
                    ? null
                    : () => _purchaseCoinBundle(bundle, canAfford),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isOwned
                      ? Colors.green
                      : canAfford
                          ? theme.primaryColor
                          : Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(isOwned
                    ? 'OWNED'
                    : canAfford
                        ? 'BUY'
                        : 'NEED COINS'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _purchaseCoinBundle(PowerUpBundle bundle, bool canAfford) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!canAfford) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Insufficient coins!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // Server-authoritative purchase. Backend looks up the bundle in
    // ProductCatalog.PowerUpBundles, atomically debits coins, and increments
    // PowerUpInventory. We rely on the server response — no local coin spend.
    final coinsCubit = context.read<CoinsCubit>();
    final powerUpCubit = context.read<PowerUpCubit>();
    final newBalance = await powerUpCubit.purchaseBundleWithCoins(bundle.id);
    if (!mounted) return;
    if (newBalance == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Purchase failed. Try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // Mark the bundle owned locally so the UI swaps to the "owned" state;
    // server doesn't track set-membership for power-up bundles (it tracks
    // consumable counts in PowerUpInventory), so we keep this flag client-side.
    await context.read<PremiumCubit>().unlockBundle(bundle.id);
    await coinsCubit.setServerBalance(newBalance);
    if (!mounted) return;
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('${bundle.name} unlocked!'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

// =============================================================================
// Helpers
// =============================================================================

class _ThemePreview extends StatelessWidget {
  final GameTheme theme;
  const _ThemePreview({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.backgroundColor,
            theme.backgroundColor.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Faint grid hint
          Positioned.fill(
            child: CustomPaint(
              painter: _ThemePreviewPainter(theme: theme),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePreviewPainter extends CustomPainter {
  final GameTheme theme;
  _ThemePreviewPainter({required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = theme.accentColor.withValues(alpha: 0.18)
      ..strokeWidth = 0.6;
    // 6×6 grid + a longer 6-segment coiled ship + 2 food items. Denser
    // than the original 8×8/4-segment preview so the card visibly
    // represents "ship game" rather than a near-empty backdrop.
    const cells = 6;
    final cellW = size.width / cells;
    final cellH = size.height / cells;
    for (int i = 1; i < cells; i++) {
      canvas.drawLine(
        Offset(cellW * i, 0),
        Offset(cellW * i, size.height),
        gridPaint,
      );
      canvas.drawLine(
        Offset(0, cellH * i),
        Offset(size.width, cellH * i),
        gridPaint,
      );
    }

    // Coiled ship path (head → tail). Index 0 is the head.
    const shipCells = <(int, int)>[
      (4, 2), (3, 2), (2, 2), (2, 3), (2, 4), (3, 4),
    ];
    final r = (cellW < cellH ? cellW : cellH) * 0.40;
    for (int i = 0; i < shipCells.length; i++) {
      final fade = 1.0 - (i / shipCells.length) * 0.55;
      final paint = Paint()
        ..color = theme.shipColor.withValues(alpha: fade);
      final (col, row) = shipCells[i];
      canvas.drawCircle(
        Offset(cellW * col + cellW / 2, cellH * row + cellH / 2),
        i == 0 ? r * 1.05 : r,
        paint,
      );
    }
    // Head highlight — small accent dot so the head is unmistakable.
    canvas.drawCircle(
      Offset(cellW * 4 + cellW / 2, cellH * 2 + cellH / 2),
      r * 0.30,
      Paint()..color = theme.accentColor,
    );

    // Two food pickups to fill the empty quadrants.
    final foodPaint = Paint()..color = theme.foodColor;
    for (final (col, row) in const <(int, int)>[(0, 0), (5, 4)]) {
      canvas.drawCircle(
        Offset(cellW * col + cellW / 2, cellH * row + cellH / 2),
        r * 0.85,
        foodPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ThemePreviewPainter old) =>
      old.theme != theme;
}

class _PowerUpCatalogItem {
  final String type;
  final String name;
  final String description;
  final IconData icon;
  final int coinCost;
  const _PowerUpCatalogItem({
    required this.type,
    required this.name,
    required this.description,
    required this.icon,
    required this.coinCost,
  });
}

/// Paints a stylized ship-trail preview specific to each trail type.
/// The shared element is a 5-segment serpentine head with a fading
/// tail; the per-trail signature (sparkles, lightning, flame, stars,
/// crystal facets, etc.) draws on top using the trail's own color
/// palette. The painter never animates — these are still previews —
/// but the geometric variation is rich enough to make twelve trails
/// visually distinct at glance.
class _TrailPreviewPainter extends CustomPainter {
  final TrailEffectType trail;
  final Color accentColor;

  _TrailPreviewPainter({required this.trail, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final palette = trail.colors;

    // 5-segment serpentine head, curving down-right across the card.
    // Coordinates are normalized inside the preview band so the
    // composition stays consistent across grid cell sizes.
    final segmentCenters = <Offset>[
      Offset(width * 0.18, height * 0.62), // tail
      Offset(width * 0.34, height * 0.52),
      Offset(width * 0.50, height * 0.45),
      Offset(width * 0.66, height * 0.42),
      Offset(width * 0.82, height * 0.45), // head
    ];
    final segmentRadius = (width < height ? width : height) * 0.08;

    // Trail-specific overlays — drawn BEHIND the ship so the head
    // reads cleanly on top.
    switch (trail) {
      case TrailEffectType.none:
        // Empty band, just the base gradient backdrop.
        break;
      case TrailEffectType.particle:
        _drawSparkles(canvas, size, palette, density: 14);
        break;
      case TrailEffectType.glow:
        _drawHalos(canvas, segmentCenters, palette, segmentRadius);
        break;
      case TrailEffectType.rainbow:
        _drawRainbowArc(canvas, segmentCenters, palette, segmentRadius);
        break;
      case TrailEffectType.fire:
        _drawFlames(canvas, segmentCenters, palette);
        break;
      case TrailEffectType.electric:
        _drawLightning(canvas, segmentCenters, palette);
        break;
      case TrailEffectType.star:
        _drawStars(canvas, size, palette);
        break;
      case TrailEffectType.cosmic:
        _drawNebula(canvas, size, palette);
        break;
      case TrailEffectType.neon:
        _drawNeonGlow(canvas, segmentCenters, palette, segmentRadius);
        break;
      case TrailEffectType.shadow:
        _drawShadowSmoke(canvas, segmentCenters, palette);
        break;
      case TrailEffectType.crystal:
        _drawCrystalShards(canvas, segmentCenters, palette, segmentRadius);
        break;
      case TrailEffectType.dragon:
        _drawDragonBreath(canvas, segmentCenters, palette);
        break;
    }

    // Ship head + body. Color picked from the trail palette so the
    // ship itself reads as part of the trail's identity. Tail fades
    // by alpha so the serpentine reads directionally.
    for (var i = 0; i < segmentCenters.length; i++) {
      final t = i / (segmentCenters.length - 1);
      final color = palette.isEmpty
          ? accentColor
          : Color.lerp(palette.first, palette.last, t) ?? palette.first;
      final fade = 0.45 + 0.55 * t;
      final paint = Paint()
        ..color = color.withValues(alpha: fade)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        segmentCenters[i],
        segmentRadius * (0.7 + 0.3 * t),
        paint,
      );
    }

    // Ship-head highlight — small bright dot on the leading segment
    // so the eye picks up direction immediately.
    canvas.drawCircle(
      segmentCenters.last,
      segmentRadius * 0.25,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  // ------------- Per-trail signature helpers -------------

  void _drawSparkles(Canvas canvas, Size size, List<Color> palette,
      {required int density}) {
    final paint = Paint()
      ..color = (palette.isEmpty ? Colors.white : palette.first)
          .withValues(alpha: 0.9);
    final rng = math.Random(7);
    for (var i = 0; i < density; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final r = 0.8 + rng.nextDouble() * 1.6;
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  void _drawHalos(Canvas canvas, List<Offset> centers, List<Color> palette,
      double r) {
    for (var i = 0; i < centers.length; i++) {
      final paint = Paint()
        ..color = (palette.isEmpty
                ? Colors.cyan
                : Color.lerp(palette.first, palette.last,
                    i / centers.length)!)
            .withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(centers[i], r * 2.0, paint);
    }
  }

  void _drawRainbowArc(Canvas canvas, List<Offset> centers,
      List<Color> palette, double r) {
    if (palette.isEmpty) return;
    final path = Path()..moveTo(centers.first.dx, centers.first.dy);
    for (var i = 1; i < centers.length; i++) {
      path.lineTo(centers[i].dx, centers[i].dy);
    }
    final paint = Paint()
      ..shader = LinearGradient(
        colors: palette,
      ).createShader(
          Rect.fromPoints(centers.first, centers.last))
      ..strokeWidth = r * 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawPath(path, paint);
  }

  void _drawFlames(Canvas canvas, List<Offset> centers, List<Color> palette) {
    if (palette.length < 2) return;
    final tail = centers.first;
    for (var i = 0; i < 6; i++) {
      final t = i / 5;
      final flameTip = Offset(
        tail.dx - 10 - i * 3,
        tail.dy + 8 - i * 2.5,
      );
      final flameBase = Offset(tail.dx + (i % 2 == 0 ? -2 : 2), tail.dy);
      final path = Path()
        ..moveTo(flameBase.dx - 4, flameBase.dy + 4)
        ..quadraticBezierTo(
          flameTip.dx - 2, flameTip.dy + 4, flameTip.dx, flameTip.dy)
        ..quadraticBezierTo(
          flameTip.dx + 2, flameTip.dy + 4, flameBase.dx + 4, flameBase.dy + 4)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = Color.lerp(palette.last, palette.first, t)!
              .withValues(alpha: 0.55 - t * 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  void _drawLightning(
      Canvas canvas, List<Offset> centers, List<Color> palette) {
    if (palette.isEmpty) return;
    final paint = Paint()
      ..color = palette.first.withValues(alpha: 0.85)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    for (var i = 0; i < centers.length - 1; i++) {
      final mid = Offset(
        (centers[i].dx + centers[i + 1].dx) / 2,
        (centers[i].dy + centers[i + 1].dy) / 2 + (i.isEven ? 6 : -6),
      );
      final path = Path()
        ..moveTo(centers[i].dx, centers[i].dy)
        ..lineTo(mid.dx, mid.dy)
        ..lineTo(centers[i + 1].dx, centers[i + 1].dy);
      canvas.drawPath(path, paint);
    }
  }

  void _drawStars(Canvas canvas, Size size, List<Color> palette) {
    if (palette.isEmpty) return;
    final rng = math.Random(42);
    for (var i = 0; i < 8; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final r = 2 + rng.nextDouble() * 3;
      _drawStarGlyph(
        canvas,
        Offset(cx, cy),
        r,
        Paint()
          ..color = palette[i % palette.length]
              .withValues(alpha: 0.85),
      );
    }
  }

  void _drawStarGlyph(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final angle = (math.pi / 2) * i;
      final tip = Offset(c.dx + math.cos(angle) * r, c.dy + math.sin(angle) * r);
      final inner = Offset(
        c.dx + math.cos(angle + math.pi / 4) * r * 0.35,
        c.dy + math.sin(angle + math.pi / 4) * r * 0.35,
      );
      if (i == 0) path.moveTo(tip.dx, tip.dy);
      path.lineTo(inner.dx, inner.dy);
      if (i < 3) {
        final nextTip = Offset(
          c.dx + math.cos(angle + math.pi / 2) * r,
          c.dy + math.sin(angle + math.pi / 2) * r,
        );
        path.lineTo(nextTip.dx, nextTip.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawNebula(Canvas canvas, Size size, List<Color> palette) {
    if (palette.length < 2) return;
    for (var i = 0; i < 5; i++) {
      final rng = math.Random(i * 11);
      final c = Offset(
        rng.nextDouble() * size.width,
        rng.nextDouble() * size.height,
      );
      final paint = Paint()
        ..color = palette[i % palette.length].withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(c, 8 + rng.nextDouble() * 12, paint);
    }
  }

  void _drawNeonGlow(Canvas canvas, List<Offset> centers, List<Color> palette,
      double r) {
    if (palette.isEmpty) return;
    for (var i = 0; i < centers.length; i++) {
      final color = palette[i % palette.length];
      canvas.drawCircle(
        centers[i],
        r * 2.5,
        Paint()
          ..color = color.withValues(alpha: 0.40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
  }

  void _drawShadowSmoke(
      Canvas canvas, List<Offset> centers, List<Color> palette) {
    if (palette.isEmpty) return;
    final rng = math.Random(99);
    for (var i = 0; i < 9; i++) {
      final base = centers[i % centers.length];
      final puff = Offset(
        base.dx - rng.nextDouble() * 24,
        base.dy + (rng.nextDouble() - 0.3) * 18,
      );
      canvas.drawCircle(
        puff,
        4 + rng.nextDouble() * 5,
        Paint()
          ..color = palette.first.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  void _drawCrystalShards(Canvas canvas, List<Offset> centers,
      List<Color> palette, double r) {
    if (palette.isEmpty) return;
    final rng = math.Random(13);
    for (var i = 0; i < 6; i++) {
      final base = centers[i % centers.length];
      final tip = Offset(
        base.dx + (rng.nextDouble() - 0.5) * 26,
        base.dy - 4 - rng.nextDouble() * 10,
      );
      final left = Offset(tip.dx - 3, tip.dy + 6);
      final right = Offset(tip.dx + 3, tip.dy + 6);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..lineTo(right.dx, right.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = palette[i % palette.length].withValues(alpha: 0.75),
      );
    }
  }

  void _drawDragonBreath(
      Canvas canvas, List<Offset> centers, List<Color> palette) {
    if (palette.length < 2) return;
    // Curving plume from the head, fanning out as it trails.
    final head = centers.last;
    for (var i = 0; i < 8; i++) {
      final t = i / 7;
      final cx = head.dx + 8 + i * 4.0;
      final cy = head.dy - 6 + (i % 2 == 0 ? 0 : 4);
      final r = 6.0 - t * 4.0;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..color = Color.lerp(palette.last, palette.first, t)!
              .withValues(alpha: 0.65 - t * 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrailPreviewPainter old) =>
      old.trail != trail || old.accentColor != accentColor;
}

/// Paints a stylized ship silhouette for the store's Skins tab, using
/// the skin's own color palette plus a per-skin signature overlay
/// (shimmer for golden, ember dots for fire, scale ridges for dragon,
/// etc.) so each skin card visually previews what the in-game ship
/// will look like with that skin equipped.
class _SkinPreviewPainter extends CustomPainter {
  final ShipSkinType skin;
  final Color accentColor;

  _SkinPreviewPainter({required this.skin, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final palette = skin.colors.isNotEmpty
        ? skin.colors
        : <Color>[accentColor, accentColor.withValues(alpha: 0.5)];

    // S-curve ship silhouette, 7 segments. Curving more dramatically
    // than the trail card's 5-segment line so the skin's colors get a
    // proper showcase across multiple body positions.
    final centers = <Offset>[
      Offset(width * 0.14, height * 0.70),
      Offset(width * 0.26, height * 0.58),
      Offset(width * 0.38, height * 0.50),
      Offset(width * 0.50, height * 0.48),
      Offset(width * 0.62, height * 0.50),
      Offset(width * 0.74, height * 0.42),
      Offset(width * 0.86, height * 0.36), // head
    ];
    final r = (width < height ? width : height) * 0.085;

    // Base body — color lerp across segments using the skin's palette.
    for (var i = 0; i < centers.length; i++) {
      final t = i / (centers.length - 1);
      Color color;
      if (palette.length == 1) {
        color = palette.first;
      } else if (palette.length == 2) {
        color = Color.lerp(palette.first, palette.last, t)!;
      } else {
        // Multi-color: pick across the palette by index position.
        final scaled = t * (palette.length - 1);
        final lower = scaled.floor();
        final upper = math.min(lower + 1, palette.length - 1);
        color = Color.lerp(palette[lower], palette[upper], scaled - lower)!;
      }
      final fade = 0.55 + 0.45 * t;
      canvas.drawCircle(
        centers[i],
        r * (0.78 + 0.22 * t),
        Paint()
          ..color = color.withValues(alpha: fade)
          ..isAntiAlias = true,
      );
    }

    // Per-skin signature overlay — same direction as the in-game
    // _drawSkinSignature so the store preview matches gameplay.
    switch (skin) {
      case ShipSkinType.classic:
        break;
      case ShipSkinType.golden:
        _shimmerStripe(canvas, centers, r);
        break;
      case ShipSkinType.rainbow:
        _whiteSparkles(canvas, centers, r, count: 4);
        break;
      case ShipSkinType.galaxy:
        _starSpecks(canvas, size, 12);
        break;
      case ShipSkinType.dragon:
        _scaleRidges(canvas, centers, r);
        break;
      case ShipSkinType.electric:
        _sparkBolts(canvas, centers);
        break;
      case ShipSkinType.fire:
        _emberRising(canvas, centers);
        break;
      case ShipSkinType.ice:
        _frostSpecks(canvas, centers, r);
        break;
      case ShipSkinType.shadow:
        _smokyHalos(canvas, centers, r);
        break;
      case ShipSkinType.neon:
        _neonHalos(canvas, centers, r);
        break;
      case ShipSkinType.crystal:
        _facetHighlights(canvas, centers, r);
        break;
      case ShipSkinType.cosmic:
        _cosmicHaze(canvas, centers, r);
        _starSpecks(canvas, size, 6);
        break;
    }

    // Head highlight — small bright dot on the leading segment so the
    // eye picks up direction immediately.
    canvas.drawCircle(
      centers.last,
      r * 0.28,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  void _shimmerStripe(Canvas canvas, List<Offset> centers, double r) {
    for (final c in centers) {
      canvas.drawCircle(
        Offset(c.dx - r * 0.25, c.dy - r * 0.25),
        r * 0.32,
        Paint()
          ..color = const Color(0xFFFFF6C4).withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      );
    }
  }

  void _whiteSparkles(Canvas canvas, List<Offset> centers, double r,
      {required int count}) {
    final rng = math.Random(3);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var i = 0; i < count; i++) {
      final c = centers[i % centers.length];
      canvas.drawCircle(
        Offset(c.dx + (rng.nextDouble() - 0.5) * r * 0.8,
            c.dy + (rng.nextDouble() - 0.5) * r * 0.8),
        1.4,
        paint,
      );
    }
  }

  void _starSpecks(Canvas canvas, Size size, int count) {
    final rng = math.Random(42);
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.75);
    for (var i = 0; i < count; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height * 0.7; // upper portion
      canvas.drawCircle(Offset(cx, cy), 0.9, paint);
    }
  }

  void _scaleRidges(Canvas canvas, List<Offset> centers, double r) {
    final paint = Paint()
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (final c in centers) {
      final rect =
          Rect.fromCenter(center: Offset(c.dx, c.dy - r * 0.1), width: r * 1.4, height: r * 0.9);
      canvas.drawArc(rect, math.pi, math.pi, false, paint);
    }
  }

  void _sparkBolts(Canvas canvas, List<Offset> centers) {
    final paint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    for (var i = 0; i < centers.length; i += 2) {
      final c = centers[i];
      final path = Path()
        ..moveTo(c.dx - 4, c.dy - 5)
        ..lineTo(c.dx, c.dy)
        ..lineTo(c.dx + 1, c.dy + 1)
        ..lineTo(c.dx + 4, c.dy + 5);
      canvas.drawPath(path, paint);
    }
  }

  void _emberRising(Canvas canvas, List<Offset> centers) {
    final rng = math.Random(7);
    for (var i = 0; i < centers.length; i++) {
      final c = centers[i];
      for (var s = 0; s < 2; s++) {
        final dy = -4 - rng.nextDouble() * 8 - s * 3.0;
        final dx = (rng.nextDouble() - 0.5) * 8;
        canvas.drawCircle(
          Offset(c.dx + dx, c.dy + dy),
          1.2 + rng.nextDouble(),
          Paint()
            ..color = Color.lerp(
                    const Color(0xFFFFD86A), const Color(0xFFFF4500), s / 2)!
                .withValues(alpha: 0.8)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
        );
      }
    }
  }

  void _frostSpecks(Canvas canvas, List<Offset> centers, double r) {
    final paint = Paint()
      ..color = const Color(0xFFE0FBFF).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    for (final c in centers) {
      const s = 2.2;
      final fx = c.dx + r * 0.3;
      final fy = c.dy - r * 0.5;
      canvas.drawLine(Offset(fx - s, fy - s), Offset(fx + s, fy + s), paint);
      canvas.drawLine(Offset(fx - s, fy + s), Offset(fx + s, fy - s), paint);
      canvas.drawLine(Offset(fx, fy - s * 1.4), Offset(fx, fy + s * 1.4),
          paint);
    }
  }

  void _smokyHalos(Canvas canvas, List<Offset> centers, double r) {
    for (final c in centers) {
      canvas.drawCircle(
        c,
        r * 1.8,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  void _neonHalos(Canvas canvas, List<Offset> centers, double r) {
    for (var i = 0; i < centers.length; i++) {
      final color = i.isEven
          ? const Color(0xFF39FF14)
          : const Color(0xFFFF1493);
      canvas.drawCircle(
        centers[i],
        r * 1.6,
        Paint()
          ..color = color.withValues(alpha: 0.40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
  }

  void _facetHighlights(Canvas canvas, List<Offset> centers, double r) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.6);
    for (final c in centers) {
      final path = Path()
        ..moveTo(c.dx - r * 0.55, c.dy - r * 0.55)
        ..lineTo(c.dx - r * 0.15, c.dy - r * 0.55)
        ..lineTo(c.dx - r * 0.55, c.dy - r * 0.15)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _cosmicHaze(Canvas canvas, List<Offset> centers, double r) {
    for (final c in centers) {
      canvas.drawCircle(
        c,
        r * 1.6,
        Paint()
          ..color = const Color(0xFFB46AFF).withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SkinPreviewPainter old) =>
      old.skin != skin || old.accentColor != accentColor;
}
