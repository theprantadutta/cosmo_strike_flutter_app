import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/models/user_profile.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/app_data_cache.dart';
import 'package:cosmo_strike_flutter_app/services/social_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

class FriendsLeaderboardScreen extends StatefulWidget {
  const FriendsLeaderboardScreen({super.key});

  @override
  State<FriendsLeaderboardScreen> createState() => _FriendsLeaderboardScreenState();
}

class _FriendsLeaderboardScreenState extends State<FriendsLeaderboardScreen> {
  final SocialService _socialService = SocialService();
  final AppDataCache _appCache = AppDataCache();
  List<UserProfile> _leaderboard = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeLeaderboard();
  }

  void _initializeLeaderboard() {
    // Check cache first - use preloaded friends list sorted by high score
    if (_appCache.isFullyLoaded && _appCache.friendsList != null && _appCache.friendsList!.isNotEmpty) {
      // Sort friends by high score for leaderboard display
      final sortedFriends = List<UserProfile>.from(_appCache.friendsList!);
      sortedFriends.sort((a, b) => b.highScore.compareTo(a.highScore));

      setState(() {
        _leaderboard = sortedFriends;
        _isLoading = false;
      });

      // Refresh in background for latest data
      _refreshInBackground();
    } else {
      // No cache - load normally
      _loadLeaderboard();
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      final leaderboard = await _socialService.getFriendsLeaderboard();
      if (mounted) {
        setState(() {
          _leaderboard = leaderboard;
        });
      }
    } catch (_) {
      // Ignore errors in background refresh
    }
  }

  Future<void> _loadLeaderboard() async {
    setState(() => _isLoading = true);

    try {
      final leaderboard = await _socialService.getFriendsLeaderboard();
      if (mounted) {
        setState(() {
          _leaderboard = leaderboard;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthCubit>().state;
    final currentUid = authState.isSignedIn ? authState.userId : null;
    final cs = context.cs;

    return CsScaffold(
      title: 'Squadron Standings',
      trailing: [
        CsIconButton(
          icon: Symbols.refresh_rounded,
          size: 36,
          bordered: false,
          color: CsColors.ink60,
          tooltip: 'Refresh',
          onPressed: _loadLeaderboard,
        ),
      ],
      body: CsSplit(
        // Inline banner in the summary column (no full-width banners).
        leftFooter: ColumnBannerAd(maxHeight: context.cs.isTablet ? 100 : 60),
        leftWidth: 270,
        gap: cs(40),
        left: _SideColumn(children: _buildLeft(currentUid)),
        right: _isLoading
            ? const CsLoadingState(label: 'Loading standings')
            : _buildLeaderboard(currentUid),
      ),
    );
  }

  List<Widget> _buildLeft(String? currentUid) {
    final cs = context.cs;
    final t = cs.type;
    final index = currentUid == null ? -1 : _leaderboard.indexWhere((u) => u.uid == currentUid);

    final Widget hero;
    if (index >= 0) {
      final rank = index + 1;
      final top = math.max(1, (rank / _leaderboard.length * 100).ceil());
      hero = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const CsLabel('Your rank'),
        SizedBox(height: cs(4)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CsPrismText('#$rank', style: t.scoreGiant.copyWith(height: 1.05)),
        ),
        SizedBox(height: cs(6)),
        Text(
          '${_formatThousands(_leaderboard[index].highScore)} PTS · TOP $top%',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.mono(12, em: 0.06, color: CsColors.ink60),
        ),
      ]);
    } else {
      hero = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const CsLabel('Wingmates'),
        SizedBox(height: cs(4)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _isLoading ? '—' : '${_leaderboard.length}',
            style: t.scoreGiant.copyWith(height: 1.05, color: _leaderboard.isEmpty ? CsColors.ink25 : CsColors.ink),
          ),
        ),
        SizedBox(height: cs(6)),
        Text(
          _leaderboard.length == 1 ? 'PILOT RANKED' : 'PILOTS RANKED',
          maxLines: 1,
          style: t.mono(12, em: 0.06, color: CsColors.ink60),
        ),
      ]);
    }

    return [
      Text('Outfly your squadron', style: t.display(26, em: -0.03, height: 1.05)),
      SizedBox(height: cs(22)),
      hero,
      SizedBox(height: cs(22)),
      Text(
        'Best single run, all time.',
        style: t.display(12, weight: FontWeight.w400, em: 0, height: 1.4, color: CsColors.ink45),
      ),
      const Spacer(),
      SizedBox(height: cs(16)),
      CsButton.secondary(
        label: 'Add wingmates',
        icon: Symbols.person_add_rounded,
        size: CsButtonSize.small,
        onPressed: () => context.push(AppRoutes.friends),
      ),
    ];
  }

  Widget _buildLeaderboard(String? currentUid) {
    if (_leaderboard.isEmpty) {
      return CsEmptyState(
        icon: Symbols.group_rounded,
        title: 'No wingmates yet',
        message: 'Add wingmates to open your squadron board.',
        action: CsButton.primary(
          label: 'Add wingmates',
          icon: Symbols.person_add_rounded,
          onPressed: () => context.push(AppRoutes.friends),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _leaderboard.length,
      itemBuilder: (context, index) {
        final user = _leaderboard[index];
        return _RankRow(
          rank: index + 1,
          name: user.publicLabel,
          photoUrl: user.photoUrl,
          games: _formatGames(user.totalGamesPlayed),
          status: user.status,
          score: _formatThousands(user.highScore),
          isYou: currentUid != null && user.uid == currentUid,
        );
      },
    );
  }

  String _formatGames(int count) => count == 1 ? '1 RUN' : '${_formatThousands(count)} RUNS';

  String _formatThousands(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

/// One leaderboard row: 0N mono rank · ringed avatar · name (+ YOU chip)
/// over runs + presence · Syne score.
class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.name,
    required this.games,
    required this.status,
    required this.score,
    this.photoUrl,
    this.isYou = false,
  });

  final int rank;
  final String name;
  final String games;
  final UserStatus status;
  final String score;
  final String? photoUrl;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final statusColor = switch (status) {
      UserStatus.online => CsColors.mint,
      UserStatus.playing => CsColors.cyan,
      UserStatus.offline => CsColors.ink45,
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: EdgeInsets.symmetric(vertical: cs(12), horizontal: cs(4)),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CsColors.hairline))),
      child: Row(children: [
        SizedBox(
          width: cs(34),
          child: Text(
            rank.toString().padLeft(2, '0'),
            maxLines: 1,
            style: t.mono(13, em: 0.04, color: isYou ? CsColors.ink : CsColors.ink55),
          ),
        ),
        _Avatar(name: name, photoUrl: photoUrl, ring: _ringFor(rank, isYou), size: 40),
        SizedBox(width: cs(16)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle)),
              if (isYou) ...[SizedBox(width: cs(8)), const CsChip('You', kind: CsChipKind.solid)],
            ]),
            SizedBox(height: cs(2)),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: games),
                const TextSpan(text: '  ·  '),
                TextSpan(text: status.displayName.toUpperCase(), style: TextStyle(color: statusColor)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.mono(10, color: CsColors.ink45),
            ),
          ]),
        ),
        SizedBox(width: cs(12)),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cs(140)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(score, maxLines: 1, style: t.display(20, em: -0.01)),
          ),
        ),
      ]),
    );
  }
}

