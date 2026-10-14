import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/game/game_assets.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_settings_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/tournament/tournament_context_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/progression_service.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/campaign_catalog.dart';

/// Pre-game loading screen shown between level select / Home LAUNCH and the
/// Game screen.
///
/// Its job is two-fold:
///   1. Give the player a 3-second buffer with the mission title, a progress
///      line and tips so the jump into gameplay feels deliberate.
///   2. Opportunistically warm up gameplay dependencies that are cheap and
///      idempotent — audio (already preloaded in main; this just touches the
///      singleton), and a decode of the gameplay sprite atlas.
///
/// Prism Noir interstitial: LEFT = "LEVEL 03 / ASTEROID BELT" + the level
/// name set huge with a prism tail, then the mode you're launching into and
/// your control scheme. RIGHT = live status, prism progress line, your record
/// (pilot level / best / games) and a rotating pro tip.
///
/// When the timer completes, the screen does a `pushReplacement` to
/// `AppRoutes.game` so back navigation from the game returns to Home, not
/// to this screen.
class PreGameLoadingScreen extends StatefulWidget {
  const PreGameLoadingScreen({super.key, this.startLevel = 1});

  /// 1-based campaign level to launch into (forwarded to the game route).
  final int startLevel;

  @override
  State<PreGameLoadingScreen> createState() => _PreGameLoadingScreenState();
}

