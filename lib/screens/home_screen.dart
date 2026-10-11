import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_settings_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/power_up/power_up_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/providers/walkthrough_provider.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/data/database/app_database.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/providers/daily_challenges_provider.dart';
import 'package:cosmo_strike_flutter_app/services/notification_service.dart';
import 'package:cosmo_strike_flutter_app/services/share_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/walkthrough_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/battle_pass_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/progression_service.dart';
import 'package:cosmo_strike_flutter_app/utils/campaign_catalog.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/rewarded_action_button.dart';
import 'package:cosmo_strike_flutter_app/widgets/credits_dialog.dart';
import 'package:cosmo_strike_flutter_app/widgets/daily_bonus_popup.dart';
import 'package:cosmo_strike_flutter_app/widgets/reward_toast.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/home_walkthrough.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/walkthrough_overlay.dart';
import 'package:talker_flutter/talker_flutter.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _dailyBonusChecked = false;
  bool _walkthroughChecked = false;

  @override
  void initState() {
    super.initState();

    // Check for daily bonus after a short delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _checkDailyBonus();
      }
    });

    // Check for walkthrough after daily bonus popup delay
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        _checkWalkthrough();
      }
    });

    // First-launch initialization of the notification service. Used to
    // live in main.dart but the OS permission dialog as a side effect
    // was firing before the user had ever seen the app — so we moved
    // it here, where it fires once the user has actually landed on
    // home. NotificationService.initialize() guards itself against
    // double-init (the _initialized flag), so re-entering home doesn't
    // re-prompt.
    _maybeInitNotifications();
  }

  void _maybeInitNotifications() {
    if (NotificationService().initialized) return;
    // Small delay so the home screen finishes its first layout +
    // animations before the permission dialog pops over it.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      NotificationService()
          .initialize()
          .then((_) {
            AppLogger.success('Notification service initialized from home');
          })
          .catchError((e) {
            AppLogger.error('Notification service init failed', e);
          });
    });
  }

  /// One-time control-method chooser (touch-drag vs D-pad), shown on the
  /// first Play tap — right where the choice is about to matter, and
  /// before the in-game tutorial so its steer beat demos the input the
  /// player actually picked. Changeable any time in Settings.
  Future<void> _maybeShowControlChoicePrompt() async {
    if (!mounted) return;
    final walkthroughs = WalkthroughService();
    if (!walkthroughs.isInitialized) await walkthroughs.initialize();
    if (walkthroughs.isComplete(WalkthroughService.controlChoiceId)) return;
    if (!mounted) return;

    final settingsCubit = context.read<GameSettingsCubit>();
    final useDPad = await showCsDialog<bool>(
      context,
      barrierDismissible: false,
      builder: (sheetContext) => const _ControlChoiceSheet(),
    );

    if (useDPad != null) {
      await settingsCubit.setDPadEnabled(useDPad);
    }
    await walkthroughs.markComplete(WalkthroughService.controlChoiceId);
  }

  /// Shows the first-launch game-mode picker if it hasn't been shown
  /// before. Returns once the sheet is dismissed (or immediately if the
  /// user has already seen it). Triggered from the Play button so it
  /// only appears in the path where the choice actually matters.
  Future<void> _maybeShowGameModePrompt() async {
    if (!mounted) return;
    final settingsCubit = context.read<GameSettingsCubit>();

    // Read the flag with a short hydration window. If the cubit is
    // already ready (overwhelmingly the case by the time the user taps
    // Play), this returns immediately. Falls back to direct storage on
    // a timeout so we never nag a user who already chose.
    bool alreadyPrompted;
    if (settingsCubit.state.isReady) {
      alreadyPrompted = settingsCubit.state.gameModeFirstLaunchPrompted;
    } else {
      try {
        final ready = await settingsCubit.stream
            .firstWhere((s) => s.isReady)
            .timeout(const Duration(seconds: 2));
        alreadyPrompted = ready.gameModeFirstLaunchPrompted;
      } catch (_) {
        alreadyPrompted = await getIt<StorageService>()
            .hasGameModeBeenPrompted();
      }
    }

    if (!mounted) return;
    if (alreadyPrompted) return;

    final selected = await showCsDialog<GameMode>(
      context,
      barrierDismissible: false,
      builder: (sheetContext) =>
          _GameModeFirstLaunchSheet(initialMode: settingsCubit.state.gameMode),
    );

    if (!mounted) return;
    if (selected != null) {
      await settingsCubit.setGameMode(selected);
    }
    await settingsCubit.markGameModePrompted();
  }

  /// Check if home walkthrough should be shown
  Future<void> _checkWalkthrough() async {
    if (_walkthroughChecked) return;
    _walkthroughChecked = true;

    final walkthroughNotifier = ref.read(walkthroughProvider.notifier);
    final isComplete = await walkthroughNotifier.isWalkthroughComplete(
      WalkthroughService.homeWalkthroughId,
    );

    if (!isComplete && mounted) {
      getIt<AnalyticsFacade>().trackWalkthroughStarted();
      walkthroughNotifier.start(
        walkthroughId: WalkthroughService.homeWalkthroughId,
        steps: HomeWalkthrough.getSteps(),
      );
    }
  }

  /// Check and show daily bonus popup if available.
  /// Offline-first: reads CoinsCubit's local state. No network call.
  Future<void> _checkDailyBonus() async {
    if (_dailyBonusChecked) return;
    _dailyBonusChecked = true;

    if (!mounted) return;

    // Frontend gate: already claimed today, skip everything
    final coinsCubit = context.read<CoinsCubit>();
    if (coinsCubit.wasDailyBonusClaimedToday) return;

    try {
      DailyBonusStatus? status;

      if (coinsCubit.state.canCollectDailyBonus) {
        final localBonus = coinsCubit.state.availableDailyBonus;
        if (localBonus != null) {
          status = DailyBonusStatus(
            canClaim: true,
            currentStreak: localBonus.day,
            todayReward: DailyBonusReward(
              day: localBonus.day,
              coins: localBonus.coins,
              bonusItem: localBonus.bonusItem,
            ),
            weekRewards: coinsCubit.state.dailyBonuses
                .map(
                  (b) => DailyBonusReward(
                    day: b.day,
                    coins: b.coins,
                    bonusItem: b.bonusItem,
                    claimed: b.isCollected,
                  ),
                )
                .toList(),
          );
        }
      }

      if (status == null || !status.canClaim || !mounted) return;

      final theme = context.read<ThemeCubit>().state.currentTheme;

      // Offer a "claim 2×" via rewarded ad when one is available (free users).
      final bonusCoins = status.todayReward?.coins ?? 0;
      final ads = getIt.isRegistered<AdService>() ? getIt<AdService>() : null;
      final canDouble = ads != null && ads.adsEnabled && ads.isRewardedReady;

      await DailyBonusPopup.show(
        context: context,
        theme: theme,
        status: status,
        onClaim: () async {
          if (!mounted) return false;
          final success = await context.read<CoinsCubit>().collectDailyBonus();
          if (success) {
            getIt<AnalyticsFacade>().trackDailyBonusCollected();
            RewardToast.show(
              title: 'DAILY BONUS',
              amount: '+$bonusCoins COINS',
            );
          }
          return success;
        },
        onClaimDoubled: canDouble
            ? () async {
                if (!mounted) return;
                final coins = context.read<CoinsCubit>();
                final ok = await coins.collectDailyBonus();
                if (!ok) return;
                getIt<AnalyticsFacade>().trackDailyBonusCollected();
                RewardToast.show(
                  title: 'DAILY BONUS',
                  amount: '+$bonusCoins COINS',
                );
                // Grant the same amount again on ad completion → 2× total.
                await ads.showRewarded(
                  onReward: () {
                    coins.earnCoins(
                      CoinEarningSource.dailyLogin,
                      customAmount: bonusCoins,
                      itemName: 'Daily bonus 2x',
                    );
                    RewardToast.show(
                      title: 'BONUS DOUBLED',
                      amount: '+$bonusCoins COINS',
                    );
                  },
                );
              }
            : null,
      );
    } catch (e) {
      AppLogger.error('Error checking daily bonus', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walkthroughState = ref.watch(walkthroughProvider);
    final theme = context.watch<ThemeCubit>().state.currentTheme;
    final authState = context.watch<AuthCubit>().state;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: CsColors.bg,
          bottomNavigationBar: const ShipBannerAd(),
          body: CsBackground(
            stars: true,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: context.cs.screenPadding,
                child: _HomeLayout(
                  topBar: _buildTopBar(context, authState),
                  hero: _buildHero(context, theme),
                  nav: _buildNav(context),
                ),
              ),
            ),
          ),
        ),

        // Walkthrough overlay
        if (walkthroughState.isActive && walkthroughState.currentStep != null)
          WalkthroughOverlay(
            step: walkthroughState.currentStep!,
            theme: theme,
            currentStepIndex: walkthroughState.currentStepIndex,
            totalSteps: walkthroughState.steps.length,
            onNext: () => ref.read(walkthroughProvider.notifier).next(),
            onSkip: () => ref.read(walkthroughProvider.notifier).skip(),
          ),

        // Sync restore overlay is mounted globally in
        // CosmoStrikeApp.builder so it appears regardless
        // of which screen is active during the pull.
      ],
    );
  }

  /// Top bar: lockup left; telemetry, overflow tools, settings and the
  /// prism-ringed avatar right.
  Widget _buildTopBar(BuildContext context, AuthState authState) {
    final cs = context.cs;
    final t = cs.type;
    final meta = t.mono(11, color: CsColors.ink60, em: 0.12);
    final adsOn = getIt.isRegistered<AdService>() && getIt<AdService>().adsEnabled;

    Widget tapText(String text, VoidCallback onTap, {Key? key, TextStyle? style}) => CsPressable(
          key: key,
          onTap: onTap,
          semanticLabel: text,
          child: SizedBox(
            height: 44,
            child: Center(child: Text(text, maxLines: 1, style: style ?? meta)),
          ),
        );

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const CsLogoLockup(),
          const Spacer(),
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tapText(
                    'BEST ${context.watch<GameSettingsCubit>().state.highScore}',
                    () => context.push(AppRoutes.statistics),
                  ),
                  SizedBox(width: cs(22)),
                  BlocBuilder<CoinsCubit, CoinsState>(
                    builder: (context, coinsState) => tapText(
                      'COINS ${_formatCoins(coinsState.total)}',
                      () => context.push(AppRoutes.store),
                      key: HomeWalkthrough.coinsKey,
                    ),
                  ),
                  // EARN — rewarded ad for free coins, free users only.
                  if (adsOn) ...[
                    SizedBox(width: cs(12)),
                    CsPressable(
                      onTap: () => _watchForCoins(context),
                      semanticLabel: 'Watch an ad to earn coins',
                      child: SizedBox(
                        height: 44,
                        child: Center(
                          child: CsChip(
                            '+${AdService.freeCoinsPerAd}',
                            kind: CsChipKind.outline,
                            icon: Symbols.play_circle_rounded,
                            size: 10,
                          ),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(width: cs(22)),
                  ListenableBuilder(
                    listenable: getIt<ProgressionService>(),
                    builder: (context, _) => tapText(
                      'LV ${getIt<ProgressionService>().level.toString().padLeft(2, '0')}',
                      () => context.push(AppRoutes.profile),
                      style: meta.copyWith(color: CsColors.ink),
                    ),
                  ),
                  SizedBox(width: cs(14)),
                  _HomeMoreMenu(
                    onShare: () => ShareService().shareApp(),
                    onAbout: () => showCreditsDialog(context, context.read<ThemeCubit>().state.currentTheme),
                    onHelp: () => context.push(AppRoutes.instructions),
                    onDebugLogs: kDebugMode
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => TalkerScreen(talker: AppLogger.instance),
                              ),
                            )
                        : null,
                  ),
                  CsIconButton(
                    key: HomeWalkthrough.settingsKey,
                    icon: Symbols.settings_rounded,
                    bordered: false,
                    size: 38,
                    color: CsColors.ink70,
                    tooltip: 'Settings',
                    onPressed: () => context.push(AppRoutes.settings),
                  ),
                  SizedBox(width: cs(8)),
                  CsPressable(
                    key: HomeWalkthrough.profileKey,
                    semanticLabel: 'Profile',
                    onTap: () => context.push(AppRoutes.profile),
                    child: CsAvatarRing(
                      name: authState.displayName,
                      size: 34,
                      image: authState.isSignedIn && (authState.photoURL?.isNotEmpty ?? false)
                          ? NetworkImage(authState.photoURL!)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Hero: mission label, the next level's name set huge with the prism on
  /// its tail, and the LAUNCH pill + loadout + campaign access.
  Widget _buildHero(BuildContext context, GameTheme theme) {
    final cs = context.cs;
    final t = cs.type;
    return StreamBuilder<List<StageProgressRow>>(
      stream: _stagesStream,
      builder: (context, snap) {
        final rows = snap.data ?? const <StageProgressRow>[];
        final unlocked = rows.where((r) => r.unlocked).map((r) => r.stageId);
        final level = unlocked.isEmpty ? 1 : unlocked.reduce((a, b) => a > b ? a : b);
        final name = _titleCase(CampaignCatalog.levelNameFor(level));
        final biome = CampaignCatalog.biomeNameFor(level);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MISSION ${level.toString().padLeft(2, '0')} / $biome',
              style: t.mono(11, em: 0.16, color: CsColors.ink55),
            ),
            SizedBox(height: cs(16)),
            _HeroTitle(name: name),
            SizedBox(height: cs(22)),
            Wrap(
              spacing: cs(14),
              runSpacing: cs(8),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CsButton.primary(
                  key: HomeWalkthrough.playButtonKey,
                  label: 'Launch',
                  trailingIcon: Symbols.arrow_forward_rounded,
                  onPressed: () => _launch(context),
                ),
                _buildLoadoutChip(theme),
                CsButton.text(
                  label: 'Campaign',
                  size: CsButtonSize.small,
                  icon: Symbols.grid_view_rounded,
                  onPressed: () => context.push(AppRoutes.levelSelect),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _launch(BuildContext context) async {
    // First-launch setup prompts, in the order they matter: how you
    // fly, then how you want the run tuned. Both are one-time no-ops
    // for users who've already chosen.
    await _maybeShowControlChoicePrompt();
    if (!context.mounted) return;
    await _maybeShowGameModePrompt();
    if (!context.mounted) return;
    // Drop STRAIGHT into the next unlocked level — the "continue"
    // target — so the most common intent (just keep playing) is a
    // single tap with no campaign screen in the way. Routes through the
    // pre-game loader (which pushReplacements to /game so back from the
    // game lands here).
    final startLevel = await getIt<AppDatabase>().stageProgressDao.getFurthestUnlocked();
    if (!context.mounted) return;
    context.push(AppRoutes.playLoading, extra: startLevel);
  }

  late final Stream<List<StageProgressRow>> _stagesStream =
      getIt<AppDatabase>().stageProgressDao.watchAll();

  static String _titleCase(String s) => s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  /// "LOADOUT · 03 ▾" / "ARMED · SPEED BOOST ▾". Hidden with no inventory.
  Widget _buildLoadoutChip(GameTheme theme) {
    return BlocBuilder<PowerUpCubit, PowerUpState>(
      builder: (context, powerUpState) {
        if (powerUpState.totalOwned == 0) return const SizedBox.shrink();
        final cs = context.cs;
        final armed = powerUpState.armed;
        final label = armed != null
            ? 'ARMED · ${CsIcons.powerUpLabel(armed).toUpperCase()}'
            : 'LOADOUT · ${powerUpState.totalOwned.toString().padLeft(2, '0')}';
        return CsPressable(
          onTap: () => _openLoadoutSheet(theme, powerUpState),
          semanticLabel: 'Power-up loadout',
          child: SizedBox(
            height: 44,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (armed != null) ...[
                Icon(CsIcons.powerUp(armed), size: cs(16), color: CsColors.gold),
                SizedBox(width: cs(6)),
              ],
              Text(label,
                  style: cs.type.mono(12, em: 0.08, color: armed != null ? CsColors.gold : CsColors.ink60)),
              SizedBox(width: cs(4)),
              Icon(Symbols.expand_more_rounded, size: cs(16), color: CsColors.ink45),
            ]),
          ),
        );
      },
    );
  }

  void _openLoadoutSheet(GameTheme theme, PowerUpState state) {
    showCsDialog(
      context,
      builder: (sheetContext) => _LoadoutSheet(theme: theme),
    );
  }

  /// Rewarded "watch for coins" from the home top bar. Honours the daily
  /// cap; credits offline-first via CoinsCubit.
  Future<void> _watchForCoins(BuildContext context) async {
    final ads = getIt<AdService>();
    if (!ads.canShowFreeCoinAd) {
      showCsToast(
        context,
        ads.freeCoinAdsRemainingToday == 0
            ? "You've hit today's free-coin limit — come back tomorrow!"
            : 'No ad available right now, try again shortly',
      );
      return;
    }
    final coins = context.read<CoinsCubit>();
    await ads.showRewardedForCoins(
      onCoins: (amount) async {
        // Deposit first (offline-first via CoinsCubit), confirm after.
        await coins.earnCoins(
          CoinEarningSource.watchedAd,
          customAmount: amount,
          itemName: 'Watched ad',
          metadata: const {'placement': 'home_free_coins'},
        );
        RewardToast.show(amount: '+$amount COINS');
      },
    );
  }

  /// Bottom text nav over a hairline. Every old menu tile maps to one item.
  Widget _buildNav(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final daily = ref.watch(dailyChallengesProvider);
    final unclaimed = _getDailyChallengesBadge();
    final passTier = context.watch<BattlePassCubit>().state.currentTier;

    Widget item(String label, VoidCallback onTap,
        {Key? key, String? badge, Color badgeColor = CsColors.mint, Color? color, bool dot = false}) {
      return CsPressable(
        key: key,
        onTap: onTap,
        semanticLabel: label,
        child: SizedBox(
          height: 44,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: t.nav.copyWith(color: color ?? CsColors.ink70)),
            if (badge != null) ...[
              SizedBox(width: cs(6)),
              Text(badge, style: t.mono(10, color: badgeColor, em: 0.04)),
            ],
            if (dot) ...[
              SizedBox(width: cs(5)),
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(color: CsColors.gold, shape: BoxShape.circle),
              ),
            ],
          ]),
        ),
      );
    }

    final gap = SizedBox(width: cs(26));
    final left = <Widget>[
      item(
        'DAILY',
        () => context.push(AppRoutes.dailyChallenges),
        key: HomeWalkthrough.dailyChallengesKey,
        color: CsColors.ink,
        badge: daily.totalCount > 0 ? '${daily.completedCount}/${daily.totalCount}' : null,
        dot: unclaimed != null,
      ),
      item('PASS', () => context.push(AppRoutes.battlePass),
          badge: 'T$passTier', badgeColor: CsColors.pink),
      item('EVENTS', () => context.push(AppRoutes.tournaments)),
      item('RANKS', () => context.push(AppRoutes.leaderboard)),
      item('FRIENDS', () => context.push(AppRoutes.friends)),
      item('HANGAR', () => context.push(AppRoutes.cosmetics), key: HomeWalkthrough.cosmeticsKey),
      item('AWARDS', () => context.push(AppRoutes.achievements)),
      item('STATS', () => context.push(AppRoutes.statistics)),
    ];
    final right = <Widget>[
      item('PRO', () => context.push(AppRoutes.premiumBenefits)),
      item('STORE ↗', () => context.push(AppRoutes.store),
          key: HomeWalkthrough.storeKey, color: CsColors.gold),
    ];

    List<Widget> spaced(List<Widget> xs) => [
          for (var i = 0; i < xs.length; i++) ...[if (i > 0) gap, xs[i]],
        ];

    return DecoratedBox(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: CsColors.hairline))),
      child: Padding(
        padding: EdgeInsets.only(top: cs(6)),
        // Scales down as one row on narrow phones instead of wrapping.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: _navNaturalWidth(context),
            child: Row(children: [...spaced(left), const Spacer(), ...spaced(right)]),
          ),
        ),
      ),
    );
  }

  /// The nav row is laid out at the full content width when it fits, and at
  /// its natural width (then scaled down) when it doesn't.
  double _navNaturalWidth(BuildContext context) {
    final cs = context.cs;
    final mq = MediaQuery.of(context);
    final avail = mq.size.width - mq.padding.horizontal - cs.screenPadding.horizontal;
    final natural = cs(880);
    return avail > natural ? avail : natural;
  }

  /// Format coin balance for display (e.g., 1.2K, 1.5M)
  String _formatCoins(int coins) {
    if (coins >= 1000000) {
      final value = coins / 1000000;
      return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}M';
    } else if (coins >= 1000) {
      final value = coins / 1000;
      return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}K';
    }
    return '$coins';
  }

  /// Get the badge count for daily challenges (unclaimed rewards).
  /// Watches the Riverpod provider so the home screen rebuilds and the
  /// badge updates the moment a reward is claimed elsewhere.
  int? _getDailyChallengesBadge() {
    final count = ref.watch(unclaimedRewardsCountProvider);
    return count > 0 ? count : null;
  }
}

