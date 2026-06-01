import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/rewarded_action_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/models/battle_pass.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/battle_pass_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';
import 'package:cosmo_strike_flutter_app/widgets/themed_loading.dart';

/// Reward-Showcase battle pass — the hero is **what you're about to earn**,
/// not the tier ladder. Layout (top → bottom):
///
///   • Compact season strip: tier number, XP bar, premium-pass status
///   • "Coming Next" hero card — large preview of the next reward the
///     player will unlock. Tapping opens a detail sheet.
///   • "Available Now" row — claimable rewards as horizontally-scrollable
///     chips. One tap per chip = claim + small celebration.
///   • Expandable full tier list — collapsed by default to keep the
///     surface uncluttered. Lets the curious see all 100 tiers.
///
/// Replaces the old horizontal-scrolling tier track which was the
/// "weird" part of the previous screen (hard to ground the scroll
/// position, free/premium track confusion). Every component on this
/// screen is vertical so it composes naturally on phones of any height.
class BattlePassScreen extends StatefulWidget {
  const BattlePassScreen({super.key});

  @override
  State<BattlePassScreen> createState() => _BattlePassScreenState();
}

class _BattlePassScreenState extends State<BattlePassScreen> {
  // Expanded by default — players want to see the full ladder right away;
  // collapsing on entry felt like hiding the main content.
  bool _showAllTiers = true;
  final Set<String> _claiming = <String>{};

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
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Text(reward.icon, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${reward.name} claimed!',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _claiming.remove(claimKey));
    }
  }

  void _openRewardDetail(
    BuildContext context,
    GameTheme theme,
    BattlePassReward reward,
    int tier,
    bool unlocked,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RewardDetailSheet(
        theme: theme,
        reward: reward,
        tier: tier,
        unlocked: unlocked,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;
        return BlocBuilder<BattlePassCubit, BattlePassState>(
          builder: (context, bpState) {
            final season = bpState.season;

            if (bpState.status == BattlePassStatus.loading && season == null) {
              return Scaffold(
                body: AppBackground(
                  theme: theme,
                  child: SafeArea(
                    child: Column(children: [
                      _TopBar(theme: theme, title: 'Battle Pass'),
                      Expanded(
                        child: ThemedLoading(
                          theme: theme,
                          label: 'Loading battle pass...',
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            }

            if (season == null) {
              return _NoActiveSeasonScreen(theme: theme);
            }

            return Scaffold(
              bottomNavigationBar: const SnakeBannerAd(),
              body: AppBackground(
                theme: theme,
                child: SafeArea(
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: _TopBar(
                          theme: theme,
                          title: season.name.toUpperCase(),
                          subtitle: _daysRemainingText(season),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _StateStrip(
                          theme: theme,
                          state: bpState,
                          season: season,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: RewardedActionButton(
                            theme: theme,
                            icon: Icons.bolt,
                            label: 'Watch ad — +50 Battle Pass XP',
                            capKey: AdService.capBattlePassXp,
                            onWatch: () async {
                              final bp = context.read<BattlePassCubit>();
                              // Capture the messenger up front — onReward fires
                              // after the ad is dismissed (an async gap), so we
                              // can't safely read context then.
                              final messenger =
                                  ScaffoldMessenger.of(context);
                              await getIt<AdService>().showRewardedCapped(
                                capKey: AdService.capBattlePassXp,
                                onReward: () {
                                  bp.bufferXP(50, source: 'ad_boost');
                                  bp.flushXP();
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: const Row(
                                        children: [
                                          Icon(Icons.bolt,
                                              color: Colors.white, size: 20),
                                          SizedBox(width: 10),
                                          Text('+50 Battle Pass XP earned!',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                      backgroundColor: Colors.green.shade700,
                                      behavior: SnackBarBehavior.floating,
                                      margin: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 16),
                                      duration: const Duration(seconds: 2),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _ComingNextSection(
                          theme: theme,
                          state: bpState,
                          season: season,
                          onTap: (r, t) =>
                              _openRewardDetail(context, theme, r, t, false),
                          onUnlockPro: () => context.push(AppRoutes.store),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _AvailableNowSection(
                          theme: theme,
                          state: bpState,
                          season: season,
                          claiming: _claiming,
                          onClaim: _claim,
                          onUnlockPro: () => context.push(AppRoutes.store),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _AllTiersToggle(
                          theme: theme,
                          expanded: _showAllTiers,
                          onTap: () =>
                              setState(() => _showAllTiers = !_showAllTiers),
                          totalTiers: season.levels.length,
                        ),
                      ),
                      if (_showAllTiers)
                        SliverPadding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final level = season.levels[index];
                                return _TierRow(
                                  theme: theme,
                                  state: bpState,
                                  level: level,
                                  onTapReward: (r) => _openRewardDetail(
                                    context,
                                    theme,
                                    r,
                                    level.level,
                                    level.level <= bpState.currentTier,
                                  ),
                                );
                              },
                              childCount: season.levels.length,
                            ),
                          ),
                        )
                      else
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 24),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

String _daysRemainingText(BattlePassSeason season) {
  if (season.hasEnded) return 'Season ended';
  final days = season.daysRemaining;
  if (days <= 0) {
    final hours = season.timeRemaining.inHours;
    return hours <= 0 ? 'Ending soon' : '${hours}h left';
  }
  return '${days}d left';
}

// ===========================================================================
// Top bar — minimal back button + season title + subtle days-remaining tag.
// Replaces the old _CompactHeader which carried more visual weight than it
// needed; the tier state moved down into _StateStrip so this row stays light.
// ===========================================================================
class _TopBar extends StatelessWidget {
  final GameTheme theme;
  final String title;
  final String? subtitle;
  const _TopBar({required this.theme, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: theme.accentColor, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.accentColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: theme.accentColor.withValues(alpha: 0.65),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// State strip — single condensed card showing tier number, XP bar, and the
// premium pass status pill. Tier number is the most-glanced number on the
// screen; the XP bar tells the player how close they are to the next tier.
// ===========================================================================
class _StateStrip extends StatelessWidget {
  final GameTheme theme;
  final BattlePassState state;
  final BattlePassSeason season;

  const _StateStrip({
    required this.theme,
    required this.state,
    required this.season,
  });

  @override
  Widget build(BuildContext context) {
    final maxTier = season.levels.length;
    final progress = state.tierProgress;
    final hasPremium = state.isActive;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.primaryColor.withValues(alpha: 0.22),
              theme.accentColor.withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.accentColor.withValues(alpha: 0.30),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'TIER',
                  style: TextStyle(
                    color: theme.accentColor.withValues(alpha: 0.65),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${state.currentTier}',
                  style: TextStyle(
                    color: theme.accentColor,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  ' / $maxTier',
                  style: TextStyle(
                    color: theme.accentColor.withValues(alpha: 0.5),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _PremiumStatusPill(
                  hasPremium: hasPremium,
                  theme: theme,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 10,
                color: Colors.white.withValues(alpha: 0.10),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [theme.accentColor, theme.primaryColor],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.accentColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              state.currentTier >= maxTier
                  ? 'Season complete'
                  : '${state.currentXP} / ${state.xpForNextTier} XP to Tier ${state.currentTier + 1}',
              style: TextStyle(
                color: theme.accentColor.withValues(alpha: 0.75),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ).gameEntrance(),
    );
  }
}

class _PremiumStatusPill extends StatelessWidget {
  final bool hasPremium;
  final GameTheme theme;

  const _PremiumStatusPill({required this.hasPremium, required this.theme});

  @override
  Widget build(BuildContext context) {
    final color = hasPremium ? Colors.amber : theme.accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasPremium
                ? Icons.workspace_premium_rounded
                : Icons.lock_outline_rounded,
            color: color,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            hasPremium ? 'PREMIUM' : 'FREE',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// "Coming Next" hero — the visual centerpiece. Shows the next reward the
// player will earn (whichever tier above current actually has a reward),
// preferring premium when the player owns the pass.
// ===========================================================================
class _ComingNextSection extends StatelessWidget {
  final GameTheme theme;
  final BattlePassState state;
  final BattlePassSeason season;
  final void Function(BattlePassReward reward, int tier) onTap;
  final VoidCallback onUnlockPro;

  const _ComingNextSection({
    required this.theme,
    required this.state,
    required this.season,
    required this.onTap,
    required this.onUnlockPro,
  });

  ({BattlePassReward reward, int tier, bool isPremium})? _findNext() {
    final hasPremium = state.isActive;
    for (int i = state.currentTier + 1; i <= season.levels.length; i++) {
      final level = season.levels[i - 1];
      // Prefer premium when the player owns the pass — that's the reward
      // they're chasing. Free is still surfaced when there's no premium
      // (and as a fallback when this tier has only a free reward).
      if (hasPremium && level.premiumReward != null) {
        return (reward: level.premiumReward!, tier: i, isPremium: true);
      }
      if (level.freeReward != null) {
        return (reward: level.freeReward!, tier: i, isPremium: false);
      }
      if (!hasPremium && level.premiumReward != null) {
        // Still preview locked premium so the player can SEE what Pro
        // would unlock. Caller renders the Unlock-Pro CTA on this card.
        return (reward: level.premiumReward!, tier: i, isPremium: true);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final next = _findNext();
    if (next == null) {
      // Player is at max tier or season has no rewards left. The strip
      // already says "Season complete"; render a celebratory card.
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.amber.withValues(alpha: 0.25),
                Colors.orange.withValues(alpha: 0.18),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
          ),
          child: Column(
            children: [
              const Text('🏆', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 8),
              Text(
                'SEASON COMPLETE',
                style: TextStyle(
                  color: Colors.amber.shade300,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'You\'ve unlocked every tier in this season.',
                style: TextStyle(
                  color: Colors.amber.shade100.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final r = next.reward;
    final tier = next.tier;
    final isPremium = next.isPremium;
    final lockedBehindPro = isPremium && !state.isActive;
    final distance = tier - state.currentTier;

    final accent = isPremium ? Colors.amber : theme.accentColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: GestureDetector(
        onTap: () => onTap(r, tier),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.30),
                theme.primaryColor.withValues(alpha: 0.20),
                accent.withValues(alpha: 0.10),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: accent.withValues(alpha: 0.55),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.25),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'COMING NEXT',
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isPremium ? 'PREMIUM' : 'FREE',
                      style: TextStyle(
                        color: accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Big reward icon — center-stage. Uses the model's emoji
              // by default; falls back to a generic gift if missing.
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.18),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.45),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.4),
                      blurRadius: 24,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  r.icon,
                  style: const TextStyle(fontSize: 44),
                ),
              ).gamePop().gameBreathe(intensity: 1.04),
              const SizedBox(height: 12),
              Text(
                r.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tier $tier',
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              if (lockedBehindPro) ...[
                _UnlockProInline(theme: theme, onTap: onUnlockPro),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    distance == 1
                        ? '1 tier away'
                        : '$distance tiers away',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ).gameEntrance(),
    );
  }
}

class _UnlockProInline extends StatelessWidget {
  final GameTheme theme;
  final VoidCallback onTap;

  const _UnlockProInline({required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.amber, Colors.orange.shade400],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withValues(alpha: 0.45),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.workspace_premium_rounded,
                color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text(
              'UNLOCK WITH PRO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward_rounded,
                color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// "Available now" — claimable rewards as compact chips. Each chip is one
// reward (free or premium at a particular tier); tapping the CLAIM pill
// flushes the claim through the cubit and the chip animates out on
// success.
// ===========================================================================
class _AvailableNowSection extends StatelessWidget {
  final GameTheme theme;
  final BattlePassState state;
  final BattlePassSeason season;
  final Set<String> claiming;
  final Future<void> Function({
    required int tier,
    required bool isPremium,
    required BattlePassReward reward,
  }) onClaim;
  final VoidCallback onUnlockPro;

  const _AvailableNowSection({
    required this.theme,
    required this.state,
    required this.season,
    required this.claiming,
    required this.onClaim,
    required this.onUnlockPro,
  });

  List<({BattlePassReward reward, int tier, bool isPremium})>
      _gatherAvailable() {
    // Gate premium chips on isValid (not just isActive) so we never surface a
    // chip the claim path (claimPremiumReward → requires isValid) would reject.
    final hasPremium = state.isValid;
    final out = <({BattlePassReward reward, int tier, bool isPremium})>[];
    for (int i = 1; i <= state.currentTier && i <= season.levels.length; i++) {
      final level = season.levels[i - 1];
      if (level.freeReward != null && !state.isFreeTierClaimed(i)) {
        out.add((reward: level.freeReward!, tier: i, isPremium: false));
      }
      if (hasPremium &&
          level.premiumReward != null &&
          !state.isPremiumTierClaimed(i)) {
        out.add((reward: level.premiumReward!, tier: i, isPremium: true));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final available = _gatherAvailable();
    final hasLockedPremium = !state.isActive &&
        season.levels.any(
          (l) =>
              l.level <= state.currentTier &&
              l.premiumReward != null &&
              !state.isPremiumTierClaimed(l.level),
        );

    if (available.isEmpty && !hasLockedPremium) {
      return const SizedBox(height: 8);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'AVAILABLE NOW',
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              if (available.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.green.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${available.length}',
                    style: TextStyle(
                      color: Colors.green.shade300,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (available.isNotEmpty)
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                itemCount: available.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final entry = available[index];
                  final claimKey =
                      '${entry.isPremium ? 'p' : 'f'}:${entry.tier}';
                  final isClaiming = claiming.contains(claimKey);
                  return _ClaimChip(
                    theme: theme,
                    reward: entry.reward,
                    tier: entry.tier,
                    isPremium: entry.isPremium,
                    isClaiming: isClaiming,
                    onClaim: () => onClaim(
                      tier: entry.tier,
                      isPremium: entry.isPremium,
                      reward: entry.reward,
                    ),
                  );
                },
              ),
            ),
          if (hasLockedPremium) ...[
            if (available.isNotEmpty) const SizedBox(height: 10),
            _PremiumTeaser(theme: theme, onTap: onUnlockPro),
          ],
        ],
      ),
    );
  }
}

class _ClaimChip extends StatelessWidget {
  final GameTheme theme;
  final BattlePassReward reward;
  final int tier;
  final bool isPremium;
  final bool isClaiming;
  final VoidCallback onClaim;

  const _ClaimChip({
    required this.theme,
    required this.reward,
    required this.tier,
    required this.isPremium,
    required this.isClaiming,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isPremium ? Colors.amber : theme.accentColor;

    return InkWell(
      onTap: isClaiming ? null : onClaim,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 132,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.22),
              accent.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: accent.withValues(alpha: 0.55), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.20),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'T$tier',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                Icon(
                  isPremium
                      ? Icons.workspace_premium_rounded
                      : Icons.card_giftcard_rounded,
                  size: 12,
                  color: accent,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(reward.icon, style: const TextStyle(fontSize: 32)),
            ),
            const SizedBox(height: 4),
            Text(
              reward.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: isClaiming
                    ? Colors.white.withValues(alpha: 0.10)
                    : accent.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: isClaiming
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                      ),
                    )
                  : Text(
                      'CLAIM',
                      style: TextStyle(
                        color: isPremium
                            ? Colors.black.withValues(alpha: 0.85)
                            : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumTeaser extends StatelessWidget {
  final GameTheme theme;
  final VoidCallback onTap;
  const _PremiumTeaser({required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.amber.withValues(alpha: 0.20),
              Colors.orange.withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium_rounded,
                color: Colors.amber, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Premium rewards waiting',
                    style: TextStyle(
                      color: Colors.amber.shade200,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Subscribe to Pro to claim them.',
                    style: TextStyle(
                      color: Colors.amber.shade100.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.amber.shade200.withValues(alpha: 0.85),
                size: 12),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// "View all tiers" toggle — header for the collapsible full tier list.
// Tapping flips the expand state; the list below the toggle is rendered
// by the parent CustomScrollView (cleaner than nesting another scroller
// inside this widget).
// ===========================================================================
class _AllTiersToggle extends StatelessWidget {
  final GameTheme theme;
  final bool expanded;
  final VoidCallback onTap;
  final int totalTiers;

  const _AllTiersToggle({
    required this.theme,
    required this.expanded,
    required this.onTap,
    required this.totalTiers,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.accentColor.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: theme.accentColor,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                expanded ? 'Hide tiers' : 'View all $totalTiers tiers',
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Text(
                expanded ? 'COLLAPSE' : 'EXPAND',
                style: TextStyle(
                  color: theme.accentColor.withValues(alpha: 0.65),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Tier row — one entry inside the expanded "all tiers" list. Shows tier
// number, milestone badge, and the free + premium rewards side-by-side
// with their current state (locked / claimable / claimed).
// ===========================================================================
class _TierRow extends StatelessWidget {
  final GameTheme theme;
  final BattlePassState state;
  final BattlePassLevel level;
  final ValueChanged<BattlePassReward> onTapReward;

  const _TierRow({
    required this.theme,
    required this.state,
    required this.level,
    required this.onTapReward,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = level.level == state.currentTier;
    final unlocked = level.level <= state.currentTier;
    final accent = level.isMilestone ? Colors.amber : theme.accentColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent
            ? theme.accentColor.withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent
              ? theme.accentColor.withValues(alpha: 0.55)
              : (level.isMilestone
                  ? Colors.amber.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.06)),
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                if (level.isMilestone)
                  const Icon(Icons.star_rounded,
                      color: Colors.amber, size: 14),
                Text(
                  '${level.level}',
                  style: TextStyle(
                    color: accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                if (isCurrent)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'NOW',
                      style: TextStyle(
                        color: theme.accentColor,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _TierRewardSlot(
              theme: theme,
              reward: level.freeReward,
              isPremium: false,
              tier: level.level,
              tierUnlocked: unlocked,
              claimed: state.isFreeTierClaimed(level.level),
              hasPremium: state.isActive,
              onTap: onTapReward,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TierRewardSlot(
              theme: theme,
              reward: level.premiumReward,
              isPremium: true,
              tier: level.level,
              tierUnlocked: unlocked,
              claimed: state.isPremiumTierClaimed(level.level),
              hasPremium: state.isActive,
              onTap: onTapReward,
            ),
          ),
        ],
      ),
    );
  }
}

class _TierRewardSlot extends StatelessWidget {
  final GameTheme theme;
  final BattlePassReward? reward;
  final bool isPremium;
  final int tier;
  final bool tierUnlocked;
  final bool claimed;
  final bool hasPremium;
  final ValueChanged<BattlePassReward> onTap;

  const _TierRewardSlot({
    required this.theme,
    required this.reward,
    required this.isPremium,
    required this.tier,
    required this.tierUnlocked,
    required this.claimed,
    required this.hasPremium,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (reward == null) {
      return Container(
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
        ),
        alignment: Alignment.center,
        child: Text(
          '—',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 16,
          ),
        ),
      );
    }

    final accent = isPremium ? Colors.amber : theme.accentColor;
    final isLockedByPremium = isPremium && !hasPremium;
    final locked = !tierUnlocked || isLockedByPremium;

    return InkWell(
      onTap: () => onTap(reward!),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: claimed
              ? Colors.green.withValues(alpha: 0.12)
              : (locked
                  ? Colors.white.withValues(alpha: 0.04)
                  : accent.withValues(alpha: 0.14)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: claimed
                ? Colors.green.withValues(alpha: 0.45)
                : (locked
                    ? Colors.white.withValues(alpha: 0.08)
                    : accent.withValues(alpha: 0.45)),
          ),
        ),
        child: Row(
          children: [
            Opacity(
              opacity: locked ? 0.4 : 1.0,
              child: Text(reward!.icon, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reward!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: locked
                      ? Colors.white.withValues(alpha: 0.55)
                      : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              claimed
                  ? Icons.check_circle_rounded
                  : (locked
                      ? (isLockedByPremium
                          ? Icons.workspace_premium_rounded
                          : Icons.lock_rounded)
                      : Icons.card_giftcard_rounded),
              color: claimed
                  ? Colors.green
                  : (locked
                      ? Colors.white.withValues(alpha: 0.45)
                      : accent),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Reward detail sheet — modal opened when the player taps the Coming-Next
// card or any tier row. Shows the full reward with name, description,
// type, tier, and unlock state. No claim action here (claims live on the
// Available-Now chips and on the tier-row slots themselves).
// ===========================================================================
class _RewardDetailSheet extends StatelessWidget {
  final GameTheme theme;
  final BattlePassReward reward;
  final int tier;
  final bool unlocked;

  const _RewardDetailSheet({
    required this.theme,
    required this.reward,
    required this.tier,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    final accent = reward.isPremium ? Colors.amber : theme.accentColor;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.backgroundColor.withValues(alpha: 0.98),
            theme.backgroundColor,
          ],
        ),
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: accent.withValues(alpha: 0.4)),
          left: BorderSide(color: accent.withValues(alpha: 0.4)),
          right: BorderSide(color: accent.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.2),
              border: Border.all(
                  color: accent.withValues(alpha: 0.5), width: 2),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.4),
                  blurRadius: 20,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(reward.icon, style: const TextStyle(fontSize: 50)),
          ),
          const SizedBox(height: 16),
          Text(
            reward.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  reward.isPremium ? 'PREMIUM' : 'FREE',
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'TIER $tier',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (reward.description.isNotEmpty)
            Text(
              reward.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: unlocked
                  ? Colors.green.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: unlocked
                    ? Colors.green.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  unlocked
                      ? Icons.check_circle_rounded
                      : Icons.lock_outline_rounded,
                  size: 14,
                  color: unlocked
                      ? Colors.green
                      : Colors.white.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Text(
                  unlocked ? 'Unlocked' : 'Reach Tier $tier to unlock',
                  style: TextStyle(
                    color: unlocked
                        ? Colors.green.shade200
                        : Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Empty state — shown when the backend reports no active season. Kept from
// the previous design because the layout is solid and the rotation
// messaging is correct.
// ===========================================================================
class _NoActiveSeasonScreen extends StatelessWidget {
  final GameTheme theme;
  const _NoActiveSeasonScreen({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        theme: theme,
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(theme: theme, title: 'BATTLE PASS'),
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                theme.accentColor.withValues(alpha: 0.25),
                                theme.accentColor.withValues(alpha: 0.08),
                              ],
                            ),
                            border: Border.all(
                              color: theme.accentColor.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.hourglass_empty_rounded,
                            color:
                                theme.accentColor.withValues(alpha: 0.85),
                            size: 44,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Between Seasons',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.accentColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "No Battle Pass is running right now — the next "
                        "season will start automatically. Check back soon.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.accentColor.withValues(alpha: 0.7),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 28),
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.read<BattlePassCubit>().refresh(),
                        icon: Icon(Icons.refresh_rounded,
                            color: theme.accentColor),
                        label: Text(
                          'Check for new season',
                          style: TextStyle(
                            color: theme.accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          side: BorderSide(
                            color: theme.accentColor.withValues(alpha: 0.5),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
    );
  }
}