/// Ring colours: you = prism, #1 gold, #2 silver, #3 bronze, others faint.
List<Color>? _ringFor(int rank, bool isYou) {
  if (isYou) return null;
  return switch (rank) {
    1 => const [CsColors.gold],
    2 => const [CsColors.rank2],
    3 => const [CsColors.rank3],
    _ => const [Color(0x26FFFFFF)],
  };
}

/// Like [CsAvatarRing] but takes a network URL (falls back to initials when
/// it is missing or fails to load) and any ring colour (null = prism).
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.photoUrl, this.ring, this.size = 40});

  final String name;
  final String? photoUrl;
  final List<Color>? ring;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final d = cs(size);
    final initials = Center(
      child: Text(
        CsAvatarRing.initialsOf(name),
        style: cs.type.display(size * 0.32, weight: FontWeight.w700, em: 0.02, height: 1),
      ),
    );
    return SizedBox.square(
      dimension: d,
      child: CsPrismRing(
        circle: true,
        fill: CsColors.raised,
        colors: ring,
        child: ClipOval(
          child: photoUrl == null
              ? initials
              : Image.network(photoUrl!, fit: BoxFit.cover, width: d, height: d, errorBuilder: (_, _, _) => initials),
        ),
      ),
    );
  }
}

/// Side summary column that fills the available height (so `Spacer`s can
/// push content apart on tall tablets) and scales DOWN instead of
/// overflowing on short phones.
class _SideColumn extends StatelessWidget {
  const _SideColumn({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth, maxWidth: c.maxWidth, minHeight: c.maxHeight),
          child: IntrinsicHeight(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      );
    });
  }
}