/// Lays out the menu: top bar, hero (vertically centred in the free space),
/// bottom nav, with the prism planet + ship composited on the right. Works
/// from a 640x360 phone up to a 13" iPad by scaling the planet to the space.
class _HomeLayout extends StatelessWidget {
  const _HomeLayout({required this.topBar, required this.hero, required this.nav});
  final Widget topBar;
  final Widget hero;
  final Widget nav;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return LayoutBuilder(builder: (context, c) {
      final topClear = cs(52);
      final planet = ((c.maxHeight - topClear) * 0.92).clamp(0.0, c.maxWidth * 0.40);
      return Stack(
        clipBehavior: Clip.none,
        children: [
          // Planet + orbit + ship. Sits behind the content and may run under
          // the top telemetry, like the mock.
          Positioned(
            right: cs(8),
            top: topClear + (c.maxHeight - topClear - planet) / 2 - cs(16),
            width: planet,
            height: planet,
            child: const IgnorePointer(child: _PlanetHero()),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              topBar,
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: c.maxWidth * 0.82),
                    child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: hero),
                  ),
                ),
              ),
              nav,
            ],
          ),
        ],
      );
    });
  }
}

/// Two-line hero name: all but the last word on line 1, the last word on
/// line 2 with its second half in prism ("Iron / Dread·nought").
class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final st = context.type.hero;
    final words = name.split(' ');
    final last = words.removeLast();
    final cut = (last.length / 2).floor().clamp(1, last.length - 1);
    final line2a = last.length > 1 ? last.substring(0, cut) : last;
    final line2b = last.length > 1 ? last.substring(cut) : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (words.isNotEmpty) Text(words.join(' '), maxLines: 1, style: st),
        Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Text(line2a, maxLines: 1, style: st),
          if (line2b.isNotEmpty) CsPrismText(line2b, style: st, maxLines: 1),
        ]),
      ],
    );
  }
}

