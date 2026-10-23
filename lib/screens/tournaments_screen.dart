import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/providers/tournaments_provider.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart' show GameMode;

enum _Tab { active, history, stats }

class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  _Tab _tab = _Tab.active;

  Future<void> _loadData() async {
    await ref.read(tournamentsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tournamentsState = ref.watch(tournamentsProvider);
    final cs = context.cs;

    return CsScaffold(
      title: 'Sector Cups',
      trailing: [
        if (tournamentsState.isOffline)
          const CsMeta('Offline', icon: Symbols.cloud_off_rounded),
        Flexible(
          child: CsPressable(
            semanticLabel: 'Refresh',
            onTap: () => ref.read(tournamentsProvider.notifier).refresh(),
            child: SizedBox(height: 44, child: Center(child: CsMeta(_freshnessLabel(tournamentsState)))),
          ),
        ),
        CsIconButton(
          icon: Symbols.refresh_rounded,
          size: 36,
          bordered: false,
          color: CsColors.ink60,
          tooltip: 'Refresh',
          onPressed: _loadData,
        ),
      ],
      body: CsSplit(
        // Inline banner in the summary column (no full-width banners).
        leftFooter: ColumnBannerAd(maxHeight: context.cs.isTablet ? 100 : 60),
        leftWidth: 270,
        gap: cs(40),
        left: _SideColumn(children: _buildLeft(tournamentsState)),
        right: tournamentsState.isLoading
            ? const CsLoadingState(label: 'Loading Cups')
            : AnimatedSwitcher(
                duration: CsMotion.base,
                switchInCurve: CsMotion.standard,
                child: KeyedSubtree(
                  key: ValueKey(_tab),
                  child: switch (_tab) {
                    _Tab.active => _buildActiveTournaments(tournamentsState.activeTournaments),
                    _Tab.history => _buildTournamentHistory(tournamentsState.historyTournaments),
                    _Tab.stats => _buildUserStats(tournamentsState.userStats),
                  },
                ),
              ),
      ),
    );
  }

  /// How stale the Drift cache for the active tab is. My Stats has no cache
  /// of its own — fall back to whichever list was most recently refreshed.
  String _freshnessLabel(TournamentsState state) {
    final ts = switch (_tab) {
      _Tab.active => state.activeLastRefreshedAt,
      _Tab.history => state.historyLastRefreshedAt,
      _Tab.stats => state.activeLastRefreshedAt ?? state.historyLastRefreshedAt,
    };
    return ts == null ? 'No cache yet' : 'Updated ${_relativeAge(ts)}';
  }

  String _relativeAge(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  List<Widget> _buildLeft(TournamentsState state) {
    final cs = context.cs;
    final t = cs.type;
    final live = state.activeTournaments.where((e) => e.status == TournamentStatus.active).toList();
    final upcoming = state.activeTournaments.where((e) => e.status == TournamentStatus.upcoming).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final endingSoon = [...live]..sort((a, b) => a.endDate.compareTo(b.endDate));
    final next = upcoming.isNotEmpty ? upcoming.first : (endingSoon.isNotEmpty ? endingSoon.first : null);

    return [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: CsSegmented<_Tab>(
          segments: const {_Tab.active: 'Active', _Tab.history: 'History', _Tab.stats: 'My stats'},
          selected: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
      ),
      SizedBox(height: cs(22)),
      const CsLabel('Live now'),
      SizedBox(height: cs(4)),
      Text(
        state.isLoading && state.activeTournaments.isEmpty ? '—' : '${live.length}',
        maxLines: 1,
        style: t.scoreGiant.copyWith(height: 1.05, color: live.isEmpty ? CsColors.ink25 : CsColors.ink),
      ),
      SizedBox(height: cs(6)),
      Text(
        live.length == 1 ? 'CUP LIVE' : 'CUPS LIVE',
        style: t.mono(12, em: 0.06, color: CsColors.ink60),
      ),
      if (next != null) ...[
        SizedBox(height: cs(22)),
        CsLabel(next.status == TournamentStatus.upcoming ? 'Next Cup opens in' : 'Next Cup closes in'),
        SizedBox(height: cs(6)),
        _Ticking(
          builder: (_) => Text(
            next.timeRemainingFormatted.toUpperCase(),
            maxLines: 1,
            style: t.display(24, em: -0.01, height: 1.1, color: CsColors.cyan),
          ),
        ),
        SizedBox(height: cs(4)),
        Text(next.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.mono(11, color: CsColors.ink55)),
      ],
      const Spacer(),
      if (state.error != null) ...[
        SizedBox(height: cs(14)),
        Text(
          state.error!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.mono(10, color: CsColors.pink, em: 0.04),
        ),
      ],
    ];
  }

  Widget _buildActiveTournaments(List<Tournament> activeTournaments) {
    if (activeTournaments.isEmpty) {
      return const CsEmptyState(
        icon: Symbols.military_tech_rounded,
        title: 'No Cups live',
        message: 'Next Cup posts soon. Stand by.',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: activeTournaments.length,
      itemBuilder: (context, index) {
        final tournament = activeTournaments[index];
        return _EventRow(tournament: tournament, onTap: () => _openTournamentDetail(tournament));
      },
    );
  }

  Widget _buildTournamentHistory(List<Tournament> historyTournaments) {
    if (historyTournaments.isEmpty) {
      return const CsEmptyState(
        icon: Symbols.history_rounded,
        title: 'No Cup record',
        message: 'Enter a Cup to log your results here.',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: historyTournaments.length,
      itemBuilder: (context, index) {
        final tournament = historyTournaments[index];
        return _EventRow(
          tournament: tournament,
          showResults: true,
          onTap: () => _openTournamentDetail(tournament),
        );
      },
    );
  }

  Widget _buildUserStats(Map<String, dynamic> userStats) {
    if (userStats.isEmpty) {
      return const CsEmptyState(
        icon: Symbols.bar_chart_rounded,
        title: 'No Cup stats',
        message: 'Enter a Cup to start tracking.',
      );
    }

    final cs = context.cs;
    final t = cs.type;
    final winRate = userStats['winRate'] ?? 0;
    Widget detail(String label, String value) => Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(vertical: cs(10)),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CsColors.hairline))),
          child: Row(children: [
            Expanded(child: Text(label, style: t.body)),
            Text(value, style: t.display(16, weight: FontWeight.w700, em: 0)),
          ]),
        );

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CsLabel('Cup overview'),
        SizedBox(height: cs(8)),
        CsStatGrid(
          columns: cs.isCompact ? 2 : 4,
          valueSize: 28,
          stats: [
            CsStat('${userStats['totalTournaments'] ?? 0}', 'Cups'),
            CsStat('${userStats['wins'] ?? 0}', 'Wins', color: CsColors.gold),
            CsStat('${userStats['topThreeFinishes'] ?? 0}', 'Top 3 finishes'),
            CsStat('${userStats['bestScore'] ?? 0}', 'Best score', color: CsColors.cyan),
          ],
        ),
        SizedBox(height: cs(24)),
        const CsLabel('Breakdown'),
        SizedBox(height: cs(4)),
        detail('Total runs', '${userStats['totalAttempts'] ?? 0}'),
        detail('Win rate', '$winRate%'),
        detail('Average finish', 'Top ${100 - winRate}%'),
      ]),
    );
  }

  void _openTournamentDetail(Tournament tournament) {
    context.push(AppRoutes.tournamentDetailPath(tournament.id), extra: tournament);
  }
}

