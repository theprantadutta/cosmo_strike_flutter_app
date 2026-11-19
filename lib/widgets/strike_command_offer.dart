import 'dart:math' as math;

import 'package:flutter_inapp_purchase/flutter_inapp_purchase.dart' as iap;
import 'package:material_ui/material_ui.dart';

import 'package:cosmo_strike_flutter_app/models/premium_cosmetics.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart' show PremiumContent;
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/subscription_legal_links.dart';

// =============================================================================
// The ONE Strike Command offer.
//
// Both entry points (Home → COMMAND = PremiumBenefitsScreen, and Armory →
// Command tab) render this file's plan cards, trial wording, disclosure line,
// feature list and legal footer, so the copy can never drift apart again.
// The hosts only own the frame around it (headline, layout) and the purchase
// flow (they pass callbacks + busy state in).
// =============================================================================

/// One-line summary under the "Strike Command" headline (both entry points).
const strikeCommandTagline = 'No ads · Every livery, exhaust & sector · 1.5× credits · Frontline Command lane';

/// The two Strike Command plans.
enum StrikeCommandPlan {
  monthly(ProductIds.commandMonthly, 'Monthly', '/mo', 4.99, 'Billed monthly'),
  annual(ProductIds.commandAnnual, 'Annual', '/yr', 39.99, 'Billed annually');

  const StrikeCommandPlan(this.productId, this.label, this.cadence, this.fallbackPrice, this.billedLabel);
  final String productId;
  final String label;

  /// "/mo" / "/yr", appended to the localized price.
  final String cadence;

  /// Shown only until the store returns real prices.
  final double fallbackPrice;
  final String billedLabel;
}

enum FreeTrialUnit { day, month, year }

/// A free-trial phase the store returned for a plan. Weeks are normalised to
/// days so every surface says "7-day", never "1-week".
@immutable
class FreeTrial {
  const FreeTrial(this.count, this.unit);
  final int count;
  final FreeTrialUnit unit;

  String get _unitWord => switch (unit) {
        FreeTrialUnit.day => 'day',
        FreeTrialUnit.month => 'month',
        FreeTrialUnit.year => 'year',
      };

  /// "7-day free trial".
  String get label => '$count-$_unitWord free trial';

  /// "7 days" / "1 month".
  String get duration => '$count $_unitWord${count == 1 ? '' : 's'}';

  static FreeTrial? _of(int n, String unit) {
    if (n <= 0) return null;
    return switch (unit) {
      'D' => FreeTrial(n, FreeTrialUnit.day),
      'W' => FreeTrial(n * 7, FreeTrialUnit.day),
      'M' => FreeTrial(n, FreeTrialUnit.month),
      'Y' => FreeTrial(n, FreeTrialUnit.year),
      _ => null,
    };
  }

  /// The free trial among a product's offers, or null. Play only returns
  /// offers the user is eligible for, so we never promise a trial the store
  /// didn't. Display only — the purchase flow picks the offer itself.
  static FreeTrial? fromOffers(List<iap.SubscriptionOffer> offers) {
    for (final offer in offers) {
      final period = offer.period;
      if (offer.paymentMode == iap.PaymentMode.FreeTrial && period != null) {
        final n = period.value * (offer.periodCount ?? 1);
        final t = switch (period.unit) {
          iap.SubscriptionPeriodUnit.Day => _of(n, 'D'),
          iap.SubscriptionPeriodUnit.Week => _of(n, 'W'),
          iap.SubscriptionPeriodUnit.Month => _of(n, 'M'),
          iap.SubscriptionPeriodUnit.Year => _of(n, 'Y'),
          iap.SubscriptionPeriodUnit.Unknown => null,
        };
        if (t != null) return t;
      }
      // Play: a zero-priced, non-recurring pricing phase is the trial.
      for (final phase in offer.pricingPhasesAndroid?.pricingPhaseList ?? const <iap.PricingPhaseAndroid>[]) {
        if ((int.tryParse(phase.priceAmountMicros) ?? -1) != 0 || phase.recurrenceMode == 1) continue;
        final m = RegExp(r'^P(\d+)([DWMY])$').firstMatch(phase.billingPeriod);
        if (m == null) continue;
        final cycles = phase.billingCycleCount > 0 ? phase.billingCycleCount : 1;
        final t = _of(int.parse(m.group(1)!) * cycles, m.group(2)!);
        if (t != null) return t;
      }
    }
    return null;
  }

