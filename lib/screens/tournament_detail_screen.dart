import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/tournament/tournament_context_cubit.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/tournament_service.dart';
import 'package:cosmo_strike_flutter_app/services/auth_service.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/screens/gameplay_screen.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/reward_toast.dart';

enum _Tab { overview, standings, rules }

class TournamentDetailScreen extends StatefulWidget {
  /// The tournament ID for deep link support.
  final String tournamentId;

  /// Optional tournament object (for instant display when navigating with object).
  final Tournament? tournament;

  const TournamentDetailScreen({
    super.key,
    required this.tournamentId,
    this.tournament,
  });

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  final TournamentService _tournamentService = TournamentService();

  _Tab _tab = _Tab.overview;
  Tournament? _tournament;
  List<TournamentParticipant> _leaderboard = [];
  // Server-authoritative rank for the current user — set from the
  // leaderboard response's current_user_rank. Preferred over the
  // local Tournament.userRank computation, which only sees the 50-item
  // slice and is wrong for users outside the top 50.
  int? _serverUserRank;
  bool _isLoading = false;
  // Distinguishes "leaderboard load actually failed" from "load returned
  // empty list" so the UI can show a retry button instead of pretending
  // the tournament has no participants.
  bool _leaderboardLoadFailed = false;
  bool _isLoadingTournament = false;
  bool _isJoining = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _tournament = widget.tournament;

