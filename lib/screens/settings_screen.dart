import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/credits_dialog.dart';

/// Settings (Prism Noir): a section list on the LEFT styled like the store's
/// category list (selected = 7% white fill + gold icon) with BACK TO GAME
/// pinned under it, and the selected section on the RIGHT — mono eyebrow,
/// Syne headline, then hairline rows with the theme's Switch / CsSegmented
/// controls.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Left-rail sections, in pane order.
const _kSections = <(IconData, String)>[
  (Symbols.gamepad_rounded, 'Controls'),
  (Symbols.sports_esports_rounded, 'Gameplay'),
  (Symbols.volume_up_rounded, 'Audio'),
  (Symbols.palette_rounded, 'Visual'),
  (Symbols.notifications_rounded, 'Notifications'),
  (Symbols.person_rounded, 'Profile'),
  (Symbols.help_rounded, 'Help'),
  (Symbols.workspace_premium_rounded, 'Premium'),
  (Symbols.accessibility_new_rounded, 'Access'),
];

class _SettingsScreenState extends State<SettingsScreen> {
  final AudioService _audioService = AudioService();
  final StorageService _storageService = StorageService();
  late final AppDataCache _appCache;
  late final AnalyticsFacade _analytics;

  /// Which section of the left rail is selected (drives the right pane).
  int _selectedSection = 0;

