import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/game/game_assets.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_settings_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/tournament/tournament_context_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/first_run_service.dart';
import 'package:cosmo_strike_flutter_app/services/progression_service.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/campaign_catalog.dart';

/// Pre-game loading screen shown between level select / Home LAUNCH and the
/// Game screen.
///
/// Its job is two-fold:
///   1. Decode the gameplay sprite atlas into Flame's cache (and touch the
///      audio singleton) so the game starts without a hitch.
///   2. Frame the jump with the mission title, a progress line and a tip,
///      on screen only until the assets are ready, with a short
///      [_minDuration] floor so it never flashes.
///
/// The very first run skips the theatre entirely (a brand-new player's
/// first tap on Play goes straight into the game; the game awaits the same
/// memoized preload in onLoad).
///
/// Prism Noir interstitial: LEFT = "LEVEL 03 / ASTEROID BELT" + the level
/// name set huge with a prism tail, then the mode you're launching into and
/// your control scheme. RIGHT = live status, prism progress line, your record
/// (pilot level / best / games) and a rotating pro tip.
///
/// When both the floor and the preload are done, the screen does a
/// `pushReplacement` to
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
  // Shortest time the loader is on screen (polish floor; the real wait is
  // the sprite preload).
  static const Duration _minDuration = Duration(milliseconds: 800);
  // Safety cap on waiting for the preload: past this the game takes over
  // (CosmoStrikeGame.onLoad awaits the same memoized future).
  static const Duration _maxAssetWait = Duration(seconds: 6);
  // Beat at 100% / "GO!" before leaving, so the bar visibly completes.
  static const Duration _goBeat = Duration(milliseconds: 150);
  // Progress the bar holds at while the assets are still decoding.
  static const double _holdProgress = 0.9;
  // How often the tip rotates.
  static const Duration _tipRotation = Duration(milliseconds: 1400);

  /// Stage milestones — each step drives the status label. Pairs are
  /// (fractional progress, status label). The bar runs to [_holdProgress]
  /// over [_minDuration] and completes when the assets are ready; the label
  /// is picked by finding the largest stage we've crossed.
  static const List<_Stage> _stages = [
    _Stage(0.00, 'Initializing flight systems...'),
    _Stage(0.30, 'Arming weapons...'),
    _Stage(0.60, 'Scanning for hostiles...'),
    _Stage(_holdProgress, 'Clear for launch...'),
    _Stage(1.00, 'Go!'),
  ];

  static const List<String> _tips = [
    'Chain kills without taking a hit to climb the ×4 combo.',
    'Skim enemy fire to graze. Grazes fill the Overdrive meter.',
    'Full Overdrive: tap it for a piercing beam and double score.',
    'Wipe a whole formation fast for a bonus and an orb.',
    'Every boss attack telegraphs. Watch the windup, then move.',
    'Pick an upgrade after each clear. It stacks for the run.',
    'Hangar upgrades are permanent. Spend credits between runs.',
    'Blitz gives you three minutes. Score everything.',
    'Cruise: enemies hold fire. Learn the patterns.',
    'Knife Edge: one hit ends the run. Fly clean.',
    'The D-Pad gives precise steering; swipe is faster.',
    'Pause anytime from the HUD. The clock holds with you.',
  ];

  late final AnimationController _progressController;

  final Random _random = Random();

  int _tipIndex = 0;
  bool _navigated = false;

  /// Brand-new player: no theatre, straight into the game.
  late final bool _skipTheatre = FirstRunService.instance.isFirstGame;

  /// Flips when the sprite preload settles (or times out).
  final ValueNotifier<bool> _assetsReady = ValueNotifier(false);
  bool _floorDone = false;

  @override
  void initState() {
    super.initState();

    // Runs 0 -> [_holdProgress] over the floor; the last stretch to 100%
    // is shown once the assets are ready (see [_displayProgress]).
    _progressController = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (_minDuration.inMilliseconds / _holdProgress).round(),
      ),
      upperBound: _holdProgress,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _floorDone = true);
          _maybeGo();
        }
      });

    _tipIndex = _random.nextInt(_tips.length);

    // Cycle tips while the progress bar fills.
    _scheduleTipRotation();

    // Warm any singletons that are cheap to touch. Audio is preloaded in
    // main(); this just guarantees the instance is alive before gameplay.
    AudioService();

    // Decode the gameplay sprite atlas into Flame's image cache. The loader
    // waits for it (capped); CosmoStrikeGame.onLoad awaits the same memoized
    // future, so the game never races a slow decode either way.
    final preload = GameAssets.preload();
    if (_skipTheatre) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goToGame());
      return;
    }
    unawaited(
      preload
          .timeout(_maxAssetWait)
          .catchError((Object _) {})
          .whenComplete(() {
        if (!mounted) return;
        _assetsReady.value = true;
        _maybeGo();
      }),
    );

    // Kick off the visual progress AFTER the first frame so the entrance
    // animations get a clean start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _progressController.forward();
    });
  }

  /// Leaves once the polish floor has run AND the assets are ready.
  void _maybeGo() {
    if (!_floorDone || !_assetsReady.value || _navigated || !mounted) return;
    Future.delayed(_goBeat, _goToGame);
  }

  /// What the bar and status show: the floor animation, held at
  /// [_holdProgress] until the assets are ready, then complete.
  double get _displayProgress =>
      _floorDone && _assetsReady.value ? 1.0 : _progressController.value;

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
    _assetsReady.dispose();
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
    if (_skipTheatre) return const ColoredBox(color: CsColors.bg);
    // Active mode = the player's settings choice unless a tournament
    // override is staged on the context (set before they tapped Play).
    final tournamentMode = context
        .select<TournamentContextCubit, GameMode?>((c) => c.state.mode);
    final settingsMode =
        context.select<GameSettingsCubit, GameMode>((c) => c.state.gameMode);
    final activeMode = tournamentMode ?? settingsMode;
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
                      isOverride ? 'CUP MODE' : 'MODE',
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
        animation: Listenable.merge([_progressController, _assetsReady]),
        builder: (context, _) {
          final p = _displayProgress;
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
          CsStat(_compactNumber(games), 'Runs'),
        ],
      ),
      SizedBox(height: cs(20)),
      Row(children: [
        Icon(Symbols.lightbulb_rounded, size: cs(14), color: CsColors.gold),
        SizedBox(width: cs(8)),
        const CsLabel('Field note'),
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