class _PreGameLoadingScreenState extends State<PreGameLoadingScreen>
    with SingleTickerProviderStateMixin {
  // Total time the loader is on screen.
  static const Duration _loadDuration = Duration(milliseconds: 3000);
  // How often the tip rotates.
  static const Duration _tipRotation = Duration(milliseconds: 1400);

  /// Stage milestones — each step drives the status label. Pairs are
  /// (fractional progress, status label). The progress controller advances
  /// linearly across the full duration; the label is picked by finding the
  /// largest stage we've crossed.
  static const List<_Stage> _stages = [
    _Stage(0.00, 'Initializing flight systems...'),
    _Stage(0.18, 'Calibrating controls...'),
    _Stage(0.36, 'Spooling thrusters...'),
    _Stage(0.54, 'Scanning for hostiles...'),
    _Stage(0.72, 'Charging power-ups...'),
    _Stage(0.88, 'Almost there...'),
    _Stage(1.00, 'Go!'),
  ];

  static const List<String> _tips = [
    'Hold fire on a tight cluster to build combo multipliers.',
    'Bonus Pickups yield more points but vanish quickly.',
    'Power-ups spawn at random — grab them while you can.',
    'Read the wave ahead, not just the enemy in front of you.',
    'Heavy ships steer slower. Ease into tight dodges early.',
    'Score Multiplier stacks with combos for monster scores.',
    'Power-Ups are rare — when one appears, prioritize it.',
    'Time Attack speeds up fast. Pace your maneuvers.',
    'Zen Mode: enemies never fire — cruise, dodge, and practice.',
    'Perfect Game: a single hit ends the run — fly flawless.',
    'The D-Pad gives precise steering; swipe is faster.',
    'Pause anytime from the HUD — your timer holds with you.',
  ];

  late final AnimationController _progressController;

  final Random _random = Random();

  int _tipIndex = 0;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: _loadDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _goToGame();
      });

    _tipIndex = _random.nextInt(_tips.length);

    // Cycle tips while the progress bar fills.
    _scheduleTipRotation();

    // Warm any singletons that are cheap to touch. Audio is preloaded in
    // main(); this just guarantees the instance is alive before gameplay.
    AudioService();

    // Decode the gameplay sprite atlas into Flame's image cache while the
    // loader runs. Fire-and-forget — CosmoStrikeGame.onLoad awaits the same
    // memoized future, so a slow decode just delays game start, never races.
    GameAssets.preload();

    // Kick off the visual progress AFTER the first frame so the entrance
    // animations get a clean start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _progressController.forward();
    });
  }

  void _scheduleTipRotation() {
    Future.delayed(_tipRotation, () {
      if (!mounted || _navigated) return;
      setState(() {
        _tipIndex = (_tipIndex + 1) % _tips.length;
      });
      _scheduleTipRotation();
    });
  }

  void _goToGame() {
    if (_navigated || !mounted) return;
    _navigated = true;
    context.pushReplacement(AppRoutes.game, extra: widget.startLevel);
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  String _statusFor(double progress) {
    // Largest stage whose threshold has been crossed.
    var label = _stages.first.label;
    for (final stage in _stages) {
      if (progress >= stage.threshold) label = stage.label;
    }
    return label;
  }

  @override
  Widget build(BuildContext context) {
    // Active mode = the player's settings choice unless a tournament
    // override is staged on the context (set before they tapped Play).
    final tournamentMode = context
        .select<TournamentContextCubit, TournamentGameMode?>((c) => c.state.mode);
    final settingsMode =
        context.select<GameSettingsCubit, GameMode>((c) => c.state.gameMode);
    final activeMode = tournamentMode?.toGameMode() ?? settingsMode;
    final isOverride = activeMode != settingsMode;
    final isDaily =
        context.select<TournamentContextCubit, bool>((c) => c.state.isDailyRun);
    final dPadEnabled =
        context.select<GameSettingsCubit, bool>((c) => c.state.dPadEnabled);
    final highScore =
        context.select<GameSettingsCubit, int>((c) => c.state.highScore);

    final cs = context.cs;
    return PopScope(
      // Allow Android back to bail out to Home — there's no game state
      // to protect yet. _navigated guards against double navigation.
      canPop: true,
      child: CsScaffold(
        showTopBar: false,
        stars: true,
        washes: const [CsWash.violetTopRight, CsWash.cyanBottomLeft],
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 6,
              child: _Entrance(
                child: CsFitColumn(
                  alignment: Alignment.centerLeft,
                  children: _buildMission(activeMode, isOverride, dPadEnabled, daily: isDaily),
                ),
              ),
            ),
            SizedBox(width: cs(44)),
            Expanded(
              flex: 4,
              child: _Entrance(
                delay: 0.25,
                child: CsFitColumn(
                  alignment: Alignment.centerLeft,
                  children: _buildStatus(highScore),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- LEFT: level + mode ----

  List<Widget> _buildMission(GameMode mode, bool isOverride, bool dPad, {bool daily = false}) {
    final cs = context.cs;
    final t = cs.type;
    final level = widget.startLevel;
    final accent = isOverride ? CsColors.gold : CsColors.ink55;
    return [
      Text(
        daily
            ? 'DAILY RUN · SAME SKY FOR EVERY PILOT TODAY'
            : 'LEVEL ${level.toString().padLeft(2, '0')} / ${CampaignCatalog.biomeNameFor(level)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.mono(11, em: 0.16, color: daily ? CsColors.gold : CsColors.ink55),
      ),
      SizedBox(height: cs(16)),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: _PrismTailTitle(name: _titleCase(CampaignCatalog.levelNameFor(level))),
      ),
      SizedBox(height: cs(26)),
      const CsHairline(),
      SizedBox(height: cs(16)),
      // The mode you're about to play.
      Row(
        children: [
          CsIconDisc(CsIcons.mode(mode), size: 40, color: isOverride ? CsColors.gold : CsColors.ink),
          SizedBox(width: cs(14)),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      isOverride ? 'TOURNAMENT MODE' : 'GAME MODE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.mono(10, color: accent),
                    ),
                  ),
                  if (isOverride) ...[
                    SizedBox(width: cs(6)),
                    Icon(Symbols.trophy_rounded, size: cs(13), color: CsColors.gold),
                  ],
                ]),
                SizedBox(height: cs(4)),
                Text(mode.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
                SizedBox(height: cs(3)),
                Text(mode.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.body),
              ],
            ),
          ),
        ],
      ),
      SizedBox(height: cs(14)),
      CsChip(
        dPad ? 'D-Pad controls' : 'Swipe controls',
        icon: dPad ? Symbols.gamepad_rounded : Symbols.swipe_rounded,
        size: 10,
      ),
    ];
  }

  // ---- RIGHT: live status + progress + record + tip ----

  List<Widget> _buildStatus(int highScore) {
    final cs = context.cs;
    final t = cs.type;
    final pilotLevel = ProgressionService().level;
    final games = StatisticsService().statistics.totalGamesPlayed;
    return [
      AnimatedBuilder(
        animation: _progressController,
        builder: (context, _) {
          final p = _progressController.value;
          final status = _statusFor(p).replaceAll('...', '').toUpperCase();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: CsMotion.base,
                    // Only the incoming label: a crossfade draws two mono
                    // labels on top of each other mid-transition.
                    layoutBuilder: (current, previous) => Align(
                      alignment: Alignment.centerLeft,
                      child: current,
                    ),
                    child: Text(
                      status,
                      key: ValueKey(status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.mono(11, em: 0.16, color: CsColors.ink),
                    ),
                  ),
                ),
                SizedBox(width: cs(12)),
                Text(
                  '${(p * 100).round().toString().padLeft(2, '0')}%',
                  style: t.mono(11, color: CsColors.ink55).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ]),
              SizedBox(height: cs(12)),
              CsProgressLine(value: p, gradient: CsGradients.prism, animate: false),
            ],
          );
        },
      ),
      SizedBox(height: cs(22)),
      CsStatGrid(
        columns: 3,
        valueSize: 20,
        stats: [
          CsStat(pilotLevel.toString().padLeft(2, '0'), 'Pilot LV'),
          CsStat(_compactNumber(highScore), 'Best'),
          CsStat(_compactNumber(games), 'Games'),
        ],
      ),
      SizedBox(height: cs(20)),
      Row(children: [
        Icon(Symbols.lightbulb_rounded, size: cs(14), color: CsColors.gold),
        SizedBox(width: cs(8)),
        const CsLabel('Pro tip'),
      ]),
      SizedBox(height: cs(8)),
      // Rotating tip with a short fade; fixed height stops jumps.
      SizedBox(
        height: cs(40),
        child: AnimatedSwitcher(
          duration: CsMotion.slow,
          switchInCurve: CsMotion.standard,
          switchOutCurve: CsMotion.standard,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: Text(
            _tips[_tipIndex],
            key: ValueKey<int>(_tipIndex),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.body,
          ),
        ),
      ),
    ];
  }

  static String _titleCase(String s) => s
      .toLowerCase()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  /// 1234 -> "1.2K", 1500000 -> "1.5M". Keeps the stats from overflowing on
  /// big lifetime numbers.
  String _compactNumber(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final v = (n / 1000);
      return '${v.toStringAsFixed(v >= 100 ? 0 : 1)}K';
    }
    final v = (n / 1000000);
    return '${v.toStringAsFixed(v >= 100 ? 0 : 1)}M';
  }
}

class _Stage {
  final double threshold;
  final String label;
  const _Stage(this.threshold, this.label);
}

/// One-shot fade + 12px rise (no looping effects). [delay] is a fraction of
/// the 600ms run.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child, this.delay = 0});
  final Widget child;
  final double delay;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: CsMotion.countUp,
      curve: Interval(delay, 1, curve: CsMotion.standard),
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

/// Two-line hero name: all but the last word on line 1, the last word on
/// line 2 with its second half in prism ("Iron / Dread·nought") — the same
/// treatment as the home hero.
class _PrismTailTitle extends StatelessWidget {
  const _PrismTailTitle({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final st = context.type.hero;
    final words = name.split(' ');
    final last = words.removeLast();
    final cut = (last.length / 2).floor().clamp(1, last.length - 1);
    final line2a = last.length > 1 ? last.substring(0, cut) : last;
    final line2b = last.length > 1 ? last.substring(cut) : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (words.isNotEmpty) Text(words.join(' '), maxLines: 1, style: st),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(line2a, maxLines: 1, style: st),
            if (line2b.isNotEmpty) CsPrismText(line2b, style: st, maxLines: 1),
          ],
        ),
      ],
    );
  }
}
