import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inapp_purchase/flutter_inapp_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cosmo_strike_flutter_app/models/premium_cosmetics.dart';
import 'package:cosmo_strike_flutter_app/models/premium_power_up.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/subscription_legal_links.dart';

/// "Strike Command" paywall — Prism Noir mock 10 (subscription panel).
///
///   • LEFT: every Pro entitlement as a hairline list with Symbols icons
///     (scrolls when it can't fit).
///   • RIGHT: "Strike Command" headline (Command in prism), mono benefit line, two plan
///     cards — Monthly (outlined, secondary SUBSCRIBE) and Yearly (prism ring,
///     SAVE chip, the screen's white primary SUBSCRIBE) — and the
///     "Cancel anytime · Restore purchases" footer.
///   • Already Pro: the status summary moves LEFT (the standard summary
///     side) and the right side lists every perk with an owned check.
class PremiumBenefitsScreen extends StatefulWidget {
  const PremiumBenefitsScreen({super.key});

  @override
  State<PremiumBenefitsScreen> createState() => _PremiumBenefitsScreenState();
}

class _PremiumBenefitsScreenState extends State<PremiumBenefitsScreen> {
  /// Which plan the in-flight (or next) purchase is for.
  bool _isYearly = true;

  /// True from the Subscribe tap until the flow resolves: the Play sheet +
  /// backend verification take a few seconds during which nothing used to
  /// change on screen. Drives the loading CTA and disables both plans.
  bool _subscribing = false;

  /// Set when the purchase stream reports success — keeps the "ACTIVATING
  /// PRO…" state up through the last verification moments (until hasPremium
  /// flips and the whole body swaps to Premium Active).
  bool _sawPurchaseSuccess = false;

  bool _restoring = false;