/// Prism planet with a tilted orbit ring and the player ship riding it.
class _PlanetHero extends StatelessWidget {
  const _PlanetHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final d = c.maxWidth;
      return Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: Image.asset('assets/images/bg/planet-prism.png', fit: BoxFit.contain),
        ),
        Positioned(
          left: -d * 0.22,
          right: -d * 0.3,
          top: d * 0.36,
          height: d * 0.26,
          child: const CustomPaint(painter: _OrbitPainter()),
        ),
        Positioned(
          left: d * 0.08,
          top: d * 0.41,
          width: d * 0.44,
          child: Image.asset('assets/images/ui/ship-hero.png', fit: BoxFit.contain),
        ),
      ]);
    });
  }
}

/// Thin tilted ellipse orbit around the planet.
class _OrbitPainter extends CustomPainter {
  const _OrbitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.14);
    final r = Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height * 0.28);
    canvas.drawOval(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = const LinearGradient(
          colors: [Color(0x00FFFFFF), Color(0x80FFFFFF), Color(0x55FFFFFF), Color(0x00FFFFFF)],
          stops: [0, .3, .75, 1],
        ).createShader(r),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbitPainter old) => false;
}

/// Overflow for the secondary tools that used to crowd the top bar.
class _HomeMoreMenu extends StatelessWidget {
  const _HomeMoreMenu({required this.onShare, required this.onAbout, required this.onHelp, this.onDebugLogs});
  final VoidCallback onShare;
  final VoidCallback onAbout;
  final VoidCallback onHelp;