    if (_tournament != null) {
      // Tournament provided via navigation, load leaderboard
      _loadLeaderboard();
      _maybeClaimPrize();
    } else {
      // Deep link: need to load tournament from service
      _loadTournamentFromId();
    }
  }

  Future<void> _loadTournamentFromId() async {
    setState(() {
      _isLoadingTournament = true;
      _loadError = null;
    });

    try {
      final tournament = await _tournamentService.getTournament(
        widget.tournamentId,
      );
      if (mounted) {
        if (tournament != null) {
          setState(() {
            _tournament = tournament;
            _isLoadingTournament = false;
          });
          _loadLeaderboard();
          _maybeClaimPrize();
        } else {
          setState(() {
            _loadError = 'Tournament not found';
            _isLoadingTournament = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = 'Failed to load tournament';
          _isLoadingTournament = false;
        });
      }
    }
  }

  Future<void> _loadLeaderboard() async {
    if (_tournament == null) return;

    setState(() {
      _isLoading = true;
      _leaderboardLoadFailed = false;
    });

    try {
      final result = await _tournamentService.getTournamentLeaderboard(
        _tournament!.id,
      );
      // Detect "real failure" vs "actually empty": if the tournament
      // says it has participants but we got an empty list back, the
      // fetch must have failed silently in the service layer.
      final isLegitimatelyEmpty =
          result.entries.isEmpty && _tournament!.currentParticipants == 0;
      setState(() {
        _leaderboard = result.entries;
        _serverUserRank = result.userRank;
        _isLoading = false;
        _leaderboardLoadFailed = result.entries.isEmpty && !isLegitimatelyEmpty;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _leaderboardLoadFailed = true;
      });
    }
  }

  Future<void> _refreshTournament() async {
    final tournamentId = _tournament?.id ?? widget.tournamentId;
    final updatedTournament = await _tournamentService.getTournament(
      tournamentId,
    );
    if (updatedTournament != null && mounted) {
      setState(() {
        _tournament = updatedTournament;
      });
      _loadLeaderboard();
      _maybeClaimPrize();
    }
  }

  /// Once per screen, if this is a completed tournament the user joined,
  /// claim the prize. Prizes are server-determined but credited locally
  /// (offline-first coin balance is client-authoritative); the claim is
  /// idempotent server-side, so coins are credited at most once.
  bool _prizeClaimAttempted = false;
  Future<void> _maybeClaimPrize() async {
    if (_prizeClaimAttempted) return;
    final t = _tournament;
    if (t == null || t.status != TournamentStatus.ended || !t.isJoinedServer) {
      return;
    }
    _prizeClaimAttempted = true;
    final coins = await _tournamentService.claimPrize(t.id);
    if (coins > 0 && mounted) {
      showCsToast(
        context,
        'Tournament prize claimed: +$coins coins!',
        kind: CsToastKind.reward,
        icon: Symbols.emoji_events_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CsScaffold(
      title: _tournament == null ? 'Event' : 'Events · ${_tournament!.type.displayName}',
      trailing: [
        if (_tournament != null)
          CsIconButton(
            icon: Symbols.refresh_rounded,
            size: 36,
            bordered: false,
            color: CsColors.ink60,
            tooltip: 'Refresh',
            onPressed: _refreshTournament,
          ),
      ],
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    // Show loading state when fetching tournament from deep link
    if (_isLoadingTournament) {
      return const CsLoadingState(label: 'Loading tournament');
    }

    // Show error state
    if (_loadError != null || _tournament == null) {
      return CsEmptyState.error(
        title: _loadError ?? 'Tournament not found',
        action: CsButton.secondary(
          label: 'Go Back',
          icon: Symbols.arrow_back_rounded,
          onPressed: () => Navigator.of(context).pop(),
        ),
      );
    }

    final cs = context.cs;
    return CsSplit(
      leftWidth: 300,
      gap: cs(40),
      left: _buildLeftPanel(),
      right: AnimatedSwitcher(
        duration: CsMotion.base,
        switchInCurve: CsMotion.standard,
        child: KeyedSubtree(
          key: ValueKey(_tab),
          child: switch (_tab) {
            _Tab.overview => _buildOverviewTab(),
            _Tab.standings => _buildLeaderboardTab(),
            _Tab.rules => _buildRulesTab(),
          },
        ),
      ),
    );
  }

  /// Left region — identity, key facts, your standing and section tabs
  /// (scaled down on short phones, never scrolls), with the one primary
  /// action pinned to the bottom.
  Widget _buildLeftPanel() {
    final tournament = _tournament!;
    final cs = context.cs;
    final t = cs.type;
    final words = tournament.name.trim().split(RegExp(r'\s+'));
    final parts = words.length < 2
        ? [tournament.name]
        : [words.sublist(0, words.length - 1).join(' '), ' ', words.last];
    final rank = (_serverUserRank ?? 0) > 0 ? _serverUserRank! : tournament.userRank;

    final info = <Widget>[
      Wrap(spacing: cs(8), runSpacing: cs(6), children: [
        _statusChip(tournament.status),
        CsChip(tournament.gameMode.displayName, icon: _modeIcon(tournament.gameMode)),
      ]),
      SizedBox(height: cs(12)),
      CsHeadline(
        parts,
        prismIndex: parts.length - 1,
        style: t.display(34, em: -0.03, height: 1.02),
      ),
      SizedBox(height: cs(10)),
      _Ticking(
        builder: (_) => Text(
          '${_timeLabel(tournament)} · ${tournament.currentParticipants}/${tournament.maxParticipants} PLAYERS',
          maxLines: 2,
          style: t.mono(11, em: 0.08, color: CsColors.ink55),
        ),
      ),
      if (tournament.hasJoined) ...[
        SizedBox(height: cs(14)),
        Row(children: [
          Icon(Symbols.check_circle_rounded, size: cs(15), color: CsColors.mint),
          SizedBox(width: cs(6)),
          Text("YOU'RE PARTICIPATING", style: t.mono(10, color: CsColors.mint)),
          // Prefer the server-authoritative rank when we have it; fall back
          // to the local heuristic only as a degraded mode.
          if (rank > 0) ...[
            SizedBox(width: cs(10)),
            CsPrismText('#$rank', style: t.display(18, em: -0.02, height: 1)),
          ],
        ]),
        if (tournament.userBestScore != null && tournament.userAttempts != null) ...[
          SizedBox(height: cs(6)),
          Text(
            'BEST ${tournament.userBestScore} · ${tournament.userAttempts} ATTEMPTS',
            style: t.mono(10, color: CsColors.ink45),
          ),
        ],
      ],
      SizedBox(height: cs(20)),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: CsSegmented<_Tab>(
          segments: const {_Tab.overview: 'Overview', _Tab.standings: 'Standings', _Tab.rules: 'Rules'},
          selected: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
      ),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: CsFitColumn(children: info)),
      if (tournament.status.canJoin || tournament.status.canSubmitScore) ...[
        SizedBox(height: cs(14)),
        ..._buildActionButtons(),
      ],
      if (tournament.status == TournamentStatus.upcoming) ...[
        SizedBox(height: cs(14)),
        _Ticking(
          builder: (_) => CsMeta(
            'Starts in ${tournament.timeRemainingFormatted}',
            icon: Symbols.schedule_rounded,
            color: CsColors.cyan,
          ),
        ),
      ],
    ]);
  }

  String _timeLabel(Tournament t) => switch (t.status) {
        TournamentStatus.active => 'ENDS IN ${t.timeRemainingFormatted.toUpperCase()}',
        TournamentStatus.upcoming => 'STARTS IN ${t.timeRemainingFormatted.toUpperCase()}',
        TournamentStatus.ended => 'ENDED ${t.formattedDateRange}',
      };

  List<Widget> _buildActionButtons() {
    final tournament = _tournament!;
    final cs = context.cs;
    return [
      if (!tournament.hasJoined && tournament.status.canJoin)
        CsButton.primary(
          label: _isJoining ? 'Joining…' : 'Join tournament',
          icon: Symbols.person_add_rounded,
          loading: _isJoining,
          expand: true,
          onPressed: _isJoining ? null : () => _joinTournament(),
        )
      else if (tournament.status.canSubmitScore)
        CsButton.primary(
          label: 'Play now',
          icon: Symbols.play_arrow_rounded,
          expand: true,
          onPressed: _playTournament,
        ),
      if (tournament.requiresEntry) ...[
        SizedBox(height: cs(10)),
        Builder(
          builder: (context) {
            final premiumCubit = context.read<PremiumCubit>();
            if (premiumCubit.state.hasPremium) {
              return const CsMeta('Pro · Unlimited entries', icon: Symbols.diamond_rounded, color: CsColors.gold);
            }
            final tier = _getTournamentTier(tournament.type);
            final count = premiumCubit.state.getTournamentEntryCount(tier);
            return count > 0
                ? CsMeta('Entries remaining: $count', icon: Symbols.confirmation_number_rounded, color: CsColors.mint)
                : const CsMeta('No entries — tap Join to buy', icon: Symbols.error_rounded, color: CsColors.pink);
          },
        ),
      ],
    ];
  }

  Widget _buildOverviewTab() {
    final tournament = _tournament!;
    final cs = context.cs;
    final t = cs.type;
    final rewards = tournament.rewards.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CsLabel('Description'),
        SizedBox(height: cs(8)),
        Text(tournament.description, style: t.body.copyWith(color: CsColors.ink70, fontSize: cs(14))),
        SizedBox(height: cs(10)),
        CsMeta(tournament.formattedDateRange, icon: Symbols.calendar_today_rounded, size: 10),
        if (rewards.isNotEmpty) ...[
          SizedBox(height: cs(24)),
          const CsLabel('Prizes'),
          SizedBox(height: cs(4)),
          for (final entry in rewards)
            CsListRow(
              leading: SizedBox(
                width: cs(30),
                child: Text(
                  entry.key.toString().padLeft(2, '0'),
                  style: t.mono(13, em: 0.04, color: _rankColor(entry.key)),
                ),
              ),
              title: entry.value.name,
              subtitle: entry.value.description.isEmpty ? null : entry.value.description,
              trailing: entry.value.coins > 0 ? CsCoins(entry.value.coins, prefix: '+', size: 12) : null,
            ),
        ],
        SizedBox(height: cs(24)),
        const CsLabel('Game mode'),
        SizedBox(height: cs(8)),
        Row(children: [
          Icon(_modeIcon(tournament.gameMode), size: cs(20), color: CsColors.ink),
          SizedBox(width: cs(10)),
          Flexible(child: Text(tournament.gameMode.displayName, style: t.rowTitle)),
        ]),
        SizedBox(height: cs(6)),
        Text(tournament.gameMode.description, style: t.body),
        SizedBox(height: cs(8)),
      ]),
    );
  }

  Widget _buildLeaderboardTab() {
    if (_isLoading) {
      return const CsLoadingState(label: 'Loading leaderboard');
    }

    // Explicit load-failure state. Distinguishes "fetch crashed" from
    // "genuinely empty tournament" so the user sees a retry button
    // instead of a misleading "no participants" screen.
    if (_leaderboardLoadFailed) {
      return CsEmptyState.offline(
        title: "Couldn't load the leaderboard",
        message: 'Check your connection and try again.',
        action: CsButton.secondary(label: 'Retry', icon: Symbols.refresh_rounded, onPressed: _loadLeaderboard),
      );
    }

    if (_leaderboard.isEmpty) {
      return const CsEmptyState(
        icon: Symbols.leaderboard_rounded,
        title: 'No participants yet',
        message: 'Be the first to join!',
      );
    }

    // AuthService is a singleton (factory pattern in auth_service.dart),
    // NOT a registered Provider — call the singleton factory directly.
    final uid = AuthService().currentUser?.uid;
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _leaderboard.length,
      itemBuilder: (context, index) {
        final participant = _leaderboard[index];
        return _RankRow(
          rank: index + 1,
          name: participant.displayName,
          photoUrl: participant.photoUrl,
          subtitle: participant.attempts == 1 ? '1 ATTEMPT' : '${participant.attempts} ATTEMPTS',
          score: '${participant.highScore}',
          isYou: uid != null && participant.userId == uid,
        );
      },
    );
  }

  Widget _buildRulesTab() {
    final cs = context.cs;
    final t = cs.type;
    final rules = _getTournamentRules();
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CsLabel('Tournament rules'),
        SizedBox(height: cs(4)),
        for (var i = 0; i < rules.length; i++)
          Container(
            padding: EdgeInsets.symmetric(vertical: cs(10)),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CsColors.hairline))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: cs(30),
                child: Text((i + 1).toString().padLeft(2, '0'), style: t.mono(12, color: CsColors.ink45)),
              ),
              Expanded(child: Text(rules[i], style: t.body.copyWith(color: CsColors.ink, fontSize: cs(14)))),
            ]),
          ),
        SizedBox(height: cs(24)),
        const CsLabel('Scoring system'),
        SizedBox(height: cs(8)),
        Text(
          'Your highest score during the tournament period will count towards the final ranking. You can play multiple times to improve your score.',
          style: t.body.copyWith(color: CsColors.ink70, fontSize: cs(14)),
        ),
        SizedBox(height: cs(8)),
      ]),
    );
  }

  List<String> _getTournamentRules() {
    final tournament = _tournament!;
    final baseRules = [
      'Play during the tournament period to have your scores counted',
      'You can play multiple times - only your highest score counts',
      'Must be signed in to participate',
      'Final rankings are determined at tournament end',
    ];

    // Add game mode specific rules
    switch (tournament.gameMode) {
      case TournamentGameMode.speedRun:
        baseRules.add('Game speed increases rapidly every 10 points');
        break;
      case TournamentGameMode.survival:
        baseRules.add('Score is based on survival time, not food consumed');
        break;
      case TournamentGameMode.noWalls:
        baseRules.add(
          'Ship wraps around screen edges instead of hitting walls',
        );
        break;
      case TournamentGameMode.powerUpMadness:
        baseRules.add('Power-ups spawn every 5 seconds');
        break;
      case TournamentGameMode.perfectGame:
        baseRules.add('Any collision immediately ends the game');
        break;
      case TournamentGameMode.classic:
        baseRules.add('Standard Ship rules apply');
        break;
    }

    return baseRules;
  }

  Color _rankColor(int rank) => switch (rank) {
        1 => CsColors.gold,
        2 => CsColors.rank2,
        3 => CsColors.rank3,
        _ => CsColors.ink55,
      };

  String _getTournamentTier(TournamentType type) {
    switch (type) {
      case TournamentType.daily:
        return 'bronze';
      case TournamentType.weekly:
        return 'silver';
      case TournamentType.special:
        return 'gold';
    }
  }

  Future<void> _joinTournament() async {
    final tournament = _tournament!;
    final tier = _getTournamentTier(tournament.type);
    // Entry costs exactly ONE ticket of the tournament's tier. (The server's
    // numeric entry_fee is a coins value we no longer charge — it only drives
    // the requiresEntry gate; it is NOT a ticket count.)
    const ticketsRequired = 1;

    // Check entry requirement
    if (tournament.requiresEntry) {
      final premiumCubit = context.read<PremiumCubit>();

      // Premium users bypass entry requirement
      if (!premiumCubit.state.hasPremium) {
        final availableEntries = premiumCubit.state.getTournamentEntryCount(
          tier,
        );
        if (availableEntries < ticketsRequired) {
          _showNoEntryDialog(tier);
          return;
        }
      }
    }

    setState(() => _isJoining = true);

    try {
      final success = await _tournamentService.joinTournament(
        tournament.id,
        entryTier: tier,
      );

      if (success && mounted) {
        // Optimistically mark the local tournament as joined so the
        // CTA button flips from JOIN → PLAY NOW immediately, before
        // the network refresh below completes. The backend's
        // TournamentDto.IsJoined will confirm it on the next fetch.
        setState(() {
          _tournament = _tournament!.copyWith(isJoinedServer: true);
        });

        // Consume one tier ticket AFTER backend confirms the join succeeded
        if (tournament.requiresEntry) {
          final premiumCubit = context.read<PremiumCubit>();
          if (!premiumCubit.state.hasPremium) {
            await premiumCubit.useTournamentEntry(tier, count: ticketsRequired);
          }
        }

        getIt<AnalyticsFacade>().trackTournamentEntered(
          tournamentId: tournament.id,
          tier: tier,
        );

        // TournamentService.onTournamentJoined broadcast (subscribed by
        // TournamentsNotifier in its constructor) handles the list
        // refresh — no more brittle ProviderScope.containerOf dance.

        if (!mounted) return;
        showCsToast(context, 'Successfully joined tournament!', kind: CsToastKind.success);
        await _refreshTournament();
      } else if (mounted) {
        showCsToast(context, 'Failed to join tournament', kind: CsToastKind.error);
      }
    } catch (e) {
      if (mounted) {
        showCsToast(context, 'Error joining tournament', kind: CsToastKind.error);
      }
    }

    if (mounted) {
      setState(() => _isJoining = false);
    }
  }

  void _showNoEntryDialog(String tier) {
    final premiumCubit = context.read<PremiumCubit>();
    final entryCount = premiumCubit.state.getTournamentEntryCount(tier);

    String productId;
    switch (tier) {
      case 'bronze':
        productId = ProductIds.tournamentBronze;
        break;
      case 'silver':
        productId = ProductIds.tournamentSilver;
        break;
      case 'gold':
        productId = ProductIds.tournamentGold;
        break;
      default:
        return;
    }

    final tierName = '${tier[0].toUpperCase()}${tier.substring(1)}';

    // Free Bronze entry via rewarded ad (free users only, bronze tier only —
    // never devalue the paid Silver/Gold entries). Daily-capped (2/day) so the
    // paid bronze entry keeps a reason to exist.
    final showAdEntry = tier == 'bronze' &&
        getIt.isRegistered<AdService>() &&
        getIt<AdService>().adsEnabled &&
        getIt<AdService>().canShowCapped(AdService.capTournamentEntry);

    showCsDialog<void>(
      context,
      builder: (ctx) {
        final cs = ctx.cs;
        final t = cs.type;
        return CsDialog(
          icon: Symbols.confirmation_number_rounded,
          iconColor: CsColors.gold,
          eyebrow: '$tierName tier',
          title: 'Entry Required',
          message: 'You need a $tierName tournament entry to join this tournament.',
          content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              'CURRENT $tierName ENTRIES: $entryCount'.toUpperCase(),
              style: t.mono(11, color: entryCount > 0 ? CsColors.mint : CsColors.pink),
            ),
            SizedBox(height: cs(10)),
            Text('Pro subscribers get unlimited tournament access.', style: t.body.copyWith(color: CsColors.ink45)),
          ]),
          actions: [
            CsButton.text(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
            if (showAdEntry)
              CsButton.secondary(
                label: 'Free entry (ad) · '
                    '${getIt<AdService>().dailyRemaining(AdService.capTournamentEntry)} left today',
                icon: Symbols.smart_display_rounded,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  getIt<AdService>().showRewardedCapped(
                    capKey: AdService.capTournamentEntry,
                    onReward: () {
                      premiumCubit.addTournamentEntry('bronze');
                      RewardToast.show(
                        icon: Symbols.emoji_events_rounded,
                        title: 'ENTRY GRANTED',
                        amount: '+1 BRONZE ENTRY',
                      );
                    },
                  );
                },
              ),
            CsButton.premium(
              label: 'Buy $tierName Entry · '
                  '${PurchaseService().getStorePrice(productId) ?? _getDefaultPrice(tier)}',
              onPressed: () {
                Navigator.of(ctx).pop();
                final purchaseService = PurchaseService();
                final product = purchaseService.getProduct(productId);
                if (product != null) {
                  purchaseService.buyProduct(product);
                }
              },
            ),
          ],
        );
      },
    );
  }

  String _getDefaultPrice(String tier) {
    switch (tier) {
      case 'bronze':
        return '\$0.99';
      case 'silver':
        return '\$1.99';
      case 'gold':
        return '\$4.99';
      default:
        return '\$0.99';
    }
  }

  void _playTournament() {
    final tournament = _tournament!;

    // Arm the tournament context so the run's score is attributed to it.
    context.read<TournamentContextCubit>().enterTournament(
      tournament.id,
      tournament.gameMode,
    );

    Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => const GameplayScreen()))
        .then((_) {
          // Refresh tournament data when returning from game
          _refreshTournament();
        });
  }
}