  StreamSubscription<String>? _statusSub;
  StreamSubscription<bool>? _pendingSub;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    final purchases = PurchaseService();
    _statusSub = purchases.purchaseStatusStream.listen((status) {
      if (!mounted) return;
      if (status.startsWith('purchase_completed:') ||
          status == 'Purchase successful!') {
        setState(() => _sawPurchaseSuccess = true);
      } else if (status == 'Purchase failed' ||
          status.startsWith('Purchase failed:') ||
          status == 'Failed to initiate purchase' ||
          status.startsWith('Purchase could not be verified')) {
        _resetSubscribing();
      }
    });
    // pending=false with no success event = the user closed/cancelled the
    // Play sheet — put the button back.
    _pendingSub = purchases.purchasePendingStream.listen((pending) {
      if (!mounted || pending) return;
      if (!_sawPurchaseSuccess) _resetSubscribing();
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _pendingSub?.cancel();
    _safetyTimer?.cancel();
    super.dispose();
  }

  void _resetSubscribing() {
    _safetyTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _subscribing = false;
      _sawPurchaseSuccess = false;
    });
  }

  void _beginSubscribing() {
    setState(() {
      _subscribing = true;
      _sawPurchaseSuccess = false;
    });
    // Safety net: never leave the button stuck if an event is lost.
    _safetyTimer?.cancel();
    _safetyTimer = Timer(const Duration(seconds: 45), _resetSubscribing);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PremiumCubit, PremiumState>(
      builder: (context, premiumState) {
        final cs = context.cs;
        return CsScaffold(
          title: 'Strike Command',
          trailing: [
            if (premiumState.hasPremium)
              const CsMeta('Active', color: CsColors.mint, icon: Symbols.verified_rounded)
            else
              const CsMeta('Command', color: CsColors.gold, icon: Symbols.workspace_premium_rounded),
          ],
          washes: const [CsWash.violetTopRight, CsWash.goldTopRight],
          body: premiumState.hasPremium
              ? CsSplit(
                  leftWidth: cs.isTablet ? 340 : 300,
                  gap: cs(36),
                  left: _PremiumActiveBlock(renewal: premiumState.renewalLabel),
                  right: const _BenefitsList(owned: true),
                )
              : CsSplit(
                  leftWidth: cs.isTablet ? 300 : 270,
                  gap: cs(36),
                  left: const _BenefitsList(),
                  right: _buildPurchasePanel(),
                ),
        );
      },
    );
  }

  /// "Save N%" for annual vs 12× monthly from live store prices; null
  /// (no chip) until both plans have loaded.
  String? _yearlySavingsLabel(PurchaseService purchases) {
    final pct = purchases.yearlySavingsPercent(ProductIds.commandMonthly, ProductIds.commandAnnual);
    return pct == null ? null : 'Save $pct%';
  }

  Widget _buildPurchasePanel() {
    final cs = context.cs;
    final t = cs.type;
    final purchases = PurchaseService();
    final monthlyPrice = purchases.getStorePriceOrDefault(ProductIds.commandMonthly, 4.99);
    final yearlyPrice = purchases.getStorePriceOrDefault(ProductIds.commandAnnual, 39.99);

    final status = _subscribing
        ? (_sawPurchaseSuccess ? 'Activating Command…' : 'Connecting to Google Play…')
        : null;

    return CsFitColumn(
      alignment: Alignment.centerLeft,
      children: [
        CsHeadline(const ['Strike ', 'Command'], prismIndex: 1, maxLines: 1, style: t.display(34, em: -0.03, height: 1)),
        SizedBox(height: cs(8)),
        Text(
          'Frontline Command lane · No ads · 2× credits · Every livery, exhaust & sector',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.mono(11, em: 0.06, color: CsColors.ink55, height: 1.4),
        ),
        SizedBox(height: cs(18)),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _PlanCard(
                  label: 'Monthly',
                  price: monthlyPrice,
                  cadence: '/mo',
                  note: _trialLabel(ProductIds.commandMonthly) ?? 'Billed monthly',
                  noteIsTrial: _trialLabel(ProductIds.commandMonthly) != null,
                  featured: false,
                  busy: _subscribing && !_isYearly,
                  busyLabel: _sawPurchaseSuccess ? 'Activating…' : 'Connecting…',
                  onSubscribe: _subscribing ? null : () => _subscribeTo(yearly: false),
                ),
              ),
              SizedBox(width: cs(14)),
              Expanded(
                child: _PlanCard(
                  label: 'Annual',
                  price: yearlyPrice,
                  cadence: '/yr',
                  note: _trialLabel(ProductIds.commandAnnual) ?? 'Billed annually',
                  noteIsTrial: _trialLabel(ProductIds.commandAnnual) != null,
                  badge: _yearlySavingsLabel(purchases),
                  featured: true,
                  busy: _subscribing && _isYearly,
                  busyLabel: _sawPurchaseSuccess ? 'Activating…' : 'Connecting…',
                  onSubscribe: _subscribing ? null : () => _subscribeTo(yearly: true),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: cs(14)),
        Row(
          children: [
            Flexible(
              child: Text(
                status ?? 'No commitment · Cancel anytime · Secure payment',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.mono(10, em: 0.04, color: status != null ? CsColors.cyan : CsColors.ink45),
              ),
            ),
            Text(' · ', style: t.mono(10, em: 0.04, color: CsColors.ink45)),
            CsPressable(
              onTap: _restoring || _subscribing ? null : _restorePurchases,
              semanticLabel: 'Restore purchases',
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    _restoring ? 'Restoring…' : 'Restore purchases',
                    style: t.mono(10, em: 0.04, color: CsColors.ink70).copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: CsColors.ink30,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SubscriptionLegalLinks(),
      ],
    );
  }

  /// Free-trial line for a plan, read from the store's subscription offers
  /// (Play only returns offers the user is eligible for). Display only — the
  /// purchase flow picks the offer itself.
  String? _trialLabel(String productId) {
    final product = PurchaseService().getProduct(productId);
    if (product is! ProductSubscriptionAndroid) return null;
    for (final offer in product.subscriptionOffers) {
      final phases = offer.pricingPhasesAndroid?.pricingPhaseList ?? const [];
      for (final p in phases) {
        if ((int.tryParse(p.priceAmountMicros) ?? -1) == 0 && p.recurrenceMode != 1) {
          final period = _isoPeriod(p.billingPeriod);
          return period == null ? 'Free trial' : '$period free trial';
        }
      }
    }
    return null;
  }

  /// "P3D" → "3-day", "P1W" → "7-day", "P1M" → "1-month".
  static String? _isoPeriod(String iso) {
    final m = RegExp(r'^P(\d+)([DWMY])$').firstMatch(iso);
    if (m == null) return null;
    var n = int.parse(m.group(1)!);
    var unit = m.group(2)!;
    if (unit == 'W') {
      n *= 7;
      unit = 'D';
    }
    final word = switch (unit) { 'D' => 'day', 'M' => 'month', _ => 'year' };
    return '$n-$word';
  }

  void _subscribeTo({required bool yearly}) {
    setState(() => _isYearly = yearly);
    _subscribe();
  }

  /// Real subscription purchase — opens the Google Play sheet.
  ///
  /// When the product can't be purchased we distinguish the actual cause so
  /// the user knows what to do, and offer a Retry when the store query simply
  /// hasn't completed.
  Future<void> _subscribe() async {
    // Guests don't have to register (App Store guideline 5.1.1(v)); they
    // get a silent anonymous account so the backend can verify the sub.
    if (!await _ensurePurchaseAccount() || !mounted) return;

    final purchaseService = PurchaseService();
    final productId = _isYearly ? ProductIds.commandAnnual : ProductIds.commandMonthly;
    final product = purchaseService.getProduct(productId);

    if (product != null) {
      _beginSubscribing();
      final started = await purchaseService.buyProduct(product);
      // Immediate launch failure — the stream listeners won't fire, so put
      // the button back here. Successful launches resolve via the purchase
      // stream (success/cancel/failure) or the 45s safety timer.
      if (!started) _resetSubscribing();
      return;
    }

    // Device has no billing support at all (no Play services, emulator, etc.).
    if (!purchaseService.isAvailable) {
      _showSubscribeIssue("In-app purchases aren't available on this device.");
      return;
    }

    // Store query hasn't returned products yet, or it errored — this is a
    // transient/recoverable state, so offer a Retry that re-runs the query.
    if (!purchaseService.hasLoadedProducts ||
        purchaseService.queryProductError != null) {
      _showSubscribeIssue(
        'The store is still loading. Please check your connection and retry.',
        actionLabel: 'Retry',
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
      "Strike Command isn't available right now. Try again later.",
    );
  }

  Future<bool> _ensurePurchaseAccount() async {
    final ok = await context.read<AuthCubit>().ensurePurchaseAccount();
    if (!ok && mounted) showCsToast(context, "Couldn't reach the store. Check your connection and try again.", kind: CsToastKind.error);
    return ok;
  }

  /// Restore — guests included; results arrive asynchronously on the
  /// purchase stream.
  Future<void> _restorePurchases() async {
    if (!await _ensurePurchaseAccount() || !mounted) return;

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
    } catch (_) {
      if (mounted) {
        showCsToast(context, 'Failed to restore purchases. Please try again.', kind: CsToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// Subscription problems are recoverable states, not crashes: a neutral
  /// toast, or a small dialog when there's a recovery action (Retry).
  void _showSubscribeIssue(
    String message, {
    String? actionLabel,
    Future<void> Function()? onAction,
  }) {
    if (!mounted) return;
    if (actionLabel == null || onAction == null) {
      showCsToast(context, message, duration: const Duration(seconds: 5));
      return;
    }
    showCsDialog<void>(
      context,
      builder: (ctx) => CsDialog(
        eyebrow: 'Armory',
        title: 'Store unavailable',
        message: message,
        icon: Symbols.cloud_off_rounded,
        iconColor: CsColors.ink45,
        actions: [
          CsButton.text(label: 'Close', onPressed: () => Navigator.of(ctx).pop()),
          CsButton.secondary(
            label: actionLabel,
            icon: Symbols.refresh_rounded,
            onPressed: () {
              Navigator.of(ctx).pop();
              onAction();
            },
          ),
        ],
      ),
    );
  }
}

/// One plan card. Monthly = outlined tile + secondary button; Yearly
/// (featured) = prism ring + SAVE chip + white primary button.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.label,
    required this.price,
    required this.cadence,
    required this.note,
    required this.noteIsTrial,
    required this.featured,
    required this.busy,
    required this.busyLabel,
    required this.onSubscribe,
    this.badge,
  });

  final String label;
  final String price;
  final String cadence;
  final String note;
  final bool noteIsTrial;
  final bool featured;
  final bool busy;
  final String busyLabel;
  final VoidCallback? onSubscribe;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(child: CsLabel(label, color: CsColors.ink55)),
          if (badge != null) CsChip(badge!, kind: CsChipKind.gold, size: 10),
        ]),
        SizedBox(height: cs(8)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: price, style: t.display(34, em: -0.02, height: 1.05)),
              TextSpan(text: ' $cadence', style: t.mono(12, color: CsColors.ink45, em: 0.02)),
            ]),
            maxLines: 1,
          ),
        ),
        SizedBox(height: cs(8)),
        Text(
          note,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.mono(11, em: 0.02, color: noteIsTrial ? CsColors.mint : CsColors.ink45),
        ),
        const Spacer(),
        SizedBox(height: cs(14)),
        featured
            ? CsButton.primary(
                label: busy ? busyLabel : 'Subscribe',
                loading: busy,
                expand: true,
                onPressed: onSubscribe,
              )
            : CsButton.secondary(
                label: busy ? busyLabel : 'Subscribe',
                loading: busy,
                expand: true,
                onPressed: onSubscribe,
              ),
      ],
    );

    if (featured) {
      return CsPrismRing(
        radius: CsRadius.card,
        fill: CsColors.raised,
        padding: EdgeInsets.all(cs(18.5)),
        child: body,
      );
    }
    return CsTile(
      state: CsTileState.done,
      radius: CsRadius.card,
      padding: EdgeInsets.all(cs(20)),
      child: body,
    );
  }
}