  /// Debug builds only: opens the Talker log viewer.
  final VoidCallback? onDebugLogs;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'More',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 44),
      onSelected: (v) => switch (v) {
        0 => onHelp(),
        1 => onShare(),
        3 => onDebugLogs?.call(),
        _ => onAbout(),
      },
      itemBuilder: (context) {
        PopupMenuItem<int> row(int v, IconData icon, String label) => PopupMenuItem(
              value: v,
              child: Row(children: [
                Icon(icon, size: 18, color: CsColors.ink60),
                const SizedBox(width: 12),
                Text(label, style: context.type.rowTitle.copyWith(fontSize: 14)),
              ]),
            );
        return [
          row(0, Symbols.help_rounded, 'How to play'),
          row(1, Symbols.share_rounded, 'Share Cosmo Strike'),
          row(2, Symbols.info_rounded, 'About'),
          if (onDebugLogs != null) row(3, Symbols.bug_report_rounded, 'Debug logs'),
        ];
      },
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(Symbols.more_horiz_rounded, size: context.cs(22), color: CsColors.ink70),
      ),
    );
  }
}

/// Shared centred-dialog frame for the first-launch choosers.
class _ChoiceDialog extends StatelessWidget {
  const _ChoiceDialog({
    required this.eyebrow,
    required this.title,
    required this.options,
    required this.footer,
    required this.cta,
  });

