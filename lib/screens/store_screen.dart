import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inapp_purchase/flutter_inapp_purchase.dart' as iap;
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/game/livery_decals.dart';
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
import 'package:cosmo_strike_flutter_app/widgets/reward_toast.dart';
import 'package:cosmo_strike_flutter_app/widgets/subscription_legal_links.dart';

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

  // Armory tab order (REBRAND_SPEC §1): Command / Credits / Liveries /
  // Exhausts / Sectors / Gear / Cup Passes. `?tab=N` deep links index into
  // this list (Credits = 1, Liveries = 2, Sectors = 4, Cup Passes = 6).
  // These names are the analytics tab ids — keep them stable.
  static const _tabNames = [
    'Command',
    'Credits',
    'Liveries',
    'Exhausts',
    'Sectors',
    'Gear',
    'Cup Passes',
  ];

  static const _tabLabels = _tabNames;

  static const _tabIcons = [
    Symbols.workspace_premium_rounded,
    Symbols.paid_rounded,
    Symbols.rocket_rounded,
    Symbols.local_fire_department_rounded,
    Symbols.public_rounded,
    Symbols.bolt_rounded,
    Symbols.confirmation_number_rounded,
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
                        // credit balance sits flush right like the mock.
                        topBarLeading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CsBackButton(),
                            SizedBox(width: cs(4)),
                            Text(
                              'ARMORY',
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
                              _buildCommandTab(premiumState),
                              _buildCreditsTab(coinsState),
                              _buildLiveriesTab(premiumState),
                              _buildExhaustsTab(theme, premiumState),
                              _buildSectorsTab(theme, premiumState),
                              _buildGearTab(coinsState),
                              _buildCupPassesTab(),
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

  /// Banner row atop the cosmetic tabs (liveries / exhausts / sectors)
  /// telling the user Strike Command unlocks everything in that tab. Tapping
  /// it (when not subscribed) jumps to the Command tab. Gear is intentionally
  /// excluded — Strike Command doesn't unlock the gear catalog.
  Widget _buildCommandIncludedRow(PremiumState premiumState, String itemsNoun) {
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
        title: isPro ? 'Unlocked by Strike Command' : 'Included with Strike Command',
        subtitle: isPro
            ? 'All $itemsNoun are unlocked for your hangar.'
            : 'Strike Command unlocks all $itemsNoun. No separate purchase.',
        trailing: isPro
            ? null
            : Icon(Symbols.chevron_right_rounded, size: cs(22), color: CsColors.ink45),
      ),
    );
  }

  /// One grid tile for a cosmetic (sector / livery / exhaust): preview on top,
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
    required bool showCommandBadge,
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
      badge: showCommandBadge
          ? const CsChip('Command', kind: CsChipKind.gold, icon: Symbols.lock_rounded)
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

  /// Dark base + soft palette wash behind a cosmetic preview — either a
  /// [painter] or a [child] widget.
  Widget _palettePreview(List<Color> palette, CustomPainter? painter, {Widget? child}) {
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
        child: SizedBox.expand(child: child ?? CustomPaint(painter: painter)),
      ),
    );
  }

  // ===========================================================================
  // COMMAND TAB (Strike Command subscription)
  // ===========================================================================

  static const _commandBenefitsLine =
      'No ads · Every livery, exhaust & sector · 1.5× credits · Frontline Command lane';

  Widget _buildCommandTab(PremiumState premiumState) {
    // Drops any Command SKU from the pending set once PremiumCubit reports
    // hasPremium=true — the spinner on the plan cards stops the moment the
    // backend's VerifyPurchase response lands.
    _reconcilePendingPurchases(premiumState);
    final cs = context.cs;
    final t = cs.type;

    // Paid subscriber → status + benefits only (no plans). Trial → status
    // with a convert CTA + the plan picker. Free → plan picker.
    final isPaidPro = premiumState.hasPremium && !premiumState.isOnPromo;
    final isTrial = premiumState.hasPremium && premiumState.isOnPromo;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: cs(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CsHeadline(
            const ['Strike ', 'Command'],
            prismIndex: 1,
            maxLines: 1,
            style: t.display(34, em: -0.03, height: 1.05),
          ),
          SizedBox(height: cs(8)),
          Text(
            _commandBenefitsLine,
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
          _sectionLabel('Clearance includes'),
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
              productId: ProductIds.commandMonthly,
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
              title: 'Annual',
              productId: ProductIds.commandAnnual,
              fallbackPrice: 39.99,
              cadence: '/yr',
              billedLabel: 'Billed annually',
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
    final anyProPending = _pendingProductIds.contains(ProductIds.commandMonthly) ||
        _pendingProductIds.contains(ProductIds.commandAnnual);
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
    // Paid subscribers keep the mint "verified" treatment.
    final isPromo = premiumState.isOnPromo;
    final expiry =
        isPromo ? premiumState.promoExpiresAt : premiumState.subscriptionExpiry;
    final expiryLabel = isPromo
        ? (expiry != null ? _formatPromoCountdown(expiry) : 'Free 3-day trial')
        : premiumState.renewalLabel;
    final anyProPending = _pendingProductIds.contains(ProductIds.commandMonthly) ||
        _pendingProductIds.contains(ProductIds.commandAnnual);
    return CsListRow(
      dividerTop: true,
      leading: CsIconDisc(
        isPromo ? Symbols.redeem_rounded : Symbols.verified_rounded,
        color: isPromo ? CsColors.gold : CsColors.mint,
      ),
      title: isPromo ? 'Strike Command trial active' : 'Strike Command active',
      titleTrailing: isPromo ? const CsChip('Trial', kind: CsChipKind.gold) : null,
      subtitle: expiryLabel,
      // Convert CTA — fires the monthly purchase, same path as the plan
      // card's Subscribe button.
      trailing: isPromo
          ? CsButton.premium(
              label: 'Keep Command — Subscribe',
              size: CsButtonSize.small,
              icon: Symbols.workspace_premium_rounded,
              loading: _pendingProductIds.contains(ProductIds.commandMonthly),
              onPressed: anyProPending
                  ? null
                  : () => _purchaseSubscription(
                      ProductIds.commandMonthly, 'Strike Command Monthly'),
            )
          : null,
    );
  }

  /// "Cancel anytime · Restore purchases" plus the auto-renew / Terms /
  /// Privacy links App Review requires next to subscription offers.
  Widget _buildProFooter() {
    final cs = context.cs;
    final t = cs.type;
    final quiet = t.mono(10, em: 0.04, color: CsColors.ink45);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Auto-renews · Cancel anytime  ·  ', style: quiet),
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
        Text('  ·  ', style: quiet),
        const SubscriptionLegalLinks(compact: true),
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
    // granted. 'No ads' is real: AdService is subscription-gated so
    // subscribers / trial users never see banners, interstitials, or
    // rewarded offers.
    final features = [
      (Symbols.block_rounded, 'No ads. Fly completely ad-free'),
      (Symbols.public_rounded, 'All ${PremiumContent.premiumThemes.length} premium Sectors'),
      (Symbols.rocket_rounded,
          'All ${LiveryType.values.where((l) => l.isPremium).length} premium liveries'),
      (Symbols.local_fire_department_rounded,
          'All ${ExhaustType.values.where((e) => e.isPremium).length} premium exhausts'),
      (Symbols.paid_rounded, '1.5× credit earnings'),
      (Symbols.bolt_rounded, '5× Tactical Gear every cycle'),
      (Symbols.confirmation_number_rounded, 'Scout, Strike and Ace Cup Passes each cycle'),
      (Symbols.workspace_premium_rounded, 'Frontline Command lane every season'),
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

  /// Every paid path on this screen funnels through this check. Guests
  /// never have to register (App Store guideline 5.1.1(v)): a local guest
  /// gets a silent anonymous account so the purchase can be verified, and
  /// signing in stays optional. Only a missing connection blocks the buy.
  Future<bool> _ensurePurchasable() async {
    final ok = await context.read<AuthCubit>().ensurePurchaseAccount();
    if (!ok && mounted) showCsToast(context, "Couldn't reach the store. Check your connection and try again.", kind: CsToastKind.error);
    return ok;
  }

  /// Restore purchases — guests included (on their silent anonymous
  /// account). Results arrive asynchronously on the purchase stream.
  Future<void> _restorePurchases() async {
    if (!await _ensurePurchasable() || !mounted) return;
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
  // CREDITS TAB
  // ===========================================================================

  Widget _buildCreditsTab(CoinsState coinsState) {
    const options = CoinPurchaseOption.availableOptions;
    return _tabScroll([
      _box(_tabHeader('Credits', subtitle: 'Requisition a Credit Cache, or earn credits in the field.')),
      _box(_sectionLabel('Credit Caches', first: true)),
      _tileGrid(
        count: options.length,
        minTile: 140,
        extent: 214,
        maxColumns: 4,
        maxColumnsTablet: 4,
        itemBuilder: (context, i) => _buildCoinPackTile(options[i]),
      ),
      _box(_sectionLabel('Earn credits in the field')),
      // Rewarded ad — self-hides for subscribers / when no ad is available.
      const SliverToBoxAdapter(child: _RewardedCoinsRow()),
      _box(_buildEarnMethodRow('Fly sorties', '5 CR per run', Symbols.rocket_launch_rounded)),
      _box(_buildEarnMethodRow('Supply Drop', '10–50 CR daily', Symbols.calendar_today_rounded)),
      _box(_buildEarnMethodRow('Commendations', '25–100 CR', Symbols.military_tech_rounded)),
      _box(_buildEarnMethodRow('Sector Cups', '100+ CR', Symbols.leaderboard_rounded)),
    ]);
  }

  Future<void> _purchaseCoinPack(CoinPurchaseOption option) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final price = PurchaseService().getStorePriceOrDefault(
        ProductIds.withPrefix(option.id), option.price);
    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Credits',
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
  // SECTORS TAB
  // ===========================================================================

  Widget _buildSectorsTab(GameTheme theme, PremiumState premiumState) {
    // Premium sectors — store products (also included with Strike Command).
    final premiumSectors = PremiumContent.premiumThemes.toList();
    // Free sectors — included with every install. Surfaced here so the
    // player has an obvious way back after trying a premium one. High
    // Contrast lives in Settings → Accessibility.
    const freeSectors = [
      GameTheme.prismNoir,
      GameTheme.neonGrid,
      GameTheme.monochrome,
    ];

    // Once a pending purchase reflects as owned, drop it from the pending
    // set on the next frame so we don't trigger a build-during-build.
    _reconcilePendingPurchases(premiumState);

    return _tabScroll([
      _box(_tabHeader(
        'Sectors',
        subtitle: 'Sectors recolour the battlefield in flight: shots, thrust '
            'and the sector glow. Menus stay Prism Noir.',
      )),
      _box(_buildCommandIncludedRow(premiumState, 'sectors')),
      // Strike Command already includes every sector — don't sell subscribers
      // the bundle.
      if (!premiumState.hasPremium) _box(_buildSectorAtlasTile(premiumState)),
      _box(_sectionLabel('Premium sectors')),
      _tileGrid(
        count: premiumSectors.length,
        itemBuilder: (context, i) => _buildSectorTile(premiumSectors[i], theme, premiumState),
      ),
      _box(_sectionLabel('Free sectors', note: 'Always cleared. Switch back any time.')),
      _tileGrid(
        count: freeSectors.length,
        itemBuilder: (context, i) => _buildSectorTile(freeSectors[i], theme, premiumState),
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

  /// Resolve "is this productId now owned" across sectors / liveries /
  /// exhausts / kits so the pending spinner clears regardless of type.
  bool _isProductOwned(String productId, PremiumState premiumState) {
    // Strike Command SKUs — once PremiumCubit flips to hasPremium=true the
    // Command tab swaps to the status row, but we also clear pending so any
    // leftover spinner state doesn't survive a tab switch.
    if (productId == ProductIds.commandMonthly ||
        productId == ProductIds.commandAnnual) {
      return premiumState.hasPremium;
    }
    final stripped = ProductIds.stripPrefix(productId);
    // Star Atlas — owned once recorded, or once every sector is unlocked.
    if (stripped == FleetKit.sectorAtlasId) {
      return premiumState.isBundleOwned(FleetKit.sectorAtlasId) ||
          PremiumContent.premiumThemes.every(premiumState.isThemeUnlocked);
    }
    final sector = GameTheme.fromId(stripped);
    if (sector != null && sector.productId == stripped) {
      return premiumState.isThemeUnlocked(sector);
    }
    if (stripped.startsWith('livery_')) return premiumState.isSkinOwned(stripped);
    if (stripped.startsWith('exhaust_')) return premiumState.isTrailOwned(stripped);
    // Fleet Kits — owned set uses the bare kit ID.
    return premiumState.isBundleOwned(stripped);
  }

  Widget _buildSectorAtlasTile(PremiumState premiumState) {
    final cs = context.cs;
    final t = cs.type;
    final bundleOwned = _isProductOwned(ProductIds.sectorAtlas, premiumState);
    final isPending = _pendingProductIds.contains(ProductIds.sectorAtlas);
    final price = PurchaseService().getStorePriceOrDefault(
      ProductIds.sectorAtlas,
      6.99,
    );
    void buy() => _purchaseSectorProduct(
          ProductIds.sectorAtlas,
          'Star Atlas',
          fallbackPrice: 6.99,
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
          CsIconDisc(Symbols.public_rounded, size: 38, color: CsColors.gold),
          SizedBox(width: cs(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Star Atlas', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
                SizedBox(height: cs(3)),
                Text(
                  _sectorAtlasSubtitle().toUpperCase(),
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

  Future<void> _purchaseFleetKit(FleetKit kit) async {
    if (!await _ensurePurchasable() || !mounted) return;
    final productId = ProductIds.withPrefix(kit.id);
    final price = PurchaseService().getStorePriceOrDefault(productId, kit.kitPrice);
    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Fleet Kit',
      title: kit.name,
      message: 'Unlock ${_kitContents(kit)} for $price?',
      confirmLabel: 'Buy · $price',
    );
    if (!confirmed || !mounted) return;
    try {
      await PurchaseService().purchaseProduct(productId);
      if (!mounted) return;
      _markPending(productId);
      showCsToast(context, 'Verifying ${kit.name}…');
    } catch (e) {
      if (mounted) {
        showCsToast(context, 'Fleet Kit unavailable. Try again later.', kind: CsToastKind.error);
      }
    }
  }

  String _kitContents(FleetKit kit) {
    String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    return '${plural(kit.liveries.length, 'livery', 'liveries')} + '
        '${plural(kit.exhausts.length, 'exhaust', 'exhausts')}';
  }

  Widget _buildFleetKitTile(FleetKit kit, PremiumState premiumState) {
    final cs = context.cs;
    final t = cs.type;
    final productId = ProductIds.withPrefix(kit.id);
    final owned = premiumState.isBundleOwned(kit.id);
    final isPending = _pendingProductIds.contains(productId);
    final price = PurchaseService().getStorePriceOrDefault(productId, kit.kitPrice);
    void buy() => _purchaseFleetKit(kit);
    final Widget action;
    if (isPending) {
      action = const CsButton.secondary(label: 'Verifying', size: CsButtonSize.small, loading: true);
    } else if (owned) {
      action = const CsChip('Owned', kind: CsChipKind.mint, size: 10);
    } else {
      action = CsButton.premium(label: 'Buy · $price', size: CsButtonSize.small, onPressed: buy);
    }
    return CsTile(
      state: owned ? CsTileState.done : CsTileState.future,
      onTap: (owned || isPending) ? null : buy,
      padding: EdgeInsets.symmetric(horizontal: cs(14), vertical: cs(12)),
      child: Row(
        children: [
          CsIconDisc(Symbols.inventory_2_rounded, size: 38, color: CsColors.gold),
          SizedBox(width: cs(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(kit.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
                SizedBox(height: cs(3)),
                Text(
                  '${_kitContents(kit)} · ${kit.description}'.toUpperCase(),
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

  Widget _buildSectorTile(
    GameTheme target,
    GameTheme currentTheme,
    PremiumState premiumState,
  ) {
    final isOwned = premiumState.isThemeUnlocked(target);
    final isActive = currentTheme == target;
    final productId = _productIdForSector(target);
    final isPending =
        productId != null && _pendingProductIds.contains(productId);
    final price = productId == null
        ? 'FREE'
        : PurchaseService().getStorePriceOrDefault(productId, 1.99);
    return _cosmeticTile(
      preview: _SectorPreview(theme: target),
      name: target.displayName,
      description: target.description,
      isEquipped: isActive,
      isOwned: isOwned,
      isPending: isPending,
      showCommandBadge: !isOwned && productId != null,
      priceLabel: price,
      equippedLabel: 'Deployed',
      ownedLabel: productId == null ? 'Free' : 'Owned',
      equipLabel: 'Deploy',
      onEquip: () {
        context.read<ThemeCubit>().setTheme(target);
        showCsToast(context, 'Sector set: ${target.displayName}.',
            kind: CsToastKind.success, duration: const Duration(seconds: 1));
      },
      onBuy: () {
        if (productId != null) _purchaseSectorProduct(productId, target.displayName);
      },
    );
  }

  /// "Save N%" for annual vs 12× monthly, from live store prices.
  String? _yearlySavingsLabel() {
    final pct = PurchaseService().yearlySavingsPercent(ProductIds.commandMonthly, ProductIds.commandAnnual);
    return pct == null ? null : 'Save $pct%';
  }

  static final List<String> _premiumSectorIds = [
    for (final t in PremiumContent.premiumThemes) ProductIds.withPrefix(t.id),
  ];

  /// Star Atlas subtitle; the saving is the bundle vs buying every premium
  /// sector separately at live store prices (omitted until all prices load).
  String _sectorAtlasSubtitle() {
    final purchases = PurchaseService();
    final bundle = purchases.getStorePriceValue(ProductIds.sectorAtlas);
    final singles = _premiumSectorIds.map(purchases.getStorePriceValue).toList();
    final sameCurrency = _premiumSectorIds.every(
      (id) => purchases.getStoreCurrency(id) == purchases.getStoreCurrency(ProductIds.sectorAtlas),
    );
    final pct = (singles.contains(null) || !sameCurrency)
        ? null
        : PurchaseService.savingsPercent(
            full: singles.fold<double>(0, (a, b) => a + b!),
            actual: bundle,
          );
    final base = 'All ${_premiumSectorIds.length} premium sectors';
    return pct == null ? base : '$base · save $pct%';
  }

  String? _productIdForSector(GameTheme target) {
    final id = target.productId;
    return id == null ? null : ProductIds.withPrefix(id);
  }

  Future<void> _purchaseSectorProduct(
    String productId,
    String displayName, {
    double fallbackPrice = 1.99,
  }) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final price = PurchaseService().getStorePriceOrDefault(productId, fallbackPrice);
    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Sector',
      title: displayName,
      message: 'Unlock $displayName for $price? Sectors recolour shots, thrust '
          'and the battlefield glow in flight.',
      confirmLabel: 'Buy · $price',
    );

    if (!confirmed || !mounted) return;

    try {
      await PurchaseService().purchaseProduct(productId);
      if (!mounted) return;
      _markPending(productId);
      showCsToast(context, 'Verifying $displayName…');
    } catch (e) {
      if (mounted) {
        showCsToast(
          context,
          'Sector unavailable. Try again later.',
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
  // LIVERIES TAB
  // ===========================================================================

  Widget _buildLiveriesTab(PremiumState premiumState) {
    _reconcilePendingPurchases(premiumState);
    const liveries = LiveryType.values;
    return _tabScroll([
      _box(_tabHeader(
        'Liveries',
        subtitle: 'Paint schemes for your hull. Each carries its own decal.',
      )),
      _box(_buildCommandIncludedRow(premiumState, 'liveries')),
      // Fleet Kits. Strike Command already includes every cosmetic.
      if (!premiumState.hasPremium) ...[
        _box(_sectionLabel('Fleet Kits', first: true, note: 'Liveries and exhausts together, for less.')),
        for (final kit in FleetKit.availableKits)
          _box(Padding(
            padding: EdgeInsets.only(bottom: context.cs(8)),
            child: _buildFleetKitTile(kit, premiumState),
          )),
        _box(_sectionLabel('Liveries')),
      ],
      _tileGrid(
        count: liveries.length,
        itemBuilder: (context, index) {
          final livery = liveries[index];
          // Strike Command unlocks every premium livery (mirrors sectors).
          final isUnlocked = premiumState.isLiveryUnlocked(livery);
          final isSelected = premiumState.selectedSkinId == livery.id;
          final productId = ProductIds.withPrefix(livery.id);
          return _cosmeticTile(
            // Each tile shows the real hull painted the way the livery
            // renders in flight: tint + decal.
            preview: _palettePreview(livery.colors, null, child: _LiveryShipPreview(livery: livery)),
            name: livery.displayName,
            description: livery.description,
            isEquipped: isSelected,
            isOwned: isUnlocked,
            isPending: _pendingProductIds.contains(productId),
            showCommandBadge: !isUnlocked && livery.isPremium,
            priceLabel: livery.isPremium
                ? PurchaseService().getStorePriceOrDefault(productId, livery.price)
                : 'FREE',
            equipLabel: 'Apply',
            equippedLabel: 'Applied',
            onEquip: () {
              context.read<PremiumCubit>().selectSkin(livery.id);
              showCsToast(context, 'Livery applied: ${livery.displayName}.',
                  kind: CsToastKind.success, duration: const Duration(seconds: 1));
            },
            onBuy: () => _purchaseCosmetic(
              productId: productId,
              displayName: livery.displayName,
              fallbackPrice: livery.price,
            ),
          );
        },
      ),
    ]);
  }

  // ===========================================================================
  // EXHAUSTS TAB
  // ===========================================================================

  Widget _buildExhaustsTab(GameTheme theme, PremiumState premiumState) {
    _reconcilePendingPurchases(premiumState);
    const exhausts = ExhaustType.values;
    return _tabScroll([
      _box(_tabHeader(
        'Exhausts',
        subtitle: 'Engine effects behind your hull. Shown while engine '
            'effects are on in Settings.',
      )),
      _box(_buildCommandIncludedRow(premiumState, 'exhausts')),
      _tileGrid(
        count: exhausts.length,
        itemBuilder: (context, index) {
          final exhaust = exhausts[index];
          final isUnlocked = premiumState.isExhaustUnlocked(exhaust);
          final isSelected = premiumState.selectedTrailId == exhaust.id;
          final productId = ProductIds.withPrefix(exhaust.id);
          // Stock falls back to the current sector's accent wash.
          final palette = exhaust.colors.isNotEmpty
              ? exhaust.colors
              : [
                  theme.accentColor.withValues(alpha: 0.35),
                  theme.backgroundColor.withValues(alpha: 0.6),
                ];
          return _cosmeticTile(
            preview: _palettePreview(palette, null, child: _ExhaustShipPreview(exhaust: exhaust)),
            name: exhaust.displayName,
            description: exhaust.description,
            isEquipped: isSelected,
            isOwned: isUnlocked,
            isPending: _pendingProductIds.contains(productId),
            showCommandBadge: !isUnlocked && exhaust.isPremium,
            priceLabel: exhaust.isPremium
                ? PurchaseService().getStorePriceOrDefault(productId, exhaust.price)
                : 'FREE',
            equipLabel: 'Fit',
            equippedLabel: 'Fitted',
            onEquip: () {
              context.read<PremiumCubit>().selectTrail(exhaust.id);
              showCsToast(context, 'Exhaust fitted: ${exhaust.displayName}.',
                  kind: CsToastKind.success, duration: const Duration(seconds: 1));
            },
            onBuy: () => _purchaseCosmetic(
              productId: productId,
              displayName: exhaust.displayName,
              fallbackPrice: exhaust.price,
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
      eyebrow: 'Armory',
      title: displayName,
      message: 'Unlock $displayName for $price?',
      confirmLabel: 'Buy · $price',
    );

    if (!confirmed || !mounted) return;

    try {
      await PurchaseService().purchaseProduct(productId);
      if (!mounted) return;
      _markPending(productId);
      showCsToast(context, 'Verifying $displayName…');
    } catch (e) {
      if (mounted) {
        showCsToast(
          context,
          'Item unavailable. Try again later.',
          kind: CsToastKind.error,
        );
      }
    }
  }

  // ===========================================================================
  // GEAR TAB (Tactical Gear)
  // ===========================================================================
  // Gear has a real credit-purchased inventory. The keys match the inventory
  // keys the gameplay engine consumes (ArmedLoadout.apply), so each purchase
  // produces a usable stockpile entry armed from the home loadout chip.

  /// Rewarded-ad row granting one free Afterburner. Self-hides for
  /// subscribers / web / when the SDK isn't ready; disables when no ad is
  /// loaded.
  Widget _buildFreeGearAdRow() {
    final ads = getIt.isRegistered<AdService>() ? getIt<AdService>() : null;
    if (ads == null || !ads.adsEnabled) return const SizedBox.shrink();
    final ready = ads.isRewardedReady;
    final name = PremiumPowerUpType.speedBoost.displayName;
    void watch() {
      final powerUps = context.read<PowerUpCubit>();
      // Capped like the identical home placement (3/day).
      ads.showRewardedCapped(
        capKey: AdService.capFreePowerUp,
        onReward: () {
          powerUps.grantFreePowerUp();
          RewardToast.show(
            icon: Symbols.bolt_rounded,
            amount: '+1 ${name.toUpperCase()}',
          );
        },
      );
    }

    return CsListRow(
      onTap: ready ? watch : null,
      leading: CsIconDisc(Symbols.play_circle_rounded, size: 34, color: CsColors.gold),
      title: 'Watch an ad: free $name',
      subtitle: ready ? 'Adds 1 $name to your loadout' : 'No ad available right now',
      trailing: CsButton.premium(
        label: 'Watch',
        size: CsButtonSize.small,
        onPressed: ready ? watch : null,
      ),
    );
  }

  Widget _buildGearTab(CoinsState coinsState) {
    // Descriptions promise exactly what ArmedLoadout.apply does, nothing
    // more. Credit costs (PremiumPowerUpType.creditCost) MUST match
    // PurchasePowerUpWithCoinsCommandHandler.AllowedCosts on the backend.
    const gear = PremiumPowerUpType.values;
    const bundles = PowerUpBundle.availableBundles;

    return BlocBuilder<PowerUpCubit, PowerUpState>(
      builder: (context, powerUpState) {
        return _tabScroll([
          _box(_tabHeader(
            'Tactical Gear',
            subtitle: 'Buy with credits, then arm one from the home loadout '
                'chip. It activates 5s into your next run.',
          )),
          // Rewarded ad — free Afterburner. Self-hides for subscribers / no ad.
          _box(_buildFreeGearAdRow()),
          _box(_sectionLabel('Gear')),
          _tileGrid(
            count: gear.length,
            extent: 214,
            itemBuilder: (context, i) => _buildGearTile(gear[i], powerUpState),
          ),
          _box(_sectionLabel(
            'Gear bundles',
            note: 'Stock several systems at once, for fewer credits.',
          )),
          _tileGrid(
            count: bundles.length,
            minTile: 300,
            extent: 200,
            maxColumns: 3,
            minColumns: 1,
            itemBuilder: (context, i) => _buildGearBundleTile(bundles[i], coinsState),
          ),
        ]);
      },
    );
  }

  // ===========================================================================
  // CUP PASSES TAB
  // ===========================================================================

  Widget _buildCupPassesTab() {
    return _tabScroll([
      _box(_tabHeader(
        'Cup Passes',
        subtitle: 'Entry passes for Sector Cups. Each Cup takes one pass of '
            'its tier. Strike Command includes free passes.',
      )),
      _box(_sectionLabel('Requisition passes', first: true)),
      _tileGrid(
        count: _visibleCupPasses.length,
        minTile: 150,
        extent: 214,
        maxColumns: 5,
        maxColumnsTablet: 5,
        itemBuilder: (context, i) => _buildCupPassTile(_visibleCupPasses[i]),
      ),
    ]);
  }

  /// Bundle offers are shown only once the store actually returns their
  /// product: App Review rejects apps that show unsubmitted purchases, and
  /// the multi-pass bundles may be approved after the build. See CLAUDE.md
  /// "Pending App Store items".
  List<_CupPassOffer> get _visibleCupPasses => [
        for (final o in _cupPasses)
          if (!o.requiresStoreProduct || PurchaseService().getProduct(o.productId) != null) o,
      ];

  /// Wire tier → pass name (bronze/silver/gold keep their wire names).
  static const _tierNames = {'bronze': 'Scout', 'silver': 'Strike', 'gold': 'Ace'};

  static const _cupPasses = [
    _CupPassOffer(ProductIds.cupScout, 'Scout Cup Pass', '1 Scout pass', 0.99, CsColors.ink70, ['bronze']),
    _CupPassOffer(ProductIds.cupStrike, 'Strike Cup Pass', '1 Strike pass', 1.99, CsColors.ink, ['silver']),
    _CupPassOffer(ProductIds.cupAce, 'Ace Cup Pass', '1 Ace pass', 4.99, CsColors.gold, ['gold']),
    _CupPassOffer(ProductIds.cupAceTrio, 'Ace Trio', '3 Ace passes', 9.99, CsColors.gold, ['gold'],
        requiresStoreProduct: true),
    _CupPassOffer(ProductIds.cupSquadron, 'Squadron Bundle', '5 Ace + 5 Strike', 19.99, CsColors.violet,
        ['gold', 'silver'], requiresStoreProduct: true),
  ];

  Future<void> _purchaseCupPass(_CupPassOffer offer) async {
    if (!await _ensurePurchasable() || !mounted) return;
    final price = PurchaseService().getStorePriceOrDefault(offer.productId, offer.fallbackPrice);
    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Cup Passes',
      title: 'Buy ${offer.name}',
      message: 'Get ${offer.grants} for $price?',
      confirmLabel: 'Buy · $price',
    );
    if (!confirmed || !mounted) return;
    try {
      await PurchaseService().purchaseProduct(offer.productId);
      _markPending(offer.productId);
    } catch (e) {
      if (mounted) {
        showCsToast(context, 'Pass unavailable. Try again later.', kind: CsToastKind.error);
      }
    }
  }

  Widget _buildCupPassTile(_CupPassOffer offer) {
    final cs = context.cs;
    final t = cs.type;
    final premium = context.watch<PremiumCubit>().state;
    final price = PurchaseService().getStorePriceOrDefault(offer.productId, offer.fallbackPrice);
    final owned = offer.tiers
        .map((tier) => (tier, premium.getTournamentEntryCount(tier)))
        .where((e) => e.$2 > 0)
        .map((e) => '${e.$2} ${_tierNames[e.$1]}')
        .join(' · ');
    void onTap() => _purchaseCupPass(offer);
    return CsTile(
      state: CsTileState.future,
      onTap: onTap,
      padding: EdgeInsets.all(cs(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.confirmation_number_rounded, size: cs(26), color: offer.color),
          const Spacer(),
          Text(
            offer.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.display(14, weight: FontWeight.w700, em: 0, height: 1.2),
          ),
          SizedBox(height: cs(2)),
          Text(offer.grants.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.mono(10, em: 0.04, color: CsColors.ink45)),
          SizedBox(height: cs(2)),
          Text(
            owned.isEmpty ? 'NONE HELD' : 'HELD: ${owned.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.mono(9, em: 0.06, color: owned.isEmpty ? CsColors.ink30 : CsColors.mint),
          ),
          SizedBox(height: cs(10)),
          CsButton.secondary(
            label: price,
            size: CsButtonSize.small,
            expand: true,
            loading: _pendingProductIds.contains(offer.productId),
            onPressed: onTap,
          ),
        ],
      ),
    );
  }

  Widget _buildGearTile(PremiumPowerUpType item, PowerUpState powerUpState) {
    final cs = context.cs;
    final owned = powerUpState.countFor(item.inventoryKey);
    void buy() => _purchaseGearWithCredits(item);
    return _ItemTile(
      state: owned > 0 ? CsTileState.done : CsTileState.future,
      onTap: buy,
      preview: ColoredBox(
        color: CsColors.raised,
        child: Center(
          child: Icon(item.icon, size: cs(34), color: CsColors.ink),
        ),
      ),
      badge: owned > 0 ? CsChip('×$owned', kind: CsChipKind.mint) : null,
      name: item.displayName,
      description: item.description,
      footer: _footerRow(
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CsCoins(item.creditCost),
        ),
        CsButton.secondary(label: 'Buy', size: CsButtonSize.small, onPressed: buy),
      ),
    );
  }

  Future<void> _purchaseGearWithCredits(PremiumPowerUpType item) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    final coinsCubit = context.read<CoinsCubit>();
    final powerUpCubit = context.read<PowerUpCubit>();
    final balance = coinsCubit.state.balance.total;
    if (balance < item.creditCost) {
      showCsToast(context, 'Insufficient credits.', kind: CsToastKind.error);
      return;
    }

    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Tactical Gear',
      title: item.displayName,
      message: 'Buy 1 ${item.displayName} for ${item.creditCost} CR?',
      confirmLabel: 'Buy · ${item.creditCost} CR',
    );
    if (!confirmed || !mounted) return;

    final newBalance =
        await powerUpCubit.purchaseWithCoins(item.inventoryKey, item.creditCost);
    if (!mounted) return;
    if (newBalance == null) {
      showCsToast(context, 'Requisition failed. Try again.', kind: CsToastKind.error);
      return;
    }
    // Reflect the server-authoritative balance locally so the CoinsCubit and
    // any other UI stays in sync without an extra round-trip.
    await coinsCubit.setServerBalance(newBalance);
    if (!mounted) return;
    showCsToast(
      context,
      '${item.displayName} added to your loadout.',
      kind: CsToastKind.success,
      duration: const Duration(seconds: 2),
    );
  }

  Widget _buildGearBundleTile(PowerUpBundle bundle, CoinsState coinsState) {
    final cs = context.cs;
    final t = cs.type;
    // Bundles are CONSUMABLE count packs — repeat-purchasable by design
    // (no "owned" latch; every buy adds the counts to the inventory).
    final canAfford = coinsState.balance.total >= bundle.bundlePrice;
    void buy() => _purchaseGearBundle(bundle, canAfford);
    final lead = bundle.powerUps.keys.isEmpty ? null : bundle.powerUps.keys.first;
    return CsTile(
      state: CsTileState.future,
      onTap: buy,
      padding: EdgeInsets.all(cs(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CsIconDisc(lead?.icon ?? Symbols.bolt_rounded, size: 34, color: CsColors.gold),
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
                      icon: entry.key.icon,
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
              label: canAfford ? 'Buy' : 'Need credits',
              size: CsButtonSize.small,
              onPressed: buy,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _purchaseGearBundle(PowerUpBundle bundle, bool canAfford) async {
    if (!await _ensurePurchasable()) return;
    if (!mounted) return;
    if (!canAfford) {
      showCsToast(context, 'Insufficient credits.', kind: CsToastKind.error);
      return;
    }
    // Local-first purchase: PowerUpCubit spends credits via CoinsCubit
    // (Drift write + sync outbox) and adds the bundle's counts to the
    // device inventory. Bundles are consumables — no ownership latch.
    final powerUpCubit = context.read<PowerUpCubit>();
    final newBalance = await powerUpCubit.purchaseBundleWithCoins(bundle.id);
    if (!mounted) return;
    if (newBalance == null) {
      showCsToast(context, 'Requisition failed. Try again.', kind: CsToastKind.error);
      return;
    }
    showCsToast(context, '${bundle.name} stowed in your loadout.', kind: CsToastKind.success);
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

/// "Watch an ad for credits" row. Self-hides for subscribers / when ads are
/// unavailable, and disables itself once the daily cap is hit or no ad is
/// loaded. Credits offline-first via [CoinsCubit.earnCoins] — the same
/// calls as the old shared rewarded card, restyled for the Armory list.
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
        RewardToast.show(amount: '+$amount CR');
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
      title: 'Watch an ad: +${AdService.freeCoinsPerAd} CR',
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

// =============================================================================
// Helpers
// =============================================================================

class _SectorPreview extends StatelessWidget {
  final GameTheme theme;
  const _SectorPreview({required this.theme});

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
          Positioned.fill(
            child: CustomPaint(painter: _SectorScenePainter(theme: theme)),
          ),
          Align(
            alignment: const Alignment(-0.55, 0),
            child: FractionallySizedBox(
              widthFactor: 0.34,
              child: Image.asset('assets/game/player/player_ship.png', filterQuality: FilterQuality.medium),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sector card scene: what a run looks like in this sector — the hull, a
/// burst of shots and the battlefield glow in the sector's primary and
/// secondary, the same pair CosmoPalette.applyGameTheme feeds the game.
class _SectorScenePainter extends CustomPainter {
  final GameTheme theme;
  _SectorScenePainter({required this.theme});

  Color get _accent => theme.shipColor;
  Color get _secondary => theme.secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // Battlefield glow: accent behind the ship, secondary far right.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.5, 0),
          radius: 0.9,
          colors: [_accent.withValues(alpha: 0.22), _accent.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.9, -0.4),
          radius: 0.7,
          colors: [_secondary.withValues(alpha: 0.18), _secondary.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    // Shots streaking right from the nose.
    final shot = Paint()
      ..color = _accent
      ..strokeWidth = h * 0.025
      ..strokeCap = StrokeCap.round;
    final glow = Paint()
      ..color = _accent.withValues(alpha: 0.25)
      ..strokeWidth = h * 0.07
      ..strokeCap = StrokeCap.round;
    for (final x in const [0.52, 0.68, 0.84]) {
      final a = Offset(w * x, h * 0.5), b = Offset(w * (x + 0.07), h * 0.5);
      canvas.drawLine(a, b, glow);
      canvas.drawLine(a, b, shot);
    }
    // A couple of hostile rounds in the secondary colour.
    final ring = Paint()
      ..color = _secondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.018;
    canvas.drawCircle(Offset(w * 0.74, h * 0.24), h * 0.04, ring);
    canvas.drawCircle(Offset(w * 0.88, h * 0.72), h * 0.04, ring);
  }

  @override
  bool shouldRepaint(covariant _SectorScenePainter old) => old.theme != theme;
}

/// Exhaust card: the hull with a static rendering of the exhaust's look
/// (mirrors the in-game ShipExhaust styles). Stock shows the bare hull.
class _ExhaustShipPreview extends StatelessWidget {
  const _ExhaustShipPreview({required this.exhaust});
  final ExhaustType exhaust;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      if (exhaust != ExhaustType.stock) CustomPaint(painter: _ExhaustPainter(exhaust)),
      Align(
        alignment: const Alignment(0.45, 0),
        child: FractionallySizedBox(
          widthFactor: 0.4,
          child: Image.asset('assets/game/player/player_ship.png', filterQuality: FilterQuality.medium),
        ),
      ),
    ]);
  }
}

class _ExhaustPainter extends CustomPainter {
  _ExhaustPainter(this.exhaust);
  final ExhaustType exhaust;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final palette = exhaust.colors;
    final cy = h * 0.5;
    final nozzle = w * 0.47; // just behind the hull's tail
    final rng = math.Random(7); // fixed seed: same scatter every frame
    final p = Paint();
    switch (exhaust) {
      case ExhaustType.stock:
        return;
      case ExhaustType.ion:
        p
          ..strokeCap = StrokeCap.round
          ..strokeWidth = h * 0.05
          ..color = palette.first.withValues(alpha: 0.2);
        canvas.drawLine(Offset(nozzle, cy), Offset(w * 0.08, cy), p);
        p
          ..strokeWidth = h * 0.016
          ..color = palette.last;
        canvas.drawLine(Offset(nozzle, cy), Offset(w * 0.08, cy), p);
      case ExhaustType.comet:
        p.shader = LinearGradient(colors: [
          palette.last.withValues(alpha: 0),
          palette.last.withValues(alpha: 0.7),
          palette.first,
        ]).createShader(Rect.fromLTRB(w * 0.02, 0, nozzle, h));
        canvas.drawPath(
          Path()
            ..moveTo(nozzle, cy - h * 0.06)
            ..lineTo(w * 0.02, cy)
            ..lineTo(nozzle, cy + h * 0.06)
            ..close(),
          p,
        );
      case ExhaustType.pulse:
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.014;
        for (var i = 0; i < 3; i++) {
          final t = i / 2;
          p.color = palette[i % palette.length].withValues(alpha: 1 - 0.6 * t);
          canvas.drawCircle(Offset(nozzle - w * (0.1 + 0.14 * i), cy), h * (0.05 + 0.07 * t), p);
        }
      case ExhaustType.quantum:
        // Fading violet/cyan hull outlines trailing behind.
        for (var i = 3; i >= 1; i--) {
          p.color = palette[i % palette.length].withValues(alpha: 0.12 + 0.1 * (3 - i));
          final x = nozzle - w * 0.12 * i;
          canvas.drawPath(
            Path()
              ..moveTo(x + w * 0.1, cy)
              ..lineTo(x - w * 0.06, cy - h * 0.17)
              ..lineTo(x - w * 0.03, cy)
              ..lineTo(x - w * 0.06, cy + h * 0.17)
              ..close(),
            p,
          );
        }
      case ExhaustType.plasma:
      case ExhaustType.ember:
      case ExhaustType.nova:
        final count = exhaust == ExhaustType.plasma ? 12 : 22;
        for (var i = 0; i < count; i++) {
          final t = i / (count - 1); // 0 at the engine, 1 at the far left
          final x = w * (0.46 - 0.42 * t);
          final spread = exhaust == ExhaustType.ember ? 0.42 : 0.24;
          var y = cy + (rng.nextDouble() - 0.5) * h * (0.04 + spread * t);
          if (exhaust == ExhaustType.ember) y += h * 0.12 * t * t; // sparks fall
          final r = exhaust == ExhaustType.plasma
              ? h * (0.09 - 0.04 * t)
              : h * (0.035 - 0.02 * t);
          final c = palette[i % palette.length];
          final alpha = 1.0 - 0.8 * t;
          canvas.drawCircle(Offset(x, y), r * 2.2, Paint()..color = c.withValues(alpha: 0.18 * alpha));
          canvas.drawCircle(Offset(x, y), r, Paint()..color = c.withValues(alpha: alpha));
        }
    }
  }

  @override
  bool shouldRepaint(covariant _ExhaustPainter old) => old.exhaust != exhaust;
}

/// Armory preview for a livery: the real hull sprite tinted exactly like
/// in flight (PlayerShip: hull colour at 55% srcATop plus a soft halo) with
/// the livery's decal painted on top, clipped to the hull.
class _LiveryShipPreview extends StatelessWidget {
  const _LiveryShipPreview({required this.livery});
  final LiveryType livery;

  @override
  Widget build(BuildContext context) {
    final tint = livery == LiveryType.standard ? null : livery.hullColor;
    final glow = tint == null
        ? null
        : (tint.computeLuminance() < 0.05 ? livery.decalColor : tint);
    return Center(
      child: FractionallySizedBox(
        widthFactor: 0.58,
        child: AspectRatio(
          aspectRatio: 1.5,
          child: Stack(fit: StackFit.expand, children: [
            if (glow != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.62,
                    colors: [glow.withValues(alpha: 0.30), glow.withValues(alpha: 0)],
                  ),
                ),
              ),
            Image.asset(
              'assets/game/player/player_ship.png',
              color: tint?.withValues(alpha: 0.55),
              colorBlendMode: BlendMode.srcATop,
              filterQuality: FilterQuality.medium,
            ),
            if (livery.decal != LiveryDecal.none)
              CustomPaint(painter: _LiveryDecalPainter(livery)),
          ]),
        ),
      ),
    );
  }
}

/// Static decal (pulse frozen mid-sweep) over the 192x128 hull space.
class _LiveryDecalPainter extends CustomPainter {
  _LiveryDecalPainter(this.livery);
  final LiveryType livery;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 192;
    final decal = livery.decal;
    final color = livery.cycles ? livery.colors[2] : livery.decalColor;
    canvas.save();
    canvas.clipPath(LiveryDecals.hull(k));
    if (decal == LiveryDecal.pulse) {
      canvas.translate(110 * k, 0);
      canvas.drawRect(
        LiveryDecals.pulseBand(k),
        Paint()
          ..shader = LiveryDecals.pulseShader(k)
          ..colorFilter = ColorFilter.mode(color, BlendMode.modulate),
      );
    } else {
      final paint = Paint()
        ..isAntiAlias = true
        ..color = color.withValues(alpha: decal == LiveryDecal.split ? 0.5 : 0.8);
      if (LiveryDecals.isStroked(decal)) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, 2.4 * k);
      }
      canvas.drawPath(LiveryDecals.pattern(decal, k), paint);
      if (decal == LiveryDecal.split) {
        canvas.drawPath(
          LiveryDecals.splitEdge(k),
          Paint()
            ..isAntiAlias = true
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3 * k
            ..color = color,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiveryDecalPainter old) => old.livery != livery;
}

/// A Cup Pass product in the Armory's Cup Passes tab.
class _CupPassOffer {
  const _CupPassOffer(this.productId, this.name, this.grants, this.fallbackPrice, this.color, this.tiers,
      {this.requiresStoreProduct = false});
  final String productId;
  final String name;

  /// What one purchase grants — mirrors ProductIds.cupPassGrants.
  final String grants;
  final double fallbackPrice;
  final Color color;

  /// Wire tiers this offer grants (for the "held" count line).
  final List<String> tiers;

  /// Hide the tile unless the store returns this product.
  final bool requiresStoreProduct;
}