class _Benefit {
  const _Benefit(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;
}

/// Honest list — every entry maps to an entitlement the server actually
/// grants on subscription verify (VerifyPurchaseCommandHandler) or a
/// client-side subscription gate (spawn boosts snapshot
/// PremiumCubit.hasPremium at game start).
final _benefits = [
  const _Benefit(Symbols.block_rounded, 'Remove all ads',
      'No banners, no interstitials. Fly completely ad-free'),
  _Benefit(Symbols.public_rounded, 'All premium Sectors',
      PremiumContent.premiumThemes.map((t) => t.displayName).join(', ')),
  _Benefit(Symbols.rocket_rounded, 'All premium liveries',
      LiveryType.values.where((l) => l.isPremium).map((l) => l.displayName).join(', ')),
  _Benefit(Symbols.local_fire_department_rounded, 'All premium exhausts',
      ExhaustType.values.where((e) => e.isPremium).map((e) => e.displayName).join(', ')),
  const _Benefit(Symbols.paid_rounded, '2× credit rewards', 'Double credits from every run'),
  const _Benefit(Symbols.stars_rounded, 'Lucky draw: rarer pickups',
      '+50% chance to spawn the rare 50-point pickup in every run'),
  const _Benefit(Symbols.bolt_rounded, 'More in-flight pickups',
      '+30% spawn rate for pickups during a run'),
  _Benefit(Symbols.inventory_2_rounded, 'Tactical Gear resupply',
      '5× ${[
        PremiumPowerUpType.teleport,
        PremiumPowerUpType.ghostMode,
        PremiumPowerUpType.magneticPickup,
        PremiumPowerUpType.scoreShield,
        PremiumPowerUpType.invincibility,
      ].map((g) => g.displayName).join(', ')} every billing cycle'),
  const _Benefit(Symbols.confirmation_number_rounded, 'Cup Passes',
      '1× Scout + 1× Strike + 1× Ace Cup Pass every billing cycle'),
];

