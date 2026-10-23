import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/models/battle_pass.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/battle_pass_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/reward_toast.dart';

/// Battle pass — Prism Noir mock 08.
///
///   • Header: season title on one line (last word in prism), T n / max with
///     a 3px XP bar + mono XP readout, and the "coming next" reward line.
///     Right: gold-bordered premium card (UNLOCK for free players, an
///     "active" state for Strike Command) + the rewarded-ad XP pill.
///   • Body: FREE / PRO rows of tier tiles in one horizontal scroller —
///     claimed = done + mint CLAIMED, claimable = prism ring (tap to claim),
///     future = faint, pro = gold dashed. Auto-scrolls to the focal tier.
class BattlePassScreen extends StatefulWidget {
  const BattlePassScreen({super.key});

  @override
  State<BattlePassScreen> createState() => _BattlePassScreenState();
}

class _BattlePassScreenState extends State<BattlePassScreen> {
  final Set<String> _claiming = <String>{};
  final ScrollController _tiers = ScrollController();
  bool _didAutoScroll = false;

  @override
  void initState() {
    super.initState();
    // Silent refresh on entry so a Pro purchase made elsewhere in the app
    // immediately reflects in the premium track. The cubit also listens
    // to PremiumCubit; this handles cold starts where the order races.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BattlePassCubit>().refresh();
    });
  }

  @override
  void dispose() {
    _tiers.dispose();
    super.dispose();
  }

  Future<void> _claim({
    required int tier,
    required bool isPremium,
    required BattlePassReward reward,
  }) async {
    final claimKey = '${isPremium ? 'p' : 'f'}:$tier';
    if (_claiming.contains(claimKey)) return;
    setState(() => _claiming.add(claimKey));

    try {
      final cubit = context.read<BattlePassCubit>();
      final ok = isPremium
          ? await cubit.claimPremiumReward(tier)
          : await cubit.claimFreeReward(tier);

      if (!mounted) return;
      if (ok) {
        RewardToast.show(
          icon: Symbols.military_tech_rounded,
          title: 'TIER $tier CLAIMED',
          amount: reward.name.toUpperCase(),
        );
      }
    } finally {
      if (mounted) setState(() => _claiming.remove(claimKey));
    }
  }

  void _unlockPro() => context.push(AppRoutes.store);

  void _openRewardDetail(
    BattlePassReward reward,
    int tier,
    bool unlocked, {
    bool lockedBehindPro = false,
  }) {
    showCsDialog<void>(
      context,
      builder: (ctx) => _RewardDetailDialog(
        reward: reward,
        tier: tier,
        unlocked: unlocked,
        lockedBehindPro: lockedBehindPro,
        onUnlockPro: () {
          Navigator.of(ctx).pop();
          _unlockPro();
        },
      ),
    );
  }

  /// Scrolls the tier strip once so the focal tier (first claimable, else the
  /// next tier to earn) sits second from the left.
  void _scheduleAutoScroll(int focusIndex, double extent) {
    if (_didAutoScroll) return;
    _didAutoScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tiers.hasClients) return;
      final max = _tiers.position.maxScrollExtent;
      final target = ((focusIndex - 1) * extent).clamp(0.0, max);
      if (target <= 0) return;
      _tiers.animateTo(target, duration: CsMotion.slow, curve: CsMotion.standard);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BattlePassCubit, BattlePassState>(
      builder: (context, bpState) {
        final season = bpState.season;

        if (bpState.status == BattlePassStatus.loading && season == null) {
          return const CsScaffold(
            title: 'Frontline',
            body: CsLoadingState(label: 'Loading Frontline'),
          );
        }

        if (season == null) return const _NoActiveSeasonScreen();

        final cs = context.cs;
        final number = _seasonNumber(season);
        return CsScaffold(
          title: number == null ? 'Frontline' : 'Frontline · Season ${number.toString().padLeft(2, '0')}',
          trailing: [
            CsMeta(
              _daysRemainingText(season),
              color: season.hasEnded ? CsColors.pink : CsColors.ink55,
            ),
          ],
          washes: const [CsWash.violetTopRight],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                state: bpState,
                season: season,
                onOpenReward: _openRewardDetail,
                onUnlockPro: _unlockPro,
              ),
              SizedBox(height: cs(cs.isTablet ? 28 : 14)),
              Expanded(
                child: _TierStrip(
                  state: bpState,
                  season: season,
                  controller: _tiers,
                  claiming: _claiming,
                  onClaim: _claim,
                  onOpenReward: _openRewardDetail,
                  onLayout: _scheduleAutoScroll,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Season number for the "SEASON 03" top bar: explicit metadata first, then
/// any digits in the id / name. Null → generic "FRONTLINE".
int? _seasonNumber(BattlePassSeason season) {
  for (final key in const ['number', 'season_number', 'seasonNumber']) {
    final v = season.metadata[key];
    if (v is int) return v;
    if (v is String && int.tryParse(v) != null) return int.parse(v);
  }
  final m = RegExp(r'(\d+)').firstMatch(season.id) ?? RegExp(r'season\s*(\d+)', caseSensitive: false).firstMatch(season.name);
  final n = m == null ? null : int.tryParse(m.group(1)!);
  return (n != null && n > 0 && n < 1000) ? n : null;
}

String _daysRemainingText(BattlePassSeason season) {
  if (season.hasEnded) return 'Season ended';
  final days = season.daysRemaining;
  if (days <= 0) {
    final hours = season.timeRemaining.inHours;
    return hours <= 0 ? 'Ending soon' : '${hours}h left';
  }
  return days == 1 ? '1 day left' : '$days days left';
}

IconData _rewardIcon(BattlePassReward r) => switch (r.type) {
      BattlePassRewardType.xp => Symbols.star_rounded,
      BattlePassRewardType.coins => Symbols.paid_rounded,
      BattlePassRewardType.theme => Symbols.palette_rounded,
      BattlePassRewardType.skin => Symbols.rocket_rounded,
      BattlePassRewardType.trail => Symbols.auto_awesome_rounded,
      BattlePassRewardType.powerUp => Symbols.bolt_rounded,
      BattlePassRewardType.tournamentEntry => Symbols.emoji_events_rounded,
      BattlePassRewardType.title => Symbols.workspace_premium_rounded,
      BattlePassRewardType.avatar => Symbols.face_rounded,
      BattlePassRewardType.special => Symbols.redeem_rounded,
    };

/// Short mono tile label ("80 CR", "LIVERY", "GEAR").
String _rewardShort(BattlePassReward r) => switch (r.type) {
      BattlePassRewardType.coins => '${r.quantity} CR',
      BattlePassRewardType.xp => '${r.quantity} XP',
      BattlePassRewardType.theme => 'SECTOR',
      BattlePassRewardType.skin => 'LIVERY',
      BattlePassRewardType.trail => 'EXHAUST',
      BattlePassRewardType.powerUp => r.quantity > 1 ? '${r.quantity}× GEAR' : 'GEAR',
      BattlePassRewardType.tournamentEntry => 'CUP PASS',
      BattlePassRewardType.title => 'TITLE',
      BattlePassRewardType.avatar => 'AVATAR',
      BattlePassRewardType.special => 'BADGE',
    };

/// Next reward the player will earn — prefers premium when they own the pass,
/// still previews locked premium for free players.
({BattlePassReward reward, int tier, bool isPremium})? _findNext(
  BattlePassState state,
  BattlePassSeason season,
) {
  final hasPremium = state.isActive;
  for (int i = state.currentTier + 1; i <= season.levels.length; i++) {
    final level = season.levels[i - 1];
    if (hasPremium && level.premiumReward != null) {
      return (reward: level.premiumReward!, tier: i, isPremium: true);
    }
    if (level.freeReward != null) {
      return (reward: level.freeReward!, tier: i, isPremium: false);
    }
    if (!hasPremium && level.premiumReward != null) {
      return (reward: level.premiumReward!, tier: i, isPremium: true);
    }
  }
  return null;
}

// ===========================================================================
// Header — season headline + tier progress (left), premium card (right).
// ===========================================================================
class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.season,
    required this.onOpenReward,
    required this.onUnlockPro,
  });

  final BattlePassState state;
  final BattlePassSeason season;
  final void Function(BattlePassReward, int, bool, {bool lockedBehindPro}) onOpenReward;
  final VoidCallback onUnlockPro;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final maxTier = season.levels.length;
    final complete = state.currentTier >= maxTier;

    final words = season.name.trim().split(RegExp(r'\s+'));
    final parts = words.length < 2
        ? <String>[season.name]
        : <String>['${words.sublist(0, words.length - 1).join(' ')} ', words.last];

    final next = _findNext(state, season);

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CsHeadline(parts, prismIndex: parts.length - 1, maxLines: 1, style: t.title),
        ),
        SizedBox(height: cs(14)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text.rich(
              TextSpan(children: [
                // Spelled out: in Syne a bare "T0" reads as the word "To".
                TextSpan(text: 'Tier ${state.currentTier}', style: t.display(22, height: 1)),
                TextSpan(text: ' / $maxTier', style: t.mono(12, color: CsColors.ink45)),
              ]),
              maxLines: 1,
            ),
            SizedBox(width: cs(14)),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cs(200)),
                child: CsProgressLine(
                  value: complete ? 1 : state.tierProgress,
                  height: cs(3).clamp(2.0, 4.0),
                  gradient: complete ? CsGradients.complete : CsGradients.progress,
                ),
              ),
            ),
            SizedBox(width: cs(14)),
            Text(
              complete ? 'MAX TIER' : '${state.currentXP}/${state.xpForNextTier} XP',
              maxLines: 1,
              style: t.mono(11, color: complete ? CsColors.mint : CsColors.ink60, em: 0.06),
            ),
          ],
        ),
        SizedBox(height: cs(10)),
        if (next == null)
          CsMeta('Season complete · every tier unlocked', color: CsColors.mint, icon: Symbols.check_circle_rounded)
        else
          CsPressable(
            onTap: () => onOpenReward(
              next.reward,
              next.tier,
              false,
              lockedBehindPro: next.isPremium && !state.isActive,
            ),
            semanticLabel: 'Next reward details',
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'NEXT · T${next.tier} · ', style: t.mono(10, color: CsColors.ink45)),
                      TextSpan(
                        text: next.reward.name.toUpperCase(),
                        style: t.mono(10, color: next.isPremium ? CsColors.gold : CsColors.ink),
                      ),
                      if (next.isPremium && !state.isActive)
                        TextSpan(text: ' · COMMAND', style: t.mono(10, color: CsColors.gold)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: cs(4)),
                Icon(Symbols.chevron_right_rounded, size: cs(14), color: CsColors.ink45),
              ]),
            ),
          ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PremiumCard(state: state, season: season, onUnlock: onUnlockPro),
        SizedBox(height: cs(10)),
        const _AdXpButton(),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        SizedBox(width: cs(24)),
        Flexible(child: right),
      ],
    );
  }
}

