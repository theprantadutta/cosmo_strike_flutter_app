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
import 'package:cosmo_strike_flutter_app/widgets/sync_status_indicator.dart';
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
  late AnimationController _playButtonPulseController;
  late Animation<double> _playButtonPulseAnimation;
  bool _dailyBonusChecked = false;
  bool _walkthroughChecked = false;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1500), // Reduced duration
      vsync: this,
    );

    // Play button pulse animation - calm breathing
    _playButtonPulseController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );
    _playButtonPulseAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(
        parent: _playButtonPulseController,
        curve: Curves.easeInOut,
      ),
    );
    _playButtonPulseController.repeat(reverse: true);

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
    _playButtonPulseController.dispose();
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

                                    // Game title with logo - flexible sizing
                                    _buildGameTitle(theme, screenHeight),

                                    // Main content area - scrollable if needed
                                    Expanded(
                                      child: screenHeight < 600
                                          ? SingleChildScrollView(
                                              child: Column(
                                                children: [
                                                  SizedBox(
                                                    height: (screenHeight * 0.6)
                                                        .clamp(300, 500),
                                                    child: _buildMainPlayArea(
                                                      context,
                                                      gameState,
                                                      authState,
                                                      theme,
                                                      screenHeight,
                                                      screenWidth,
                                                      screenHeight,
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          horizontal:
                                                              screenWidth *
                                                              0.04,
                                                        ),
                                                    child:
                                                        _buildBottomNavigation(
                                                          context,
                                                          themeState,
                                                          theme,
                                                          screenHeight,
                                                          screenWidth,
                                                        ),
                                                  ),
                                                  SizedBox(
                                                    height: isVerySmallScreen
                                                        ? 8
                                                        : 12,
                                                  ),
                                                ],
                                              ),
                                            )
                                          : Column(
                                              children: [
                                                // Main play area - takes available space
                                                Expanded(
                                                  child: _buildMainPlayArea(
                                                    context,
                                                    gameState,
                                                    authState,
                                                    theme,
                                                    screenHeight,
                                                    screenWidth,
                                                    screenHeight,
                                                  ),
                                                ),

                                                // Bottom navigation grid - fixed at bottom
                                                Padding(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal:
                                                        screenWidth * 0.04,
                                                    vertical: isVerySmallScreen
                                                        ? 8
                                                        : 12,
                                                  ),
                                                  child: _buildBottomNavigation(
                                                    context,
                                                    themeState,
                                                    theme,
                                                    screenHeight,
                                                    screenWidth,
                                                  ),
                                                ),
                                              ],
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
    return Row(
      children: [
        // Left: player identity (profile) + About — two tools, mirroring the
        // settings + how-to-play pair on the right.
        PlayerIdentityBadge(
          key: HomeWalkthrough.profileKey,
          theme: theme,
          isSmallScreen: isSmallScreen,
          photoUrl: authState.isSignedIn ? authState.photoURL : null,
          onTap: () => context.push(AppRoutes.profile),
        ),

        SizedBox(width: isSmallScreen ? 8 : 12),

        // About & credits (app version, credits, links).
        GestureDetector(
          onTap: () => showCreditsDialog(context, theme),
          child: Container(
            padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Icon(
              Icons.info_outline,
              color: theme.accentColor,
              size: isSmallScreen ? 20 : 24,
            ),
          ),
        ),

        // Center: coins pill → store.
        Expanded(
          child: Center(
            child: BlocBuilder<CoinsCubit, CoinsState>(
              builder: (context, coinsState) {
                return GestureDetector(
                  onTap: () {
                    context.push(AppRoutes.store);
                  },
                  child: Container(
                    key: HomeWalkthrough.coinsKey,
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 10 : 14,
                      vertical: isSmallScreen ? 6 : 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.amber.withValues(alpha: 0.15),
                          Colors.orange.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(
                        isSmallScreen ? 16 : 20,
                      ),
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
                          size: isSmallScreen ? 18 : 22,
                        ),
                        SizedBox(width: isSmallScreen ? 4 : 6),
                        Text(
                          _formatCoins(coinsState.total),
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // Right: tools — settings + how-to-play.
        Row(
          children: [
            // Settings
            GestureDetector(
              onTap: () {
                context.push(AppRoutes.settings);
              },
              child: Container(
                key: HomeWalkthrough.settingsKey,
                padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
                  border: Border.all(
                    color: theme.accentColor.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.settings_rounded,
                  color: theme.accentColor,
                  size: isSmallScreen ? 20 : 24,
                ),
              ),
            ),

            SizedBox(width: isSmallScreen ? 8 : 12),

            // How to play
            GestureDetector(
              onTap: () {
                context.push(AppRoutes.instructions);
              },
              child: Container(
                padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                decoration: BoxDecoration(
                  color: theme.foodColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
                  border: Border.all(
                    color: theme.foodColor.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.help_outline,
                  color: theme.foodColor,
                  size: isSmallScreen ? 20 : 24,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGameTitle(GameTheme theme, double screenHeight) {
    // Tighter logo sizes (~30% smaller than before) so the new title
    // text below has room to breathe without pushing the play button
    // off the bottom on small screens.
    final logoSize = screenHeight < 650
        ? 70.0
        : screenHeight < 750
        ? 85.0
        : 100.0;

    // Title font scales with the logo so they read as a unit.
    final titleSize = screenHeight < 650
        ? 28.0
        : screenHeight < 750
        ? 32.0
        : 36.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: screenHeight < 650 ? 4 : 8,
        horizontal: 16,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: theme.accentColor.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
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
                            size: logoSize * 0.5,
                            color: theme.accentColor,
                          );
                        },
                      )
                      .animate(
                        onPlay: (controller) =>
                            controller.repeat(reverse: true),
                      )
                      .shimmer(
                        duration: 2500.ms,
                        color: theme.accentColor.withValues(alpha: 0.25),
                      )
                      .gameHero(),
            ),
            // Tight gap so the logo + "Cosmo Strike" text read as a
            // single unit. The wider gap between this title block and
            // the play button below comes from _buildGameTitle's outer
            // vertical padding + _buildMainPlayArea's top padding,
            // creating the desired hierarchy: tight logo+text, looser
            // text→play-button.
            SizedBox(height: screenHeight < 650 ? 0 : 2),
            // "Cosmo Strike" title — gradient-shaded text styled to
            // match the game's hero look. ShaderMask gives it the same
            // primary→accent gradient used elsewhere in the app
            // (game-over screen, About dialog).
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [theme.primaryColor, theme.accentColor],
              ).createShader(bounds),
              child: Text(
                'Cosmo Strike',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  color: Colors.white, // base for ShaderMask
                  letterSpacing: 1.5,
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
          ],
        ),
      ),
    );
  }

  Widget _buildMainPlayArea(
    BuildContext context,
    GameCubitState gameCubitState,
    AuthState authState,
    GameTheme theme,
    double screenHeight,
    double screenWidth,
    double actualScreenHeight,
  ) {
    final isSmallScreen = screenHeight < 750;
    // High score reads from GameSettingsCubit only — same pattern as
    // CoinsCubit. The cubit's state is backed by the local Drift settings
    // table (monotonic via the never-decrease guard) and refreshed from
    // the server on each online launch via GameSettingsCubit.syncWithBackend.
    // Once an online session lands the server value into the DB, every
    // subsequent offline session shows the right number. No dual-source
    // max needed.
    final highScore = context.watch<GameSettingsCubit>().state.highScore;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final availableWidth = constraints.maxWidth;
        final spacing = (availableHeight * 0.02).clamp(8.0, 16.0);

        // Ensure minimum height constraints
        if (availableHeight < 200) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return Padding(
          padding: EdgeInsets.symmetric(
            vertical: (availableHeight * 0.02).clamp(8.0, 20.0),
            horizontal: 16,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Power-up loadout chip — only renders when the user has
              // any inventory. Sits directly above the play button so
              // it's the last thing they see before tapping PLAY.
              _buildPowerUpLoadoutChip(theme),

              // Hero Play Button - Main focal point, now at the top so
              // the user's eye lands on the call-to-action first.
              Flexible(
                flex: 5,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: availableHeight > 0
                        ? availableHeight * 0.4
                        : 200,
                    maxWidth: availableWidth * 0.8,
                  ),
                  child: _buildHeroPlayButton(
                    context,
                    theme,
                    screenHeight,
                    screenWidth,
                  ),
                ),
              ),

              SizedBox(height: spacing),

              // Compact stats row (high score + quick actions) — moved
              // under the play button so it reads as 'your best so far'
              // commentary on the primary CTA above.
              Flexible(
                flex: 3,
                child: Container(
                  // maxHeight is clamped to be at least 80 (the minHeight
                  // floor) so a transient small availableHeight on Android
                  // resume — when SafeArea/system-bars haven't resettled —
                  // can't produce minHeight > maxHeight and trip the
                  // BoxConstraints assertion. The 0.25 ratio is preserved
                  // for the common case; the clamp only kicks in below
                  // ~320 px of available height.
                  constraints: BoxConstraints(
                    minHeight: 80,
                    maxHeight: (availableHeight > 0
                            ? availableHeight * 0.25
                            : 120.0)
                        .clamp(80.0, double.infinity),
                  ),
                  child: _buildCompactStatsRow(
                    context: context,
                    highScore: highScore,
                    theme: theme,
                    screenWidth: screenWidth,
                    isSmallScreen: isSmallScreen,
                    hasSync: authState.isSignedIn,
                  ),
                ),
              ),

              // Tighter gap directly above the action buttons so the
              // taller button row below doesn't grow the column —
              // ~half of the standard inter-section spacing, clamped so
              // a very tall screen doesn't open the gap back up.
              SizedBox(
                height: (spacing * 0.4).clamp(2.0, 6.0),
              ),

              // Action buttons row - Store and Pro. Taller container
              // (~20 px more) for a more tappable target; the column's
              // spaceEvenly distribution absorbs the extra height by
              // shrinking the implicit gap below, keeping the total
              // play-area height constant. Both maxHeight and minHeight
              // grow together so the constraint stays responsive on the
              // smallest screens.
              Container(
                constraints: const BoxConstraints(maxHeight: 72, minHeight: 56),
                child: _buildActionButtonsRow(
                  context: context,
                  theme: theme,
                  screenWidth: screenWidth,
                  isSmallScreen: isSmallScreen,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeroPlayButton(
    BuildContext context,
    GameTheme theme,
    double screenHeight,
    double screenWidth,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use constraints to determine button size - make it much bigger
        final maxSize = constraints.maxHeight > 0
            ? constraints.maxHeight * 0.95
            : 200.0;
        final buttonSize = screenHeight < 650
            ? (maxSize > 160 ? 160.0 : maxSize)
            : screenHeight < 750
            ? (maxSize > 200 ? 200.0 : maxSize)
            : (maxSize > 240 ? 240.0 : maxSize);

        final isSmallButton = buttonSize < 120;

        return GestureDetector(
          onTap: () async {
            // Show the one-time game-mode picker before launching the
            // first game; no-op for users who've already picked.
            await _maybeShowGameModePrompt();
            if (!context.mounted) return;
            // Detour through the themed pre-game loader. It self-advances
            // to /game on completion via pushReplacement so back from the
            // game lands on Home rather than the loader.
            context.push(AppRoutes.playLoading);
          },
          child: AnimatedBuilder(
            animation: _playButtonPulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _playButtonPulseAnimation.value,
                child: child,
              );
            },
            child: Container(
              key: HomeWalkthrough.playButtonKey,
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    theme.accentColor,
                    theme.foodColor,
                    theme.accentColor.withValues(alpha: 0.8),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.accentColor.withValues(alpha: 0.4),
                    blurRadius: isSmallButton ? 20 : 30,
                    spreadRadius: isSmallButton ? 3 : 5,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: theme.foodColor.withValues(alpha: 0.3),
                    blurRadius: isSmallButton ? 30 : 50,
                    spreadRadius: 0,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Animated pulse ring
                  Container(
                    width: buttonSize - (isSmallButton ? 8 : 10),
                    height: buttonSize - (isSmallButton ? 8 : 10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: isSmallButton ? 2 : 3,
                      ),
                    ),
                  ),
                  // Inner content. mainAxisSize: min + Stack's
                  // Alignment.center keeps the icon+text block precisely
                  // in the middle of the circle. Transform.translate on
                  // the text counteracts the icon glyph's intrinsic
                  // bottom padding (Material icons leave ~15% empty
                  // space below the visible symbol). Text height: 1.0
                  // strips the default 1.2 line-height multiplier so
                  // the text's own glyph box doesn't add extra padding
                  // on top.
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: isSmallButton
                            ? 60
                            : buttonSize < 180
                            ? 80
                            : buttonSize < 220
                            ? 100
                            : 120,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            offset: const Offset(0, 3),
                            blurRadius: 12,
                            color: Colors.black.withValues(alpha: 0.4),
                          ),
                        ],
                      ),
                      Transform.translate(
                        // Pull text up just enough to neutralize most of
                        // the icon's intrinsic bottom padding, leaving a
                        // small (~4-5px) visible gap instead of either
                        // a big space OR an overlap.
                        offset: Offset(
                          0,
                          isSmallButton
                              ? -4.0
                              : buttonSize < 180
                              ? -6.0
                              : buttonSize < 220
                              ? -8.0
                              : -10.0,
                        ),
                        child: Text(
                          'PLAY',
                          style: TextStyle(
                            fontSize: isSmallButton
                                ? 14
                                : buttonSize < 180
                                ? 18
                                : buttonSize < 220
                                ? 22
                                : 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 2,
                            height: 1.0,
                            shadows: [
                              Shadow(
                                offset: const Offset(0, 2),
                                blurRadius: 6,
                                color: Colors.black.withValues(alpha: 0.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

  Widget _buildCompactStatsRow({
    required BuildContext context,
    required int highScore,
    required GameTheme theme,
    required double screenWidth,
    required bool isSmallScreen,
    required bool hasSync,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 12 : 16,
        vertical: isSmallScreen ? 10 : 14,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            theme.accentColor.withValues(alpha: 0.08),
            Colors.amber.withValues(alpha: 0.12),
            theme.accentColor.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(isSmallScreen ? 20 : 24),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Stats button (left)
          _buildCircularNavButton(
            icon: Icons.analytics,
            color: theme.accentColor,
            isSmallScreen: isSmallScreen,
            onTap: () => context.push(AppRoutes.statistics),
          ),

          // Center: High Score display. Wrapped in FittedBox so a
          // marginal vertical squeeze (Row + spacer + score Text can
          // exceed the parent's 61.2px slot by sub-pixel amounts on
          // some screens) scales the whole stack down instead of
          // tripping a RenderFlex overflow.
          Expanded(
            child: GestureDetector(
              onTap: () => context.push(AppRoutes.statistics),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.emoji_events,
                          color: Colors.amber,
                          size: isSmallScreen ? 18 : 22,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'HIGH SCORE',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 10 : 12,
                            fontWeight: FontWeight.w600,
                            color: theme.accentColor.withValues(alpha: 0.7),
                            letterSpacing: 1.5,
                          ),
                        ),
                        if (hasSync) ...[
                          const SizedBox(width: 6),
                          SyncStatusIndicator(size: isSmallScreen ? 14 : 16),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$highScore',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 28 : 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.amber,
                        height: 1.0,
                        shadows: [
                          Shadow(
                            color: Colors.amber.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Replays button (right). Replaces the leaderboard entry
          // point — online leaderboards are disabled in the offline-first
          // build; the local replay history is the closest analog.
          _buildCircularNavButton(
            icon: Icons.video_library,
            color: Colors.amber,
            isSmallScreen: isSmallScreen,
            onTap: () => context.push(AppRoutes.replays),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularNavButton({
    required IconData icon,
    required Color color,
    required bool isSmallScreen,
    required VoidCallback onTap,
  }) {
    final size = isSmallScreen ? 44.0 : 52.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: isSmallScreen ? 20 : 24),
      ),
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
              minWidth: 100,
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
    // Dynamic sizing based on screen height
    final isVerySmallScreen = screenHeight < 650;
    final isSmallScreen = screenHeight < 750;
    // Note: isMediumScreen not needed in bottom navigation
    // 8 items split 4+4 across two rows. STATS is duplicated in the
    // compact stats row above the nav (left of high score) AND in the
    // grid here — the upper instance keeps stats one tap away from the
    // home eyeline, the grid instance makes the 4x4 layout balance.
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
        'COSMETICS',
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

    // Two-row layout, balanced. Ceiling-divide so 7 items become 4+3,
    // 6 stays 3+3, 8 becomes 4+4, etc. — keeps the larger row on top
    // visually anchoring the grid.
    final firstRowCount = (navigationItems.length + 1) ~/ 2;
    final firstRow = navigationItems.take(firstRowCount).toList();
    final secondRow = navigationItems.skip(firstRowCount).toList();

    Widget buildRow(List<_NavItem> items, int indexOffset) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: items.asMap().entries.map((entry) {
            final index = entry.key + indexOffset;
            final item = entry.value;
            return _buildNavButton(
                  icon: item.icon,
                  label: item.label,
                  color: item.color,
                  onTap: item.onTap,
                  theme: theme,
                  isSmallScreen: isVerySmallScreen || isSmallScreen,
                  screenHeight: screenHeight,
                  badge: item.badge,
                  widgetKey: item.widgetKey,
                )
                .gameGridItem(index);
          }).toList(),
        );

    return Column(
      children: [
        buildRow(firstRow, 0),
        SizedBox(
          height: isVerySmallScreen
              ? 8
              : isSmallScreen
              ? 12
              : 16,
        ),
        buildRow(secondRow, firstRowCount),
      ],
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required GameTheme theme,
    required bool isSmallScreen,
    required double screenHeight,
    int? badge,
    GlobalKey? widgetKey,
  }) {
    final buttonSize = _getResponsiveNavButtonSize(screenHeight);
    // Icon size tracks the button bump from _getResponsiveNavButtonSize
    // so the icon-to-button ratio stays balanced (~40-45% of the button
    // width). Going too big crowds the rounded-corner padding; this is
    // the sweet spot.
    final iconSize = screenHeight < 600
        ? 20.0
        : screenHeight < 700
        ? 22.0
        : 26.0;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                key: widgetKey,
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.15),
                      color.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 18),
                  border: Border.all(
                    color: color.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 8,
                      spreadRadius: 0,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, color: color, size: iconSize),
              ),
              if (badge != null && badge > 0)
                Positioned(
                  right: -4,
                  top: -4,
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
                        '$badge',
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

          SizedBox(height: isSmallScreen ? 4 : 6),

          Text(
            label,
            style: TextStyle(
              fontSize: isSmallScreen ? 8 : 9,
              fontWeight: FontWeight.w600,
              color: theme.accentColor.withValues(alpha: 0.8),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
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

  double _getResponsiveNavButtonSize(double screenHeight) {
    // Each tier bumped ~6dp from the previous values (38/44/50/56) to
    // make the buttons easier to hit. The small-screen size now lands
    // close to the Material Design 48dp minimum tap target, and the
    // large-screen size reads more solidly without crowding the row.
    if (screenHeight < 600) return 44.0;
    if (screenHeight < 700) return 50.0;
    if (screenHeight < 850) return 56.0;
    return 62.0;
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
