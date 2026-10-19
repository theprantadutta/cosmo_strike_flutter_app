import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/models/achievement.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/number_format.dart';
import 'package:cosmo_strike_flutter_app/widgets/account_upgrade_sheet.dart';
import 'package:cosmo_strike_flutter_app/widgets/player_progression.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AppDataCache _appCache;

  @override
  void initState() {
    super.initState();
    _appCache = getIt<AppDataCache>();
    // Trigger background refresh for fresh data (non-blocking)
    _appCache.refreshInBackground();

    // Edge case: if the screen is opened while already unauthenticated
    // (token expired, race during nav), the BlocListener won't fire because
    // there's no state transition. Schedule a redirect for the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authState = context.read<AuthCubit>().state;
      if (authState.status == AuthStatus.unauthenticated) {
        context.go(AppRoutes.firstTimeAuth);
      }
    });
  }

  // Convenience getters using cached data
  Map<String, dynamic> get _displayStats => _appCache.statistics ?? {};

  /// An integer stat with thousand separators ("121,360"), matching Ranks.
  String _num(String key) {
    final v = _displayStats[key];
    return v is num ? formatThousands(v.round()) : '${v ?? 0}';
  }
  List<Achievement> get _recentAchievements => _appCache.recentAchievements ?? [];
  bool get _isLoading => !_appCache.isFullyLoaded;

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    // BlocListener routes the user to the sign-in screen as soon as they
    // become unauthenticated (i.e. after a successful sign-out). This is the
    // sole place the redirect happens — the build path below is responsible
    // for the loader UI during the transition itself.
    return BlocListener<AuthCubit, AuthState>(
      listenWhen: (previous, current) =>
          current.status == AuthStatus.unauthenticated &&
          previous.status != AuthStatus.unauthenticated,
      listener: (context, state) {
        if (mounted) {
          // .go (not .push) so the back stack doesn't preserve the stale
          // profile screen behind the auth screen.
          context.go(AppRoutes.firstTimeAuth);
        }
      },
      // Subscribe to AppDataCache so a post-game refreshStatistics() call
      // rebuilds the stat grid with the updated high score / totals.
      child: ListenableBuilder(
        listenable: _appCache,
        builder: (context, _) => BlocBuilder<AuthCubit, AuthState>(
          builder: (context, authState) {
            return CsScaffold(
              title: 'Profile',
              washes: const [CsWash.violetTopRight],
              trailing: [
                if (authState.isSignedIn && !authState.isLoading)
                  CsMeta(_accountType(authState), icon: _accountIcon(authState)),
              ],
              body: _buildBody(context, authState, themeState),
            );
          },
        ),
      ),
    );
  }

  /// Pick the right body view for the current auth state. Loading takes
  /// priority over content so we never render a half-rendered profile
  /// (with stale name/badge/sections) while sign-out is in flight.
  Widget _buildBody(BuildContext context, AuthState authState, ThemeState themeState) {
    if (authState.isLoading) {
      return const CsLoadingState(label: 'Signing out');
    }
    if (authState.isSignedIn) {
      return CsSplit(
        left: _buildIdentity(context, authState, themeState),
        right: _buildSections(context, authState),
      );
    }
    // Unauthenticated and not loading — the BlocListener will navigate us
    // away on the next frame; show a clean loader meanwhile.
    return const CsLoadingState();
  }

  String _accountType(AuthState a) {
    if (a.isAnonymous || a.isGuestUser) return 'Guest';
    // UserType.google covers every signed-in account, so ask Firebase which
    // provider is actually linked (Apple / Google / email+password).
    final providers =
        FirebaseAuth.instance.currentUser?.providerData.map((p) => p.providerId) ?? const <String>[];
    if (providers.contains('apple.com')) return 'Apple';
    if (providers.contains('google.com')) return 'Google';
    if (providers.contains('password')) return 'Email';
    return (a.user?.email?.isNotEmpty ?? false) ? 'Email' : 'Verified';
  }

  IconData _accountIcon(AuthState a) =>
      a.isAnonymous || a.isGuestUser ? Symbols.person_rounded : Symbols.verified_user_rounded;

  // ── LEFT: identity ─────────────────────────────────────────────────────

  Widget _buildIdentity(BuildContext context, AuthState authState, ThemeState themeState) {
    final cs = context.cs;
    final t = cs.type;
    final guest = authState.isAnonymous || authState.isGuestUser;
    return CsFitColumn(
      alignment: Alignment.centerLeft,
      children: [
        _ProfileAvatar(
          name: authState.publicLabel,
          photoUrl: authState.photoURL,
          size: cs.isTablet ? 120 : 104,
        ),
        SizedBox(height: cs(18)),
        // Uses publicLabel so it matches the leaderboard rendering — your
        // profile shows the same name everyone else sees.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            authState.publicLabel,
            maxLines: 1,
            style: t.display(34, em: -0.03, height: 1.05),
          ),
        ),
        SizedBox(height: cs(8)),
        Row(children: [
          Icon(_accountIcon(authState), size: cs(14), color: guest ? CsColors.gold : CsColors.mint),
          SizedBox(width: cs(6)),
          Flexible(
            child: Text(
              guest ? 'GUEST PLAYER' : '${_accountType(authState).toUpperCase()} · VERIFIED ACCOUNT',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.mono(11, color: guest ? CsColors.gold : CsColors.mint),
            ),
          ),
        ]),
        SizedBox(height: cs(22)),
        PlayerProgressionCard(theme: themeState.currentTheme),
      ],
    );
  }

  // ── RIGHT: stats + account + links ─────────────────────────────────────

  Widget _buildSections(BuildContext context, AuthState authState) {
    final cs = context.cs;
    final showUpgrade = authState.isAnonymous && !authState.isGoogleUser;
    return ListView(
      padding: EdgeInsets.only(bottom: cs(12)),
      children: [
        _SectionHeader(
          'Statistics',
          action: _isLoading ? null : CsButton.text(
            label: 'View all',
            size: CsButtonSize.small,
            trailingIcon: Symbols.arrow_forward_rounded,
            onPressed: () => _navigateToStatistics(context),
          ),
        ),
        if (_isLoading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: cs(28)),
            child: const CsLoadingState(label: 'Loading stats'),
          )
        else
          CsStatGrid(
            columns: 3,
            valueSize: 22,
            stats: [
              CsStat(_num('highScore'), 'High score'),
              CsStat(_num('totalGames'), 'Games played'),
              CsStat('${_displayStats['totalPlayTime'] ?? '0s'}', 'Play time'),
              CsStat(_num('averageScore'), 'Average score'),
              CsStat(_num('enemiesKilled'), 'Enemies'),
              CsStat(_num('bossesKilled'), 'Bosses'),
            ],
          ),
        SizedBox(height: cs.groupGap),
        const _SectionHeader('Account'),
        if (showUpgrade)
          CsListRow(
            dividerTop: true,
            leading: const CsIconDisc(Symbols.cloud_upload_rounded, color: CsColors.gold),
            title: 'Save your progress',
            subtitle: 'Sign in to sync across devices',
            trailing: CsButton.primary(
              label: 'Sign in',
              icon: Symbols.login_rounded,
              size: CsButtonSize.small,
              onPressed: () => _handleAccountUpgrade(context),
            ),
            onTap: () => _handleAccountUpgrade(context),
          ),
        CsListRow(
          dividerTop: !showUpgrade,
          leading: const CsIconDisc(Symbols.logout_rounded, color: CsColors.pink),
          title: 'Sign out',
          trailing: _chevron(context),
          onTap: () => _showSignOutDialog(context),
        ),
        SizedBox(height: cs.groupGap),
        const _SectionHeader('Explore'),
        CsListRow(
          dividerTop: true,
          leading: const CsIconDisc(Symbols.monitoring_rounded, color: CsColors.cyan),
          title: 'Statistics',
          subtitle: 'Performance, trends and play patterns',
          trailing: _chevron(context),
          onTap: () => _navigateToStatistics(context),
        ),
        CsListRow(
          leading: const CsIconDisc(Symbols.emoji_events_rounded, color: CsColors.gold),
          title: 'Achievements',
          subtitle: 'Awards, rewards and progress',
          trailing: _chevron(context),
          onTap: () => _navigateToAchievements(context),
        ),
        _buildReplaysRow(context),
        if (_recentAchievements.isNotEmpty) ...[
          SizedBox(height: cs.groupGap),
          _SectionHeader(
            'Recent awards',
            action: CsButton.text(
              label: 'View all',
              size: CsButtonSize.small,
              trailingIcon: Symbols.arrow_forward_rounded,
              onPressed: () => _navigateToAchievements(context),
            ),
          ),
          for (var i = 0; i < _recentAchievements.length; i++)
            _buildAchievementRow(_recentAchievements[i], first: i == 0),
        ],
      ],
    );
  }

  Widget _chevron(BuildContext context) =>
      Icon(Symbols.chevron_right_rounded, size: context.cs(22), color: CsColors.ink45);

  Widget _buildReplaysRow(BuildContext context) {
    final count = (_appCache.replayKeys ?? []).length;
    return CsListRow(
      leading: const CsIconDisc(Symbols.movie_rounded, color: CsColors.violet),
      title: 'Replays',
      subtitle: count == 0 ? 'No replays yet. Play some games!' : '$count replays saved',
      trailing: _chevron(context),
      onTap: () => _navigateToReplays(context),
    );
  }

  String _rarityName(AchievementRarity rarity) => switch (rarity) {
        AchievementRarity.common => 'Common',
        AchievementRarity.rare => 'Rare',
        AchievementRarity.epic => 'Epic',
        AchievementRarity.legendary => 'Legendary',
        AchievementRarity.diamond => 'Diamond',
      };

  Widget _buildAchievementRow(Achievement achievement, {required bool first}) {
    final unlocked = achievement.isUnlocked;
    return CsListRow(
      dividerTop: first,
      leading: CsIconDisc(achievement.icon, color: unlocked ? CsColors.gold : CsColors.ink30),
      title: achievement.title,
      subtitle: achievement.description,
      trailing: CsChip(
        _rarityName(achievement.rarity),
        kind: achievement.rarity == AchievementRarity.legendary ||
                achievement.rarity == AchievementRarity.diamond
            ? CsChipKind.gold
            : CsChipKind.outline,
      ),
      onTap: () => _navigateToAchievements(context),
    );
  }

  void _navigateToStatistics(BuildContext context) {
    context.push(AppRoutes.statistics);
  }

  void _navigateToAchievements(BuildContext context) {
    context.push(AppRoutes.achievements);
  }

  void _navigateToReplays(BuildContext context) {
    context.push(AppRoutes.replays);
  }

  /// Offers every sign-in option (Apple on iOS, Google, email) via the
  /// shared account dialog, which links Firebase-anonymous users in place.
  Future<void> _handleAccountUpgrade(BuildContext context) async {
    await showAccountUpgradeSheet(
      context,
      reason: AccountUpgradeReason.saveProgress,
    );
  }

  Future<void> _showSignOutDialog(BuildContext context) async {
    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Account',
      title: 'Sign out?',
      message: 'Are you sure you want to sign out?\n\n'
          'Your progress will be saved if you\'re signed in.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final authCubit = context.read<AuthCubit>();
    await authCubit.signOut();
    if (context.mounted) {
      showCsToast(context, 'Signed out successfully');
    }
  }
}

/// Mono section label with an optional right-aligned action.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {this.action});
  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(children: [
        Expanded(child: CsLabel(label)),
        ?action,
      ]),
    );
  }
}

/// Large prism avatar that falls back to initials when the network photo
/// fails (CsAvatarRing has no error fallback for images).
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.name, required this.photoUrl, required this.size});
  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (photoUrl == null) {
      return CsAvatarRing(name: name, size: size, rotate: true);
    }
    final cs = context.cs;
    final d = cs(size);
    return SizedBox.square(
      dimension: d,
      child: CsPrismRing(
        circle: true,
        rotate: true,
        fill: CsColors.raised,
        child: ClipOval(
          child: Image.network(
            photoUrl!,
            fit: BoxFit.cover,
            width: d,
            height: d,
            errorBuilder: (_, _, _) => Center(
              child: Text(
                CsAvatarRing.initialsOf(name),
                style: cs.type.display(size * 0.32, weight: FontWeight.w700, em: 0.02, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
