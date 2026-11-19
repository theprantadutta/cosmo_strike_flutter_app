import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/strike_command_offer.dart';

/// "Strike Command" paywall — Prism Noir mock 10 (subscription panel).
///
///   • LEFT: every entitlement (`StrikeCommandFeatureList`), scrolls when
///     it can't fit.
///   • RIGHT: "Strike Command" headline (Command in prism), mono tagline and
///     the shared `StrikeCommandOffer` (plan cards, trial + renewal
///     disclosure under each Subscribe, Restore / Terms / Privacy) — the
///     exact same offer the Armory's Command tab shows.
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

  Widget _buildPurchasePanel() {
    final cs = context.cs;
    final t = cs.type;
    final status = _subscribing
        ? (_sawPurchaseSuccess ? 'Activating Command…' : 'Connecting to the store…')
        : null;

    // Content side: may scroll on short phones (never shrinks the fine print
    // below its readable size), centred vertically when it fits.
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CsHeadline(const ['Strike ', 'Command'], prismIndex: 1, maxLines: 1, style: t.display(34, em: -0.03, height: 1)),
              SizedBox(height: cs(8)),
              Text(strikeCommandTagline, style: t.mono(11, em: 0.06, color: CsColors.ink55, height: 1.4)),
              SizedBox(height: cs(16)),
              StrikeCommandOffer(
                busyPlan: _subscribing ? (_isYearly ? StrikeCommandPlan.annual : StrikeCommandPlan.monthly) : null,
                busyLabel: _sawPurchaseSuccess ? 'Activating…' : 'Connecting…',
                onSubscribe: _subscribing ? null : (plan) => _subscribeTo(yearly: plan == StrikeCommandPlan.annual),
                onRestore: _subscribing ? null : _restorePurchases,
                restoring: _restoring,
                status: status,
              ),
            ],
          ),
        ),
      ),
    );
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
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(bottom: cs(8)),
            child: StrikeCommandFeatureList(owned: owned),
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
        // Scale down rather than wrap: on phones "Command" alone is wider
        // than the column and broke mid-word ("Comman / d").
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CsHeadline(const ['Command\n', 'active.'], prismIndex: 1, maxLines: 2, style: t.title),
        ),
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