  static FreeTrial? fromProduct(iap.ProductCommon? product) {
    if (product is! iap.ProductSubscription) return null;
    final offers = switch (product) {
      iap.ProductSubscriptionAndroid(:final subscriptionOffers) => subscriptionOffers,
      iap.ProductSubscriptionIOS(:final subscriptionOffers) => subscriptionOffers ?? const <iap.SubscriptionOffer>[],
    };
    return fromOffers(offers);
  }

  @override
  bool operator ==(Object other) => other is FreeTrial && other.count == count && other.unit == unit;

  @override
  int get hashCode => Object.hash(count, unit);
}

/// Everything a plan card shows, resolved from the store in one place.
@immutable
class StrikeCommandQuote {
  const StrikeCommandQuote({required this.plan, required this.price, this.trial, this.badge});

  final StrikeCommandPlan plan;

  /// Localized recurring price from the store ("BDT 5,700.00").
  final String price;
  final FreeTrial? trial;

  /// "Save 33%" on the annual plan once both prices load.
  final String? badge;

  /// The line under the plan's price.
  String get note => trial?.label ?? plan.billedLabel;

  /// The renewal disclosure under the Subscribe button.
  String get disclosure => trial != null
      ? 'Free for ${trial!.duration}, then $price${plan.cadence} · cancel anytime'
      : '$price${plan.cadence}, renews automatically · cancel anytime';

  /// [disclosure] as rendered: the price + cadence are glued (no-break
  /// spaces, a word joiner after "/") so "BDT 5,700.00/yr" never splits
  /// across lines.
  String get disclosureDisplay {
    final glued = '${price.replaceAll(' ', '\u00A0')}${plan.cadence.replaceAll('/', '/\u2060')}';
    return disclosure.replaceFirst('$price${plan.cadence}', glued);
  }

  /// Live quotes for both plans (fallback prices until the store loads).
  static List<StrikeCommandQuote> fromStore() {
    final purchases = PurchaseService();
    final pct = purchases.yearlySavingsPercent(ProductIds.commandMonthly, ProductIds.commandAnnual);
    return [
      for (final plan in StrikeCommandPlan.values)
        StrikeCommandQuote(
          plan: plan,
          price: purchases.getStorePriceOrDefault(plan.productId, plan.fallbackPrice),
          trial: FreeTrial.fromProduct(purchases.getProduct(plan.productId)),
          badge: plan == StrikeCommandPlan.annual && pct != null ? 'Save $pct%' : null,
        ),
    ];
  }
}

/// A readable small-print style: never below 12 logical px (scaled up on
/// big screens), ink70 on the near-black canvas (> 7:1 contrast).
TextStyle strikeCommandFinePrint(BuildContext context, {Color color = CsColors.ink70}) {
  final cs = context.cs;
  final size = math.max(12.0, cs(12));
  return TextStyle(
    fontFamily: CsFonts.mono,
    fontSize: size,
    fontWeight: FontWeight.w500,
    letterSpacing: size * 0.02,
    height: 1.4,
    color: color,
  );
}

/// Plan cards + per-plan disclosure + restore / terms / privacy footer.
class StrikeCommandOffer extends StatelessWidget {
  const StrikeCommandOffer({
    super.key,
    required this.onSubscribe,
    required this.onRestore,
    this.quotes,
    this.busyPlan,
    this.busyLabel = 'Connecting…',
    this.restoring = false,
    this.status,
  });