  final String eyebrow;
  final String title;
  final Widget options;
  final Widget footer;
  final Widget cta;

  @override
  Widget build(BuildContext context) {
    return CsDialog(
      maxWidth: 640,
      eyebrow: eyebrow,
      title: title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [options, SizedBox(height: context.cs(14)), footer],
      ),
      actions: [cta],
    );
  }
}

/// First-launch control chooser: touch-drag steering vs on-screen D-pad.
/// Pops `true` for D-pad, `false` for touch.
class _ControlChoiceSheet extends StatefulWidget {
  const _ControlChoiceSheet();

  @override
  State<_ControlChoiceSheet> createState() => _ControlChoiceSheetState();
}

class _ControlChoiceSheetState extends State<_ControlChoiceSheet> {
  bool _useDPad = false;

  @override
  Widget build(BuildContext context) {
    return _ChoiceDialog(
      eyebrow: 'Controls',
      title: 'How do you want to fly?',
      options: Row(children: [
        Expanded(
          child: _option(
            useDPad: false,
            icon: Symbols.swipe_rounded,
            title: 'Touch drag',
            tagline: 'Recommended',
            description: 'Drag anywhere on screen — your ship mirrors your finger.',
          ),
        ),
        SizedBox(width: context.cs(12)),
        Expanded(
          child: _option(
            useDPad: true,
            icon: Symbols.gamepad_rounded,
            title: 'D-pad',
            tagline: 'Classic',
            description: 'An on-screen directional pad, old-school handheld style.',
          ),
        ),
      ]),
      footer: Text('You can change this anytime in Settings', style: context.type.micro),
      cta: CsButton.primary(label: 'Confirm', onPressed: () => Navigator.of(context).pop(_useDPad)),
    );
  }

