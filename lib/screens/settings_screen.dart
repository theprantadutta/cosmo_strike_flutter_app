import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_settings_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/widgets/account_upgrade_sheet.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/haptic_service.dart';
import 'package:cosmo_strike_flutter_app/services/notification_service.dart';
import 'package:cosmo_strike_flutter_app/services/preferences_service.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/services/username_service.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/services/review_service.dart';
import 'package:cosmo_strike_flutter_app/services/share_service.dart';
import 'package:cosmo_strike_flutter_app/services/walkthrough_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/widgets/credits_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AudioService _audioService = AudioService();
  final StorageService _storageService = StorageService();
  late final AppDataCache _appCache;
  late final AnalyticsFacade _analytics;

  /// Which section of the left rail is selected (drives the right pane).
  int _selectedSection = 0;

  /// Shared by the rail's ListView and its always-visible Scrollbar.
  final ScrollController _railScrollController = ScrollController();
  bool _soundEnabled = true;
  bool _musicEnabled = true;
  bool _dPadEnabled = false;
  bool _screenShakeEnabled = false;
  // Hydrated in main.dart from the Drift settings row — the in-memory
  // singleton value is authoritative by the time this screen builds.
  bool _hapticsEnabled = HapticService().isEnabled;
  // Accessibility: reduce-motion mirror. PreferencesService is a boot-time
  // singleton, so its value is authoritative by the time this screen builds.
  bool _reduceMotion = PreferencesService().reduceMotion;
  DPadPosition _dPadPosition = DPadPosition.bottomCenter;
  GameMode _selectedGameMode = GameMode.classic;

  // Notification preferences. Mirrored from NotificationService at init
  // and on every toggle; service is the source of truth (persists to
  // SharedPreferences + triggers backend topic (un)subscribe).
  final NotificationService _notificationService = NotificationService();
  bool _notifDailyReminder = true;
  bool _notifTournament = true;
  bool _notifAchievement = true;
  bool _notifSocial = true;
  bool _notifSpecialEvent = true;

  @override
  void initState() {
    super.initState();
    _appCache = getIt<AppDataCache>();
    _analytics = getIt<AnalyticsFacade>();
    _loadSettingsFromCache();
    _loadNotificationPreferences();
    // Pull fresh user data so the USER PROFILE row shows the live
    // username (handles the case where the local UnifiedUser was
    // cached pre-backfill / pre-rename and is missing the value).
    // Fire-and-forget — the screen renders from current state and
    // updates if anything changed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthCubit>().refreshUserFromBackend();
      // The AppDataCache settings map is populated at boot and never
      // re-synced — but GameSettingsCubit gets live writes from places
      // like the game-screen first-launch modal that flips D-Pad on.
      // After our initial cache-based paint, overlay the cubit's
      // authoritative state so the toggles reflect reality.
      _syncFromSettingsCubit(context.read<GameSettingsCubit>().state);
    });
  }

  @override
  void dispose() {
    _railScrollController.dispose();
    super.dispose();
  }

  /// Mirror the GameSettingsCubit state into our local UI fields. Used both
  /// for the post-frame initial sync and from the BlocListener below so the
  /// settings screen stays in lock-step with the cubit (source of truth).
  void _syncFromSettingsCubit(GameSettingsState s) {
    if (!s.isReady) return;
    final changed =
        _dPadEnabled != s.dPadEnabled ||
        _dPadPosition != s.dPadPosition ||
        _screenShakeEnabled != s.screenShakeEnabled ||
        _selectedGameMode != s.gameMode;
    if (!changed) return;
    setState(() {
      _dPadEnabled = s.dPadEnabled;
      _dPadPosition = s.dPadPosition;
      _screenShakeEnabled = s.screenShakeEnabled;
      _selectedGameMode = s.gameMode;
    });
  }

  void _loadNotificationPreferences() {
    final prefs = _notificationService.notificationPreferences;
    setState(() {
      _notifDailyReminder = prefs[NotificationType.dailyReminder] ?? true;
      _notifTournament = prefs[NotificationType.tournament] ?? true;
      _notifAchievement = prefs[NotificationType.achievement] ?? true;
      _notifSocial = prefs[NotificationType.social] ?? true;
      _notifSpecialEvent = prefs[NotificationType.specialEvent] ?? true;
    });
  }

  Future<void> _toggleNotification(
    NotificationType type,
    bool value,
    void Function(bool) localSetter,
  ) async {
    setState(() => localSetter(value));
    await _notificationService.setNotificationEnabled(type, value);
    _analytics.trackSettingChanged(
      settingName: 'notification_${type.key}',
      value: '$value',
    );
  }

  void _loadSettingsFromCache() {
    // Use cached settings data for instant display
    final settingsData = _appCache.settingsData;
    if (settingsData != null) {
      setState(() {
        _soundEnabled = _audioService.isSoundEnabled;
        _musicEnabled = _audioService.isMusicEnabled;
        _dPadEnabled = settingsData['dPadEnabled'] ?? false;
        _screenShakeEnabled = settingsData['screenShakeEnabled'] ?? false;
        _dPadPosition =
            settingsData['dPadPosition'] ?? DPadPosition.bottomCenter;
      });
      // Game mode lives in SharedPreferences, not the cached settings map.
      _storageService.getGameMode().then((mode) {
        if (mounted) setState(() => _selectedGameMode = mode);
      });
    } else {
      // Fallback to direct load if cache not available
      _loadSettingsDirectly();
    }
  }

  Future<void> _loadSettingsDirectly() async {
    await _audioService.initialize();
    final dPadEnabled = await _storageService.isDPadEnabled();
    final screenShakeEnabled = await _storageService.isScreenShakeEnabled();
    final dPadPosition = await _storageService.getDPadPosition();
    final gameMode = await _storageService.getGameMode();
    setState(() {
      _soundEnabled = _audioService.isSoundEnabled;
      _musicEnabled = _audioService.isMusicEnabled;
      _dPadEnabled = dPadEnabled;
      _screenShakeEnabled = screenShakeEnabled;
      _dPadPosition = dPadPosition;
      _selectedGameMode = gameMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep our local UI mirrors in lock-step with GameSettingsCubit so
    // changes that originate elsewhere (e.g. the game-screen first-launch
    // modal flipping D-Pad on) reflect here even if the screen is already
    // mounted. The cubit is the source of truth; AppDataCache is a
    // boot-time snapshot that can go stale.
    return BlocListener<GameSettingsCubit, GameSettingsState>(
      listenWhen: (prev, curr) =>
          prev.isReady != curr.isReady ||
          prev.dPadEnabled != curr.dPadEnabled ||
          prev.dPadPosition != curr.dPadPosition ||
          prev.screenShakeEnabled != curr.screenShakeEnabled ||
          prev.gameMode != curr.gameMode,
      listener: (context, settingsState) =>
          _syncFromSettingsCubit(settingsState),
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return BlocBuilder<AuthCubit, AuthState>(
            builder: (context, authState) {
              return BlocBuilder<PremiumCubit, PremiumState>(
                builder: (context, premiumState) {
                  final theme = themeState.currentTheme;

                  return CommandScaffold(
                    theme: theme,
                    title: 'Settings',
                    bottomBar: const ShipBannerAd(),
                    bodyPadding: EdgeInsets.zero,
                    body: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // LEFT — vertical section rail. Deliberate
                          // exception to the no-scroll rule: 8 sections at
                          // a readable size don't fit the short viewport,
                          // so the rail scrolls, with edge fades hinting
                          // that more items are above/below. The BACK
                          // button stays pinned outside the scroll.
                          Expanded(flex: 3, child: _buildNavRail(theme)),
                          const SizedBox(width: 20),
                          // RIGHT — the selected section's content.
                          Expanded(
                            flex: 7,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: SingleChildScrollView(
                                key: ValueKey(_selectedSection),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: _buildSectionPane(
                                    _selectedSection,
                                    themeState,
                                    authState,
                                    premiumState,
                                    theme,
                                  ),
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
            },
          );
        },
      ),
    );
  }

  /// Vertical, borderless section rail for the left region. Selection
  /// reads purely through the neon icon, brighter text, and a glowing
  /// indicator dot — no backgrounds, no borders.
  ///
  /// The item list SCROLLS (deliberate exception — 8 readable items don't
  /// fit the short landscape viewport); top/bottom edge fades signal the
  /// overflow, and the always-visible scrollbar thumb reinforces it.
  Widget _buildNavRail(GameTheme theme) {
    const items = [
      (Icons.gamepad, 'Controls'),
      (Icons.sports_esports, 'Gameplay'),
      (Icons.volume_up, 'Audio'),
      (Icons.palette, 'Visual'),
      (Icons.notifications, 'Notifications'),
      (Icons.person, 'Profile'),
      (Icons.help_outline, 'Help'),
      (Icons.workspace_premium, 'Premium'),
      (Icons.accessibility_new, 'Access'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ShaderMask(
            // Fade the list out at the top/bottom edges so it reads as
            // "more above / more below" — the scroll affordance.
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.07, 0.9, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: Scrollbar(
              controller: _railScrollController,
              thumbVisibility: true,
              thickness: 2.5,
              radius: const Radius.circular(2),
              child: ListView(
                controller: _railScrollController,
                padding: const EdgeInsets.fromLTRB(0, 10, 8, 14),
                children: [
                  for (var i = 0; i < items.length; i++)
                    _buildNavItem(theme, i, items[i].$1, items[i].$2),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        NeonButton(
          onPressed: () => context.pop(),
          label: 'BACK TO GAME',
          theme: theme,
          icon: Icons.arrow_back,
          expand: true,
          height: 44,
        ),
      ],
    );
  }

  Widget _buildNavItem(GameTheme theme, int i, IconData icon, String label) {
    final selected = _selectedSection == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedSection = i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(
              icon,
              size: 21,
              color: selected ? theme.neonPrimary : theme.textMuted,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected ? theme.textPrimary : theme.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (selected)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.neonPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.neonPrimary.withValues(alpha: 0.7),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Right-pane content for the selected rail section. Every control keeps
  /// its exact handler / cubit wiring — only the layout moved from one long
  /// scroll into per-section panes.
  List<Widget> _buildSectionPane(
    int section,
    ThemeState themeState,
    AuthState authState,
    PremiumState premiumState,
    GameTheme theme,
  ) {
    switch (section) {
      // 1. Controls (most frequently adjusted during gameplay)
      case 0:
        return [
          _buildSection('CONTROLS', [
            _buildAudioSwitch('D-Pad Controls', _dPadEnabled, (value) async {
              setState(() {
                _dPadEnabled = value;
              });
              await context.read<GameSettingsCubit>().updateDPadEnabled(value);
              _analytics.trackSettingChanged(
                settingName: 'dpad_enabled',
                value: '$value',
              );
            }, theme),
            const SizedBox(height: 8),
            Text(
              'Show an on-screen analog pad for steering during gameplay',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            // D-Pad Position Selector (only show when D-Pad is enabled)
            if (_dPadEnabled) ...[
              const SizedBox(height: 16),
              _buildDPadPositionSelector(theme),
            ],
            const SizedBox(height: 16),
            _buildAudioSwitch('Haptic Feedback', _hapticsEnabled, (
              value,
            ) async {
              setState(() {
                _hapticsEnabled = value;
              });
              HapticService().setEnabled(value);
              await _storageService.setHapticsEnabled(value);
              // Confirm-by-feel: a single thud instantly proves it works.
              if (value) await HapticService().mediumImpact();
              _analytics.trackSettingChanged(
                settingName: 'haptics_enabled',
                value: '$value',
              );
            }, theme),
            const SizedBox(height: 8),
            Text(
              'Vibrate on hits, pickups, and boss beats',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            _buildControlInfo(theme),
          ], theme),
        ];

      // 2. Gameplay (mode + effects). Board size and the crash-feedback
      // duration were legacy grid settings with no meaning in the
      // shooter — both removed (the data plumbing stays for sync compat).
      case 1:
        return [
          _buildSection('GAMEPLAY', [
            _buildGameModeSelector(theme),
            const SizedBox(height: 20),
            _buildAudioSwitch('Screen Shake', _screenShakeEnabled, (
              value,
            ) async {
              setState(() {
                _screenShakeEnabled = value;
              });
              await context.read<GameSettingsCubit>().setScreenShakeEnabled(
                value,
              );
              _analytics.trackSettingChanged(
                settingName: 'screen_shake',
                value: '$value',
              );
            }, theme),
            const SizedBox(height: 8),
            Text(
              'Jolt the view when you take hits, lose a ship, or down a boss',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ], theme),
        ];

      // 3. Audio
      case 2:
        return [
          _buildSection('AUDIO', [
            _buildAudioSwitch('Sound Effects', _soundEnabled, (value) async {
              setState(() {
                _soundEnabled = value;
              });
              await _audioService.setSoundEnabled(value);
              // Audible confirmation — instantly proves the SFX work.
              if (value) _audioService.playSound('pickup');
              _analytics.trackSettingChanged(
                settingName: 'sound_effects',
                value: '$value',
              );
            }, theme),
            const SizedBox(height: 16),
            _buildAudioSwitch('Background Music', _musicEnabled, (value) async {
              setState(() {
                _musicEnabled = value;
              });
              await _audioService.setMusicEnabled(value);
              _analytics.trackSettingChanged(
                settingName: 'background_music',
                value: '$value',
              );
            }, theme),
          ], theme),
        ];

      // 4. Visual (theme + trail effects)
      case 3:
        return [
          _buildSection('VISUAL', [
            _buildThemeSelector(themeState, theme),
            const SizedBox(height: 20),
            _buildAudioSwitch(
              'Engine Trail Effects',
              themeState.isTrailSystemEnabled,
              (value) async {
                await context.read<ThemeCubit>().setTrailSystemEnabled(value);
              },
              theme,
            ),
            const SizedBox(height: 4),
            Text(
              'Enable particle trails behind your ship',
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ], theme),
        ];

      // 5. Notifications (+ debug-only test panel)
      case 4:
        return [
          _buildSection('NOTIFICATIONS', [
            _buildAudioSwitch(
              'Daily Reminder',
              _notifDailyReminder,
              (v) => _toggleNotification(
                NotificationType.dailyReminder,
                v,
                (val) => _notifDailyReminder = val,
              ),
              theme,
            ),
            const SizedBox(height: 16),
            _buildAudioSwitch(
              'Tournament Alerts',
              _notifTournament,
              (v) => _toggleNotification(
                NotificationType.tournament,
                v,
                (val) => _notifTournament = val,
              ),
              theme,
            ),
            const SizedBox(height: 16),
            _buildAudioSwitch(
              'Achievement Unlocks',
              _notifAchievement,
              (v) => _toggleNotification(
                NotificationType.achievement,
                v,
                (val) => _notifAchievement = val,
              ),
              theme,
            ),
            const SizedBox(height: 16),
            _buildAudioSwitch(
              'Social Updates',
              _notifSocial,
              (v) => _toggleNotification(
                NotificationType.social,
                v,
                (val) => _notifSocial = val,
              ),
              theme,
            ),
            const SizedBox(height: 16),
            _buildAudioSwitch(
              'Special Events',
              _notifSpecialEvent,
              (v) => _toggleNotification(
                NotificationType.specialEvent,
                v,
                (val) => _notifSpecialEvent = val,
              ),
              theme,
            ),
          ], theme),

          // Diagnostic buttons that isolate each layer of the notification
          // pipeline. Gated behind kDebugMode so production builds never see
          // it — these are developer-facing controls for triage during
          // development + Play Store internal testing, not user features.
          // See NOTIFICATIONS_TESTING.md for triage guide.
          if (kDebugMode) ...[
            const SizedBox(height: 32),
            _buildSection('TEST NOTIFICATIONS', [
              _buildNotificationTestPanel(theme),
            ], theme),
          ],
        ];

      // 6. User profile
      case 5:
        return [
          _buildSection('USER PROFILE', [
            _buildUserProfileSettings(authState, theme),
          ], theme),
        ];

      // 7. Help & tutorial
      case 6:
        return [
          _buildSection('HELP & TUTORIAL', [
            _buildReplayTutorialButton(theme),
            const SizedBox(height: 16),
            _buildRateButton(theme),
            const SizedBox(height: 16),
            _buildShareButton(theme),
            const SizedBox(height: 16),
            _buildCreditsButton(theme),
            _buildPrivacyChoicesButton(theme),
          ], theme),
        ];

      // 8. Premium (if available)
      case 7:
        return [
          if (premiumState.isInitialized)
            _buildSection('PREMIUM FEATURES', [
              _buildPremiumStatusCard(premiumState, theme),
              if (!premiumState.hasPremium)
                _buildUpgradeButton(premiumState, theme),
              _buildRestorePurchasesButton(premiumState, theme),
              _buildPurchaseHistoryButton(premiumState, theme),
              if (premiumState.hasPremium || premiumState.ownedSkins.isNotEmpty)
                _buildCosmeticsButton(premiumState, theme),
              if (premiumState.hasBattlePass)
                _buildBattlePassButton(premiumState, theme),
            ], theme),
        ];

      // 9. Accessibility
      case 8:
        return [
          _buildSection('ACCESSIBILITY', [
            _buildColorBlindControl(themeState, theme),
            const SizedBox(height: 24),
            _buildReduceMotionControl(theme),
          ], theme),
        ];

      default:
        return const [];
    }
  }

  /// One-tap color-blind friendly skin. Toggling on applies the high-contrast
  /// blue↔orange [GameTheme.accessible] palette through the normal ThemeCubit
  /// path (persisted + synced); toggling off returns to Classic.
  Widget _buildColorBlindControl(ThemeState themeState, GameTheme theme) {
    final isOn = themeState.currentTheme == GameTheme.accessible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAudioSwitch('Color-Blind Friendly', isOn, (value) async {
          await context.read<ThemeCubit>().setTheme(
            value ? GameTheme.accessible : GameTheme.classic,
          );
          _analytics.trackSettingChanged(
            settingName: 'color_blind_mode',
            value: '$value',
          );
        }, theme),
        const SizedBox(height: 8),
        Text(
          'High-contrast blue & orange palette that stays distinct for all '
          'types of color blindness.',
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  /// Reduce-motion accessibility toggle. Persists the preference and, when
  /// enabled, immediately calms the most motion-heavy effects (screen shake +
  /// engine trails) through their existing cubits for instant feedback.
  Widget _buildReduceMotionControl(GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAudioSwitch('Reduce Motion', _reduceMotion, (value) async {
          // Capture cubits before any await so we never touch context across
          // an async gap.
          final settingsCubit = context.read<GameSettingsCubit>();
          final themeCubit = context.read<ThemeCubit>();
          setState(() => _reduceMotion = value);
          await PreferencesService().setReduceMotion(value);
          if (value) {
            setState(() => _screenShakeEnabled = false);
            await settingsCubit.setScreenShakeEnabled(false);
            await themeCubit.setTrailSystemEnabled(false);
          }
          _analytics.trackSettingChanged(
            settingName: 'reduce_motion',
            value: '$value',
          );
        }, theme),
        const SizedBox(height: 8),
        Text(
          'Dials down screen shake, engine trails, and busy background motion.',
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  /// Section pane: uppercase HUD label + content floating directly on the
  /// starfield — no glass, no borders (the rail already names the section).
  Widget _buildSection(String title, List<Widget> children, GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: theme.accentColor,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Widget _buildThemeSelector(ThemeState themeState, GameTheme theme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Theme',
                    style: TextStyle(color: theme.textMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    theme.name,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Theme preview swatch — the dark fill IS the preview content
            // (it shows the skin's background colour); no halo around it.
            Container(
              width: 60,
              height: 40,
              decoration: BoxDecoration(
                color: theme.backgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: theme.shipColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.foodColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        NeonButton(
          // Routes to the Themes tab of the unified store (tab index 2:
          // Pro / Coins / Themes / Skins / Trails / Power-Ups).
          onPressed: () => context.push('${AppRoutes.store}?tab=2'),
          label: 'BROWSE THEMES',
          theme: theme,
          variant: NeonButtonVariant.outline,
          icon: Icons.palette,
          expand: true,
        ),
      ],
    );
  }

  Widget _buildAudioSwitch(
    String title,
    bool value,
    Function(bool) onChanged,
    GameTheme theme,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: TextStyle(color: theme.textPrimary, fontSize: 16)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: theme.accentColor,
          activeTrackColor: theme.accentColor.withValues(alpha: 0.3),
        ),
      ],
    );
  }

  Widget _buildDPadPositionSelector(GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.gamepad, color: theme.neonPrimary, size: 20),
            const SizedBox(width: 8),
            Text(
              'D-Pad Position',
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: DPadPosition.values.map((position) {
            final isSelected = _dPadPosition == position;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  setState(() {
                    _dPadPosition = position;
                  });
                  await context.read<GameSettingsCubit>().updateDPadPosition(
                    position,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                  // No background — selection reads via the neon label.
                  decoration: const BoxDecoration(),
                  child: Column(
                    children: [
                      Text(position.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(height: 4),
                      Text(
                        position.displayName,
                        style: TextStyle(
                          color: isSelected
                              ? theme.neonPrimary
                              : theme.textMuted,
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildControlInfo(GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Flight Controls',
          style: TextStyle(
            color: theme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        _buildControlItem(
          'Drag',
          'Slide anywhere — your ship mirrors the movement',
          theme,
        ),
        _buildControlItem('D-Pad', 'Analog steering (when enabled)', theme),
        _buildControlItem('Double Tap', 'Fire a missile (uses ammo)', theme),
        _buildControlItem('🚀 Button', 'Fire a missile (uses ammo)', theme),
        _buildControlItem('⏸ HUD Button', 'Pause / resume the run', theme),
        const SizedBox(height: 8),
        Text(
          'Your ship fires automatically — focus on flying.',
          style: TextStyle(
            color: theme.textMuted,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildControlItem(String control, String action, GameTheme theme) {
    // Gesture chip: borderless faint tint + plain muted description.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              control,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              action,
              style: TextStyle(color: theme.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameModeSelector(GameTheme theme) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Game Mode',
                    style: TextStyle(color: theme.textMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedGameMode.icon} ${_selectedGameMode.name}',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _selectedGameMode.description,
          style: TextStyle(
            color: theme.textMuted,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: GameMode.values.map((mode) {
            final isSelected = _selectedGameMode == mode;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                setState(() => _selectedGameMode = mode);
                await context.read<GameSettingsCubit>().updateGameMode(mode);
                _analytics.trackSettingChanged(
                  settingName: 'game_mode',
                  value: mode.name,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                // No background at all — the selected option reads through
                // its neon text color alone.
                decoration: const BoxDecoration(),
                child: Text(
                  '${mode.icon} ${mode.name}',
                  style: TextStyle(
                    color: isSelected ? theme.neonPrimary : theme.textMuted,
                    fontSize: 11,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // _buildCrashFeedbackDurationSelector removed — "crash explanation
  // duration" was the snake grid engine's death-reason overlay; the Flame
  // shooter has no such overlay. The storage/sync plumbing for the value
  // stays untouched for backend compatibility.

  Widget _buildUserProfileSettings(AuthState authState, GameTheme theme) {
    // Resolve the username explicitly so the row labels it as "Username"
    // and shows the same value the change-username dialog pre-fills.
    // Falls back to displayName / 'Not set' so the row never goes blank.
    final username = authState.user?.username;
    final hasRealUsername = username != null && username.isNotEmpty;
    final usernameLabel = hasRealUsername
        ? username
        : (authState.user?.displayName.isNotEmpty == true
              ? authState.user!.displayName
              : 'Not set');

    return Column(
      children: [
        // Current username display
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Username',
                    style: TextStyle(
                      color: theme.textMuted,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        authState.isGuestUser
                            ? Icons.person_outline
                            : Icons.verified_user,
                        color: authState.isGuestUser
                            ? Colors.orange
                            : Colors.green,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '@$usernameLabel',
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    authState.isGuestUser
                        ? 'Guest Account'
                        : 'Authenticated Account',
                    style: TextStyle(color: theme.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),

            // Profile type indicator — borderless tinted status disc
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: (authState.isGuestUser ? Colors.orange : Colors.green)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Icon(
                authState.isGuestUser
                    ? Icons.person_outline
                    : Icons.account_circle,
                color: authState.isGuestUser ? Colors.orange : Colors.green,
                size: 24,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Username actions
        if (authState.isGuestUser) ...[
          // For guest users, allow username change
          NeonButton(
            onPressed: () => _showUsernameDialog(authState, theme),
            label: 'CHANGE USERNAME',
            theme: theme,
            variant: NeonButtonVariant.outline,
            icon: Icons.edit,
            expand: true,
          ),
          const SizedBox(height: 12),
          Text(
            'Sign in to keep your progress and play with friends',
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ] else ...[
          // For authenticated users
          NeonButton(
            onPressed: () => _showUsernameDialog(authState, theme),
            label: 'CHANGE USERNAME',
            theme: theme,
            variant: NeonButtonVariant.outline,
            icon: Icons.edit,
            expand: true,
          ),
          const SizedBox(height: 12),
          Text(
            'Your username is visible to friends and on leaderboards',
            style: TextStyle(
              color: theme.textMuted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Three-button diagnostic surface for the notification pipeline. Each
  /// button isolates one layer:
  ///   • Send Local Test   → permission + channel + display path
  ///   • Send Push via Backend → FCM token + backend send + delivery
  ///   • Copy FCM Token    → manual Firebase Console testing
  /// If "local" works but "backend" doesn't, the break is in token
  /// registration or backend send. If neither works, the OS-level
  /// permission is denied.
  Widget _buildNotificationTestPanel(GameTheme theme) {
    final fcmToken = _notificationService.fcmToken;
    final hasFcmToken = fcmToken != null && fcmToken.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeonButton(
          onPressed: _sendTestLocalNotification,
          label: 'SEND LOCAL TEST',
          theme: theme,
          variant: NeonButtonVariant.outline,
          icon: Icons.notifications_active,
          expand: true,
        ),
        const SizedBox(height: 4),
        Text(
          'Fires immediately. If you don\'t see it, OS permission is denied '
          'or the channel is blocked in system settings.',
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        NeonButton(
          onPressed: hasFcmToken ? _sendTestPushViaBackend : null,
          label: hasFcmToken ? 'SEND PUSH VIA BACKEND' : 'NO FCM TOKEN',
          theme: theme,
          variant: NeonButtonVariant.outline,
          icon: Icons.cloud_upload,
          expand: true,
        ),
        const SizedBox(height: 4),
        Text(
          hasFcmToken
              ? 'Backend sends a push to your device via FCM. Should arrive '
                    'within ~5 seconds if token + backend + delivery all work.'
              : 'FCM token not yet registered. Sign in or restart the app, '
                    'then return to retry.',
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          NeonButton(
            onPressed: hasFcmToken ? _copyFcmTokenToClipboard : null,
            label: 'COPY FCM TOKEN',
            theme: theme,
            variant: NeonButtonVariant.outline,
            icon: Icons.content_copy,
            expand: true,
          ),
          const SizedBox(height: 4),
          Text(
            'Debug only. Paste into Firebase Console → Cloud Messaging → '
            'Send test message to bypass the backend entirely.',
            style: TextStyle(
              color: theme.accentColor.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          NeonButton(
            onPressed: _scheduleTestAtTime,
            label: 'SCHEDULE TEST AT TIME',
            theme: theme,
            variant: NeonButtonVariant.outline,
            icon: Icons.schedule,
            expand: true,
          ),
          const SizedBox(height: 4),
          Text(
            'Pick date + time. Backend schedules a one-off Hangfire job to '
            'fire an FCM push at that instant — fires even if the app is '
            'killed and even if the device clock drifts. Cancel via the '
            'next button.',
            style: TextStyle(
              color: theme.accentColor.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          NeonButton(
            onPressed: _cancelScheduledTest,
            label: 'CANCEL SCHEDULED TEST',
            theme: theme,
            variant: NeonButtonVariant.ghost,
            icon: Icons.cancel_outlined,
            expand: true,
          ),
          const SizedBox(height: 16),
          NeonButton(
            onPressed: _previewDailyReminder,
            label: 'PREVIEW DAILY REMINDER',
            theme: theme,
            variant: NeonButtonVariant.outline,
            icon: Icons.alarm_on,
            expand: true,
          ),
          const SizedBox(height: 4),
          Text(
            'Backend fires the exact daily reminder variant this user '
            'would receive at the next 20:00-local tick — streak / '
            'challenge / high-score branches all evaluated server-side '
            'from your real DB state. Bypasses the timing gate for '
            'instant verification.',
            style: TextStyle(
              color: theme.accentColor.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _sendTestLocalNotification() async {
    await _notificationService.sendTestLocalNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Local test fired — check your notification tray.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _sendTestPushViaBackend() async {
    final ok = await _notificationService.sendTestNotificationViaBackend();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Backend accepted the push. Should arrive within ~5s.'
              : 'Backend rejected. Check API logs (FCM token registered?).',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _copyFcmTokenToClipboard() async {
    final token = _notificationService.fcmToken;
    if (token == null) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('FCM token copied. Paste into Firebase Console.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  /// Two-step picker: date → time. Defaults bias toward "now + 2 min" so
  /// the common dev workflow (tap-tap-OK to verify scheduling works) is
  /// fast. Schedules via OS-level zonedSchedule on confirm.
  Future<void> _scheduleTestAtTime() async {
    final now = DateTime.now();
    final preset = now.add(const Duration(minutes: 2));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: preset,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(preset),
    );
    if (pickedTime == null || !mounted) return;

    final fireAt = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (!fireAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick a future date + time'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final ok = await _notificationService.scheduleTestNotificationAt(fireAt);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Scheduled via backend for ${_formatScheduledTime(fireAt)}'
              : 'Backend rejected the schedule. Check the API logs.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _cancelScheduledTest() async {
    final ok = await _notificationService.cancelScheduledTestNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Scheduled test cancelled (backend job deleted)'
              : 'Cancel returned non-200 — local handle cleared anyway',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _previewDailyReminder() async {
    // Backend reads streak / challenge / high-score state from the DB
    // directly — no need to pass anything from here. Variant matches
    // exactly what the wild user would see at the next 20:00-local tick.
    final variant = await _notificationService.previewDailyReminder();

    if (!mounted) return;
    final message = variant == null
        ? 'No variant applied (no streak / no challenge / no high score yet, or no FCM token registered).'
        : 'Preview fired via backend (variant: $variant). Check your tray.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  String _formatScheduledTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}/${dt.day} $hh:$mm';
  }

  /// Re-opens Google's UMP privacy options form so users can change their
  /// personalized-ad consent. Only shown to free users with ads enabled.
  Widget _buildPrivacyChoicesButton(GameTheme theme) {
    final ads = getIt.isRegistered<AdService>() ? getIt<AdService>() : null;
    // Only show when ads are enabled AND a consent form is actually available
    // to present. Without the form check this button opened nothing (and logged
    // a "no form(s) configured" UMP error) when no consent form exists for the
    // app ID or consent isn't required in the user's region.
    if (ads == null || !ads.adsEnabled || !ads.privacyOptionsRequired) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        NeonButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final shown = await ads.showPrivacyOptions();
            if (!shown) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    "Ad privacy options aren't available right now.",
                  ),
                ),
              );
            }
          },
          label: 'PRIVACY & AD CHOICES',
          theme: theme,
          variant: NeonButtonVariant.outline,
          icon: Icons.privacy_tip,
          expand: true,
        ),
        const SizedBox(height: 8),
        Text(
          'Manage personalized ad consent',
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  /// User-initiated app rating. Unlike the auto-prompt (which is gated to
  /// strong moments), this always tries to surface the native review sheet
  /// and falls back to the store listing when the in-app API isn't available.
  Widget _buildRateButton(GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeonButton(
          onPressed: () => getIt<ReviewService>().rateAppManually(),
          label: 'RATE THIS GAME',
          theme: theme,
          variant: NeonButtonVariant.outline,
          icon: Icons.star_rate,
          expand: true,
        ),
        const SizedBox(height: 8),
        Text(
          'Enjoying Cosmo Strike? Leave us a rating',
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  /// Opens the native OS share sheet with a pre-filled invite + store link.
  Widget _buildShareButton(GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeonButton(
          onPressed: () => ShareService().shareApp(),
          label: 'SHARE WITH FRIENDS',
          theme: theme,
          variant: NeonButtonVariant.outline,
          icon: Icons.share,
          expand: true,
        ),
        const SizedBox(height: 8),
        Text(
          'Invite friends to join the fight',
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCreditsButton(GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeonButton(
          onPressed: () => showCreditsDialog(context, theme),
          label: 'ABOUT & CREDITS',
          theme: theme,
          variant: NeonButtonVariant.outline,
          icon: Icons.info_outline,
          expand: true,
        ),
        const SizedBox(height: 8),
        Text(
          'App version, credits, and links',
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildReplayTutorialButton(GameTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeonButton(
          onPressed: () => _showReplayTutorialDialog(theme),
          label: 'REPLAY TUTORIAL',
          theme: theme,
          variant: NeonButtonVariant.outline,
          icon: Icons.school,
          expand: true,
        ),
        const SizedBox(height: 8),
        Text(
          'Watch the home tour or game tutorial again',
          style: TextStyle(color: theme.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  void _showReplayTutorialDialog(GameTheme theme) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.school, color: theme.accentColor),
            const SizedBox(width: 12),
            Text(
              'Replay Tutorial',
              style: TextStyle(
                color: theme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Which tutorial would you like to replay?',
          style: TextStyle(color: theme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: Text('Cancel', style: TextStyle(color: theme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final walkthroughService = WalkthroughService();
              await walkthroughService.initialize();
              await walkthroughService.reset(
                WalkthroughService.homeWalkthroughId,
              );
              if (mounted) {
                context.go(AppRoutes.home);
              }
            },
            child: Text('Home Tour', style: TextStyle(color: theme.foodColor)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final walkthroughService = WalkthroughService();
              await walkthroughService.initialize();
              await walkthroughService.reset(WalkthroughService.gameTutorialId);
              if (mounted) {
                context.go(AppRoutes.game);
              }
            },
            child: Text(
              'Game Tutorial',
              style: TextStyle(color: theme.accentColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showUsernameDialog(AuthState authState, GameTheme theme) {
    // Pre-fill with the current username so the user can see what it is
    // before editing. Previously the field opened empty, which made it
    // unclear what the existing value was and forced users to retype
    // their full username just to make a small tweak.
    final currentUsername = authState.user?.username ?? '';
    final TextEditingController usernameController = TextEditingController(
      text: currentUsername,
    );
    final UsernameService usernameService = UsernameService();
    String? errorMessage;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              backgroundColor: theme.backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Change Username',
                style: TextStyle(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentUsername.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person,
                              size: 14,
                              color: theme.accentColor.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Current: ',
                              style: TextStyle(
                                color: theme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            Flexible(
                              child: Text(
                                currentUsername,
                                style: TextStyle(
                                  color: theme.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'Choose a unique username that represents you in the game.',
                      style: TextStyle(color: theme.textMuted, fontSize: 14),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        labelStyle: TextStyle(color: theme.textMuted),
                        hintText: 'Enter new username',
                        hintStyle: TextStyle(color: theme.textMuted),
                        // Borderless filled input — definition comes from
                        // the faint fill, not an outline.
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        errorText: errorMessage,
                        errorStyle: const TextStyle(color: Colors.red),
                      ),
                      style: TextStyle(color: theme.textPrimary),
                      maxLength: 20,
                    ),

                    const SizedBox(height: 8),

                    Text(
                      '• 3-20 characters\n• Must start with a letter\n• Letters, numbers, and underscores only',
                      style: TextStyle(color: theme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: theme.textMuted),
                  ),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final newUsername = usernameController.text.trim();
                          if (newUsername.isEmpty) return;

                          setState(() {
                            isLoading = true;
                            errorMessage = null;
                          });

                          bool success = false;
                          final authCubit = context.read<AuthCubit>();
                          final scaffoldMessenger = ScaffoldMessenger.of(
                            context,
                          );

                          if (authState.isGuestUser) {
                            success = await authCubit.updateGuestUsername(
                              newUsername,
                            );
                            if (!success) {
                              final validation = usernameService
                                  .validateUsername(newUsername);
                              setState(() {
                                errorMessage =
                                    validation.error ??
                                    'Failed to update username';
                              });
                            }
                          } else {
                            // For authenticated users
                            success = await authCubit
                                .updateAuthenticatedUsername(newUsername);
                            if (!success) {
                              final validation = await UsernameService()
                                  .validateUsernameComplete(newUsername);
                              setState(() {
                                errorMessage =
                                    validation.error ??
                                    'Failed to update username';
                              });
                            }
                          }

                          if (success && dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Username updated to "$newUsername"',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }

                          setState(() {
                            isLoading = false;
                          });
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isLoading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text('Update', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// Premium UI Components
extension _SettingsPremium on _SettingsScreenState {
  Widget _buildPremiumStatusCard(PremiumState premiumState, GameTheme theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: premiumState.hasPremium
            ? const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              )
            : LinearGradient(
                colors: [
                  theme.accentColor.withValues(alpha: 0.1),
                  theme.backgroundColor.withValues(alpha: 0.05),
                ],
              ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            premiumState.hasPremium ? Icons.diamond : Icons.lock,
            color: premiumState.hasPremium ? Colors.black : theme.accentColor,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  premiumState.hasPremium
                      ? 'Cosmo Strike Pro'
                      : 'Premium Status',
                  style: TextStyle(
                    color: premiumState.hasPremium
                        ? Colors.black
                        : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  premiumState.hasPremium
                      ? 'Active subscription'
                      : 'Unlock premium features',
                  style: TextStyle(
                    color: premiumState.hasPremium
                        ? Colors.black.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                if (premiumState.hasPremium &&
                    premiumState.subscriptionExpiry != null)
                  Text(
                    'Renews ${premiumState.subscriptionExpiry!.day}/${premiumState.subscriptionExpiry!.month}',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (premiumState.hasPremium)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUpgradeButton(PremiumState premiumState, GameTheme theme) {
    // Full-width so the CTA actually reads as the primary action of the
    // Premium section. Routes to the dedicated subscription screen
    // (PremiumBenefitsScreen → /premium-benefits) — the same destination
    // the pause overlay's Premium button uses. The previous in-screen
    // dialog locked the user to monthly with no upsell or comparison.
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: NeonButton(
        onPressed: () => context.push(AppRoutes.premiumBenefits),
        label: 'Upgrade to Pro',
        theme: theme,
        icon: Icons.star,
        expand: true,
      ),
    );
  }

  Widget _buildRestorePurchasesButton(
    PremiumState premiumState,
    GameTheme theme,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: TextButton(
        onPressed: () => _restorePurchases(),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          backgroundColor: theme.accentColor.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restore, color: theme.accentColor),
            const SizedBox(width: 8),
            Text(
              'Restore Purchases',
              style: TextStyle(
                color: theme.accentColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseHistoryButton(
    PremiumState premiumState,
    GameTheme theme,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: TextButton(
        onPressed: () => _showPurchaseHistory(),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          backgroundColor: theme.accentColor.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, color: theme.accentColor),
            const SizedBox(width: 8),
            Text(
              'Purchase History',
              style: TextStyle(
                color: theme.accentColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCosmeticsButton(PremiumState premiumState, GameTheme theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: TextButton(
        onPressed: () => _openCosmeticsSelector(),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          backgroundColor: theme.accentColor.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.palette, color: theme.accentColor),
            const SizedBox(width: 8),
            Text(
              'Ship Cosmetics',
              style: TextStyle(
                color: theme.accentColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            if (premiumState.ownedSkins.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.accentColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${premiumState.ownedSkins.length}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBattlePassButton(PremiumState premiumState, GameTheme theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.purple.withValues(alpha: 0.3),
              Colors.blue.withValues(alpha: 0.3),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: TextButton(
          onPressed: () => _openBattlePass(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            backgroundColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.military_tech, color: Colors.purple),
              const SizedBox(width: 8),
              const Text(
                'Battle Pass',
                style: TextStyle(
                  color: Colors.purple,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Tier ${premiumState.battlePassTier}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Removed _showPremiumDialog + _purchasePro — the Upgrade button now
  // routes to PremiumBenefitsScreen which carries the full subscription
  // experience (monthly/yearly toggle, feature grid, benefits walk-through,
  // proper purchase flow). The old inline dialog was monthly-only with no
  // upsell.

  void _restorePurchases() async {
    // Guests can't restore: the backend rejects anonymous verifies, which
    // used to leave an unverified local-only grant + a stuck retry queue.
    // Restored purchases need the signed-in account they belong to.
    final user = context.read<AuthCubit>().state.user;
    if (user == null || user.isAnonymous) {
      await showAccountUpgradeSheet(context);
      return;
    }
    if (!mounted) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Restoring purchases...'),
          backgroundColor: Colors.blue,
        ),
      );

      final purchaseService = PurchaseService();
      await purchaseService.restorePurchases();

      if (mounted) {
        // Results arrive asynchronously on the purchase stream — this only
        // confirms the restore REQUEST went through, not that items landed.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Restore requested — any purchases will appear in a moment.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to restore purchases. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPurchaseHistory() async {
    try {
      final premiumCubit = context.read<PremiumCubit>();
      final history = await premiumCubit.getPurchaseHistory();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Purchase History'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: history.isEmpty
                ? const Center(
                    child: Text(
                      'No purchases found',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final purchase = history[index];
                      // Purchase is already a Map<String, dynamic>
                      try {
                        final productId =
                            purchase['productId']?.toString() ?? 'Unknown';
                        final transactionDate =
                            purchase['transactionDate']?.toString() ?? '';
                        final status =
                            purchase['status']?.toString() ?? 'Unknown';

                        return Card(
                          child: ListTile(
                            leading: Icon(
                              _getPurchaseIcon(
                                _getTypeFromProductId(productId),
                              ),
                            ),
                            title: Text(_formatProductName(productId)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Status: $status'),
                                Text('Date: ${_formatDate(transactionDate)}'),
                              ],
                            ),
                          ),
                        );
                      } catch (e) {
                        return ListTile(
                          title: Text('Purchase #${index + 1}'),
                          subtitle: const Text('Data parsing error'),
                        );
                      }
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to load purchase history'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  IconData _getPurchaseIcon(String type) {
    switch (type) {
      case 'subscription':
        return Icons.star;
      case 'theme':
        return Icons.palette;
      case 'skin':
        return Icons.pets;
      case 'trail':
        return Icons.auto_awesome;
      case 'bundle':
        return Icons.shopping_bag;
      case 'battlepass':
        return Icons.emoji_events;
      case 'tournament':
        return Icons.sports_esports;
      default:
        return Icons.shopping_cart;
    }
  }

  String _formatDate(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return 'Unknown date';
    }
  }

  String _getTypeFromProductId(String productId) {
    // Strip store prefix before checking
    final bare = ProductIds.stripPrefix(productId);
    if (bare.contains('pro_monthly') || bare.contains('pro_yearly')) {
      return 'subscription';
    } else if (bare.contains('theme')) {
      return 'theme';
    } else if (bare.contains('skin')) {
      return 'skin';
    } else if (bare.contains('trail')) {
      return 'trail';
    } else if (bare.contains('bundle') ||
        bare.contains('pack') ||
        bare.contains('collection')) {
      return 'bundle';
    } else if (bare.contains('battle_pass')) {
      return 'battlepass';
    } else if (bare.contains('tournament') ||
        bare.contains('championship') ||
        bare.contains('vip')) {
      return 'tournament';
    }
    return 'unknown';
  }

  String _formatProductName(String productId) {
    // Strip store prefix before formatting
    final bare = ProductIds.stripPrefix(productId);
    return bare
        .replaceAll('skin_', '')
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) => word.isNotEmpty
              ? '${word[0].toUpperCase()}${word.substring(1)}'
              : '',
        )
        .join(' ');
  }

  void _openCosmeticsSelector() {
    context.push(AppRoutes.cosmetics);
  }

  void _openBattlePass() {
    context.push(AppRoutes.battlePass);
  }
}
