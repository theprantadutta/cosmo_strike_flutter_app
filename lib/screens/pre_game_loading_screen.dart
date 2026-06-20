import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/game/game_assets.dart';
import 'package:cosmo_strike_flutter_app/models/tournament.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/game/game_cubit.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/services/audio_service.dart';
import 'package:cosmo_strike_flutter_app/services/progression_service.dart';
import 'package:cosmo_strike_flutter_app/services/statistics_service.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';

/// Pre-game loading screen shown between the Home Play tap and the Game screen.
///
/// Its job is two-fold:
///   1. Give the player a beautiful 3-second buffer with tips, animations,
///      and a progress bar so the jump into gameplay feels deliberate.
///   2. Opportunistically warm up gameplay dependencies that are cheap and
///      idempotent — audio (already preloaded in main; this just touches the
///      singleton), and a decode of the gameplay sprite atlas.
///
/// Visually it mirrors the app's INITIAL loading screen: a clean, borderless
/// landscape two-region layout — brand + the mode you're launching into on the
/// LEFT, live launch status (rotating beacon, slim neon progress bar, your
/// record, a rotating pro-tip) on the RIGHT. No glass boxes; definition comes
/// from neon glow, slim bars, and the cyan/magenta accents.
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
    with TickerProviderStateMixin {
  // Total time the loader is on screen.
  static const Duration _loadDuration = Duration(milliseconds: 3000);
  // How often the tip rotates.
  static const Duration _tipRotation = Duration(milliseconds: 1400);

  /// Stage milestones — each step drives the progress bar and the
  /// status label. Pairs are (fractional progress, status label).
  /// The progress controller advances linearly across the full duration;
  /// the label is picked by finding the largest stage we've crossed.
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
  late final AnimationController _logoController;
  late final AnimationController _pulseController;
  late final AnimationController _particleController;
  late final AnimationController _shimmerController;

  final Random _random = Random();
  final List<_LoadingParticle> _particles = [];

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

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();

    _seedParticles();
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

  void _seedParticles() {
    _particles.clear();
    for (int i = 0; i < 28; i++) {
      _particles.add(
        _LoadingParticle(
          x: _random.nextDouble(),
          y: _random.nextDouble(),
          speed: 0.15 + _random.nextDouble() * 0.35,
          size: 1.5 + _random.nextDouble() * 3.5,
          opacity: 0.25 + _random.nextDouble() * 0.45,
        ),
      );
    }
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
    _logoController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    _shimmerController.dispose();
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
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;
        // Active mode = the player's settings choice unless a tournament
        // override is staged on the cubit (set before they tapped Play).
        final tournamentMode = context
            .select<GameCubit, TournamentGameMode?>(
                (c) => c.state.tournamentMode);
        final settingsMode = context
            .select<GameSettingsCubit, GameMode>((c) => c.state.gameMode);
        final activeMode = tournamentMode?.toGameMode() ?? settingsMode;
        final isOverride = activeMode != settingsMode;
        final dPadEnabled = context
            .select<GameSettingsCubit, bool>((c) => c.state.dPadEnabled);
        final highScore = context
            .select<GameSettingsCubit, int>((c) => c.state.highScore);

        return PopScope(
          // Allow Android back to bail out to Home — there's no game state
          // to protect yet. _navigated guards against double navigation.
          canPop: true,
          child: CommandScaffold(
            theme: theme,
            showTopBar: false,
            bodyPadding: EdgeInsets.zero,
            body: Stack(
              children: [
                // Themed particles streaming upward behind everything.
                _ParticleLayer(
                  controller: _particleController,
                  particles: _particles,
                  theme: theme,
                ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Landscape phones report a short height — treat
                      // < 340 as "compact" so nothing clips.
                      final isSmall = constraints.maxHeight < 340;
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          30,
                          isSmall ? 8 : 16,
                          30,
                          isSmall ? 8 : 16,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // LEFT — brand + the mode you're launching into.
                            Expanded(
                              flex: 5,
                              child: Center(
                                child: SingleChildScrollView(
                                  primary: false,
                                  child: _buildBrand(
                                    theme,
                                    activeMode,
                                    isOverride,
                                    dPadEnabled,
                                    isSmall,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 30),
                            // RIGHT — live launch status, progress, record, tip.
                            Expanded(
                              flex: 6,
                              child: Center(
                                child: SingleChildScrollView(
                                  primary: false,
                                  child: _buildStatus(theme, highScore, isSmall),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- LEFT: brand + mode ----

  Widget _buildBrand(
    GameTheme theme,
    GameMode mode,
    bool isOverride,
    bool dPad,
    bool isSmall,
  ) {
    final markSize = isSmall ? 58.0 : 74.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _beaconLabel(theme, 'PREPARING LAUNCH'),
        SizedBox(height: isSmall ? 10 : 16),
        // Brand mark — the rocket glyph in neon, glow + breathing + shimmer,
        // exactly the language of the initial loading screen.
        AnimatedBuilder(
          animation: _logoController,
          builder: (context, child) {
            final pulse = 1.0 + sin(_logoController.value * 2 * pi) * 0.04;
            return Transform.scale(scale: pulse, child: child);
          },
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: theme.accentColor.withValues(alpha: 0.3),
                  blurRadius: 32,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              Icons.rocket_launch,
              size: markSize,
              color: theme.accentColor,
            ),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(
              duration: 2500.ms,
              color: theme.accentColor.withValues(alpha: 0.25),
            ),
        SizedBox(height: isSmall ? 8 : 12),
        // Gradient wordmark — matches the home / loader brand.
        ShaderMask(
          shaderCallback: (b) => LinearGradient(
            colors: [theme.neonPrimary, theme.neonSecondary],
          ).createShader(b),
          child: Text(
            'COSMO STRIKE',
            maxLines: 1,
            style: TextStyle(
              fontSize: isSmall ? 22 : 26,
              fontWeight: FontWeight.w900,
              color: Colors.white, // base for ShaderMask
              letterSpacing: 3,
            ),
          ),
        ),
        SizedBox(height: isSmall ? 14 : 20),
        _buildModeHero(theme, mode, isOverride),
        SizedBox(height: isSmall ? 12 : 16),
        _buildControlChip(theme, dPad),
      ],
    ).gameEntrance();
  }

  /// Pulsing beacon dot + an uppercase HUD label — the same idiom the
  /// loader / home use for live status.
  Widget _beaconLabel(GameTheme theme, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            final t = _pulseController.value;
            return Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.foodColor,
                boxShadow: [
                  BoxShadow(
                    color: theme.foodColor.withValues(alpha: 0.4 + 0.4 * t),
                    blurRadius: 6 + 6 * t,
                    spreadRadius: 0.5 + t,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: theme.accentColor.withValues(alpha: 0.85),
            letterSpacing: 2.4,
          ),
        ),
      ],
    );
  }

  /// The mode you're about to play — a neon icon disc + label/name/desc.
  /// Borderless: a glowing tinted disc carries it, no panel box.
  Widget _buildModeHero(GameTheme theme, GameMode mode, bool isOverride) {
    final accent = isOverride ? const Color(0xFFFFC857) : theme.neonSecondary;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.14),
            boxShadow: softGlow(accent, intensity: 0.55),
          ),
          child: Text(mode.icon, style: const TextStyle(fontSize: 24)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      isOverride ? 'TOURNAMENT MODE' : 'GAME MODE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: accent.withValues(alpha: 0.85),
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                  if (isOverride) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.emoji_events_rounded, size: 12, color: accent),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                mode.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: theme.textPrimary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                mode.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  color: theme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlChip(GameTheme theme, bool dPad) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(GameTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            dPad ? Icons.gamepad_rounded : Icons.swipe_rounded,
            size: 16,
            color: theme.accentColor,
          ),
          const SizedBox(width: 8),
          Text(
            dPad ? 'D-Pad Controls' : 'Swipe Controls',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.accentColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ---- RIGHT: live status + progress + record + tip ----

  Widget _buildStatus(GameTheme theme, int highScore, bool isSmall) {
    final level = ProgressionService().level;
    final games = StatisticsService().statistics.totalGamesPlayed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Rotating status line driven by the progress controller.
        AnimatedBuilder(
          animation: _progressController,
          builder: (context, _) =>
              _buildStatusLine(theme, _statusFor(_progressController.value)),
        ),
        SizedBox(height: isSmall ? 12 : 18),
        _buildProgressBar(theme),
        SizedBox(height: isSmall ? 16 : 24),
        _buildStatsRow(theme, level, highScore, games),
        SizedBox(height: isSmall ? 16 : 24),
        _buildTip(theme, isSmall),
      ],
    ).gameEntrance(delay: 120.ms);
  }

  Widget _buildStatusLine(GameTheme theme, String label) {
    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            final t = _pulseController.value;
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.accentColor,
                boxShadow: [
                  BoxShadow(
                    color: theme.accentColor.withValues(alpha: 0.4 + 0.4 * t),
                    blurRadius: 4 + 4 * t,
                    spreadRadius: 0.5 + t,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: theme.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(GameTheme theme) {
    return AnimatedBuilder(
      animation: _progressController,
      builder: (context, _) {
        final p = _progressController.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Slim neon bar — borderless track per the clean design.
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    return Stack(
                      children: [
                        Container(color: Colors.white.withValues(alpha: 0.08)),
                        FractionallySizedBox(
                          widthFactor: p.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.accentColor,
                                  theme.foodColor,
                                  theme.accentColor,
                                ],
                                stops: const [0.0, 0.5, 1.0],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.foodColor.withValues(alpha: 0.45),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Sliding shimmer streak across the bar.
                        AnimatedBuilder(
                          animation: _shimmerController,
                          builder: (context, _) => Positioned(
                            left: _shimmerController.value * w - 45,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                width: 45,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0.0),
                                      Colors.white.withValues(alpha: 0.35),
                                      Colors.white.withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PREPARING',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.textMuted,
                    letterSpacing: 1.6,
                  ),
                ),
                Text(
                  '${(p * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: theme.accentColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Your record — three compact stats, borderless with hairline dividers.
  Widget _buildStatsRow(GameTheme theme, int level, int best, int games) {
    return Row(
      children: [
        Expanded(
          child: _statTile(
            theme,
            Icons.military_tech_rounded,
            '$level',
            'LEVEL',
          ),
        ),
        _statDivider(theme),
        Expanded(
          child: _statTile(
            theme,
            Icons.emoji_events_rounded,
            _compactNumber(best),
            'BEST',
          ),
        ),
        _statDivider(theme),
        Expanded(
          child: _statTile(
            theme,
            Icons.sports_esports_rounded,
            _compactNumber(games),
            'GAMES',
          ),
        ),
      ],
    );
  }

  Widget _statDivider(GameTheme theme) {
    return Container(
      width: 1,
      height: 34,
      color: theme.accentColor.withValues(alpha: 0.18),
    );
  }

  Widget _statTile(
    GameTheme theme,
    IconData icon,
    String value,
    String label,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: theme.foodColor.withValues(alpha: 0.95)),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: theme.primaryColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: theme.accentColor.withValues(alpha: 0.7),
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }

  /// 1234 -> "1.2K", 1500000 -> "1.5M". Keeps the tiles from overflowing on
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

  Widget _buildTip(GameTheme theme, bool isSmall) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.lightbulb_rounded,
              size: 15,
              color: theme.foodColor,
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 900.ms)
                .then()
                .fade(begin: 1.0, end: 0.5, duration: 900.ms),
            const SizedBox(width: 8),
            Text(
              'PRO TIP',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: theme.accentColor.withValues(alpha: 0.85),
                letterSpacing: 1.8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Rotating tip with a smooth fade/slide; fixed height stops jumps.
        SizedBox(
          height: isSmall ? 44 : 52,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0.0, 0.18),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: Text(
              _tips[_tipIndex],
              key: ValueKey<int>(_tipIndex),
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: theme.primaryColor.withValues(alpha: 0.92),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Stage {
  final double threshold;
  final String label;
  const _Stage(this.threshold, this.label);
}

class _LoadingParticle {
  double x;
  double y;
  final double speed;
  final double size;
  final double opacity;

  _LoadingParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
    required this.opacity,
  });
}

class _ParticleLayer extends StatelessWidget {
  final AnimationController controller;
  final List<_LoadingParticle> particles;
  final GameTheme theme;

  const _ParticleLayer({
    required this.controller,
    required this.particles,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _ParticlePainter(
            particles: particles,
            t: controller.value,
            accent: theme.accentColor,
            food: theme.foodColor,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_LoadingParticle> particles;
  final double t;
  final Color accent;
  final Color food;

  _ParticlePainter({
    required this.particles,
    required this.t,
    required this.accent,
    required this.food,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final rng = Random();

    for (int i = 0; i < particles.length; i++) {
      final p = particles[i];
      p.y -= p.speed * 0.008;
      if (p.y < -0.05) {
        p.y = 1.05;
        p.x = rng.nextDouble();
      }

      // Alternate particle tint between accent and food so the field
      // reads as belonging to the active theme without feeling flat.
      paint.color = (i.isEven ? accent : food)
          .withValues(alpha: p.opacity * 0.55);

      final pos = Offset(p.x * size.width, p.y * size.height);
      canvas.drawCircle(pos, p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) => true;
}