/// Gold-bordered premium card. Free players: "Command lane locked" +
/// UNLOCK pill. Strike Command: "Command lane active" + claimable count.
class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.state, required this.season, required this.onUnlock});

  final BattlePassState state;
  final BattlePassSeason season;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final hasPremium = state.isActive;

    final reachedPremium = season.levels
        .where((l) => l.level <= state.currentTier && l.premiumReward != null && !state.isPremiumTierClaimed(l.level))
        .length;
    final totalPremium = season.levels.where((l) => l.premiumReward != null).length;

    final String title;
    final String sub;
    if (hasPremium) {
      title = 'Command lane active';
      sub = reachedPremium > 0
          ? '$reachedPremium ${reachedPremium == 1 ? 'reward' : 'rewards'} to claim'
          : (state.isValid ? 'All caught up' : 'Season closed');
    } else {
      title = 'Command lane locked';
      sub = reachedPremium > 0
          ? '$reachedPremium ${reachedPremium == 1 ? 'reward' : 'rewards'} waiting'
          : '$totalPremium Command rewards this season';
    }

    return Container(
      padding: EdgeInsets.fromLTRB(cs(18), cs(12), cs(hasPremium ? 20 : 12), cs(12)),
      decoration: BoxDecoration(
        color: CsColors.gold.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(cs(20)),
        border: Border.all(color: CsColors.gold.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/ui/gem.png', width: cs(30), height: cs(30)),
          SizedBox(width: cs(14)),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.display(14, weight: FontWeight.w700, em: 0, height: 1.2)),
                SizedBox(height: cs(3)),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.mono(10, em: 0.06, color: hasPremium && reachedPremium > 0 ? CsColors.mint : CsColors.ink60)),
              ],
            ),
          ),
          SizedBox(width: cs(14)),
          if (hasPremium)
            Icon(Symbols.workspace_premium_rounded, size: cs(22), color: CsColors.gold)
          else
            CsButton.premium(label: 'Unlock', size: CsButtonSize.small, onPressed: onUnlock),
        ],
      ),
    );
  }
}