  /// Null disables both Subscribe buttons (e.g. a purchase is in flight).
  final ValueChanged<StrikeCommandPlan>? onSubscribe;
  final VoidCallback? onRestore;

  /// Defaults to [StrikeCommandQuote.fromStore]; injectable for tests.
  final List<StrikeCommandQuote>? quotes;

  /// The plan whose purchase is in flight (shows a spinner + [busyLabel]).
  final StrikeCommandPlan? busyPlan;
  final String busyLabel;
  final bool restoring;

  /// Optional live status ("Connecting to Google Play…") in the footer.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final q = quotes ?? StrikeCommandQuote.fromStore();
    StrikeCommandQuote of(StrikeCommandPlan p) => q.firstWhere((e) => e.plan == p);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _plan(of(StrikeCommandPlan.monthly), featured: false)),
              SizedBox(width: cs(14)),
              Expanded(child: _plan(of(StrikeCommandPlan.annual), featured: true)),
            ],
          ),
        ),
        SizedBox(height: cs(8)),
        StrikeCommandFooter(onRestore: onRestore, restoring: restoring, status: status),
      ],
    );
  }

  Widget _plan(StrikeCommandQuote quote, {required bool featured}) => _PlanCard(
        quote: quote,
        featured: featured,
        busy: busyPlan == quote.plan,
        busyLabel: busyLabel,
        onSubscribe: onSubscribe == null ? null : () => onSubscribe!(quote.plan),
      );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.quote,
    required this.featured,
    required this.busy,
    required this.busyLabel,
    required this.onSubscribe,
  });

  final StrikeCommandQuote quote;
  final bool featured;
  final bool busy;
  final String busyLabel;
  final VoidCallback? onSubscribe;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final label = busy ? busyLabel : 'Subscribe';
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(child: CsLabel(quote.plan.label, color: CsColors.ink55)),
          if (quote.badge != null) CsChip(quote.badge!, kind: CsChipKind.gold, size: 10),
        ]),
        SizedBox(height: cs(8)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: quote.price, style: t.number(30, em: -0.03, height: 1.05)),
              TextSpan(text: ' ${quote.plan.cadence}', style: t.mono(12, color: CsColors.ink45, em: 0.02)),
            ]),
            maxLines: 1,
          ),
        ),
        SizedBox(height: cs(6)),
        Text(
          quote.note,
          style: strikeCommandFinePrint(context, color: quote.trial != null ? CsColors.mint : CsColors.ink55),
        ),
        const Spacer(),
        SizedBox(height: cs(12)),
        featured
            ? CsButton.primary(label: label, loading: busy, expand: true, onPressed: onSubscribe)
            : CsButton.secondary(label: label, loading: busy, expand: true, onPressed: onSubscribe),
        SizedBox(height: cs(8)),
        Text(
          quote.disclosureDisplay,
          semanticsLabel: quote.disclosure,
          textAlign: TextAlign.center,
          style: strikeCommandFinePrint(context),
        ),
      ],
    );

    if (featured) {
      return CsPrismRing(
        radius: CsRadius.card,
        fill: CsColors.raised,
        padding: EdgeInsets.all(cs(16.5)),
        child: body,
      );
    }
    return CsTile(
      state: CsTileState.done,
      radius: CsRadius.card,
      padding: EdgeInsets.all(cs(18)),
      child: body,
    );
  }
}

/// "Restore purchases · Strike Command auto-renews until cancelled · Terms
/// of Use · Privacy Policy" — the links App Review requires next to the plans.
class StrikeCommandFooter extends StatelessWidget {
  const StrikeCommandFooter({super.key, required this.onRestore, this.restoring = false, this.status});