  Widget _option({
    required bool useDPad,
    required IconData icon,
    required String title,
    required String tagline,
    required String description,
  }) {
    final cs = context.cs;
    final t = cs.type;
    final on = _useDPad == useDPad;
    return CsTile(
      state: on ? CsTileState.current : CsTileState.done,
      onTap: () => setState(() => _useDPad = useDPad),
      padding: EdgeInsets.all(cs(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: cs(22), color: on ? CsColors.ink : CsColors.ink45),
          const Spacer(),
          Text(tagline.toUpperCase(), style: t.mono(9, color: on ? CsColors.mint : CsColors.ink45)),
        ]),
        SizedBox(height: cs(12)),
        Text(title, style: t.rowTitle),
        SizedBox(height: cs(4)),
        Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.body),
      ]),
    );
  }
}

class _GameModeFirstLaunchSheet extends StatefulWidget {
  const _GameModeFirstLaunchSheet({required this.initialMode});

  final GameMode initialMode;

  @override
  State<_GameModeFirstLaunchSheet> createState() => _GameModeFirstLaunchSheetState();
}

class _GameModeFirstLaunchSheetState extends State<_GameModeFirstLaunchSheet> {
  late GameMode _selected = widget.initialMode;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    const modes = GameMode.values;
    const cols = 4;
    return _ChoiceDialog(
      eyebrow: 'Game mode',
      title: 'Pick a game mode',
      options: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var r = 0; r * cols < modes.length; r++) ...[
          if (r > 0) SizedBox(height: cs(8)),
          Row(children: [
            for (var c = 0; c < cols; c++) ...[
              if (c > 0) SizedBox(width: cs(8)),
              Expanded(
                child: r * cols + c < modes.length ? _modeTile(modes[r * cols + c]) : const SizedBox.shrink(),
              ),
            ],
          ]),
        ],
      ]),
      footer: SizedBox(
        height: cs(34),
        child: Text(_selected.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.body),
      ),
      cta: CsButton.primary(
        label: 'Start playing',
        trailingIcon: Symbols.arrow_forward_rounded,
        onPressed: () => Navigator.of(context).pop(_selected),
      ),
    );
  }

  Widget _modeTile(GameMode mode) {
    final cs = context.cs;
    final on = _selected == mode;
    return CsTile(
      state: on ? CsTileState.current : CsTileState.future,
      onTap: () => setState(() => _selected = mode),
      height: cs(64).clamp(48.0, 96.0),
      padding: EdgeInsets.symmetric(horizontal: cs(10), vertical: cs(8)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(CsIcons.mode(mode), size: cs(18), color: on ? CsColors.ink : CsColors.ink45),
        SizedBox(height: cs(6)),
        Text(
          mode.name.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: cs.type.mono(9, color: on ? CsColors.ink : CsColors.ink55),
        ),
      ]),
    );
  }
}