IconData _modeIcon(TournamentGameMode mode) => switch (mode) {
      TournamentGameMode.classic => Symbols.rocket_rounded,
      TournamentGameMode.speedRun => Symbols.speed_rounded,
      TournamentGameMode.survival => Symbols.timer_rounded,
      TournamentGameMode.noWalls => Symbols.all_inclusive_rounded,
      TournamentGameMode.powerUpMadness => Symbols.bolt_rounded,
      TournamentGameMode.perfectGame => Symbols.diamond_rounded,
    };

Widget _statusChip(TournamentStatus status) => switch (status) {
      TournamentStatus.active => const CsChip('Live', kind: CsChipKind.mint),
      TournamentStatus.upcoming => const CsChip('Upcoming'),
      TournamentStatus.ended => const CsChip('Ended'),
    };

/// Standings row — same language as the global leaderboard.
class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.name,
    required this.subtitle,
    required this.score,
    this.photoUrl,
    this.isYou = false,
  });

  final int rank;
  final String name;
  final String subtitle;
  final String score;
  final String? photoUrl;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final List<Color>? ring = isYou
        ? null
        : switch (rank) {
            1 => const [CsColors.gold],
            2 => const [CsColors.rank2],
            3 => const [CsColors.rank3],
            _ => const [Color(0x26FFFFFF)],
          };
    final d = cs(40);
    final initials = Center(
      child: Text(
        CsAvatarRing.initialsOf(name),
        style: t.display(40 * 0.32, weight: FontWeight.w700, em: 0.02, height: 1),
      ),
    );
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
        SizedBox.square(
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
        ),
        SizedBox(width: cs(16)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle)),
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
