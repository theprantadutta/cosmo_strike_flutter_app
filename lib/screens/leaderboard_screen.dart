import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/providers/leaderboard_provider.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:cosmo_strike_flutter_app/utils/number_format.dart';

/// The boards on this screen. [friends] is not a local board: it opens the
/// dedicated friends leaderboard screen.
enum _Board { global, weekly, friends }

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  _Board _board = _Board.global;

  @override
  void initState() {
    super.initState();
    // Calculate user rank once data is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateUserRank();
    });
  }

  void _selectBoard(_Board board) {
    if (board == _Board.friends) {
      context.push(AppRoutes.friendsLeaderboard);
      return;
    }
    if (board == _board) return;
    setState(() => _board = board);
    getIt<AnalyticsFacade>().trackLeaderboardViewed(board == _Board.weekly ? 'weekly' : 'global');
  }

  void _calculateUserRank() {
    final authState = context.read<AuthCubit>().state;
    if (!authState.isSignedIn || authState.userId == null) return;
    ref.read(combinedLeaderboardProvider.notifier).calculateUserRankFor(authState.userId);
  }

  Future<void> _loadGlobalLeaderboard() async {
    await ref.read(combinedLeaderboardProvider.notifier).refresh();
    _calculateUserRank();
  }

  Future<void> _loadWeeklyLeaderboard() async {
    await ref.read(combinedLeaderboardProvider.notifier).refresh();
  }

  bool get _weekly => _board == _Board.weekly;

  @override
  Widget build(BuildContext context) {
    final leaderboardState = ref.watch(combinedLeaderboardProvider);
    final authState = context.watch<AuthCubit>().state;

    // Update user rank when global leaderboard loads
    ref.listen<CombinedLeaderboardState>(combinedLeaderboardProvider, (prev, next) {
      if (prev?.isLoadingGlobal == true && next.isLoadingGlobal == false) {
        _calculateUserRank();
      }
    });

    final cs = context.cs;
    return CsScaffold(
      title: 'Standings',
      trailing: [
        ?_freshness(leaderboardState),
        CsIconButton(
          icon: Symbols.refresh_rounded,
          size: 36,
          bordered: false,
          color: CsColors.ink60,
          tooltip: 'Refresh',
          onPressed: _weekly ? _loadWeeklyLeaderboard : _loadGlobalLeaderboard,
        ),
      ],
      body: CsSplit(
        // Inline banner in the summary column (no full-width banners).
        leftFooter: ColumnBannerAd(maxHeight: context.cs.isTablet ? 100 : 60),
        leftWidth: 270,
        gap: cs(40),
        left: _SideColumn(children: _buildLeft(authState, leaderboardState)),
        right: AnimatedSwitcher(
          duration: CsMotion.base,
          switchInCurve: CsMotion.standard,
          child: KeyedSubtree(
            key: ValueKey(_board),
            child: _weekly
                ? _buildWeeklyLeaderboard(authState, leaderboardState)
                : _buildGlobalLeaderboard(authState, leaderboardState),
          ),
        ),
      ),
    );
  }

  /// "UPDATED 3M AGO" for the active board — the Drift cache survives
  /// offline launches, so this tells the player whether the list is stale.
  /// Tap forces a refresh. Hidden until the cache has ever been populated.
  Widget? _freshness(CombinedLeaderboardState state) {
    final ts = _weekly ? state.weeklyLastRefreshedAt : state.globalLastRefreshedAt;
    final hasData = _weekly ? state.weeklyEntries.isNotEmpty : state.globalEntries.isNotEmpty;
    if (ts == null && !hasData) return null;
    final label = ts == null ? 'No cache yet' : 'Updated ${_relativeAge(ts)}';
    return Flexible(
      child: CsPressable(
        semanticLabel: '$label. Tap to refresh',
        onTap: () => ref.read(combinedLeaderboardProvider.notifier).refresh(),
        child: SizedBox(height: 44, child: Center(child: CsMeta(label))),
      ),
    );
  }

  String _relativeAge(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  List<Widget> _buildLeft(AuthState authState, CombinedLeaderboardState state) {
    final cs = context.cs;
    final t = cs.type;
    final entries = _weekly ? state.weeklyEntries : state.globalEntries;
    final uid = authState.isSignedIn ? authState.userId : null;
    final index = uid == null ? -1 : entries.indexWhere((e) => e['uid'] == uid);

    final Widget rankBlock;
    if (index >= 0) {
      final rank = index + 1;
      final score = (entries[index]['highScore'] ?? 0) as int;
      final top = math.max(1, (rank / entries.length * 100).ceil());
      rankBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const CsLabel('Your rank'),
        SizedBox(height: cs(4)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CsPrismText('#$rank', style: t.scoreGiant.copyWith(height: 1.05)),
        ),
        SizedBox(height: cs(6)),
        Text(
          '${formatThousands(score)} PTS · TOP $top%',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.mono(12, em: 0.06, color: CsColors.ink60),
        ),
      ]);
    } else {
      rankBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const CsLabel('Your rank'),
        SizedBox(height: cs(4)),
        Text('#—', style: t.scoreGiant.copyWith(height: 1.05, color: CsColors.ink25)),
        SizedBox(height: cs(6)),
        Text(
          authState.isSignedIn ? 'NOT POSTED ON THIS BOARD' : 'SIGN IN TO POST A SCORE',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.mono(12, em: 0.06, color: CsColors.ink45),
        ),
      ]);
    }

    // What the active board ranks by. Mirrors the backend handlers: global =
    // lifetime max single-run score; weekly = scores since Sunday.
    final caption = _weekly
        ? 'Best single run this week. Board resets Sunday.'
        : 'Best single run, all time.';

    return [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: CsSegmented<_Board>(
          segments: const {_Board.global: 'Global', _Board.weekly: 'Weekly', _Board.friends: 'Squadron'},
          selected: _board,
          onChanged: _selectBoard,
        ),
      ),
      SizedBox(height: cs(22)),
      rankBlock,
      SizedBox(height: cs(22)),
      Text(caption, style: t.display(12, weight: FontWeight.w400, em: 0, height: 1.4, color: CsColors.ink45)),
      const Spacer(),
    ];
  }

  Widget _buildGlobalLeaderboard(AuthState authState, CombinedLeaderboardState state) {
    if (state.isLoadingGlobal) {
      return const CsLoadingState(label: 'Loading global standings');
    }
    if (state.globalError != null) {
      return CsEmptyState.error(
        title: "Couldn't load standings",
        message: state.globalError,
        action: CsButton.secondary(label: 'Retry', icon: Symbols.refresh_rounded, onPressed: _loadGlobalLeaderboard),
      );
    }
    if (state.globalEntries.isEmpty) {
      return const CsEmptyState(
        icon: Symbols.emoji_events_rounded,
        title: 'Board is empty',
        message: 'Post the first score.',
      );
    }
    return _buildList(state.globalEntries, authState, _loadGlobalLeaderboard);
  }

  Widget _buildWeeklyLeaderboard(AuthState authState, CombinedLeaderboardState state) {
    if (state.isLoadingWeekly) {
      return const CsLoadingState(label: 'Loading weekly standings');
    }
    if (state.weeklyError != null) {
      return CsEmptyState.error(
        title: "Couldn't load standings",
        message: state.weeklyError,
        action: CsButton.secondary(label: 'Retry', icon: Symbols.refresh_rounded, onPressed: _loadWeeklyLeaderboard),
      );
    }
    if (state.weeklyEntries.isEmpty) {
      return const CsEmptyState(
        icon: Symbols.calendar_today_rounded,
        title: 'No runs logged this week',
        message: 'Fly a run to post on this board.',
      );
    }
    return _buildList(state.weeklyEntries, authState, _loadWeeklyLeaderboard);
  }

  Widget _buildList(List<Map<String, dynamic>> entries, AuthState authState, Future<void> Function() onRefresh) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: CsColors.ink,
      backgroundColor: CsColors.raised,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final player = entries[index];
          final isCurrentUser =
              authState.isSignedIn && authState.userId != null && player['uid'] == authState.userId;
          // Prefer the stable username over the display name, which can be
          // missing for anonymous users and changes with the Google profile.
          final name = (player['username'] ?? player['displayName'] ?? 'Unknown pilot') as String;
          return _RankRow(
            rank: index + 1,
            name: name,
            photoUrl: player['photoURL'] as String?,
            subtitle: _formatRuns((player['totalGamesPlayed'] ?? 0) as int),
            score: formatThousands((player['highScore'] ?? 0) as int),
            isYou: isCurrentUser,
            isGuest: player['isAnonymous'] == true,
          );
        },
      ),
    );
  }

  String _formatRuns(int count) => count == 1 ? '1 RUN' : '${formatThousands(count)} RUNS';
}

/// One leaderboard row: 0N mono rank · ringed avatar · name (+ YOU / GUEST
/// chips) over a mono caption · Syne score.
class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.name,
    required this.subtitle,
    required this.score,
    this.photoUrl,
    this.isYou = false,
    this.isGuest = false,
  });

  final int rank;
  final String name;
  final String subtitle;
  final String score;
  final String? photoUrl;
  final bool isYou;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
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
              if (isGuest) ...[SizedBox(width: cs(8)), const CsChip('Guest')],
              if (isYou) ...[SizedBox(width: cs(8)), const CsChip('You', kind: CsChipKind.solid)],
            ]),
            SizedBox(height: cs(2)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.mono(10, color: CsColors.ink45)),
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
              : Image.network(
                  photoUrl!,
                  fit: BoxFit.cover,
                  width: d,
                  height: d,
                  errorBuilder: (_, _, _) => initials,
                ),
        ),
      ),
    );
  }
}

/// Side summary column that fills the available height (so `Spacer`s can
/// push content apart on tall tablets) and scales DOWN instead of
/// overflowing on short phones. Children must not contain LayoutBuilders or
/// text fields (it measures intrinsic height).
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