IconData _typeIcon(TournamentType type) => switch (type) {
      TournamentType.daily => Symbols.today_rounded,
      TournamentType.weekly => Symbols.military_tech_rounded,
      TournamentType.special => Symbols.auto_awesome_rounded,
    };

IconData _modeIcon(GameMode mode) => mode.icon;

Widget _statusChip(TournamentStatus status) => switch (status) {
      TournamentStatus.active => const CsChip('Live', kind: CsChipKind.mint),
      TournamentStatus.upcoming => const CsChip('Upcoming'),
      TournamentStatus.ended => const CsChip('Ended'),
    };

/// One event row: type disc · name + status chip / description / mono meta ·
/// top prize + entry on the right.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.tournament, required this.onTap, this.showResults = false});

  final Tournament tournament;
  final VoidCallback onTap;
  final bool showResults;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final tm = tournament;
    final ended = tm.status == TournamentStatus.ended;
    final topPrize = tm.rewards[1] ?? (tm.rewards.isEmpty ? null : tm.rewards.values.first);
    final meta = t.mono(10, color: CsColors.ink45);

    Widget metaItem(IconData icon, String text, {Color color = CsColors.ink45}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: cs(13), color: color),
            SizedBox(width: cs(4)),
            Text(text.toUpperCase(), maxLines: 1, style: meta.copyWith(color: color)),
          ],
        );

    final reward = tm.userReward;
    return CsPressable(
      onTap: onTap,
      scale: 0.99,
      semanticLabel: tm.name,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: cs(14), horizontal: cs(2)),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CsColors.hairline))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Opacity(
            opacity: ended ? 0.5 : 1,
            child: CsIconDisc(_typeIcon(tm.type), size: 40),
          ),
          SizedBox(width: cs(14)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                // Two lines: long Cup names get
                // cut mid-word on landscape phones at one line.
                Flexible(child: Text(tm.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.rowTitle)),
                SizedBox(width: cs(8)),
                _statusChip(tm.status),
              ]),
              SizedBox(height: cs(2)),
              Text(tm.type.displayName.toUpperCase(), maxLines: 1, style: t.mono(9, color: CsColors.ink45)),
              if (tm.description.isNotEmpty) ...[
                SizedBox(height: cs(6)),
                Text(
                  tm.description,
                  maxLines: cs.isCompact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.body,
                ),
              ],
              SizedBox(height: cs(8)),
              Wrap(spacing: cs(14), runSpacing: cs(6), children: [
                metaItem(_modeIcon(tm.gameMode), tm.gameMode.name),
                metaItem(Symbols.schedule_rounded, tm.timeRemainingFormatted),
                metaItem(Symbols.group_rounded, '${tm.currentParticipants}/${tm.maxParticipants}'),
                if (tm.hasJoined) metaItem(Symbols.check_circle_rounded, 'Joined', color: CsColors.mint),
                if (tm.hasJoined && tm.userBestScore != null)
                  metaItem(Symbols.star_rounded, 'Best ${tm.userBestScore}', color: CsColors.gold),
              ]),
              if (showResults && reward != null) ...[
                SizedBox(height: cs(10)),
                Row(children: [
                  Icon(Symbols.military_tech_rounded, size: cs(16), color: CsColors.gold),
                  SizedBox(width: cs(8)),
                  Flexible(
                    child: Text(
                      'Rank #${tm.userRank} · ${reward.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.display(13, weight: FontWeight.w700, em: 0, color: CsColors.gold),
                    ),
                  ),
                  if (reward.coins > 0) ...[SizedBox(width: cs(10)), CsCoins(reward.coins, prefix: '+')],
                ]),
              ],
            ]),
          ),
          SizedBox(width: cs(14)),
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            if (!showResults && topPrize != null) ...[
              if (topPrize.coins > 0) CsCoins(topPrize.coins, size: 13) else Icon(Symbols.redeem_rounded, size: cs(18), color: CsColors.gold),
              SizedBox(height: cs(3)),
              Text(
                tm.rewards.length > 1 ? '${tm.rewards.length} PRIZES' : 'TOP PRIZE',
                style: t.mono(9, color: CsColors.ink45),
              ),
              SizedBox(height: cs(8)),
            ],
            if (tm.requiresEntry)
              const CsChip('Cup Pass', icon: Symbols.confirmation_number_rounded)
            else
              Text('FREE ENTRY', style: t.mono(9, color: CsColors.ink45)),
            SizedBox(height: cs(6)),
            Icon(Symbols.chevron_right_rounded, size: cs(20), color: CsColors.ink45),
          ]),
        ]),
      ),
    );
  }
}

/// Rebuilds [builder] every second (countdowns).
class _Ticking extends StatefulWidget {
  const _Ticking({required this.builder});
  final WidgetBuilder builder;

  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
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