  final VoidCallback? onRestore;
  final bool restoring;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final fine = strikeCommandFinePrint(context);
    final link = fine.copyWith(
      color: CsColors.ink,
      decoration: TextDecoration.underline,
      decorationColor: CsColors.ink45,
    );
    return SubscriptionLegalLinks(
      style: fine,
      linkStyle: link,
      leading: [
        if (status != null) Text('$status  ·  ', style: fine.copyWith(color: CsColors.cyan)),
        CsPressable(
          onTap: restoring ? null : onRestore,
          semanticLabel: 'Restore purchases',
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(widthFactor: 1, child: Text(restoring ? 'Restoring…' : 'Restore purchases', style: link)),
          ),
        ),
        Text('  ·  ', style: fine),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Feature list
// -----------------------------------------------------------------------------

@immutable
class StrikeCommandFeature {
  const StrikeCommandFeature(this.title, this.detail, {this.icon, this.coin = false});
  final IconData? icon;

  /// Render the Credits coin instead of [icon].
  final bool coin;
  final String title;
  final String detail;
}

/// Honest list: every entry maps to an entitlement the server grants on
/// subscription verify (VerifyPurchaseCommandHandler) or a client-side
/// subscription gate. Counts are live from the catalog; no name lists, so
/// nothing ever truncates.
List<StrikeCommandFeature> strikeCommandFeatures() {
  final sectors = PremiumContent.premiumThemes.length;
  final liveries = LiveryType.values.where((l) => l.isPremium).length;
  final exhausts = ExhaustType.values.where((e) => e.isPremium).length;
  return [
    const StrikeCommandFeature('No ads', 'No banners, interstitials or ad breaks', icon: Symbols.block_rounded),
    StrikeCommandFeature('All $sectors premium Sectors', 'Every premium Sector, deploy any time',
        icon: Symbols.public_rounded),
    StrikeCommandFeature('All $liveries premium liveries', 'Every premium ship livery', icon: Symbols.rocket_rounded),
    StrikeCommandFeature('All $exhausts premium exhausts', 'Every premium engine exhaust',
        icon: Symbols.local_fire_department_rounded),
    const StrikeCommandFeature('1.5× credits', '50% more credits from every run', coin: true),
    const StrikeCommandFeature('Tactical Gear resupply', '5× Tactical Gear every billing cycle',
        icon: Symbols.inventory_2_rounded),
    const StrikeCommandFeature('Cup Passes', 'Scout, Strike and Ace Cup Pass every billing cycle',
        icon: Symbols.confirmation_number_rounded),
    const StrikeCommandFeature('Frontline Command lane', 'The premium reward lane, every season',
        icon: Symbols.workspace_premium_rounded),
  ];
}

/// The feature list, in one or two columns. Text wraps; never ellipsizes.
/// [owned] adds a mint check to every row (subscribers).
class StrikeCommandFeatureList extends StatelessWidget {
  const StrikeCommandFeatureList({super.key, this.owned = false, this.columns = 1});

  final bool owned;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final features = strikeCommandFeatures();
    if (columns <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [for (final f in features) _FeatureRow(f, owned: owned)],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < features.length; i += columns)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < columns; j++) ...[
                  if (j > 0) SizedBox(width: cs(24)),
                  Expanded(
                    child: i + j < features.length
                        ? _FeatureRow(features[i + j], owned: owned)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.f, {required this.owned});
  final StrikeCommandFeature f;
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: EdgeInsets.symmetric(vertical: cs(9), horizontal: cs(2)),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CsColors.hairline))),
      child: Row(children: [
        Container(
          width: cs(34),
          height: cs(34),
          decoration: BoxDecoration(
            color: CsColors.raised,
            shape: BoxShape.circle,
            border: Border.all(color: CsColors.hairline),
          ),
          alignment: Alignment.center,
          child: f.coin ? const CsCoinGlyph(size: 18) : Icon(f.icon, size: cs(17), color: CsColors.gold),
        ),
        SizedBox(width: cs(12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(f.title, style: t.rowTitle),
              SizedBox(height: cs(2)),
              Text(f.detail, style: t.body),
            ],
          ),
        ),
        if (owned) ...[
          SizedBox(width: cs(8)),
          Icon(Symbols.check_circle_rounded, size: cs(18), color: CsColors.mint),
        ],
      ]),
    );
  }
}
