import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inapp_purchase/flutter_inapp_purchase.dart' as iap;
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/models/premium_cosmetics.dart';
import 'package:cosmo_strike_flutter_app/models/premium_power_up.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/power_up/power_up_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/account_upgrade_sheet.dart';
import 'package:cosmo_strike_flutter_app/widgets/reward_toast.dart';

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
  // hasn't reflected back from the backend yet. The tile switches from
  // "BUY" to a "Verifying" spinner during this window (typically 2-15s
  // for Play Store → webhook → entitlement → cubit). Auto-cleared once
  // the PremiumCubit reports the item as owned, or after a safety timeout
  // so the spinner never spins forever if a webhook is genuinely lost.
  final Set<String> _pendingProductIds = {};

  /// True while a "Restore purchases" request is in flight.
  bool _restoring = false;

  // Tab order: Pro / Coins / Themes / Skins / Trails / Power-Ups.
  // Keeps Coins at index 1 so existing `?tab=1` deep links still land on
  // coins. These names are the analytics tab ids — keep them stable.
  static const _tabNames = [
    'Pro',
    'Coins',
    'Themes',
    'Skins',
    'Trails',
    'Power-Ups',
  ];

  static const _tabLabels = [
    'Pro',
    'Coins',
    'Themes',
    'Skins',
    'Trails',
    'Power-ups',
  ];

  static const _tabIcons = [
    Symbols.diamond_rounded,
    Symbols.paid_rounded,
    Symbols.palette_rounded,
    Symbols.rocket_rounded,
    Symbols.auto_awesome_rounded,
    Symbols.bolt_rounded,
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
                final cs = context.cs;
                return ColoredBox(
                  color: CsColors.bg,
                  child: Stack(
                    children: [
                      const Positioned.fill(child: _PrismGlow()),
                      CsScaffold(
                        backgroundColor: Colors.transparent,
                        // Back + title passed as the (non-flex) leading so the
                        // coin balance sits flush right like the mock.
                        topBarLeading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CsBackButton(),
                            SizedBox(width: cs(4)),
                            Text(
                              'STORE',
                              maxLines: 1,
                              style: cs.type.mono(11, color: CsColors.ink, weight: FontWeight.w600),
                            ),
                          ],
                        ),
                        trailing: [
                          if (coinsState.hasPremiumBonus)
                            CsChip(
                              '${coinsState.earningMultiplier}x bonus',
                              kind: CsChipKind.gold,
                            ),
                          CsCoins(coinsState.balance.total, size: 12),
                        ],
                        body: CsSplit(
                          leftWidth: 200,
                          gap: cs(38),
                          left: _buildCategoryRail(),
                          right: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildProTab(premiumState),
                              _buildCoinsTab(coinsState),
                              _buildThemesTab(theme, premiumState),
                              _buildSkinsTab(theme, premiumState),
                              _buildTrailsTab(theme, premiumState),
                              _buildPowerUpsTab(coinsState),
                            ],
                          ),
                        ),
                      ),
                    ],
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
  // Left category rail
  // ===========================================================================

  /// Never scrolls — renders at natural size and scales down on short
  /// phones. Driven by [_tabController] so rail taps and swipes stay in sync.
  Widget _buildCategoryRail() {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        final cs = context.cs;
        // Scrolls (rather than scaling down) on short phones so every
        // category keeps a full 44dp tap target.
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < _tabLabels.length; i++) ...[
                if (i > 0) SizedBox(height: cs(2)),
                _buildRailItem(i),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildRailItem(int i) {
    final cs = context.cs;
    final t = cs.type;
    final on = _tabController.index == i;
    return CsPressable(
      onTap: () => _tabController.animateTo(i),
      semanticLabel: _tabLabels[i],
      child: AnimatedContainer(
        duration: CsMotion.base,
        curve: CsMotion.standard,
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.symmetric(horizontal: cs(14), vertical: cs(11)),
        decoration: BoxDecoration(
          color: on ? CsColors.fill07 : Colors.transparent,
          borderRadius: BorderRadius.circular(CsRadius.tile),
        ),
        child: Row(
          children: [
            Icon(
              _tabIcons[i],
              size: cs(20),
              color: on ? CsColors.gold : CsColors.ink45,
            ),
            SizedBox(width: cs(12)),
            Flexible(
              child: Text(
                _tabLabels[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.display(
                  15,
                  weight: on ? FontWeight.w700 : FontWeight.w600,
                  em: 0,
                  height: 1.1,
                  color: on ? CsColors.ink : CsColors.ink60,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // Shared tab building blocks
  // ===========================================================================

  /// Big Syne headline + optional mono sub-line at the top of each tab.
  Widget _tabHeader(String title, {String? subtitle}) {
    final cs = context.cs;
    final t = cs.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.display(34, em: -0.03, height: 1),
        ),
        if (subtitle != null) ...[
          SizedBox(height: cs(8)),
          Text(
            subtitle,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: t.mono(11, em: 0.04, color: CsColors.ink55, height: 1.45),
          ),
        ],
        SizedBox(height: cs(18)),
      ],
    );
  }

  /// Mono section label with an optional quiet note under it.
  Widget _sectionLabel(String label, {String? note, bool first = false}) {
    final cs = context.cs;
    final t = cs.type;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : cs(24), bottom: cs(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CsLabel(label),
          if (note != null) ...[
            SizedBox(height: cs(4)),
            Text(note, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.body),
          ],
        ],
      ),
    );
  }

  Widget _box(Widget child) => SliverToBoxAdapter(child: child);

  /// Scrollable tab body. A little bottom room so the last row never sits
  /// flush against the banner ad.
  Widget _tabScroll(List<Widget> slivers) {
    return CustomScrollView(
      slivers: [
        ...slivers,
        SliverToBoxAdapter(child: SizedBox(height: context.cs(20))),
      ],
    );
  }

  /// Responsive tile grid: more columns as the pane gets wider (tablets get
  /// a smaller minimum tile so they show more at once). Fixed row height so
  /// tiles never overflow — previews flex to whatever room is left.
  Widget _tileGrid({
    required int count,
    required IndexedWidgetBuilder itemBuilder,
    double minTile = 170,
    double extent = 236,
    int maxColumns = 5,
    int minColumns = 2,
    int? maxColumnsTablet,
  }) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final cs = context.cs;
        final gap = cs(12);
        final min = cs(cs.isTablet ? minTile * 0.86 : minTile);
        final cols = ((constraints.crossAxisExtent + gap) / (min + gap))
            .floor()
            .clamp(minColumns, cs.isTablet ? (maxColumnsTablet ?? maxColumns + 1) : maxColumns);
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            mainAxisExtent: cs(extent),
          ),
          delegate: SliverChildBuilderDelegate(itemBuilder, childCount: count),
        );
      },
    );
  }

  /// Banner row atop the cosmetic tabs (themes / skins / trails) telling the
  /// user a Pro subscription unlocks everything in that tab. Tapping it (when
  /// not already Pro) jumps to the Pro tab. Power-Ups are intentionally
  /// excluded — Pro doesn't unlock the power-up catalog.
  Widget _buildProIncludedRow(PremiumState premiumState, String itemNoun) {
    final cs = context.cs;
    final isPro = premiumState.hasPremium;
    return Padding(
      padding: EdgeInsets.only(bottom: cs(18)),
      child: CsListRow(
        dividerTop: true,
        onTap: isPro ? null : () => _tabController.animateTo(0),
        leading: CsIconDisc(
          isPro ? Symbols.check_circle_rounded : Symbols.diamond_rounded,
          size: 34,
          color: isPro ? CsColors.mint : CsColors.gold,
        ),
        title: isPro ? 'Unlocked with Pro' : 'Included with Cosmo Strike Pro',
        subtitle: isPro
            ? 'Every $itemNoun here is yours with your subscription.'
            : 'Subscribe to Pro to unlock every $itemNoun here — no separate purchase needed.',
        trailing: isPro
            ? null
            : Icon(Symbols.chevron_right_rounded, size: cs(22), color: CsColors.ink45),
      ),
    );
  }

  /// One grid tile for a cosmetic (theme / skin / trail): preview on top,
  /// Syne name + one-line blurb, then a status/action footer.
  ///
  /// equipped → prism ring (current) · owned → done + mint label + EQUIP ·
  /// buyable → future + gold price + BUY · verifying → spinner.
  Widget _cosmeticTile({
    required Widget preview,
    required String name,
    required String description,
    required bool isEquipped,
    required bool isOwned,
    required bool isPending,
    required bool showProBadge,
    required String priceLabel,
    required VoidCallback onEquip,
    required VoidCallback onBuy,
    String equippedLabel = 'Equipped',
    String ownedLabel = 'Owned',
    String equipLabel = 'Equip',
  }) {
    final cs = context.cs;
    final t = cs.type;
    final state = isEquipped
        ? CsTileState.current
        : isOwned
            ? CsTileState.done
            : CsTileState.future;
    final VoidCallback? onTap =
        isPending ? null : (isEquipped ? null : (isOwned ? onEquip : onBuy));

    final Widget footer;
    if (isPending) {
      footer = _footerRow(
        CsLabel('Verifying', color: CsColors.ink45, size: 10),
        SizedBox.square(
          dimension: cs(14),
          child: const CircularProgressIndicator(strokeWidth: 2, color: CsColors.ink60),
        ),
      );
    } else if (isEquipped) {
      footer = _footerRow(
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.check_circle_rounded, size: cs(14), color: CsColors.ink),
          SizedBox(width: cs(6)),
          Flexible(child: CsLabel(equippedLabel, color: CsColors.ink, size: 10)),
        ]),
        null,
      );
    } else if (isOwned) {
      footer = _footerRow(
        CsLabel(ownedLabel, color: CsColors.mint, size: 10),
        CsButton.secondary(label: equipLabel, size: CsButtonSize.small, onPressed: onEquip),
      );
    } else {
      footer = _footerRow(
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(priceLabel, maxLines: 1, style: t.mono(12, color: CsColors.gold, em: 0.04)),
        ),
        CsButton.secondary(label: 'Buy', size: CsButtonSize.small, onPressed: onBuy),
      );
    }

    return _ItemTile(
      state: state,
      onTap: onTap,
      preview: preview,
      badge: showProBadge
          ? const CsChip('Pro', kind: CsChipKind.gold, icon: Symbols.lock_rounded)
          : null,
      name: name,
      description: description,
      footer: footer,
    );
  }

  Widget _footerRow(Widget left, Widget? right) {
    final cs = context.cs;
    return Row(
      children: [
        Expanded(child: Align(alignment: Alignment.centerLeft, child: left)),
        if (right != null) ...[SizedBox(width: cs(6)), right],
      ],
    );
  }

  /// Dark base + soft palette wash behind a painted cosmetic preview.
  Widget _palettePreview(List<Color> palette, CustomPainter painter) {
    return ColoredBox(
      color: CsColors.raised,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.first.withValues(alpha: 0.38),
              palette.last.withValues(alpha: 0.08),
            ],
          ),
        ),
        child: SizedBox.expand(child: CustomPaint(painter: painter)),
      ),
    );
  }

  // ===========================================================================
  // PRO TAB
  // ===========================================================================

  static const _proBenefitsLine =
      'No ads · All themes, skins & trails · 2× coins · Pass premium track';

  Widget _buildProTab(PremiumState premiumState) {
    // Drops any Pro SKU from the pending set once PremiumCubit reports
    // hasPremium=true — the spinner on the plan cards stops the moment the
    // backend's VerifyPurchase response lands.
    _reconcilePendingPurchases(premiumState);
    final cs = context.cs;
    final t = cs.type;

    // Paid Pro → status + benefits only (no plans). Trial → status with a
    // convert CTA + the plan picker. Free → plan picker.
    final isPaidPro = premiumState.hasPremium && !premiumState.isOnPromo;
    final isTrial = premiumState.hasPremium && premiumState.isOnPromo;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: cs(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CsHeadline(
            const ['Cosmo ', 'Pro'],
            prismIndex: 1,
            maxLines: 1,
            style: t.display(34, em: -0.03, height: 1.05),
          ),
          SizedBox(height: cs(8)),
          Text(
            _proBenefitsLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.mono(11, em: 0.06, color: CsColors.ink55, height: 1.4),
          ),
          SizedBox(height: cs(18)),
          if (isPaidPro || isTrial) ...[
            _buildProStatus(premiumState),
            SizedBox(height: cs(18)),
          ],
          if (!isPaidPro) ...[
            if (isTrial) _sectionLabel('Subscribe before the trial ends', first: true),
            _buildPlanCards(),
            SizedBox(height: cs(10)),
          ],
          _buildProFooter(),
          _sectionLabel('What you get'),
          _buildProFeatureGrid(),
        ],
      ),
    );
  }

  Widget _buildPlanCards() {
    final cs = context.cs;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildProPlanCard(
              title: 'Monthly',
              productId: ProductIds.proMonthly,
              fallbackPrice: 4.99,
              cadence: '/mo',
              billedLabel: 'Billed monthly',
              savingsLabel: null,
              featured: false,
            ),
          ),
          SizedBox(width: cs(14)),
          Expanded(
            child: _buildProPlanCard(
              title: 'Yearly',
              productId: ProductIds.proYearly,
              fallbackPrice: 39.99,
              cadence: '/yr',
              billedLabel: 'Billed yearly',
              // Live from Play / App Store prices; hidden until both load.
              savingsLabel: _yearlySavingsLabel(),
              featured: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProPlanCard({
    required String title,
    required String productId,
    required double fallbackPrice,
    required String cadence,
    required String billedLabel,
    required String? savingsLabel,
    required bool featured,
  }) {
    final cs = context.cs;
    final t = cs.type;
    final price =
        PurchaseService().getStorePriceOrDefault(productId, fallbackPrice);
    final trial = _freeTrialLabel(productId);
    final isPending = _pendingProductIds.contains(productId);
    // While a sibling plan card is mid-verify we disable BOTH plan cards so
    // the user can't kick off a second purchase before the first one's
    // VerifyPurchase response lands — that would double-charge and bug out
    // the PremiumCubit's mid-flight state.
    final anyProPending = _pendingProductIds.contains(ProductIds.proMonthly) ||
        _pendingProductIds.contains(ProductIds.proYearly);
    final VoidCallback? onBuy = anyProPending
        ? null
        : () => _purchaseSubscription(productId, '$title plan');

    final label = isPending ? 'Verifying…' : 'Subscribe';
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: CsLabel(title)),
            if (savingsLabel != null)
              CsChip(savingsLabel, kind: CsChipKind.gold, size: 10),
          ],
        ),
        SizedBox(height: cs(10)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(price, maxLines: 1, style: t.display(34, em: -0.02, height: 1.1)),
              Text(' $cadence', style: t.mono(12, em: 0, color: CsColors.ink45)),
            ],
          ),
        ),
        SizedBox(height: cs(8)),
        Text(
          trial ?? billedLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.mono(11, em: 0.02, color: trial != null ? CsColors.mint : CsColors.ink45),
        ),
        SizedBox(height: cs(14)),
        const Spacer(),
        featured
            ? CsButton.primary(label: label, expand: true, loading: isPending, onPressed: onBuy)
            : CsButton.secondary(label: label, expand: true, loading: isPending, onPressed: onBuy),
      ],
    );

    final Widget card = featured
        ? CsPrismRing(
            radius: CsRadius.card,
            fill: CsColors.raised,
            padding: EdgeInsets.all(cs(18.5)),
            child: content,
          )
        : Container(
            padding: EdgeInsets.all(cs(20)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(CsRadius.card),
              border: Border.all(color: CsColors.lineSubtle),
            ),
            child: content,
          );
    return CsPressable(onTap: onBuy, scale: 0.99, semanticLabel: '$title plan', child: card);
  }

  /// "N-day free trial" when the store product carries a free-trial offer
  /// the user is eligible for; null otherwise (we never promise a trial the
  /// store didn't return).
  String? _freeTrialLabel(String productId) {
    final product = PurchaseService().getProduct(productId);
    if (product is! iap.ProductSubscription) return null;
    final offers = switch (product) {
      iap.ProductSubscriptionAndroid(:final subscriptionOffers) => subscriptionOffers,
      iap.ProductSubscriptionIOS(:final subscriptionOffers) =>
        subscriptionOffers ?? const <iap.SubscriptionOffer>[],
    };
    for (final offer in offers) {
      final period = offer.period;
      if (offer.paymentMode == iap.PaymentMode.FreeTrial && period != null) {
        final unit = switch (period.unit) {
          iap.SubscriptionPeriodUnit.Day => 'day',
          iap.SubscriptionPeriodUnit.Week => 'week',
          iap.SubscriptionPeriodUnit.Month => 'month',
          iap.SubscriptionPeriodUnit.Year => 'year',
          iap.SubscriptionPeriodUnit.Unknown => null,
        };
        final n = period.value * (offer.periodCount ?? 1);
        return unit == null ? 'Free trial included' : '$n-$unit free trial';
      }
      // Play: a zero-priced, non-recurring pricing phase is the trial.
      for (final phase in offer.pricingPhasesAndroid?.pricingPhaseList ??
          const <iap.PricingPhaseAndroid>[]) {
        if ((int.tryParse(phase.priceAmountMicros) ?? -1) != 0 ||
            phase.recurrenceMode == 1) {
          continue;
        }
        final m = RegExp(r'^P(\d+)([DWMY])$').firstMatch(phase.billingPeriod);
        if (m == null) return 'Free trial included';
        final cycles = phase.billingCycleCount > 0 ? phase.billingCycleCount : 1;
        final n = int.parse(m.group(1)!) * cycles;
        const units = {'D': 'day', 'W': 'week', 'M': 'month', 'Y': 'year'};
        return '$n-${units[m.group(2)]} free trial';
      }
    }
    return null;
  }

  Widget _buildProStatus(PremiumState premiumState) {
    // Promo trials (welcome bonus / app-wide giveaway) get a gold TRIAL chip
    // + countdown + a convert CTA so the user knows this is a limited window.
    // Paid Pro keeps the mint "verified" treatment.
    final isPromo = premiumState.isOnPromo;
    final expiry =
        isPromo ? premiumState.promoExpiresAt : premiumState.subscriptionExpiry;
    final expiryLabel = isPromo
        ? (expiry != null ? _formatPromoCountdown(expiry) : 'Free 3-day trial')
        : (expiry != null ? 'Renews ${_formatDate(expiry)}' : null);
    final anyProPending = _pendingProductIds.contains(ProductIds.proMonthly) ||
        _pendingProductIds.contains(ProductIds.proYearly);
    return CsListRow(
      dividerTop: true,
      leading: CsIconDisc(
        isPromo ? Symbols.redeem_rounded : Symbols.verified_rounded,
        color: isPromo ? CsColors.gold : CsColors.mint,
      ),
      title: isPromo ? "You're on a free Pro trial!" : "You're Pro!",
      titleTrailing: isPromo ? const CsChip('Trial', kind: CsChipKind.gold) : null,
      subtitle: expiryLabel,
      // Convert CTA — fires the monthly purchase, same path as the plan
      // card's Subscribe button.
      trailing: isPromo
          ? CsButton.premium(
              label: 'Keep Pro — Subscribe',
              size: CsButtonSize.small,
              icon: Symbols.workspace_premium_rounded,
              loading: _pendingProductIds.contains(ProductIds.proMonthly),
              onPressed: anyProPending
                  ? null
                  : () => _purchaseSubscription(ProductIds.proMonthly, 'Pro Monthly'),
            )
          : null,
    );
  }

  /// "Cancel anytime · Restore purchases" — the restore half is live.
  Widget _buildProFooter() {
    final cs = context.cs;
    final t = cs.type;
    final quiet = t.mono(10, em: 0.04, color: CsColors.ink45);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Cancel anytime  ·  ', style: quiet),
        CsPressable(
          onTap: _restoring ? null : _restorePurchases,
          semanticLabel: 'Restore purchases',
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Restore purchases',
                  style: quiet.copyWith(
                    color: CsColors.ink70,
                    decoration: TextDecoration.underline,
                    decorationColor: CsColors.ink30,
                  ),
                ),
                if (_restoring) ...[
                  SizedBox(width: cs(8)),
                  SizedBox.square(
                    dimension: cs(10),
                    child: const CircularProgressIndicator(strokeWidth: 1.5, color: CsColors.ink60),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
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

  Widget _buildProFeatureGrid() {
    // Honest list — every line maps to an entitlement that's actually
    // granted. 'No ads' is real: AdService is Pro-gated so Pro/trial users
    // never see banners, interstitials, or rewarded offers.
    const features = [
      (Symbols.block_rounded, 'No ads — play completely ad-free'),
      (Symbols.palette_rounded, 'All 6 premium themes'),
      (Symbols.rocket_rounded, 'All 11 premium ship skins'),
      (Symbols.auto_awesome_rounded, 'All 11 premium trail effects'),
      (Symbols.paid_rounded, '2× coin earnings'),
      (Symbols.bolt_rounded, '5× premium power-ups every cycle'),
      (Symbols.emoji_events_rounded, 'Bronze + Silver + Gold tournament entries each cycle'),
      (Symbols.workspace_premium_rounded, 'Battle Pass Premium track every season'),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cs = context.cs;
        final t = cs.type;
        final twoCols = c.maxWidth >= cs(520);
        Widget row((IconData, String) f) => Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: EdgeInsets.symmetric(vertical: cs(10)),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: CsColors.hairline)),
              ),
              child: Row(
                children: [
                  Icon(f.$1, size: cs(18), color: CsColors.ink45),
                  SizedBox(width: cs(12)),
                  Expanded(
                    child: Text(
                      f.$2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(color: CsColors.ink),
                    ),
                  ),
                  SizedBox(width: cs(8)),
                  Icon(Symbols.check_circle_rounded, size: cs(16), color: CsColors.mint),
                ],
              ),
            );
        if (!twoCols) {
          return Column(children: [for (final f in features) row(f)]);
        }
        return Column(
          children: [
            for (var i = 0; i < features.length; i += 2)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: row(features[i])),
                    SizedBox(width: cs(24)),
                    Expanded(
                      child: i + 1 < features.length
                          ? row(features[i + 1])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Anonymous (guest) users can't make purchases — every paid path on this
  /// screen funnels through this check. On block we show the upgrade dialog;
  /// the caller bails so the user can re-tap Buy after they link an account.
  Future<bool> _ensurePurchasable() async {
    final user = context.read<AuthCubit>().state.user;
    if (user == null || !user.isAnonymous) return true;
    await showAccountUpgradeSheet(context);
    return false;
  }

  /// Restore purchases. Guests can't restore: the backend rejects anonymous
  /// verifies, so restored purchases need the signed-in account they belong
  /// to. Results arrive asynchronously on the purchase stream.
  Future<void> _restorePurchases() async {
    final user = context.read<AuthCubit>().state.user;
    if (user == null || user.isAnonymous) {
      await showAccountUpgradeSheet(context);
      return;
    }
    if (!mounted) return;
    setState(() => _restoring = true);
    showCsToast(context, 'Restoring purchases…', icon: Symbols.restore_rounded);
    try {
      await PurchaseService().restorePurchases();
      if (mounted) {
        showCsToast(
          context,
          'Restore requested — any purchases will appear in a moment.',
          kind: CsToastKind.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showCsToast(
          context,
          'Failed to restore purchases. Please try again.',
          kind: CsToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _purchaseSubscription(String productId, String displayName) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    // Mark pending up-front so the plan cards swap to a "Verifying…" state
    // covering the ~2–15s window between Play Store confirmation and the
    // backend's VerifyPurchase response landing in PremiumCubit. Auto-cleared
    // by _reconcilePendingPurchases when hasPremium flips true, or by the
    // 45s safety timeout in _markPending if the webhook is genuinely lost.
    _markPending(productId);
    try {
      await PurchaseService().purchaseProduct(productId);
      if (mounted) {
        showCsToast(context, 'Initiating $displayName purchase...');
      }
    } catch (e) {
      // Failure path — drop the pending state immediately so the user can
      // retry without waiting for the 45s safety timeout.
      if (mounted) {
        setState(() => _pendingProductIds.remove(productId));
        showCsToast(
          context,
          'Subscription not available. Please try again later.',
          kind: CsToastKind.error,
        );
      }
    }
  }

  // ===========================================================================
  // COINS TAB
  // ===========================================================================

  Widget _buildCoinsTab(CoinsState coinsState) {
    const options = CoinPurchaseOption.availableOptions;
    return _tabScroll([
      _box(_tabHeader('Star Coins', subtitle: 'Buy a coin pack, or earn coins free below.')),
      _box(_sectionLabel('Buy Star Coins', first: true)),
      _tileGrid(
        count: options.length,
        minTile: 140,
        extent: 214,
        maxColumns: 4,
        maxColumnsTablet: 4,
        itemBuilder: (context, i) => _buildCoinPackTile(options[i]),
      ),
      _box(_sectionLabel('Earn free coins')),
      // Rewarded ad — self-hides for Pro / when no ad is available.
      const SliverToBoxAdapter(child: _RewardedCoinsRow()),
      _box(_buildEarnMethodRow('Play Games', '5 coins per game', Symbols.sports_esports_rounded)),
      _box(_buildEarnMethodRow('Daily Login', '10-50 coins daily', Symbols.calendar_today_rounded)),
      _box(_buildEarnMethodRow('Achievements', '25-100 coins', Symbols.emoji_events_rounded)),
      _box(_buildEarnMethodRow('Tournaments', '100+ coins', Symbols.leaderboard_rounded)),
    ]);
  }

  Future<void> _purchaseCoinPack(CoinPurchaseOption option) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final price = PurchaseService().getStorePriceOrDefault(
        ProductIds.withPrefix(option.id), option.price);
    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Star Coins',
      title: 'Buy ${option.name}',
      message: 'Purchase ${option.displayCoins} for $price?',
      confirmLabel: 'Buy · $price',
    );
    if (!confirmed || !mounted) return;
    try {
      await PurchaseService().purchaseProduct(ProductIds.withPrefix(option.id));
      if (mounted) {
        showCsToast(context, 'Initiating purchase for ${option.name}...');
      }
    } catch (e) {
      if (mounted) {
        showCsToast(
          context,
          'Product not available. Please try again later.',
          kind: CsToastKind.error,
        );
      }
    }
  }

  Widget _buildCoinPackTile(CoinPurchaseOption option) {
    final cs = context.cs;
    final t = cs.type;
    final price = PurchaseService().getStorePriceOrDefault(
        ProductIds.withPrefix(option.id), option.price);
    void onTap() => _purchaseCoinPack(option);
    return CsTile(
      state: CsTileState.future,
      onTap: onTap,
      padding: EdgeInsets.all(cs(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: cs(20),
            child: Row(
              children: [
                if (option.isBestValue || option.isPopular)
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: option.isBestValue
                          ? const CsChip('Best value', kind: CsChipKind.gold)
                          : const CsChip('Popular'),
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
          Image.asset('assets/images/ui/coin.png', width: cs(28), height: cs(28)),
          SizedBox(height: cs(8)),
          Text(
            option.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.display(14, weight: FontWeight.w700, em: 0, height: 1.2),
          ),
          SizedBox(height: cs(2)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${option.totalCoins}',
              maxLines: 1,
              style: t.display(26, em: -0.02, height: 1.1, color: CsColors.gold),
            ),
          ),
          Text(
            option.displayCoins,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.mono(10, em: 0.04, color: CsColors.ink45),
          ),
          SizedBox(height: cs(10)),
          option.isBestValue
              ? CsButton.premium(label: price, size: CsButtonSize.small, expand: true, onPressed: onTap)
              : CsButton.secondary(label: price, size: CsButtonSize.small, expand: true, onPressed: onTap),
        ],
      ),
    );
  }

  Widget _buildEarnMethodRow(String title, String reward, IconData icon) {
    final cs = context.cs;
    return CsListRow(
      leading: CsIconDisc(icon, size: 34, color: CsColors.ink70),
      title: title,
      trailing: Text(
        reward,
        maxLines: 1,
        style: cs.type.mono(11, color: CsColors.gold, em: 0.06),
      ),
    );
  }

  // ===========================================================================
  // THEMES TAB
  // ===========================================================================

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
    // after trying a premium one.
    const freeThemes = [
      GameTheme.classic,
      GameTheme.modern,
      GameTheme.neon,
      GameTheme.retro,
    ];

    // Once a pending purchase reflects as owned, drop it from the pending
    // set on the next frame so we don't trigger a build-during-build.
    _reconcilePendingPurchases(premiumState);

    return _tabScroll([
      _box(_tabHeader(
        'Themes',
        subtitle: "Themes change the in-game look — they recolor your ship's trail, "
            'shots and the battlefield glow.',
      )),
      _box(_buildProIncludedRow(premiumState, 'theme')),
      _box(_buildThemesBundleTile(premiumState)),
      _box(_sectionLabel('Premium themes')),
      _tileGrid(
        count: premiumThemes.length,
        itemBuilder: (context, i) => _buildThemeTile(premiumThemes[i], theme, premiumState),
      ),
      _box(_sectionLabel('Free themes', note: 'Always available — switch back any time.')),
      _tileGrid(
        count: freeThemes.length,
        itemBuilder: (context, i) => _buildThemeTile(freeThemes[i], theme, premiumState),
      ),
    ]);
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
    // Pro tab swaps to the "you are Pro" status, but we also clear pending
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

  Widget _buildThemesBundleTile(PremiumState premiumState) {
    final cs = context.cs;
    final t = cs.type;
    final bundleOwned = premiumState.isBundleOwned('premium_themes_bundle');
    final isPending = _pendingProductIds.contains(ProductIds.themesBundle);
    final price = PurchaseService().getStorePriceOrDefault(
      ProductIds.themesBundle,
      7.99,
    );
    void buy() => _purchaseThemeProduct(
          ProductIds.themesBundle,
          'All Themes Bundle',
          fallbackPrice: 7.99,
        );
    final Widget action;
    if (isPending) {
      action = const CsButton.secondary(
        label: 'Verifying',
        size: CsButtonSize.small,
        loading: true,
      );
    } else if (bundleOwned) {
      action = const CsChip('Owned', kind: CsChipKind.mint, size: 10);
    } else {
      action = CsButton.premium(
        label: 'Buy · $price',
        size: CsButtonSize.small,
        onPressed: buy,
      );
    }
    return CsTile(
      state: bundleOwned ? CsTileState.done : CsTileState.future,
      onTap: (bundleOwned || isPending) ? null : buy,
      padding: EdgeInsets.symmetric(horizontal: cs(14), vertical: cs(12)),
      child: Row(
        children: [
          CsIconDisc(Symbols.redeem_rounded, size: 38, color: CsColors.gold),
          SizedBox(width: cs(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('All Themes Bundle', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
                SizedBox(height: cs(3)),
                Text(
                  _themesBundleSubtitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.mono(10, em: 0.06, color: CsColors.ink55),
                ),
              ],
            ),
          ),
          SizedBox(width: cs(12)),
          action,
        ],
      ),
    );
  }

  Widget _buildThemeTile(
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
    return _cosmeticTile(
      preview: _ThemePreview(theme: target),
      name: target.name,
      description: _shortThemeDescription(target),
      isEquipped: isActive,
      isOwned: isOwned,
      isPending: isPending,
      showProBadge: !isOwned && productId != null,
      priceLabel: price,
      equippedLabel: 'Active',
      ownedLabel: productId == null ? 'Free' : 'Owned',
      equipLabel: 'Apply',
      onEquip: () => context.read<ThemeCubit>().setTheme(target),
      onBuy: () {
        if (productId != null) _purchaseThemeProduct(productId, target.name);
      },
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
      case GameTheme.accessible:
        return 'High-contrast, color-blind friendly';
    }
  }

  /// "Save N%" for yearly vs 12× monthly, from live store prices.
  String? _yearlySavingsLabel() {
    final pct = PurchaseService().yearlySavingsPercent(ProductIds.proMonthly, ProductIds.proYearly);
    return pct == null ? null : 'Save $pct%';
  }

  static const _premiumThemeIds = [
    ProductIds.crystalTheme,
    ProductIds.cyberpunkTheme,
    ProductIds.spaceTheme,
    ProductIds.oceanTheme,
    ProductIds.desertTheme,
    ProductIds.forestTheme,
  ];

  /// Bundle subtitle; the saving is the bundle vs buying every premium theme
  /// separately at live store prices (omitted until all prices load).
  String _themesBundleSubtitle() {
    final purchases = PurchaseService();
    final bundle = purchases.getStorePriceValue(ProductIds.themesBundle);
    final singles = _premiumThemeIds.map(purchases.getStorePriceValue).toList();
    final sameCurrency = _premiumThemeIds.every(
      (id) => purchases.getStoreCurrency(id) == purchases.getStoreCurrency(ProductIds.themesBundle),
    );
    final pct = (singles.contains(null) || !sameCurrency)
        ? null
        : PurchaseService.savingsPercent(
            full: singles.fold<double>(0, (a, b) => a + b!),
            actual: bundle,
          );
    final base = 'All ${_premiumThemeIds.length} premium themes';
    return pct == null ? base : '$base · save $pct%';
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

  Future<void> _purchaseThemeProduct(
    String productId,
    String displayName, {
    double fallbackPrice = 1.99,
  }) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final price = PurchaseService().getStorePriceOrDefault(productId, fallbackPrice);
    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Theme',
      title: displayName,
      message: "Unlock $displayName for $price? Themes recolor your ship's trail, "
          'shots and the battlefield glow in-game.',
      confirmLabel: 'Buy · $price',
    );

    if (!confirmed || !mounted) return;

    try {
      await PurchaseService().purchaseProduct(productId);
      if (!mounted) return;
      _markPending(productId);
      showCsToast(context, 'Verifying $displayName purchase…');
    } catch (e) {
      if (mounted) {
        showCsToast(
          context,
          'Theme not available. Please try again later.',
          kind: CsToastKind.error,
        );
      }
    }
  }

  /// Mark a productId as "purchase pending" so its tile shows the
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
    const skins = ShipSkinType.values;
    return _tabScroll([
      _box(_tabHeader('Ship skins')),
      _box(_buildProIncludedRow(premiumState, 'skin')),
      _tileGrid(
        count: skins.length,
        itemBuilder: (context, index) {
          final skin = skins[index];
          // Pro subscription unlocks all premium skins (mirrors theme bundling).
          final isUnlocked = premiumState.isSkinUnlocked(skin);
          final isSelected = premiumState.selectedSkinId == skin.id;
          final productId = ProductIds.skinStoreId(skin.id);
          // Each tile paints a ship-silhouette preview using the skin's own
          // colors and per-skin signature so users see the in-game look.
          final palette = skin.colors.isNotEmpty
              ? skin.colors
              : [theme.shipColor, theme.shipColor.withValues(alpha: 0.6)];
          return _cosmeticTile(
            preview: _palettePreview(
              palette,
              _SkinPreviewPainter(skin: skin, accentColor: theme.accentColor),
            ),
            name: skin.displayName,
            description: skin.description,
            isEquipped: isSelected,
            isOwned: isUnlocked,
            isPending: _pendingProductIds.contains(productId),
            showProBadge: !isUnlocked && skin.isPremium,
            priceLabel: skin.isPremium
                ? PurchaseService().getStorePriceOrDefault(productId, skin.price)
                : 'FREE',
            onEquip: () {
              context.read<PremiumCubit>().selectSkin(skin.id);
              showCsToast(context, '${skin.displayName} equipped',
                  kind: CsToastKind.success, duration: const Duration(seconds: 1));
            },
            onBuy: () => _purchaseCosmetic(
              productId: productId,
              displayName: skin.displayName,
              fallbackPrice: skin.price,
            ),
          );
        },
      ),
    ]);
  }

  // ===========================================================================
  // TRAILS TAB
  // ===========================================================================

  Widget _buildTrailsTab(GameTheme theme, PremiumState premiumState) {
    _reconcilePendingPurchases(premiumState);
    const trails = TrailEffectType.values;
    return _tabScroll([
      _box(_tabHeader('Trails')),
      _box(_buildProIncludedRow(premiumState, 'trail')),
      _tileGrid(
        count: trails.length,
        itemBuilder: (context, index) {
          final trail = trails[index];
          // Pro subscription unlocks all premium trails (mirrors theme bundling).
          final isUnlocked = premiumState.isTrailUnlocked(trail);
          final isSelected = premiumState.selectedTrailId == trail.id;
          final productId = ProductIds.withPrefix(trail.id);
          // Painted preview with the trail's own colors + a type-specific
          // signature (sparkles, lightning, flames…). "No Trail" falls back
          // to the current theme's accent.
          final palette = trail.colors.isNotEmpty
              ? trail.colors
              : [
                  theme.accentColor.withValues(alpha: 0.35),
                  theme.backgroundColor.withValues(alpha: 0.6),
                ];
          return _cosmeticTile(
            preview: _palettePreview(
              palette,
              _TrailPreviewPainter(trail: trail, accentColor: theme.accentColor),
            ),
            name: trail.displayName,
            description: trail.description,
            isEquipped: isSelected,
            isOwned: isUnlocked,
            isPending: _pendingProductIds.contains(productId),
            showProBadge: !isUnlocked && trail.isPremium,
            priceLabel: trail.isPremium
                ? PurchaseService().getStorePriceOrDefault(productId, trail.price)
                : 'FREE',
            onEquip: () {
              context.read<PremiumCubit>().selectTrail(trail.id);
              showCsToast(context, '${trail.displayName} equipped',
                  kind: CsToastKind.success, duration: const Duration(seconds: 1));
            },
            onBuy: () => _purchaseCosmetic(
              productId: productId,
              displayName: trail.displayName,
              fallbackPrice: trail.price,
            ),
          );
        },
      ),
    ]);
  }

  Future<void> _purchaseCosmetic({
    required String productId,
    required String displayName,
    required double fallbackPrice,
  }) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final price =
        PurchaseService().getStorePriceOrDefault(productId, fallbackPrice);
    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Unlock',
      title: displayName,
      message: 'Unlock $displayName for $price?',
      confirmLabel: 'Buy · $price',
    );

    if (!confirmed || !mounted) return;

    try {
      await PurchaseService().purchaseProduct(productId);
      if (!mounted) return;
      _markPending(productId);
      showCsToast(context, 'Verifying $displayName purchase…');
    } catch (e) {
      if (mounted) {
        showCsToast(
          context,
          'Item not available. Please try again later.',
          kind: CsToastKind.error,
        );
      }
    }
  }

  // ===========================================================================
  // POWER-UPS TAB
  // ===========================================================================
  // Power-ups have a real coin-purchased inventory. The types here match the
  // inventory keys used by the gameplay engine, so each purchase produces a
  // usable stockpile entry armed from the home loadout chip.

  /// Rewarded-ad row granting one free Speed Boost. Self-hides for Pro /
  /// web / when the SDK isn't ready; disables when no ad is loaded.
  Widget _buildFreePowerUpAdRow() {
    final ads = getIt.isRegistered<AdService>() ? getIt<AdService>() : null;
    if (ads == null || !ads.adsEnabled) return const SizedBox.shrink();
    final ready = ads.isRewardedReady;
    void watch() {
      final powerUps = context.read<PowerUpCubit>();
      // Capped like the identical home placement (3/day).
      ads.showRewardedCapped(
        capKey: AdService.capFreePowerUp,
        onReward: () {
          powerUps.grantFreePowerUp();
          RewardToast.show(
            icon: Symbols.bolt_rounded,
            amount: '+1 SPEED BOOST',
          );
        },
      );
    }

    return CsListRow(
      onTap: ready ? watch : null,
      leading: CsIconDisc(Symbols.play_circle_rounded, size: 34, color: CsColors.gold),
      title: 'Watch an ad — free Speed Boost',
      subtitle: ready ? 'Adds 1 Speed Boost to your loadout' : 'No ad available right now',
      trailing: CsButton.premium(
        label: 'Watch',
        size: CsButtonSize.small,
        onPressed: ready ? watch : null,
      ),
    );
  }

  Widget _buildPowerUpsTab(CoinsState coinsState) {
    // Power-up keys are snake_case and map 1:1 to ArmedLoadout.apply in
    // the Flame game (lib/game/run_effects.dart) — descriptions promise
    // exactly what that switch does, nothing more.
    // Coin costs MUST match PurchasePowerUpWithCoinsCommandHandler.AllowedCosts
    // on the backend — server rejects request.CoinCost mismatches outright.
    const powerUps = [
      _PowerUpCatalogItem(
        type: 'speed_boost',
        name: 'Speed Boost',
        description: 'Faster flying and firing for the first 15 seconds.',
        coinCost: 500,
      ),
      _PowerUpCatalogItem(
        type: 'invincibility',
        name: 'Invincibility',
        description: 'Launch with a shield plus 8s of invulnerability.',
        coinCost: 1000,
      ),
      _PowerUpCatalogItem(
        type: 'score_multiplier',
        name: 'Score Multiplier',
        description: 'Double points for the first 30 seconds.',
        coinCost: 750,
      ),
      _PowerUpCatalogItem(
        type: 'slow_motion',
        name: 'Slow Motion',
        description: 'Enemies and bullets crawl for 10 seconds.',
        coinCost: 500,
      ),
      _PowerUpCatalogItem(
        type: 'teleport',
        name: 'Warp Escape',
        description: 'One charge: the first hit warps you home unharmed.',
        coinCost: 1200,
      ),
      _PowerUpCatalogItem(
        type: 'ghost_mode',
        name: 'Ghost Mode',
        description: 'Phase through enemies and bullets for 12 seconds.',
        coinCost: 1500,
      ),
      _PowerUpCatalogItem(
        type: 'magnetic_pickup',
        name: 'Orb Magnet',
        description: 'Power-up orbs home toward you for 60 seconds.',
        coinCost: 1250,
      ),
      _PowerUpCatalogItem(
        type: 'score_shield',
        name: 'Last Stand',
        description: 'One charge: a lethal hit restores half health instead.',
        coinCost: 1500,
      ),
    ];
    const bundles = PowerUpBundle.availableBundles;

    return BlocBuilder<PowerUpCubit, PowerUpState>(
      builder: (context, powerUpState) {
        return _tabScroll([
          _box(_tabHeader(
            'Power-ups',
            subtitle: 'Buy with coins, then arm one from the home screen '
                'loadout chip — it activates 5s into your next game.',
          )),
          // Rewarded ad — free Speed Boost. Self-hides for Pro / no ad.
          _box(_buildFreePowerUpAdRow()),
          _box(_sectionLabel('Power-ups')),
          _tileGrid(
            count: powerUps.length,
            extent: 214,
            itemBuilder: (context, i) => _buildPowerUpTile(powerUps[i], powerUpState),
          ),
          _box(_sectionLabel(
            'Power-up bundles',
            note: 'Unlock multiple power-up types at a discount.',
          )),
          _tileGrid(
            count: bundles.length,
            minTile: 300,
            extent: 200,
            maxColumns: 3,
            minColumns: 1,
            itemBuilder: (context, i) => _buildPowerUpBundleTile(bundles[i], coinsState),
          ),
        ]);
      },
    );
  }

  Widget _buildPowerUpTile(_PowerUpCatalogItem item, PowerUpState powerUpState) {
    final cs = context.cs;
    final owned = powerUpState.countFor(item.type);
    void buy() => _purchasePowerUpWithCoins(item);
    return _ItemTile(
      state: owned > 0 ? CsTileState.done : CsTileState.future,
      onTap: buy,
      preview: ColoredBox(
        color: CsColors.raised,
        child: Center(
          child: Icon(CsIcons.powerUp(item.type), size: cs(34), color: CsColors.ink),
        ),
      ),
      badge: owned > 0 ? CsChip('×$owned', kind: CsChipKind.mint) : null,
      name: item.name,
      description: item.description,
      footer: _footerRow(
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CsCoins(item.coinCost),
        ),
        CsButton.secondary(label: 'Buy', size: CsButtonSize.small, onPressed: buy),
      ),
    );
  }

  Future<void> _purchasePowerUpWithCoins(_PowerUpCatalogItem item) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final coinsCubit = context.read<CoinsCubit>();
    final powerUpCubit = context.read<PowerUpCubit>();
    final coinsBalance = coinsCubit.state.balance.total;
    if (coinsBalance < item.coinCost) {
      showCsToast(context, 'Insufficient coins!', kind: CsToastKind.error);
      return;
    }

    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Power-up',
      title: item.name,
      message: 'Buy 1 ${item.name} for ${item.coinCost} coins?',
      confirmLabel: 'Buy · ${item.coinCost} coins',
    );
    if (!confirmed || !mounted) return;

    final newBalance =
        await powerUpCubit.purchaseWithCoins(item.type, item.coinCost);
    if (!mounted) return;
    if (newBalance == null) {
      showCsToast(context, 'Purchase failed. Try again.', kind: CsToastKind.error);
      return;
    }
    // Reflect the server-authoritative coin balance locally so the
    // CoinsCubit and any other UI stays in sync without an extra round-trip.
    await coinsCubit.setServerBalance(newBalance);
    if (!mounted) return;
    showCsToast(
      context,
      '${item.name} added to your loadout!',
      kind: CsToastKind.success,
      duration: const Duration(seconds: 2),
    );
  }

  Widget _buildPowerUpBundleTile(PowerUpBundle bundle, CoinsState coinsState) {
    final cs = context.cs;
    final t = cs.type;
    // Bundles are CONSUMABLE count packs — repeat-purchasable by design
    // (no "owned" latch; every buy adds the counts to the inventory).
    final canAfford = coinsState.balance.total >= bundle.bundlePrice;
    void buy() => _purchaseCoinBundle(bundle, canAfford);
    final leadKey = bundle.powerUps.keys.isEmpty
        ? ''
        : bundle.powerUps.keys.first.inventoryKey;
    return CsTile(
      state: CsTileState.future,
      onTap: buy,
      padding: EdgeInsets.all(cs(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CsIconDisc(CsIcons.powerUp(leadKey), size: 34, color: CsColors.gold),
              SizedBox(width: cs(12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(bundle.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
                    SizedBox(height: cs(2)),
                    Text(
                      bundle.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.display(11, weight: FontWeight.w400, em: 0, height: 1.25, color: CsColors.ink55),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: cs(10)),
          Expanded(
            child: ClipRect(
              child: Wrap(
                spacing: cs(6),
                runSpacing: cs(6),
                children: [
                  for (final entry in bundle.powerUps.entries)
                    CsChip(
                      '${entry.key.displayName} ×${entry.value}',
                      icon: CsIcons.powerUp(entry.key.inventoryKey),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: cs(8)),
          _footerRow(
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (bundle.originalPrice > bundle.bundlePrice) ...[
                    Text(
                      '${bundle.originalPrice.toInt()}',
                      style: t.mono(11, em: 0.04, color: CsColors.ink45).copyWith(
                            decoration: TextDecoration.lineThrough,
                            decorationColor: CsColors.ink45,
                          ),
                    ),
                    SizedBox(width: cs(8)),
                  ],
                  CsCoins(bundle.bundlePrice.toInt(), size: 12),
                ],
              ),
            ),
            CsButton.secondary(
              label: canAfford ? 'Buy' : 'Need coins',
              size: CsButtonSize.small,
              onPressed: buy,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _purchaseCoinBundle(PowerUpBundle bundle, bool canAfford) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    if (!canAfford) {
      showCsToast(context, 'Insufficient coins!', kind: CsToastKind.error);
      return;
    }
    // Local-first purchase: PowerUpCubit spends coins via CoinsCubit
    // (Drift write + sync outbox) and adds the bundle's counts to the
    // device inventory. Bundles are consumables — no ownership latch.
    final powerUpCubit = context.read<PowerUpCubit>();
    final newBalance = await powerUpCubit.purchaseBundleWithCoins(bundle.id);
    if (!mounted) return;
    if (newBalance == null) {
      showCsToast(context, 'Purchase failed. Try again.', kind: CsToastKind.error);
      return;
    }
    showCsToast(context, '${bundle.name} added to your armory!', kind: CsToastKind.success);
  }
}

// =============================================================================
// Private components
// =============================================================================

/// Grid tile for store items: rounded preview (with an optional corner
/// badge), Syne name, one/two-line blurb, then a fixed-height footer row.
/// The preview flexes so the tile fits any fixed grid row height.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.state,
    required this.preview,
    required this.name,
    required this.description,
    required this.footer,
    this.badge,
    this.onTap,
  });

  final CsTileState state;
  final Widget preview;
  final String name;
  final String description;
  final Widget footer;
  final Widget? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final footerH = cs(34).clamp(34.0, 44.0);
    return CsTile(
      state: state,
      onTap: onTap,
      padding: EdgeInsets.all(cs(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CsRadius.tile - 4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  preview,
                  if (badge != null)
                    Positioned(top: cs(6), right: cs(6), child: badge!),
                ],
              ),
            ),
          ),
          SizedBox(height: cs(8)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: cs(2)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.display(14, weight: FontWeight.w700, em: 0, height: 1.2),
                ),
                SizedBox(height: cs(2)),
                Text(
                  description,
                  maxLines: cs.isCompact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.display(11, weight: FontWeight.w400, em: 0, height: 1.25, color: CsColors.ink55),
                ),
                SizedBox(height: cs(6)),
                SizedBox(height: footerH, child: footer),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Watch an ad for coins" row. Self-hides for Pro users / when ads are
/// unavailable, and disables itself once the daily cap is hit or no ad is
/// loaded. Credits coins offline-first via [CoinsCubit.earnCoins] — the same
/// calls as the old shared rewarded-coins card, restyled for the store list.
class _RewardedCoinsRow extends StatefulWidget {
  const _RewardedCoinsRow();

  @override
  State<_RewardedCoinsRow> createState() => _RewardedCoinsRowState();
}

class _RewardedCoinsRowState extends State<_RewardedCoinsRow> {
  AdService? get _ads =>
      getIt.isRegistered<AdService>() ? getIt<AdService>() : null;

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
        RewardToast.show(amount: '+$amount COINS');
      },
    );
    if (mounted) setState(() {}); // refresh "N left today"
  }

  @override
  Widget build(BuildContext context) {
    final ads = _ads;
    if (ads == null || !ads.adsEnabled) return const SizedBox.shrink();
    final remaining = ads.freeCoinAdsRemainingToday;
    final enabled = ads.canShowFreeCoinAd;
    return CsListRow(
      onTap: enabled ? _watch : null,
      leading: const CsIconDisc(Symbols.play_circle_rounded, size: 34, color: CsColors.gold),
      title: 'Watch an ad — +${AdService.freeCoinsPerAd} coins',
      subtitle: enabled
          ? '$remaining left today'
          : (remaining == 0 ? 'Come back tomorrow for more' : 'No ad available right now'),
      trailing: CsButton.premium(
        label: 'Watch',
        size: CsButtonSize.small,
        onPressed: enabled ? _watch : null,
      ),
    );
  }
}

/// Very soft conic prism glow bleeding in from the top-right corner (the
/// store mock's only decoration). Painted once, never animates.
class _PrismGlow extends StatelessWidget {
  const _PrismGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _PrismGlowPainter(context.cs.s)),
      ),
    );
  }
}

class _PrismGlowPainter extends CustomPainter {
  _PrismGlowPainter(this.s);
  final double s;

  @override
  void paint(Canvas canvas, Size size) {
    final r = 180 * s;
    final c = Offset(size.width - 100 * s, 100 * s);
    final rect = Rect.fromCircle(center: c, radius: r);
    const alpha = 0.15;
    final paint = Paint()
      ..shader = SweepGradient(
        colors: [
          CsColors.cyan.withValues(alpha: alpha),
          CsColors.violet.withValues(alpha: alpha),
          CsColors.pink.withValues(alpha: alpha),
          CsColors.gold.withValues(alpha: alpha),
          CsColors.mint.withValues(alpha: alpha),
          CsColors.cyan.withValues(alpha: alpha),
        ],
        // CSS conic "from 200deg" → Flutter sweep starts at 3 o'clock.
        transform: const GradientRotation(1.92),
      ).createShader(rect)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 40 * s);
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(_PrismGlowPainter old) => old.s != s;
}

class _PowerUpCatalogItem {
  final String type;
  final String name;
  final String description;
  final int coinCost;
  const _PowerUpCatalogItem({
    required this.type,
    required this.name,
    required this.description,
    required this.coinCost,
  });
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
                ? CsColors.cyan
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