  /// Shared by the rail's ListView and its Scrollbar.
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
                  final cs = context.cs;
                  final section = _kSections[_selectedSection];
                  return CsScaffold(
                    title: 'Settings',
                    trailing: [
                      CsMeta(
                        '${_two(_selectedSection + 1)} / ${_two(_kSections.length)}',
                      ),
                    ],
                    body: CsSplit(
                      leftWidth: cs.isTablet ? 260 : 220,
                      left: _buildNavRail(),
                      right: AnimatedSwitcher(
                        duration: CsMotion.base,
                        switchInCurve: CsMotion.standard,
                        child: SingleChildScrollView(
                          key: ValueKey(_selectedSection),
                          padding: EdgeInsets.only(bottom: cs(16)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CsLabel('${_two(_selectedSection + 1)} · Settings'),
                              SizedBox(height: cs(6)),
                              Text(
                                section.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: cs.type.display(30, em: -0.03, height: 1.05),
                              ),
                              SizedBox(height: cs(14)),
                              ..._buildSectionPane(
                                _selectedSection,
                                themeState,
                                authState,
                                premiumState,
                                themeState.currentTheme,
                              ),
                            ],
                          ),
                        ),
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

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Section list for the left region. 9 sections at a ≥44dp target don't
  /// fit a short landscape phone, so the list scrolls (with a thin
  /// scrollbar); BACK TO GAME stays pinned below it.
  Widget _buildNavRail() {
    final cs = context.cs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Scrollbar(
            controller: _railScrollController,
            thickness: 2,
            radius: const Radius.circular(1),
            child: ListView.separated(
              controller: _railScrollController,
              padding: EdgeInsets.only(right: cs(8)),
              itemCount: _kSections.length,
              separatorBuilder: (_, _) => SizedBox(height: cs(2)),
              itemBuilder: (context, i) => _NavItem(
                icon: _kSections[i].$1,
                label: _kSections[i].$2,
                selected: _selectedSection == i,
                onTap: () => setState(() => _selectedSection = i),
              ),
            ),
          ),
        ),
        // Short phones: the top-bar back arrow is enough; give the
        // section list the room instead.
        if (!cs.isCompact) SizedBox(height: cs(10)),
        if (!cs.isCompact) CsButton.secondary(
          onPressed: () => context.pop(),
          label: 'Back to Game',
          icon: Symbols.arrow_back_rounded,
          // Phones: the compact pill so the label never truncates.
          size: cs.isTablet ? CsButtonSize.regular : CsButtonSize.small,
          expand: true,
        ),
      ],
    );
  }

  /// Right-pane content for the selected rail section. Every control keeps
  /// its exact handler / cubit wiring.
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
          _buildSwitchRow(
            icon: Symbols.gamepad_rounded,
            title: 'D-Pad Controls',
            subtitle: 'Show an on-screen analog pad for steering during gameplay',
            value: _dPadEnabled,
            first: true,
            onChanged: (value) async {
              setState(() {
                _dPadEnabled = value;
              });
              await context.read<GameSettingsCubit>().updateDPadEnabled(value);
              _analytics.trackSettingChanged(
                settingName: 'dpad_enabled',
                value: '$value',
              );
            },
          ),
          // D-Pad Position Selector (only show when D-Pad is enabled)
          if (_dPadEnabled) _buildDPadPositionSelector(),
          _buildSwitchRow(
            icon: Symbols.vibration_rounded,
            title: 'Haptic Feedback',
            subtitle: 'Vibrate on hits, pickups, and boss beats',
            value: _hapticsEnabled,
            onChanged: (value) async {
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
            },
          ),
          SizedBox(height: context.cs(22)),
          _buildControlInfo(),
        ];

      // 2. Gameplay (mode + effects). Board size and the crash-feedback
      // duration were legacy grid settings with no meaning in the
      // shooter — both removed (the data plumbing stays for sync compat).
      case 1:
        return [
          _buildGameModeSelector(),
          SizedBox(height: context.cs(18)),
          _buildSwitchRow(
            icon: Symbols.vibration_rounded,
            title: 'Screen Shake',
            subtitle: 'Jolt the view when you take hits, lose a ship, or down a boss',
            value: _screenShakeEnabled,
            first: true,
            onChanged: (value) async {
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
            },
          ),
        ];

      // 3. Audio
      case 2:
        return [
          _buildSwitchRow(
            icon: Symbols.volume_up_rounded,
            title: 'Sound Effects',
            subtitle: 'Weapons, explosions, pickups and UI sounds',
            value: _soundEnabled,
            first: true,
            onChanged: (value) async {
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
            },
          ),
          _buildSwitchRow(
            icon: Symbols.music_note_rounded,
            title: 'Background Music',
            subtitle: 'Menu and in-flight soundtrack',
            value: _musicEnabled,
            onChanged: (value) async {
              setState(() {
                _musicEnabled = value;
              });
              await _audioService.setMusicEnabled(value);
              _analytics.trackSettingChanged(
                settingName: 'background_music',
                value: '$value',
              );
            },
          ),
        ];

      // 4. Visual (gameplay theme + trail effects)
      case 3:
        return [
          _buildThemeSelector(theme),
          _buildSwitchRow(
            icon: Symbols.auto_awesome_rounded,
            title: 'Engine Trail Effects',
            subtitle: 'Enable particle trails behind your ship',
            value: themeState.isTrailSystemEnabled,
            onChanged: (value) async {
              await context.read<ThemeCubit>().setTrailSystemEnabled(value);
            },
          ),
        ];

      // 5. Notifications (+ debug-only test panel)
      case 4:
        return [
          _buildSwitchRow(
            icon: Symbols.alarm_rounded,
            title: 'Daily Reminder',
            value: _notifDailyReminder,
            first: true,
            onChanged: (v) => _toggleNotification(
              NotificationType.dailyReminder,
              v,
              (val) => _notifDailyReminder = val,
            ),
          ),
          _buildSwitchRow(
            icon: Symbols.emoji_events_rounded,
            title: 'Tournament Alerts',
            value: _notifTournament,
            onChanged: (v) => _toggleNotification(
              NotificationType.tournament,
              v,
              (val) => _notifTournament = val,
            ),
          ),
          _buildSwitchRow(
            icon: Symbols.military_tech_rounded,
            title: 'Achievement Unlocks',
            value: _notifAchievement,
            onChanged: (v) => _toggleNotification(
              NotificationType.achievement,
              v,
              (val) => _notifAchievement = val,
            ),
          ),
          _buildSwitchRow(
            icon: Symbols.group_rounded,
            title: 'Social Updates',
            value: _notifSocial,
            onChanged: (v) => _toggleNotification(
              NotificationType.social,
              v,
              (val) => _notifSocial = val,
            ),
          ),
          _buildSwitchRow(
            icon: Symbols.celebration_rounded,
            title: 'Special Events',
            value: _notifSpecialEvent,
            onChanged: (v) => _toggleNotification(
              NotificationType.specialEvent,
              v,
              (val) => _notifSpecialEvent = val,
            ),
          ),

          // Diagnostic buttons that isolate each layer of the notification
          // pipeline. Gated behind kDebugMode so production builds never see
          // it — these are developer-facing controls for triage during
          // development + Play Store internal testing, not user features.
          // See NOTIFICATIONS_TESTING.md for triage guide.
          if (kDebugMode) ...[
            SizedBox(height: context.cs(26)),
            const CsLabel('Test notifications · debug', color: CsColors.gold),
            SizedBox(height: context.cs(8)),
            _buildNotificationTestPanel(),
          ],
        ];

      // 6. User profile
      case 5:
        return [_buildUserProfileSettings(authState)];

      // 7. Help & tutorial
      case 6:
        return [
          _buildReplayTutorialButton(),
          _buildRateButton(),
          _buildShareButton(),
          _buildCreditsButton(theme),
          _buildPrivacyChoicesButton(),
        ];

      // 8. Premium (if available)
      case 7:
        if (!premiumState.isInitialized) {
          return [
            SizedBox(
              height: context.cs(160),
              child: const CsLoadingState(label: 'Loading premium status'),
            ),
          ];
        }
        return [
          _buildPremiumStatusCard(premiumState),
          if (!premiumState.hasPremium) _buildUpgradeButton(premiumState),
          _buildRestorePurchasesButton(premiumState),
          _buildPurchaseHistoryButton(premiumState),
          if (premiumState.hasPremium || premiumState.ownedSkins.isNotEmpty)
            _buildCosmeticsButton(premiumState),
          if (premiumState.hasBattlePass) _buildBattlePassButton(premiumState),
        ];

      // 9. Accessibility
      case 8:
        return [
          _buildColorBlindControl(themeState),
          _buildReduceMotionControl(),
        ];

      default:
        return const [];
    }
  }

  /// One-tap color-blind friendly skin. Toggling on applies the high-contrast
  /// blue↔orange [GameTheme.accessible] palette through the normal ThemeCubit
  /// path (persisted + synced); toggling off returns to Classic.
  Widget _buildColorBlindControl(ThemeState themeState) {
    final isOn = themeState.currentTheme == GameTheme.accessible;
    return _buildSwitchRow(
      icon: Symbols.contrast_rounded,
      title: 'Color-Blind Friendly',
      subtitle: 'High-contrast blue & orange gameplay palette that stays '
          'distinct for all types of color blindness.',
      value: isOn,
      first: true,
      onChanged: (value) async {
        await context.read<ThemeCubit>().setTheme(
          value ? GameTheme.accessible : GameTheme.classic,
        );
        _analytics.trackSettingChanged(
          settingName: 'color_blind_mode',
          value: '$value',
        );
      },
    );
  }

  /// Reduce-motion accessibility toggle. Persists the preference and, when
  /// enabled, immediately calms the most motion-heavy effects (screen shake +
  /// engine trails) through their existing cubits for instant feedback.
  Widget _buildReduceMotionControl() {
    return _buildSwitchRow(
      icon: Symbols.motion_photos_off_rounded,
      title: 'Reduce Motion',
      subtitle: 'Dials down screen shake, engine trails, and busy background motion.',
      value: _reduceMotion,
      onChanged: (value) async {
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
      },
    );
  }

  /// Hairline row with a theme [Switch]; the whole row toggles.
  Widget _buildSwitchRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required Function(bool) onChanged,
    bool first = false,
  }) {
    return _SettingRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      first: first,
      onTap: () => onChanged(!value),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  /// Hairline action row: icon · title/subtitle · chevron.
  Widget _buildActionRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback? onTap,
    bool first = false,
    Widget? trailing,
    Color iconColor = CsColors.ink70,
    Color? titleColor,
    Color? subtitleColor,
  }) {
    return _SettingRow(
      icon: icon,
      iconColor: iconColor,
      title: title,
      titleColor: titleColor,
      subtitle: subtitle,
      subtitleColor: subtitleColor,
      first: first,
      onTap: onTap,
      trailing: trailing ??
          Icon(Symbols.chevron_right_rounded, size: context.cs(20), color: CsColors.ink45),
    );
  }

  /// Purchased colour themes now tint GAMEPLAY only — menus always use
  /// Prism Noir. The picker still lives in the store's Themes tab.
  Widget _buildThemeSelector(GameTheme theme) {
    final cs = context.cs;
    return _SettingRow(
      icon: Symbols.palette_rounded,
      title: 'Gameplay Theme · ${theme.name}',
      subtitle: 'Colours your ship, enemies and effects in flight. '
          'Menus always use Prism Noir.',
      first: true,
      onTap: () => context.push('${AppRoutes.store}?tab=2'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ThemeSwatch(theme: theme),
          SizedBox(width: cs(12)),
          // Routes to the Themes tab of the unified store (tab index 2:
          // Pro / Coins / Themes / Skins / Trails / Power-Ups).
          CsButton.secondary(
            onPressed: () => context.push('${AppRoutes.store}?tab=2'),
            label: 'Browse',
            size: CsButtonSize.small,
          ),
        ],
      ),
    );
  }

  Widget _buildDPadPositionSelector() {
    final cs = context.cs;
    return _SettingRow(
      icon: Symbols.open_with_rounded,
      title: 'D-Pad Position',
      below: Padding(
        padding: EdgeInsets.only(top: cs(4)),
        child: Align(
          alignment: Alignment.centerLeft,
          child: CsSegmented<DPadPosition>(
            segments: {
              for (final p in DPadPosition.values) p: p.displayName,
            },
            selected: _dPadPosition,
            onChanged: (position) async {
              setState(() {
                _dPadPosition = position;
              });
              await context.read<GameSettingsCubit>().updateDPadPosition(
                position,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildControlInfo() {
    final cs = context.cs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CsLabel('Flight controls'),
        SizedBox(height: cs(6)),
        _buildControlItem('Drag', 'Slide anywhere — your ship mirrors the movement', first: true),
        _buildControlItem('D-Pad', 'Analog steering (when enabled)'),
        _buildControlItem('Double Tap', 'Fire a missile (uses ammo)'),
        _buildControlItem('Missile Button', 'Fire a missile (uses ammo)'),
        _buildControlItem('Pause Button', 'Pause / resume the run'),
        SizedBox(height: cs(10)),
        Text(
          'Your ship fires automatically — focus on flying.'.toUpperCase(),
          style: cs.type.micro,
        ),
      ],
    );
  }

  Widget _buildControlItem(String control, String action, {bool first = false}) {
    final cs = context.cs;
    return Container(
      padding: EdgeInsets.symmetric(vertical: cs(9)),
      decoration: BoxDecoration(
        border: Border(
          top: first ? const BorderSide(color: CsColors.hairline) : BorderSide.none,
          bottom: const BorderSide(color: CsColors.hairline),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: cs(130),
            child: Align(alignment: Alignment.centerLeft, child: CsChip(control)),
          ),
          SizedBox(width: cs(10)),
          Expanded(child: Text(action, style: cs.type.body)),
        ],
      ),
    );
  }

  Widget _buildGameModeSelector() {
    final cs = context.cs;
    final t = cs.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CsLabel('Game mode'),
        SizedBox(height: cs(8)),
        Row(
          children: [
            Icon(CsIcons.mode(_selectedGameMode), size: cs(22), color: CsColors.ink),
            SizedBox(width: cs(10)),
            Expanded(
              child: Text(
                _selectedGameMode.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.display(20, em: -0.02),
              ),
            ),
          ],
        ),
        SizedBox(height: cs(4)),
        Text(_selectedGameMode.description, style: t.body),
        SizedBox(height: cs(14)),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth > cs(560) ? 4 : (c.maxWidth > cs(300) ? 3 : 2);
            final gap = cs(8);
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: GameMode.values.map((mode) {
                final isSelected = _selectedGameMode == mode;
                return CsTile(
                  width: w,
                  state: isSelected ? CsTileState.current : CsTileState.future,
                  padding: EdgeInsets.symmetric(horizontal: cs(10), vertical: cs(10)),
                  onTap: () async {
                    setState(() => _selectedGameMode = mode);
                    await context.read<GameSettingsCubit>().updateGameMode(mode);
                    _analytics.trackSettingChanged(
                      settingName: 'game_mode',
                      value: mode.name,
                    );
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 24),
                    child: Row(
                      children: [
                        Icon(
                          CsIcons.mode(mode),
                          size: cs(16),
                          color: isSelected ? CsColors.ink : CsColors.ink45,
                        ),
                        SizedBox(width: cs(8)),
                        Expanded(
                          child: Text(
                            mode.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.display(
                              12,
                              weight: FontWeight.w700,
                              em: 0,
                              color: isSelected ? CsColors.ink : CsColors.ink60,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  // _buildCrashFeedbackDurationSelector removed — "crash explanation
  // duration" was the snake grid engine's death-reason overlay; the Flame
  // shooter has no such overlay. The storage/sync plumbing for the value
  // stays untouched for backend compatibility.

  Widget _buildUserProfileSettings(AuthState authState) {
    final cs = context.cs;
    final t = cs.type;
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
    final isGuest = authState.isGuestUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Current username display
        Row(
          children: [
            CsAvatarRing(
              name: usernameLabel,
              size: 52,
              ring: isGuest ? CsRingKind.none : CsRingKind.prism,
            ),
            SizedBox(width: cs(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CsLabel('Username'),
                  SizedBox(height: cs(4)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '@$usernameLabel',
                      maxLines: 1,
                      style: t.display(22, em: -0.02),
                    ),
                  ),
                  SizedBox(height: cs(4)),
                  CsMeta(
                    isGuest ? 'Guest Account' : 'Authenticated Account',
                    icon: isGuest ? Symbols.person_rounded : Symbols.verified_user_rounded,
                    iconColor: isGuest ? CsColors.gold : CsColors.mint,
                    size: 10,
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: cs(16)),

        // Username actions — same dialog for guest and authenticated users;
        // only the helper copy differs.
        _buildActionRow(
          icon: Symbols.edit_rounded,
          title: 'Change Username',
          subtitle: isGuest
              ? 'Sign in to keep your progress and play with friends'
              : 'Your username is visible to friends and on leaderboards',
          first: true,
          onTap: () => _showUsernameDialog(authState),
        ),

        // Danger zone — permanent account deletion (Play policy requires an
        // in-app path). Shown for every account type: guests have server
        // rows too once they've synced.
        SizedBox(height: cs(22)),
        const CsLabel('Danger zone', color: CsColors.pink),
        SizedBox(height: cs(6)),
        _buildActionRow(
          icon: Symbols.delete_forever_rounded,
          iconColor: CsColors.pink,
          title: 'Delete Account',
          titleColor: CsColors.pink,
          subtitle: 'Permanently deletes your account and all game data. '
              'This cannot be undone.',
          first: true,
          onTap: _showDeleteAccountDialog,
        ),
      ],
    );
  }

  /// Two-step destructive confirm: an explicit list of what gets deleted,
  /// then a type-DELETE gate before the button arms. On success every local
  /// store is already wiped (AuthCubit → UnifiedUserService.deleteAccount),
  /// so we route straight back to first-time auth.
  void _showDeleteAccountDialog() {
    final confirmController = TextEditingController();
    showCsDialog<void>(
      context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final cs = dialogContext.cs;
          final t = cs.type;
          final armed = confirmController.text.trim().toUpperCase() == 'DELETE';
          return CsDialog(
            icon: Symbols.delete_forever_rounded,
            iconColor: CsColors.pink,
            eyebrow: 'Danger zone',
            title: 'Delete Account?',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This permanently deletes:',
                  style: t.body.copyWith(color: CsColors.ink),
                ),
                SizedBox(height: cs(8)),
                Text(
                  '• Your account and sign-in identity\n'
                  '• All progress, scores and statistics\n'
                  '• Coins, cosmetics and unlocked content\n'
                  '• Friends, achievements and quest history',
                  style: t.body.copyWith(height: 1.6),
                ),
                SizedBox(height: cs(12)),
                Text(
                  'This cannot be undone.'.toUpperCase(),
                  style: t.mono(11, color: CsColors.pink, weight: FontWeight.w600),
                ),
                SizedBox(height: cs(8)),
                TextField(
                  controller: confirmController,
                  onChanged: (_) => setDialogState(() {}),
                  style: t.rowTitle,
                  decoration: const InputDecoration(
                    labelText: 'TYPE DELETE TO CONFIRM',
                  ),
                ),
              ],
            ),
            actions: [
              CsButton.text(
                label: 'Cancel',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
              CsButton.primary(
                label: 'Delete forever',
                icon: Symbols.delete_forever_rounded,
                onPressed: armed
                    ? () {
                        Navigator.of(dialogContext).pop();
                        _performAccountDeletion();
                      }
                    : null,
              ),
            ],
          );
        },
      ),
    ).then((_) => confirmController.dispose());
  }

  Future<void> _performAccountDeletion() async {
    showCsToast(context, 'Deleting your account...', icon: Symbols.delete_forever_rounded);

    final ok = await context.read<AuthCubit>().deleteAccount();
    if (!mounted) return;

    if (ok) {
      // Local state is fully wiped — land on the fresh-install auth screen.
      context.go(AppRoutes.firstTimeAuth);
    } else {
      showCsToast(
        context,
        context.read<AuthCubit>().state.errorMessage ??
            'Could not delete your account. Please try again.',
        kind: CsToastKind.error,
      );
    }
  }

  /// Diagnostic surface for the notification pipeline. Each row isolates
  /// one layer:
  ///   • Send Local Test   → permission + channel + display path
  ///   • Send Push via Backend → FCM token + backend send + delivery
  ///   • Copy FCM Token    → manual Firebase Console testing
  /// If "local" works but "backend" doesn't, the break is in token
  /// registration or backend send. If neither works, the OS-level
  /// permission is denied.
  Widget _buildNotificationTestPanel() {
    final fcmToken = _notificationService.fcmToken;
    final hasFcmToken = fcmToken != null && fcmToken.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildActionRow(
          icon: Symbols.notifications_active_rounded,
          title: 'Send Local Test',
          subtitle: 'Fires immediately. If you don\'t see it, OS permission is denied '
              'or the channel is blocked in system settings.',
          first: true,
          onTap: _sendTestLocalNotification,
        ),
        _buildActionRow(
          icon: Symbols.cloud_upload_rounded,
          title: hasFcmToken ? 'Send Push via Backend' : 'No FCM Token',
          subtitle: hasFcmToken
              ? 'Backend sends a push to your device via FCM. Should arrive '
                    'within ~5 seconds if token + backend + delivery all work.'
              : 'FCM token not yet registered. Sign in or restart the app, '
                    'then return to retry.',
          onTap: hasFcmToken ? _sendTestPushViaBackend : null,
        ),
        if (kDebugMode) ...[
          _buildActionRow(
            icon: Symbols.content_copy_rounded,
            title: 'Copy FCM Token',
            subtitle: 'Debug only. Paste into Firebase Console → Cloud Messaging → '
                'Send test message to bypass the backend entirely.',
            subtitleColor: CsColors.gold.withValues(alpha: 0.7),
            onTap: hasFcmToken ? _copyFcmTokenToClipboard : null,
          ),
          _buildActionRow(
            icon: Symbols.schedule_rounded,
            title: 'Schedule Test at Time',
            subtitle: 'Pick date + time. Backend schedules a one-off Hangfire job to '
                'fire an FCM push at that instant — fires even if the app is '
                'killed and even if the device clock drifts. Cancel via the '
                'next button.',
            subtitleColor: CsColors.gold.withValues(alpha: 0.7),
            onTap: _scheduleTestAtTime,
          ),
          _buildActionRow(
            icon: Symbols.cancel_rounded,
            title: 'Cancel Scheduled Test',
            onTap: _cancelScheduledTest,
          ),
          _buildActionRow(
            icon: Symbols.alarm_on_rounded,
            title: 'Preview Daily Reminder',
            subtitle: 'Backend fires the exact daily reminder variant this user '
                'would receive at the next 20:00-local tick — streak / '
                'challenge / high-score branches all evaluated server-side '
                'from your real DB state. Bypasses the timing gate for '
                'instant verification.',
            subtitleColor: CsColors.gold.withValues(alpha: 0.7),
            onTap: _previewDailyReminder,
          ),
        ],
      ],
    );
  }

  Future<void> _sendTestLocalNotification() async {
    await _notificationService.sendTestLocalNotification();
    if (!mounted) return;
    showCsToast(
      context,
      'Local test fired — check your notification tray.',
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _sendTestPushViaBackend() async {
    final ok = await _notificationService.sendTestNotificationViaBackend();
    if (!mounted) return;
    showCsToast(
      context,
      ok
          ? 'Backend accepted the push. Should arrive within ~5s.'
          : 'Backend rejected. Check API logs (FCM token registered?).',
      kind: ok ? CsToastKind.success : CsToastKind.error,
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _copyFcmTokenToClipboard() async {
    final token = _notificationService.fcmToken;
    if (token == null) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    showCsToast(
      context,
      'FCM token copied. Paste into Firebase Console.',
      kind: CsToastKind.success,
      duration: const Duration(seconds: 3),
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
      showCsToast(
        context,
        'Pick a future date + time',
        kind: CsToastKind.error,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    final ok = await _notificationService.scheduleTestNotificationAt(fireAt);
    if (!mounted) return;
    showCsToast(
      context,
      ok
          ? 'Scheduled via backend for ${_formatScheduledTime(fireAt)}'
          : 'Backend rejected the schedule. Check the API logs.',
      kind: ok ? CsToastKind.success : CsToastKind.error,
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _cancelScheduledTest() async {
    final ok = await _notificationService.cancelScheduledTestNotification();
    if (!mounted) return;
    showCsToast(
      context,
      ok
          ? 'Scheduled test cancelled (backend job deleted)'
          : 'Cancel returned non-200 — local handle cleared anyway',
      duration: const Duration(seconds: 3),
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
    showCsToast(context, message, duration: const Duration(seconds: 4));
  }

  String _formatScheduledTime(DateTime dt) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}/${dt.day} $hh:$mm';
  }

  /// Re-opens Google's UMP privacy options form so users can change their
  /// personalized-ad consent. Only shown to free users with ads enabled.
  Widget _buildPrivacyChoicesButton() {
    final ads = getIt.isRegistered<AdService>() ? getIt<AdService>() : null;
    // Only show when ads are enabled AND a consent form is actually available
    // to present. Without the form check this button opened nothing (and logged
    // a "no form(s) configured" UMP error) when no consent form exists for the
    // app ID or consent isn't required in the user's region.
    if (ads == null || !ads.adsEnabled || !ads.privacyOptionsRequired) {
      return const SizedBox.shrink();
    }
    return _buildActionRow(
      icon: Symbols.privacy_tip_rounded,
      title: 'Privacy & Ad Choices',
      subtitle: 'Manage personalized ad consent',
      onTap: () async {
        final shown = await ads.showPrivacyOptions();
        if (!shown && mounted) {
          showCsToast(context, "Ad privacy options aren't available right now.");
        }
      },
    );
  }

  /// User-initiated app rating. Unlike the auto-prompt (which is gated to
  /// strong moments), this always tries to surface the native review sheet
  /// and falls back to the store listing when the in-app API isn't available.
  Widget _buildRateButton() {
    return _buildActionRow(
      icon: Symbols.star_rate_rounded,
      iconColor: CsColors.gold,
      title: 'Rate This Game',
      subtitle: 'Enjoying Cosmo Strike? Leave us a rating',
      onTap: () => getIt<ReviewService>().rateAppManually(),
    );
  }

  /// Opens the native OS share sheet with a pre-filled invite + store link.
  Widget _buildShareButton() {
    return _buildActionRow(
      icon: Symbols.share_rounded,
      title: 'Share with Friends',
      subtitle: 'Invite friends to join the fight',
      onTap: () => ShareService().shareApp(),
    );
  }

  Widget _buildCreditsButton(GameTheme theme) {
    return _buildActionRow(
      icon: Symbols.info_rounded,
      title: 'About & Credits',
      subtitle: 'App version, credits, and links',
      onTap: () => showCreditsDialog(context, theme),
    );
  }

  Widget _buildReplayTutorialButton() {
    return _buildActionRow(
      icon: Symbols.school_rounded,
      title: 'Replay Tutorial',
      subtitle: 'Watch the home tour or game tutorial again',
      first: true,
      onTap: _showReplayTutorialDialog,
    );
  }

  void _showReplayTutorialDialog() {
    showCsDialog<void>(
      context,
      builder: (dialogContext) => CsDialog(
        icon: Symbols.school_rounded,
        eyebrow: 'Help',
        title: 'Replay Tutorial',
        message: 'Which tutorial would you like to replay?',
        actions: [
          CsButton.text(
            label: 'Cancel',
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
          ),
          CsButton.secondary(
            label: 'Home Tour',
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
          ),
          CsButton.primary(
            label: 'Game Tutorial',
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final walkthroughService = WalkthroughService();
              await walkthroughService.initialize();
              await walkthroughService.reset(WalkthroughService.gameTutorialId);
              if (mounted) {
                context.go(AppRoutes.game);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showUsernameDialog(AuthState authState) {
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

    showCsDialog<void>(
      context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            final cs = dialogContext.cs;
            final t = cs.type;
            return CsDialog(
              eyebrow: 'Profile',
              title: 'Change Username',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (currentUsername.isNotEmpty) ...[
                    Row(
                      children: [
                        Text('CURRENT ', style: t.mono(10, color: CsColors.ink45)),
                        Flexible(
                          child: Text(
                            currentUsername,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.mono(11, color: CsColors.ink, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: cs(10)),
                  ],
                  Text(
                    'Choose a unique username that represents you in the game.',
                    style: t.body,
                  ),
                  SizedBox(height: cs(10)),
                  TextField(
                    controller: usernameController,
                    style: t.rowTitle,
                    decoration: InputDecoration(
                      labelText: 'USERNAME',
                      hintText: 'Enter new username',
                      errorText: errorMessage,
                      counterStyle: t.micro,
                    ),
                    maxLength: 20,
                  ),
                  SizedBox(height: cs(6)),
                  Text(
                    '3-20 characters · Must start with a letter · '
                    'Letters, numbers, and underscores only'.toUpperCase(),
                    style: t.micro.copyWith(height: 1.5),
                  ),
                ],
              ),
              actions: [
                CsButton.text(
                  label: 'Cancel',
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                ),
                CsButton.primary(
                  label: 'Update',
                  loading: isLoading,
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
                            if (mounted) {
                              showCsToast(
                                context,
                                'Username updated to "$newUsername"',
                                kind: CsToastKind.success,
                              );
                            }
                          }

                          setState(() {
                            isLoading = false;
                          });
                        },
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
  Widget _buildPremiumStatusCard(PremiumState premiumState) {
    final cs = context.cs;
    final t = cs.type;
    final pro = premiumState.hasPremium;
    return Padding(
      padding: EdgeInsets.only(bottom: cs(14)),
      child: CsTile(
        state: pro ? CsTileState.pro : CsTileState.future,
        radius: CsRadius.card,
        padding: EdgeInsets.all(cs(16)),
        child: Row(
          children: [
            Icon(
              pro ? Symbols.diamond_rounded : Symbols.lock_rounded,
              color: pro ? CsColors.gold : CsColors.ink60,
              size: cs(26),
            ),
            SizedBox(width: cs(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  pro
                      ? CsHeadline(const ['Cosmo Strike ', 'Pro'], prismIndex: 1, style: t.display(20, em: -0.02))
                      : Text('Premium Status', style: t.display(20, em: -0.02)),
                  SizedBox(height: cs(3)),
                  Text(
                    pro ? 'Active subscription' : 'Unlock premium features',
                    style: t.body,
                  ),
                  if (pro && premiumState.subscriptionExpiry != null) ...[
                    SizedBox(height: cs(3)),
                    Text(
                      'Renews ${premiumState.subscriptionExpiry!.day}/${premiumState.subscriptionExpiry!.month}'
                          .toUpperCase(),
                      style: t.mono(10, color: CsColors.gold),
                    ),
                  ],
                ],
              ),
            ),
            if (pro) const CsChip('PRO', kind: CsChipKind.gold),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeButton(PremiumState premiumState) {
    // Routes to the dedicated subscription screen
    // (PremiumBenefitsScreen → /premium-benefits) — the same destination
    // the pause overlay's Premium button uses. The previous in-screen
    // dialog locked the user to monthly with no upsell or comparison.
    return Padding(
      padding: EdgeInsets.only(bottom: context.cs(14)),
      child: CsButton.premium(
        onPressed: () => context.push(AppRoutes.premiumBenefits),
        label: 'Upgrade to Pro',
        icon: Symbols.workspace_premium_rounded,
        expand: true,
      ),
    );
  }

  Widget _buildRestorePurchasesButton(PremiumState premiumState) {
    return _buildActionRow(
      icon: Symbols.restore_rounded,
      title: 'Restore Purchases',
      first: true,
      onTap: () => _restorePurchases(),
    );
  }

  Widget _buildPurchaseHistoryButton(PremiumState premiumState) {
    return _buildActionRow(
      icon: Symbols.history_rounded,
      title: 'Purchase History',
      onTap: () => _showPurchaseHistory(),
    );
  }

  Widget _buildCosmeticsButton(PremiumState premiumState) {
    final cs = context.cs;
    return _buildActionRow(
      icon: Symbols.rocket_rounded,
      title: 'Ship Cosmetics',
      onTap: () => _openCosmeticsSelector(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (premiumState.ownedSkins.isNotEmpty)
            CsChip('${premiumState.ownedSkins.length} owned'),
          SizedBox(width: cs(8)),
          Icon(Symbols.chevron_right_rounded, size: cs(20), color: CsColors.ink45),
        ],
      ),
    );
  }

  Widget _buildBattlePassButton(PremiumState premiumState) {
    final cs = context.cs;
    return _buildActionRow(
      icon: Symbols.military_tech_rounded,
      iconColor: CsColors.violet,
      title: 'Battle Pass',
      onTap: () => _openBattlePass(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TIER ${premiumState.battlePassTier}',
            style: cs.type.mono(10, color: CsColors.violet),
          ),
          SizedBox(width: cs(8)),
          Icon(Symbols.chevron_right_rounded, size: cs(20), color: CsColors.ink45),
        ],
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
      showCsToast(context, 'Restoring purchases...', icon: Symbols.restore_rounded);

      final purchaseService = PurchaseService();
      await purchaseService.restorePurchases();

      if (mounted) {
        // Results arrive asynchronously on the purchase stream — this only
        // confirms the restore REQUEST went through, not that items landed.
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
    }
  }

  void _showPurchaseHistory() async {
    try {
      final premiumCubit = context.read<PremiumCubit>();
      final history = await premiumCubit.getPurchaseHistory();

      if (!mounted) return;

      showCsDialog<void>(
        context,
        builder: (context) {
          final cs = context.cs;
          return CsDialog(
            eyebrow: 'Premium',
            title: 'Purchase History',
            content: SizedBox(
              height: cs(220),
              child: history.isEmpty
                  ? const CsEmptyState(
                      icon: Symbols.receipt_long_rounded,
                      title: 'No purchases found',
                      compact: true,
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

                          return CsListRow(
                            dividerTop: index == 0,
                            leading: CsIconDisc(
                              _getPurchaseIcon(_getTypeFromProductId(productId)),
                              size: 34,
                            ),
                            title: _formatProductName(productId),
                            subtitle:
                                'Status: $status · Date: ${_formatDate(transactionDate)}',
                          );
                        } catch (e) {
                          return CsListRow(
                            dividerTop: index == 0,
                            title: 'Purchase #${index + 1}',
                            subtitle: 'Data parsing error',
                          );
                        }
                      },
                    ),
            ),
            actions: [
              CsButton.secondary(
                label: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        showCsToast(
          context,
          'Failed to load purchase history',
          kind: CsToastKind.error,
        );
      }
    }
  }

  IconData _getPurchaseIcon(String type) {
    switch (type) {
      case 'subscription':
        return Symbols.star_rounded;
      case 'theme':
        return Symbols.palette_rounded;
      case 'skin':
        return Symbols.rocket_rounded;
      case 'trail':
        return Symbols.auto_awesome_rounded;
      case 'bundle':
        return Symbols.shopping_bag_rounded;
      case 'battlepass':
        return Symbols.emoji_events_rounded;
      case 'tournament':
        return Symbols.sports_esports_rounded;
      default:
        return Symbols.shopping_cart_rounded;
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

/// Category-list item (as on the store): 7% white fill + gold icon when
/// selected, quiet ink otherwise. ≥44dp tall.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return CsPressable(
      onTap: onTap,
      scale: 0.98,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: CsMotion.base,
        curve: CsMotion.standard,
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.symmetric(horizontal: cs(14), vertical: cs(9)),
        decoration: BoxDecoration(
          color: selected ? CsColors.fill07 : Colors.transparent,
          borderRadius: BorderRadius.circular(CsRadius.tile),
        ),
        child: Row(
          children: [
            Icon(icon, size: cs(20), color: selected ? CsColors.gold : CsColors.ink45),
            SizedBox(width: cs(14)),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cs.type.display(
                  15,
                  weight: selected ? FontWeight.w700 : FontWeight.w600,
                  em: 0,
                  color: selected ? CsColors.ink : CsColors.ink60,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings row: hairline-separated, leading glyph, title, unclamped
/// subtitle (settings copy is the documentation — never truncate it),
/// optional extra content [below], trailing control.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.below,
    this.first = false,
    this.iconColor = CsColors.ink70,
    this.titleColor,
    this.subtitleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? below;
  final bool first;
  final Color iconColor;
  final Color? titleColor;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: EdgeInsets.symmetric(vertical: cs(11), horizontal: cs(2)),
      decoration: BoxDecoration(
        border: Border(
          top: first ? const BorderSide(color: CsColors.hairline) : BorderSide.none,
          bottom: const BorderSide(color: CsColors.hairline),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: cs(20), color: iconColor),
          SizedBox(width: cs(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleColor == null ? t.rowTitle : t.rowTitle.copyWith(color: titleColor),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: cs(3)),
                  Text(
                    subtitle!,
                    style: subtitleColor == null ? t.body : t.body.copyWith(color: subtitleColor),
                  ),
                ],
                if (below != null) ...[SizedBox(height: cs(8)), below!],
              ],
            ),
          ),
          if (trailing != null) ...[SizedBox(width: cs(14)), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return CsPressable(onTap: onTap, scale: 0.99, semanticLabel: title, child: row);
  }
}

/// Small preview of a gameplay colour theme: its background fill with the
/// ship + pickup colours as dots. Reads [GameTheme] purely as data.
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme});
  final GameTheme theme;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      width: cs(44),
      height: cs(28),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(cs(8)),
        border: Border.all(color: CsColors.lineSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Container(
            width: cs(10),
            height: cs(10),
            decoration: BoxDecoration(color: theme.shipColor, borderRadius: BorderRadius.circular(2)),
          ),
          Container(
            width: cs(7),
            height: cs(7),
            decoration: BoxDecoration(color: theme.foodColor, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}