class _BenefitsList extends StatelessWidget {
  const _BenefitsList({this.owned = false});

  /// Subscribers: "Unlocked with Strike Command" + a mint check on every row.
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CsLabel(owned ? 'Unlocked with Strike Command' : 'Strike Command includes', color: CsColors.gold),
        SizedBox(height: cs(6)),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(bottom: cs(8)),
            itemCount: _benefits.length,
            itemBuilder: (context, i) {
              final b = _benefits[i];
              return CsListRow(
                leading: CsIconDisc(b.icon, size: 34, color: CsColors.gold),
                title: b.title,
                subtitle: b.description,
                trailing: owned
                    ? Icon(Symbols.check_circle_rounded, size: cs(20), color: CsColors.mint)
                    : null,
                padding: EdgeInsets.symmetric(vertical: cs(10), horizontal: cs(2)),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Shown when the user already owns Pro: status summary + manage link.
class _PremiumActiveBlock extends StatelessWidget {
  const _PremiumActiveBlock({this.renewal});

  /// [PremiumState.renewalLabel] — null for lifetime / far-future grants.
  final String? renewal;

  static final _manageUrl = Uri.parse(
    defaultTargetPlatform == TargetPlatform.iOS
        ? 'https://apps.apple.com/account/subscriptions'
        : 'https://play.google.com/store/account/subscriptions',
  );

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return CsFitColumn(
      alignment: Alignment.centerLeft,
      children: [
        const CsChip('Command', kind: CsChipKind.gold, icon: Symbols.workspace_premium_rounded),
        SizedBox(height: cs(16)),
        CsHeadline(const ['Command\n', 'active.'], prismIndex: 1, maxLines: 2, style: t.title),
        SizedBox(height: cs(14)),
        Text(
          'Strike Command is active. Every perk on the right applies to this account.',
          style: t.body.copyWith(fontSize: cs(14)),
        ),
        SizedBox(height: cs(18)),
        CsMeta(renewal ?? 'Active', color: CsColors.mint, icon: Symbols.verified_rounded),
        SizedBox(height: cs(18)),
        CsButton.secondary(
          label: 'Manage plan',
          icon: Symbols.open_in_new_rounded,
          onPressed: () => launchUrl(_manageUrl, mode: LaunchMode.externalApplication),
        ),
      ],
    );
  }
}
