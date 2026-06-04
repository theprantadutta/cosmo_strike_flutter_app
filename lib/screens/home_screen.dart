import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/coins/coins_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/power_up/power_up_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/providers/walkthrough_provider.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/providers/daily_challenges_provider.dart';
import 'package:cosmo_strike_flutter_app/services/notification_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/walkthrough_service.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/logger.dart';
import 'package:cosmo_strike_flutter_app/models/ship_coins.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/rewarded_action_button.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';
import 'package:cosmo_strike_flutter_app/widgets/credits_dialog.dart';
import 'package:cosmo_strike_flutter_app/widgets/daily_bonus_popup.dart';
import 'package:cosmo_strike_flutter_app/widgets/player_progression.dart';
import 'package:cosmo_strike_flutter_app/widgets/theme_transition_system.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/home_walkthrough.dart';
import 'package:cosmo_strike_flutter_app/widgets/walkthrough/walkthrough_overlay.dart';
import 'package:talker_flutter/talker_flutter.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  bool _dailyBonusChecked = false;
  bool _walkthroughChecked = false;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1500), // Reduced duration
      vsync: this,
    );

    // Theme transitions are handled by ThemeTransitionWidget directly

    // Start logo animation with a slight delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _logoController.forward();
      }
    });

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
      NotificationService().initialize().then((_) {
        AppLogger.success('Notification service initialized from home');
      }).catchError((e) {
        AppLogger.error('Notification service init failed', e);
      });
    });
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
        alreadyPrompted =
            await getIt<StorageService>().hasGameModeBeenPrompted();
      }
    }

    if (!mounted) return;
    if (alreadyPrompted) return;

    final selected = await showModalBottomSheet<GameMode>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _GameModeFirstLaunchSheet(
        initialMode: settingsCubit.state.gameMode,
      ),
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
                // Grant the same amount again on ad completion → 2× total.
                await ads.showRewarded(
                  onReward: () => coins.earnCoins(
                    CoinEarningSource.dailyLogin,
                    customAmount: bonusCoins,
                    itemName: 'Daily bonus 2x',
                  ),
                );
              }
            : null,
      );
    } catch (e) {
      AppLogger.error('Error checking daily bonus', e);
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final walkthroughState = ref.watch(walkthroughProvider);

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;

        return BlocBuilder<AuthCubit, AuthState>(
          builder: (context, authState) {
            return BlocBuilder<GameCubit, GameCubitState>(
              builder: (context, gameState) {
                return Stack(
                  children: [
                    ThemeTransitionWidget(
                      controller: ThemeTransitionController(vsync: this),
                      currentTheme: theme,
                      child: Scaffold(
                        bottomNavigationBar: const ShipBannerAd(),
                        body: AppBackground(
                          theme: theme,
                          child: SafeArea(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final screenWidth = constraints.maxWidth;
                                final screenHeight = constraints.maxHeight;

                                // Enhanced screen size detection with more granular breakpoints
                                final isVerySmallScreen =
                                    screenHeight < 600 || screenWidth < 350;

                                // Use a simple Column with proper constraints for better stability
                                return Column(
                                  children: [
                                    // Top navigation bar - fixed height
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: screenWidth * 0.04,
                                        vertical: isVerySmallScreen ? 4 : 8,
                                      ),
                                      child: _buildTopNavigation(
                                        context,
                                        authState,
                                        theme,
                                        isVerySmallScreen,
                                      ),
                                    ),

                                    // Landscape command deck: LEFT brand +
                                    // nav grid + action row, RIGHT big hero
                                    // LAUNCH bay. Reuses the existing
                                    // sub-builders (so the walkthrough keys /
                                    // daily-bonus / game-mode logic stay
                                    // intact); only the composition changes.
                                    Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: screenWidth * 0.03,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            // Left — brand/telemetry header,
                                            // nav grid, and PRO/STORE/COINS row.
                                            Expanded(
                                              flex: 6,
                                              // BEST + coins now live in the top
                                              // command bar, so the left column
                                              // is given entirely to the icon
                                              // rail.
                                              child: _buildBottomNavigation(
                                                context,
                                                themeState,
                                                theme,
                                                screenHeight,
                                                screenWidth,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            // Right — big hero LAUNCH bay.
                                            Expanded(
                                              flex: 5,
                                              child: Column(
                                                children: [
                                                  Expanded(
                                                    child: _buildLaunchHero(
                                                      context,
                                                      theme,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  ConstrainedBox(
                                                    constraints:
                                                        const BoxConstraints(
                                                            maxHeight: 52),
                                                    child:
                                                        _buildActionButtonsRow(
                                                      context: context,
                                                      theme: theme,
                                                      screenWidth: screenWidth,
                                                      isSmallScreen:
                                                          screenHeight < 750,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        floatingActionButton: kDebugMode
                            ? FloatingActionButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => TalkerScreen(
                                        talker: AppLogger.instance,
                                      ),
                                    ),
                                  );
                                },
                                backgroundColor: theme.accentColor.withValues(
                                  alpha: 0.1,
                                ),
                                foregroundColor: theme.accentColor,
                                mini: true,
                                child: const Icon(Icons.bug_report),
                              )
                            : null,
                      ),
                    ),

                    // Walkthrough overlay
                    if (walkthroughState.isActive &&
                        walkthroughState.currentStep != null)
                      WalkthroughOverlay(
                        step: walkthroughState.currentStep!,
                        theme: theme,
                        currentStepIndex: walkthroughState.currentStepIndex,
                        totalSteps: walkthroughState.steps.length,
                        onNext: () =>
                            ref.read(walkthroughProvider.notifier).next(),
                        onSkip: () =>
                            ref.read(walkthroughProvider.notifier).skip(),
                      ),

                    // Sync restore overlay is mounted globally in
                    // CosmoStrikeApp.builder so it appears regardless
                    // of which screen is active during the pull.
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTopNavigation(
    BuildContext context,
    AuthState authState,
    GameTheme theme,
    bool isSmallScreen,
  ) {
    final gap = SizedBox(width: isSmallScreen ? 6 : 8);
    final screenHeight = MediaQuery.of(context).size.height;
    return Row(
      children: [
        // LEFT: brand (logo + COSMO STRIKE). Expanded so it owns the left
        // third; FittedBox inside scales the name instead of truncating.
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildGameTitle(theme, screenHeight),
          ),
        ),

        // CENTER: live telemetry — BEST high score + coins. The equal-flex
        // Expanded zones on either side keep this group dead-centred.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => context.push(AppRoutes.statistics),
              child: HudChip(
                theme: theme,
                accent: Colors.amber,
                icon: Icons.emoji_events,
                label:
                    'BEST ${context.watch<GameSettingsCubit>().state.highScore}',
                dense: true,
              ),
            ),
            gap,
            BlocBuilder<CoinsCubit, CoinsState>(
              builder: (context, coinsState) {
                return GestureDetector(
                  onTap: () => context.push(AppRoutes.store),
                  child: Container(
                    key: HomeWalkthrough.coinsKey,
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 10 : 12,
                      vertical: isSmallScreen ? 6 : 7,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.amber.withValues(alpha: 0.15),
                          Colors.orange.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius:
                          BorderRadius.circular(isSmallScreen ? 14 : 16),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.monetization_on,
                          color: Colors.amber,
                          size: isSmallScreen ? 16 : 18,
                        ),
                        SizedBox(width: isSmallScreen ? 4 : 6),
                        Text(
                          _formatCoins(coinsState.total),
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: isSmallScreen ? 13 : 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),

        // RIGHT: tool icons — settings, profile, about, help.
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildTopIconButton(
                key: HomeWalkthrough.settingsKey,
                icon: Icons.settings_rounded,
                color: theme.accentColor,
                isSmallScreen: isSmallScreen,
                onTap: () => context.push(AppRoutes.settings),
              ),
              gap,
              PlayerIdentityBadge(
                key: HomeWalkthrough.profileKey,
                theme: theme,
                isSmallScreen: true,
                photoUrl: authState.isSignedIn ? authState.photoURL : null,
                onTap: () => context.push(AppRoutes.profile),
              ),
              gap,
              _buildTopIconButton(
                icon: Icons.info_outline,
                color: theme.accentColor,
                isSmallScreen: isSmallScreen,
                onTap: () => showCreditsDialog(context, theme),
              ),
              gap,
              _buildTopIconButton(
                icon: Icons.help_outline,
                color: theme.foodColor,
                isSmallScreen: isSmallScreen,
                onTap: () => context.push(AppRoutes.instructions),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A square neon icon tool for the top command bar (about / settings /
  /// how-to). Centralises the bordered-glass icon button styling.
  Widget _buildTopIconButton({
    Key? key,
    required IconData icon,
    required Color color,
    required bool isSmallScreen,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: key,
        padding: EdgeInsets.all(isSmallScreen ? 7 : 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(isSmallScreen ? 13 : 15),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        ),
        child: Icon(icon, color: color, size: isSmallScreen ? 18 : 20),
      ),
    );
  }

  Widget _buildGameTitle(GameTheme theme, double screenHeight) {
    // Compact HORIZONTAL brand lockup for the wide-short landscape header:
    // a small glowing logo beside the gradient wordmark (left-aligned), with
    // a tiny HUD subtitle. Replaces the old big centered logo-over-text stack
    // that crowded the top of the command deck and read as misaligned next to
    // the BEST chip.
    final logoSize = screenHeight < 650 ? 38.0 : 46.0;
    final titleSize = screenHeight < 650 ? 22.0 : 26.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: theme.accentColor.withValues(alpha: 0.3),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child:
              Image.asset(
                    'assets/images/cosmo_strike_transparent.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.games,
                        size: logoSize * 0.7,
                        color: theme.accentColor,
                      );
                    },
                  )
                  .animate(
                    onPlay: (controller) => controller.repeat(reverse: true),
                  )
                  .shimmer(
                    duration: 2500.ms,
                    color: theme.accentColor.withValues(alpha: 0.25),
                  )
                  .gameHero(),
        ),
        const SizedBox(width: 12),
        // "COSMO STRIKE" wordmark — gradient-shaded to match the hero look
        // used elsewhere (game-over screen, About dialog). Wrapped in a
        // FittedBox(scaleDown) so it shrinks to fit the available width
        // instead of EVER truncating the name.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [theme.primaryColor, theme.accentColor],
              ).createShader(bounds),
              child: Text(
                'COSMO STRIKE',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  color: Colors.white, // base for ShaderMask
                  letterSpacing: 2,
                  height: 1.0,
                  shadows: [
                    Shadow(
                      color: theme.accentColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Landscape hero "launch bay" — the RIGHT half of the command deck.
  ///
  /// A big tappable glass panel that fills the right column: a self-animating
  /// neon [LaunchEmblem] (sized from the available space via LayoutBuilder so
  /// it never overflows), a gradient "LAUNCH" CTA, and the loadout chip
  /// (which self-hides when the user owns no power-ups). Tapping anywhere on
  /// the panel runs the one-time game-mode prompt then routes to playLoading.
  Widget _buildLaunchHero(BuildContext context, GameTheme theme) {
    return GestureDetector(
      onTap: () async {
        // Show the one-time game-mode picker before launching the first
        // game; no-op for users who've already picked.
        await _maybeShowGameModePrompt();
        if (!context.mounted) return;
        // Detour through the themed pre-game loader. It self-advances to
        // /game on completion via pushReplacement so back from the game
        // lands on Home rather than the loader.
        context.push(AppRoutes.playLoading);
      },
      child: GlassPanel(
        // Walkthrough targets the whole launch bay panel now.
        key: HomeWalkthrough.playButtonKey,
        theme: theme,
        glow: true,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (ctx, cons) {
                    final s =
                        (cons.biggest.shortestSide).clamp(90.0, 220.0);
                    return LaunchEmblem(theme: theme, size: s);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (b) => LinearGradient(
                colors: [theme.neonPrimary, theme.neonSecondary],
              ).createShader(b),
              child: const Text(
                'LAUNCH',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 6,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap to deploy',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 13,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            // Loadout chip self-hides when the user owns no power-ups.
            _buildPowerUpLoadoutChip(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildPowerUpLoadoutChip(GameTheme theme) {
    return BlocBuilder<PowerUpCubit, PowerUpState>(
      builder: (context, powerUpState) {
        // Hide entirely when the user has no inventory — keeps the home
        // screen uncluttered for free users / users who haven't bought
        // power-ups yet.
        if (powerUpState.totalOwned == 0) return const SizedBox.shrink();

        final armed = powerUpState.armed;
        final armedLabel = armed == null ? null : _loadoutLabelFor(armed);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => _openLoadoutSheet(theme, powerUpState),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: armed != null
                    ? theme.accentColor.withValues(alpha: 0.18)
                    : theme.accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: armed != null
                      ? theme.accentColor
                      : theme.accentColor.withValues(alpha: 0.25),
                  width: armed != null ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    armed != null ? Icons.flash_on : Icons.flash_on_outlined,
                    color: armed != null ? Colors.amber : theme.accentColor,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    armed != null
                        ? 'Armed: $armedLabel'
                        : 'Loadout (${powerUpState.totalOwned})',
                    style: TextStyle(
                      color: theme.accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: theme.accentColor.withValues(alpha: 0.7),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _loadoutLabelFor(String inventoryKey) {
    switch (inventoryKey) {
      case 'speed_boost':
        return 'Speed Boost';
      case 'invincibility':
        return 'Invincibility';
      case 'score_multiplier':
        return 'Score Multiplier';
      case 'slow_motion':
        return 'Slow Motion';
      default:
        return inventoryKey;
    }
  }

  IconData _loadoutIconFor(String inventoryKey) {
    switch (inventoryKey) {
      case 'speed_boost':
        return Icons.speed;
      case 'invincibility':
        return Icons.shield;
      case 'score_multiplier':
        return Icons.star;
      case 'slow_motion':
        return Icons.slow_motion_video;
      default:
        return Icons.flash_on;
    }
  }

  void _openLoadoutSheet(GameTheme theme, PowerUpState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _LoadoutBottomSheet(
          theme: theme,
          labelFor: _loadoutLabelFor,
          iconFor: _loadoutIconFor,
        );
      },
    );
  }

  Widget _buildActionButtonsRow({
    required BuildContext context,
    required GameTheme theme,
    required double screenWidth,
    required bool isSmallScreen,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildModernActionButton(
            context: context,
            theme: theme,
            icon: Icons.diamond,
            label: 'PRO',
            gradient: [Colors.purple.shade400, Colors.indigo.shade400],
            isSmallScreen: isSmallScreen,
            onTap: () => context.push(AppRoutes.premiumBenefits),
          ),
        ),
        SizedBox(width: isSmallScreen ? 12 : 16),
        Expanded(
          child: _buildModernActionButton(
            context: context,
            theme: theme,
            icon: Icons.store,
            label: 'STORE',
            gradient: [Colors.orange.shade400, Colors.amber.shade400],
            isSmallScreen: isSmallScreen,
            onTap: () => context.push(AppRoutes.store),
            widgetKey: HomeWalkthrough.storeKey,
          ),
        ),
        // Watch-for-coins — only for free users with ads enabled (Pro keeps
        // the clean 2-button row).
        if (getIt.isRegistered<AdService>() && getIt<AdService>().adsEnabled) ...[
          SizedBox(width: isSmallScreen ? 12 : 16),
          Expanded(
            child: _buildModernActionButton(
              context: context,
              theme: theme,
              icon: Icons.play_circle_fill,
              label: 'COINS',
              gradient: [Colors.amber.shade400, Colors.yellow.shade700],
              isSmallScreen: isSmallScreen,
              onTap: () => _watchForCoins(context),
            ),
          ),
        ],
      ],
    );
  }

  /// Rewarded "watch for coins" from the home action row. Honours the daily
  /// cap; credits offline-first via CoinsCubit.
  Future<void> _watchForCoins(BuildContext context) async {
    final ads = getIt<AdService>();
    if (!ads.canShowFreeCoinAd) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ads.freeCoinAdsRemainingToday == 0
              ? "You've hit today's free-coin limit — come back tomorrow!"
              : 'No ad available right now, try again shortly'),
        ),
      );
      return;
    }
    final coins = context.read<CoinsCubit>();
    await ads.showRewardedForCoins(
      onCoins: (amount) => coins.earnCoins(
        CoinEarningSource.watchedAd,
        customAmount: amount,
        itemName: 'Watched ad',
        metadata: const {'placement': 'home_free_coins'},
      ),
    );
  }

  Widget _buildModernActionButton({
    required BuildContext context,
    required GameTheme theme,
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required bool isSmallScreen,
    required VoidCallback onTap,
    Key? widgetKey,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Track the parent's max height so the button fills the wider
        // 72 px container we now give it from _buildMainPlayArea (was
        // 48 before). Clamped to keep small-screen sanity; on a 750+ px
        // device this lands at ~64 px tall.
        final buttonHeight = constraints.maxHeight > 0
            ? (constraints.maxHeight * 0.92).clamp(48.0, 66.0)
            : 56.0;
        // Drive icon + text sizing off the height so the visual weight
        // scales with the button instead of staying frozen at the old
        // 48-px values. The clamps keep the geometry within sensible
        // bounds on extreme screen sizes.
        final iconBgPadding = (buttonHeight * 0.14).clamp(6.0, 9.0);
        final iconSize = (buttonHeight * 0.32).clamp(16.0, 22.0);
        final labelSize = (buttonHeight * 0.24).clamp(12.0, 16.0);
        final iconTextGap = (buttonHeight * 0.18).clamp(8.0, 12.0);

        return GestureDetector(
          onTap: onTap,
          child: Container(
            key: widgetKey,
            height: buttonHeight,
            constraints: BoxConstraints(
              // Clamp so minWidth can never exceed the (narrow, in landscape)
              // available width — otherwise BoxConstraints is non-normalized
              // and asserts.
              minWidth: constraints.maxWidth.clamp(0.0, 100.0),
              maxWidth: constraints.maxWidth,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  gradient[0].withValues(alpha: 0.2),
                  gradient[1].withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: gradient[0].withValues(alpha: 0.4),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: gradient[0].withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(iconBgPadding),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: gradient[0].withValues(alpha: 0.3),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: iconSize),
                ),
                SizedBox(width: iconTextGap),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: labelSize,
                        fontWeight: FontWeight.w800,
                        color: gradient[0],
                        letterSpacing: 0.9,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomNavigation(
    BuildContext context,
    ThemeState themeState,
    GameTheme theme,
    double screenHeight,
    double screenWidth,
  ) {
    // 8 items laid out as a 4×2 grid of glass tiles that FILL the right
    // command-deck column. Each row is an Expanded so the four rows share
    // the column height evenly; each tile is an Expanded so the two tiles
    // share the row width evenly. STATS is duplicated in the compact stats
    // row above the nav (left of high score) AND in the grid here — the
    // upper instance keeps stats one tap away from the home eyeline.
    final navigationItems = [
      _NavItem(
        Icons.calendar_today,
        'DAILY',
        Colors.cyan,
        () {
          context.push(AppRoutes.dailyChallenges);
        },
        badge: _getDailyChallengesBadge(),
        widgetKey: HomeWalkthrough.dailyChallengesKey,
      ),
      _NavItem(Icons.timeline, 'BATTLE', Colors.deepPurple, () {
        context.push(AppRoutes.battlePass);
      }),
      _NavItem(Icons.emoji_events, 'EVENTS', Colors.deepOrange, () {
        context.push(AppRoutes.tournaments);
      }),
      _NavItem(Icons.leaderboard, 'BOARD', Colors.lightBlue, () {
        context.push(AppRoutes.leaderboard);
      }),
      _NavItem(Icons.people, 'FRIENDS', Colors.pinkAccent, () {
        context.push(AppRoutes.friends);
      }),
      _NavItem(
        Icons.palette,
        'SKINS',
        Colors.indigo,
        () {
          context.push(AppRoutes.cosmetics);
        },
        widgetKey: HomeWalkthrough.cosmeticsKey,
      ),
      _NavItem(Icons.military_tech, 'AWARDS', Colors.orange, () {
        context.push(AppRoutes.achievements);
      }),
      _NavItem(Icons.analytics, 'STATS', Colors.teal, () {
        context.push(AppRoutes.statistics);
      }),
    ];

    // Compact icon rail: 2 rows × 4 columns of neon icon chips. Each row is
    // an Expanded so the two rows split the column height; each cell is an
    // Expanded so the four chips split the row width evenly.
    const cols = 4;
    final rows = <Widget>[];
    for (var r = 0; r * cols < navigationItems.length; r++) {
      final cells = <Widget>[];
      for (var c = 0; c < cols; c++) {
        final i = r * cols + c;
        cells.add(
          Expanded(
            child: i < navigationItems.length
                ? _buildNavChip(navigationItems[i], theme, i)
                : const SizedBox.shrink(),
          ),
        );
        if (c < cols - 1) cells.add(const SizedBox(width: 10));
      }
      rows.add(
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: cells),
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildNavChip(_NavItem item, GameTheme theme, int index) {
    // Unified Command-HUD palette: alternate the two neon accents per cell so
    // the rail reads as an intentional cyan/magenta console (no rainbow).
    final accent = index.isEven ? theme.neonPrimary : theme.neonSecondary;
    return Column(
      children: [
        Expanded(
          child: HoloCard(
            key: item.widgetKey,
            theme: theme,
            onTap: item.onTap,
            padding: EdgeInsets.zero,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Neon icon disc — a glowing HUD button.
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.12),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.55),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.30),
                          blurRadius: 12,
                          spreadRadius: -2,
                        ),
                      ],
                    ),
                    child: Icon(item.icon, color: accent, size: 26),
                  ),
                  if (item.badge != null && item.badge! > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Center(
                          child: Text(
                            '${item.badge}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    ).gameGridItem(index);
  }


  // void _showComingSoonDialog(
  //   BuildContext context,
  //   GameTheme theme,
  //   String featureName,
  // ) {
  //   showDialog(
  //     context: context,
  //     builder: (BuildContext context) {
  //       return AlertDialog(
  //         backgroundColor: theme.backgroundColor,
  //         shape: RoundedRectangleBorder(
  //           borderRadius: BorderRadius.circular(24),
  //           side: BorderSide(
  //             color: Colors.green.withValues(alpha: 0.3),
  //             width: 2,
  //           ),
  //         ),
  //         title: Row(
  //           children: [
  //             Icon(Icons.construction, color: Colors.amber, size: 28),
  //             const SizedBox(width: 12),
  //             Expanded(
  //               child: Text(
  //                 'Coming Soon',
  //                 style: TextStyle(
  //                   color: theme.accentColor,
  //                   fontWeight: FontWeight.bold,
  //                   fontSize: 20,
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //         content: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           children: [
  //             Container(
  //               padding: const EdgeInsets.all(20),
  //               decoration: BoxDecoration(
  //                 gradient: LinearGradient(
  //                   colors: [
  //                     Colors.green.withValues(alpha: 0.1),
  //                     Colors.teal.withValues(alpha: 0.05),
  //                   ],
  //                 ),
  //                 borderRadius: BorderRadius.circular(16),
  //                 border: Border.all(
  //                   color: Colors.green.withValues(alpha: 0.3),
  //                 ),
  //               ),
  //               child: Column(
  //                 children: [
  //                   Icon(Icons.group_work, size: 48, color: Colors.green),
  //                   const SizedBox(height: 16),
  //                   Text(
  //                     featureName,
  //                     style: TextStyle(
  //                       color: theme.accentColor,
  //                       fontWeight: FontWeight.bold,
  //                       fontSize: 18,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 8),
  //                   Text(
  //                     'We\'re working hard to bring you an amazing multiplayer experience!',
  //                     textAlign: TextAlign.center,
  //                     style: TextStyle(
  //                       color: theme.accentColor.withValues(alpha: 0.7),
  //                       fontSize: 14,
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //             const SizedBox(height: 16),
  //             Row(
  //               children: [
  //                 Icon(Icons.star, color: Colors.amber, size: 16),
  //                 const SizedBox(width: 8),
  //                 Expanded(
  //                   child: Text(
  //                     'Stay tuned for updates!',
  //                     style: TextStyle(
  //                       color: theme.accentColor.withValues(alpha: 0.8),
  //                       fontSize: 12,
  //                       fontStyle: FontStyle.italic,
  //                     ),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ],
  //         ),
  //         actions: [
  //           TextButton(
  //             onPressed: () => Navigator.of(context).pop(),
  //             style: TextButton.styleFrom(
  //               backgroundColor: Colors.green.withValues(alpha: 0.1),
  //               padding: const EdgeInsets.symmetric(
  //                 horizontal: 24,
  //                 vertical: 12,
  //               ),
  //               shape: RoundedRectangleBorder(
  //                 borderRadius: BorderRadius.circular(16),
  //                 side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
  //               ),
  //             ),
  //             child: Text(
  //               'Got it!',
  //               style: TextStyle(
  //                 color: Colors.green,
  //                 fontWeight: FontWeight.w600,
  //               ),
  //             ),
  //           ),
  //         ],
  //       );
  //     },
  //   );
  // }

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
  /// badge updates the moment a reward is claimed elsewhere — previously
  /// the value was read once from the singleton DailyChallengeService
  /// (a ChangeNotifier the home screen didn't subscribe to), leaving
  /// the badge stale until a manual rebuild.
  int? _getDailyChallengesBadge() {
    final count = ref.watch(unclaimedRewardsCountProvider);
    return count > 0 ? count : null;
  }
}

// Navigation item helper class
class _NavItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int? badge;
  final GlobalKey? widgetKey;

  _NavItem(
    this.icon,
    this.label,
    this.color,
    this.onTap, {
    this.badge,
    this.widgetKey,
  });
}

/// First-launch bottom sheet that asks the user to pick a default game mode.
/// Returns the selected GameMode, or null if dismissed without confirming.
class _GameModeFirstLaunchSheet extends StatefulWidget {
  const _GameModeFirstLaunchSheet({
    required this.initialMode,
  });

  final GameMode initialMode;

  @override
  State<_GameModeFirstLaunchSheet> createState() =>
      _GameModeFirstLaunchSheetState();
}

class _GameModeFirstLaunchSheetState extends State<_GameModeFirstLaunchSheet> {
  late GameMode _selected = widget.initialMode;

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state.currentTheme;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.backgroundColor.withValues(alpha: 0.98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: theme.accentColor.withValues(alpha: 0.4),
            width: 2,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Pick a Game Mode',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.accentColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'You can change this anytime in Settings',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            ...GameMode.values.map((mode) {
              final isSelected = _selected == mode;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selected = mode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.accentColor.withValues(alpha: 0.18)
                          : Colors.white.withValues(alpha: 0.04),
                      border: Border.all(
                        color: isSelected
                            ? theme.accentColor
                            : Colors.white.withValues(alpha: 0.1),
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Text(mode.icon, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mode.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                mode.description,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle,
                              color: theme.accentColor, size: 22),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: theme.backgroundColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(_selected),
                child: const Text(
                  'START PLAYING',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, letterSpacing: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pre-game power-up loadout sheet. Lists every type the user owns,
/// highlights the currently armed one, and lets them switch / unarm.
/// Closing the sheet without picking leaves the previous selection
/// intact — the sheet is a passive viewer/editor, not a wizard.
class _LoadoutBottomSheet extends StatelessWidget {
  final GameTheme theme;
  final String Function(String key) labelFor;
  final IconData Function(String key) iconFor;

  const _LoadoutBottomSheet({
    required this.theme,
    required this.labelFor,
    required this.iconFor,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PowerUpCubit, PowerUpState>(
      builder: (context, state) {
        final entries = state.inventory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: theme.backgroundColor.withValues(alpha: 0.98),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.flash_on, color: theme.accentColor, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Power-Up Loadout',
                      style: TextStyle(
                        color: theme.accentColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Pre-load one power-up — it activates 5 seconds into your next game.',
                  style: TextStyle(
                    color: theme.accentColor.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                // Rewarded — grab a free Speed Boost without spending coins.
                RewardedActionButton(
                  theme: theme,
                  icon: Icons.bolt,
                  label: 'Watch ad — free Speed Boost',
                  capKey: AdService.capFreePowerUp,
                  onWatch: () async {
                    final powerUps = context.read<PowerUpCubit>();
                    await getIt<AdService>().showRewardedCapped(
                      capKey: AdService.capFreePowerUp,
                      onReward: powerUps.grantFreePowerUp,
                    );
                  },
                ),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'You have no power-ups.\nVisit the store to buy some!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.accentColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  )
                else
                  ...entries.map((e) {
                    final key = e.key;
                    final count = e.value;
                    final isArmed = state.armed == key;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (isArmed) {
                            context.read<PowerUpCubit>().unarm();
                          } else {
                            context.read<PowerUpCubit>().arm(key);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isArmed
                                ? theme.accentColor.withValues(alpha: 0.20)
                                : Colors.white.withValues(alpha: 0.04),
                            border: Border.all(
                              color: isArmed
                                  ? theme.accentColor
                                  : Colors.white.withValues(alpha: 0.10),
                              width: isArmed ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.accentColor
                                      .withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  iconFor(key),
                                  color: theme.accentColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      labelFor(key),
                                      style: TextStyle(
                                        color: theme.accentColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Owned: $count',
                                      style: TextStyle(
                                        color: theme.accentColor
                                            .withValues(alpha: 0.65),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isArmed)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: theme.accentColor,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'ARMED',
                                    style: TextStyle(
                                      color: theme.backgroundColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else
                                Icon(
                                  Icons.add_circle_outline,
                                  color: theme.accentColor
                                      .withValues(alpha: 0.7),
                                  size: 22,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      foregroundColor: theme.backgroundColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'DONE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