/// Pre-game power-up loadout. Lists every type the user owns, highlights
/// the armed one, and lets them switch / unarm. Closing leaves the previous
/// selection intact — a passive viewer/editor, not a wizard.
class _LoadoutSheet extends StatelessWidget {
  const _LoadoutSheet({required this.theme});
  final GameTheme theme;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PowerUpCubit, PowerUpState>(
      builder: (context, state) {
        final cs = context.cs;
        final t = cs.type;
        final entries = state.inventory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        return CsDialog(
          maxWidth: 600,
          eyebrow: 'Loadout',
          title: 'Power-up loadout',
          message: 'Pre-load one power-up — it activates 5 seconds into your next game.',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Rewarded — grab a free Speed Boost without spending coins.
              RewardedActionButton(
                theme: theme,
                icon: Symbols.bolt_rounded,
                label: 'Watch ad — free Speed Boost',
                capKey: AdService.capFreePowerUp,
                onWatch: () async {
                  final powerUps = context.read<PowerUpCubit>();
                  await getIt<AdService>().showRewardedCapped(
                    capKey: AdService.capFreePowerUp,
                    onReward: () {
                      powerUps.grantFreePowerUp();
                      RewardToast.show(icon: Symbols.bolt_rounded, amount: '+1 SPEED BOOST');
                    },
                  );
                },
              ),
              SizedBox(height: cs(8)),
              if (entries.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: cs(20)),
                  child: Text('You have no power-ups. Visit the store to buy some!',
                      textAlign: TextAlign.center, style: t.body),
                )
              else
                for (final e in entries)
                  CsListRow(
                    title: CsIcons.powerUpLabel(e.key),
                    subtitle: 'Owned · ${e.value}',
                    leading: CsIconDisc(
                      CsIcons.powerUp(e.key),
                      color: state.armed == e.key ? CsColors.gold : CsColors.ink60,
                    ),
                    trailing: state.armed == e.key
                        ? const CsChip('Armed', kind: CsChipKind.gold)
                        : Icon(Symbols.add_circle_rounded, size: cs(22), color: CsColors.ink45),
                    onTap: () {
                      final cubit = context.read<PowerUpCubit>();
                      state.armed == e.key ? cubit.unarm() : cubit.arm(e.key);
                    },
                  ),
            ],
          ),
          actions: [CsButton.primary(label: 'Done', onPressed: () => Navigator.of(context).pop())],
        );
      },
    );
  }
}