/// Rewarded-ad "+50 Frontline XP" pill. Same gating as the shared
/// RewardedActionButton (self-hides for Pro / ads off, disabled without a
/// loaded ad or once the daily cap is hit, re-checks every 2s), restyled as a
/// compact secondary pill so it fits the header.
class _AdXpButton extends StatefulWidget {
  const _AdXpButton();

  @override
  State<_AdXpButton> createState() => _AdXpButtonState();
}

class _AdXpButtonState extends State<_AdXpButton> {
  Timer? _ticker;

  AdService? get _ads => getIt.isRegistered<AdService>() ? getIt<AdService>() : null;

  @override
  void initState() {
    super.initState();
    _ads?.preloadRewarded();
    _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _watch() async {
    final bp = context.read<BattlePassCubit>();
    await getIt<AdService>().showRewardedCapped(
      capKey: AdService.capBattlePassXp,
      onReward: () {
        bp.bufferXP(50, source: 'ad_boost');
        bp.flushXP();
        RewardToast.show(
          icon: Symbols.bolt_rounded,
          title: 'XP BOOST',
          amount: '+50 FRONTLINE XP',
        );
      },
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ads = _ads;
    if (ads == null || !ads.adsEnabled) return const SizedBox.shrink();
    final cs = context.cs;
    final enabled = ads.canShowCapped(AdService.capBattlePassXp);
    final remaining = ads.dailyRemaining(AdService.capBattlePassXp);
    final note = enabled ? '$remaining left' : (remaining == 0 ? 'Tomorrow' : 'No ad yet');

    return CsButton.secondary(
      label: 'Watch ad · +50 XP',
      icon: Symbols.play_circle_rounded,
      size: CsButtonSize.small,
      onPressed: enabled ? _watch : null,
      trailing: Text(
        note.toUpperCase(),
        maxLines: 1,
        style: cs.type.mono(9, color: enabled ? CsColors.violet : CsColors.ink45),
      ),
    );
  }
}

// ===========================================================================
// Tier strip — FREE / PRO labels fixed on the left, one horizontal scroller
// of tier columns (tier number + free tile + pro tile) on the right.
// ===========================================================================
class _TierStrip extends StatelessWidget {
  const _TierStrip({
    required this.state,
    required this.season,
    required this.controller,
    required this.claiming,
    required this.onClaim,
    required this.onOpenReward,
    required this.onLayout,
  });

  final BattlePassState state;
  final BattlePassSeason season;
  final ScrollController controller;
  final Set<String> claiming;
  final Future<void> Function({required int tier, required bool isPremium, required BattlePassReward reward}) onClaim;
  final void Function(BattlePassReward, int, bool, {bool lockedBehindPro}) onOpenReward;
  final void Function(int focusIndex, double extent) onLayout;

  bool _freeClaimable(BattlePassLevel l) =>
      l.freeReward != null && l.level <= state.currentTier && !state.isFreeTierClaimed(l.level);

  bool _proClaimable(BattlePassLevel l) =>
      state.isValid && l.premiumReward != null && l.level <= state.currentTier && !state.isPremiumTierClaimed(l.level);

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final levels = season.levels;

    // Focal tier: first claimable reward, else the next tier to earn.
    final firstClaimable = levels.indexWhere((l) => _freeClaimable(l) || _proClaimable(l));
    final nextIndex = state.currentTier.clamp(0, levels.isEmpty ? 0 : levels.length - 1);
    final focusIndex = firstClaimable >= 0 ? firstClaimable : nextIndex;
    final noClaimable = firstClaimable < 0;

    return LayoutBuilder(builder: (context, c) {
      final labelH = cs(14);
      final gap = cs(8);
      // Tablets get taller, wider tiles so the two tracks fill the screen
      // instead of floating in an empty band.
      final maxTile = cs(cs.isTablet ? 150 : 66);
      final tileH = ((c.maxHeight - labelH - gap * 2) / 2).clamp(36.0, maxTile);
      final tileW = cs(cs.isTablet ? 150 : 106);
      final extent = tileW + gap;
      if (levels.isNotEmpty) onLayout(focusIndex, extent);

      final rowLabels = SizedBox(
        width: cs(58),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: labelH + gap),
            SizedBox(height: tileH, child: Align(alignment: Alignment.centerLeft, child: CsLabel('Free', size: 10))),
            SizedBox(height: gap),
            SizedBox(
              height: tileH,
              child: Align(alignment: Alignment.centerLeft, child: CsLabel('Command', size: 10, color: CsColors.gold)),
            ),
          ],
        ),
      );

      final strip = ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: levels.length,
        separatorBuilder: (_, _) => SizedBox(width: gap),
        itemBuilder: (context, i) {
          final level = levels[i];
          final isCurrent = level.level == state.currentTier;
          return SizedBox(
            width: tileW,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: labelH,
                  child: Row(children: [
                    Text('T${level.level}',
                        style: t.mono(10, color: isCurrent ? CsColors.ink : CsColors.ink45, em: 0.1)),
                    if (level.isMilestone) ...[
                      SizedBox(width: cs(4)),
                      Icon(Symbols.star_rounded, size: cs(11), color: CsColors.gold),
                    ],
                    if (isCurrent) ...[
                      SizedBox(width: cs(6)),
                      Text('NOW', style: t.mono(8, color: CsColors.violet, em: 0.14)),
                    ],
                  ]),
                ),
                SizedBox(height: gap),
                _tile(level, premium: false, height: tileH, focal: noClaimable && i == focusIndex),
                SizedBox(height: gap),
                _tile(level, premium: true, height: tileH, focal: false),
              ],
            ),
          );
        },
      );

      // Centre the two tracks in the free height so tall screens (iPad)
      // don't leave an empty band under the grid.
      return Align(
        alignment: Alignment.center,
        child: SizedBox(
          height: labelH + gap * 2 + tileH * 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [rowLabels, Expanded(child: strip)],
          ),
        ),
      );
    });
  }

  Widget _tile(BattlePassLevel level, {required bool premium, required double height, required bool focal}) {
    final reward = premium ? level.premiumReward : level.freeReward;
    final tier = level.level;
    final reached = tier <= state.currentTier;

    if (reward == null) {
      return CsTile(
        state: CsTileState.locked,
        height: height,
        padding: EdgeInsets.zero,
        child: const Center(child: _TileLabel(icon: null, label: '—', color: CsColors.ink25)),
      );
    }

    final claimed = premium ? state.isPremiumTierClaimed(tier) : state.isFreeTierClaimed(tier);
    final claimable = premium ? _proClaimable(level) : _freeClaimable(level);
    final lockedBehindPro = premium && !state.isActive;
    final isClaiming = claiming.contains('${premium ? 'p' : 'f'}:$tier');
    void detail() => onOpenReward(reward, tier, reached, lockedBehindPro: lockedBehindPro);

    if (claimed) {
      return CsTile(
        state: CsTileState.done,
        height: height,
        padding: EdgeInsets.zero,
        onTap: detail,
        child: _TileLabel(icon: _rewardIcon(reward), iconColor: CsColors.ink45, label: 'CLAIMED', color: CsColors.mint),
      );
    }

    if (claimable) {
      return CsTile(
        state: CsTileState.current,
        height: height,
        padding: EdgeInsets.zero,
        onTap: isClaiming ? null : () => onClaim(tier: tier, isPremium: premium, reward: reward),
        child: isClaiming
            ? const Center(child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            : _TileLabel(
                icon: _rewardIcon(reward),
                iconColor: premium ? CsColors.gold : CsColors.ink,
                label: 'CLAIM · ${_rewardShort(reward)}',
                color: CsColors.ink,
              ),
      );
    }

    if (premium) {
      return CsTile(
        state: CsTileState.pro,
        height: height,
        padding: EdgeInsets.zero,
        onTap: detail,
        child: Stack(children: [
          Positioned.fill(
            child: _TileLabel(
              icon: _rewardIcon(reward),
              iconColor: CsColors.gold,
              label: _rewardShort(reward),
              color: CsColors.gold.withValues(alpha: .8),
            ),
          ),
          if (lockedBehindPro && reached)
            Builder(
              builder: (context) => Positioned(
                top: context.cs(6),
                right: context.cs(6),
                child: Icon(Symbols.lock_rounded, size: context.cs(12), color: CsColors.gold.withValues(alpha: .7)),
              ),
            ),
        ]),
      );
    }

    // Free, not yet reached. The next tier is the focal one when nothing is
    // claimable (mock: T5 prism ring).
    return CsTile(
      state: focal ? CsTileState.current : CsTileState.future,
      height: height,
      padding: EdgeInsets.zero,
      onTap: detail,
      child: _TileLabel(
        icon: _rewardIcon(reward),
        iconColor: focal ? CsColors.ink : CsColors.ink55,
        label: _rewardShort(reward),
        color: focal ? CsColors.ink : CsColors.ink45,
      ),
    );
  }
}

