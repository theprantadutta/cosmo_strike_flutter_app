import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/tournament/tournament_context_cubit.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/ads/ad_service.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/tournament_service.dart';
import 'package:cosmo_strike_flutter_app/services/auth_service.dart';
import 'package:cosmo_strike_flutter_app/services/purchase_service.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/auth/auth_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/premium/premium_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/screens/gameplay_screen.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart' show GameMode;
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
            _loadError = 'Cup not found';
            _isLoadingTournament = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = 'Cup failed to load';
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
        'Cup prize claimed. +$coins CR.',
        kind: CsToastKind.reward,
        icon: Symbols.military_tech_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CsScaffold(
      title: _tournament == null ? 'Sector Cup' : 'Sector Cups · ${_tournament!.type.displayName}',
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
      return const CsLoadingState(label: 'Loading Cup');
    }

    // Show error state
    if (_loadError != null || _tournament == null) {
      return CsEmptyState.error(
        title: _loadError ?? 'Cup not found',
        action: CsButton.secondary(
          label: 'Back',
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
        CsChip(tournament.gameMode.name, icon: _modeIcon(tournament.gameMode)),
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
            'BEST ${tournament.userBestScore} · ${tournament.userAttempts} RUNS',
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
            'Opens in ${tournament.timeRemainingFormatted}',
            icon: Symbols.schedule_rounded,
            color: CsColors.cyan,
          ),
        ),
      ],
    ]);
  }

  String _timeLabel(Tournament t) => switch (t.status) {
        TournamentStatus.active => 'CLOSES IN ${t.timeRemainingFormatted.toUpperCase()}',
        TournamentStatus.upcoming => 'OPENS IN ${t.timeRemainingFormatted.toUpperCase()}',
        TournamentStatus.ended => 'ENDED ${t.formattedDateRange}',
      };

  List<Widget> _buildActionButtons() {
    final tournament = _tournament!;
    final cs = context.cs;
    return [
      if (!tournament.hasJoined && tournament.status.canJoin)
        CsButton.primary(
          label: _isJoining ? 'Entering…' : 'Enter Cup',
          icon: Symbols.person_add_rounded,
          loading: _isJoining,
          expand: true,
          onPressed: _isJoining ? null : () => _joinTournament(),
        )
      else if (tournament.status.canSubmitScore)
        CsButton.primary(
          label: 'Launch',
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
              return const CsMeta('Strike Command · Unlimited entries', icon: Symbols.workspace_premium_rounded, color: CsColors.gold);
            }
            final tier = _getTournamentTier(tournament.type);
            final count = premiumCubit.state.getTournamentEntryCount(tier);
            return count > 0
                ? CsMeta('Cup Passes: $count', icon: Symbols.confirmation_number_rounded, color: CsColors.mint)
                : const CsMeta('No Cup Pass. Tap Enter to get one', icon: Symbols.error_rounded, color: CsColors.pink);
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
        const CsLabel('Briefing'),
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
        const CsLabel('Mode'),
        SizedBox(height: cs(8)),
        Row(children: [
          Icon(_modeIcon(tournament.gameMode), size: cs(20), color: CsColors.ink),
          SizedBox(width: cs(10)),
          Flexible(child: Text(tournament.gameMode.name, style: t.rowTitle)),
        ]),
        SizedBox(height: cs(6)),
        Text(tournament.gameMode.description, style: t.body),
        SizedBox(height: cs(8)),
      ]),
    );
  }

  Widget _buildLeaderboardTab() {
    if (_isLoading) {
      return const CsLoadingState(label: 'Loading standings');
    }

    // Explicit load-failure state. Distinguishes "fetch crashed" from
    // "genuinely empty tournament" so the user sees a retry button
    // instead of a misleading "no participants" screen.
    if (_leaderboardLoadFailed) {
      return CsEmptyState.offline(
        title: "Couldn't load standings",
        message: 'Check your connection and try again.',
        action: CsButton.secondary(label: 'Retry', icon: Symbols.refresh_rounded, onPressed: _loadLeaderboard),
      );
    }

    if (_leaderboard.isEmpty) {
      return const CsEmptyState(
        icon: Symbols.leaderboard_rounded,
        title: 'No pilots yet',
        message: 'Be the first pilot in.',
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
          subtitle: participant.attempts == 1 ? '1 RUN' : '${participant.attempts} RUNS',
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
        const CsLabel('Cup rules'),
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
        const CsLabel('Scoring'),
        SizedBox(height: cs(8)),
        Text(
          'Your best score while the Cup is open sets your standing. Fly as many runs as you like.',
          style: t.body.copyWith(color: CsColors.ink70, fontSize: cs(14)),
        ),
        SizedBox(height: cs(8)),
      ]),
    );
  }

  List<String> _getTournamentRules() {
    final tournament = _tournament!;
    final mode = tournament.gameMode;
    return [
      'Only runs flown while the Cup is open count',
      'Fly as many runs as you like. Your best score stands',
      'Sign in to post a score',
      'Final standings lock when the Cup closes',
      '${mode.name}: ${mode.description}',
    ];
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
        showCsToast(context, 'Cup locked in.', kind: CsToastKind.success);
        await _refreshTournament();
      } else if (mounted) {
        showCsToast(context, 'Cup entry failed. Try again.', kind: CsToastKind.error);
      }
    } catch (e) {
      if (mounted) {
        showCsToast(context, 'Cup entry failed. Check your connection.', kind: CsToastKind.error);
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
        productId = ProductIds.cupScout;
        break;
      case 'silver':
        productId = ProductIds.cupStrike;
        break;
      case 'gold':
        productId = ProductIds.cupAce;
        break;
      default:
        return;
    }

    // Wire tiers stay bronze/silver/gold; players see Scout/Strike/Ace.
    final tierName = switch (tier) {
      'bronze' => 'Scout',
      'silver' => 'Strike',
      _ => 'Ace',
    };

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
          eyebrow: '$tierName Cup Pass',
          title: 'Cup Pass required',
          message: 'This Cup takes a $tierName Cup Pass.',
          content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              '$tierName PASSES ON HAND: $entryCount'.toUpperCase(),
              style: t.mono(11, color: entryCount > 0 ? CsColors.mint : CsColors.pink),
            ),
            SizedBox(height: cs(10)),
            Text('Strike Command members enter every Cup free.', style: t.body.copyWith(color: CsColors.ink45)),
          ]),
          actions: [
            CsButton.text(label: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
            // Armory's Cup Passes tab also sells the multi-pass bundles.
            CsButton.text(
              label: 'More Cup Passes',
              onPressed: () {
                Navigator.of(ctx).pop();
                context.push('${AppRoutes.store}?tab=6');
              },
            ),
            if (showAdEntry)
              CsButton.secondary(
                label: 'Free pass (ad) · '
                    '${getIt<AdService>().dailyRemaining(AdService.capTournamentEntry)} left today',
                icon: Symbols.smart_display_rounded,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  getIt<AdService>().showRewardedCapped(
                    capKey: AdService.capTournamentEntry,
                    onReward: () {
                      premiumCubit.addTournamentEntry('bronze');
                      RewardToast.show(
                        icon: Symbols.confirmation_number_rounded,
                        title: 'PASS GRANTED',
                        amount: '+1 SCOUT CUP PASS',
                      );
                    },
                  );
                },
              ),
            CsButton.premium(
              label: 'Buy $tierName Cup Pass · '
                  '${PurchaseService().getStorePrice(productId) ?? _getDefaultPrice(tier)}',
              onPressed: () async {
                Navigator.of(ctx).pop();
                // Guests buy on a silent anonymous account (no sign-in).
                if (!await context.read<AuthCubit>().ensurePurchaseAccount()) {
                  if (mounted) {
                    showCsToast(context, "Couldn't reach the store. Check your connection and try again.",
                        kind: CsToastKind.error);
                  }
                  return;
                }
                final purchaseService = PurchaseService();
                final product = purchaseService.getProduct(productId);
                if (product != null) {
                  await purchaseService.buyProduct(product);
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

IconData _modeIcon(GameMode mode) => mode.icon;

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