class _TileLabel extends StatelessWidget {
  const _TileLabel({required this.icon, required this.label, required this.color, this.iconColor});
  final IconData? icon;
  final String label;
  final Color color;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: cs(6), vertical: cs(4)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: cs(22), color: iconColor ?? color),
              SizedBox(height: cs(2)),
            ],
            Text(label, maxLines: 1, style: cs.type.mono(9, color: color, em: 0.06)),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Reward detail dialog — opened from any tile or the "next" line.
// ===========================================================================
class _RewardDetailDialog extends StatelessWidget {
  const _RewardDetailDialog({
    required this.reward,
    required this.tier,
    required this.unlocked,
    required this.lockedBehindPro,
    required this.onUnlockPro,
  });

  final BattlePassReward reward;
  final int tier;
  final bool unlocked;
  final bool lockedBehindPro;
  final VoidCallback onUnlockPro;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final accent = reward.isPremium ? CsColors.gold : CsColors.ink;
    return CsDialog(
      maxWidth: 440,
      icon: _rewardIcon(reward),
      iconColor: accent,
      eyebrow: 'Tier $tier · ${reward.isPremium ? 'Command lane' : 'Frontline track'} · ${reward.type.displayName}',
      title: reward.name,
      message: reward.description.isNotEmpty ? reward.description : null,
      content: Wrap(spacing: cs(8), runSpacing: cs(8), children: [
        if (unlocked && !lockedBehindPro)
          const CsChip('Unlocked', kind: CsChipKind.mint, icon: Symbols.check_circle_rounded)
        else if (!unlocked)
          CsChip('Reach tier $tier to unlock', icon: Symbols.lock_rounded),
        if (lockedBehindPro) const CsChip('Command lane', kind: CsChipKind.gold, icon: Symbols.workspace_premium_rounded),
      ]),
      actions: [
        CsButton.text(label: 'Close', onPressed: () => Navigator.of(context).pop()),
        if (lockedBehindPro) CsButton.premium(label: 'Unlock Command lane', onPressed: onUnlockPro),
      ],
    );
  }
}

// ===========================================================================
// Empty state — no active season.
// ===========================================================================
class _NoActiveSeasonScreen extends StatelessWidget {
  const _NoActiveSeasonScreen();

  @override
  Widget build(BuildContext context) {
    return CsScaffold(
      title: 'Frontline',
      washes: const [CsWash.violetTopRight],
      body: CsEmptyState(
        icon: Symbols.hourglass_empty_rounded,
        title: 'Between seasons',
        message: 'No Frontline season is running. The next one deploys automatically. Stand by.',
        action: CsButton.secondary(
          label: 'Check for new season',
          icon: Symbols.refresh_rounded,
          onPressed: () => context.read<BattlePassCubit>().refresh(),
        ),
      ),
    );
  }
}
