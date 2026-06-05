import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
///   1. Give the player a beautiful 4.5-second buffer with tips, animations,
///      and a progress bar so the jump into gameplay feels deliberate.
///   2. Opportunistically warm up gameplay dependencies that are cheap and
///      idempotent — audio (already preloaded in main; this just touches the
///      singleton), and a paint of the AppBackground in the active theme.
///
/// When the timer completes, the screen does a `pushReplacement` to
/// `AppRoutes.game` so back navigation from the game returns to Home, not
/// to this screen.
class PreGameLoadingScreen extends StatefulWidget {
  const PreGameLoadingScreen({super.key});

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
    context.pushReplacement(AppRoutes.game);
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
        // The active mode is the player's settings choice unless the cubit
        // has a tournament override staged (set via setTournamentMode before
        // the user tapped Play). We resolve both so the card can flag the
        // override and the inner description still picks up.
        final tournamentMode = context
            .select<GameCubit, TournamentGameMode?>(
                (c) => c.state.tournamentMode);
        final settingsMode = context
            .select<GameSettingsCubit, GameMode>((c) => c.state.gameMode);
        final activeMode = tournamentMode?.toGameMode() ?? settingsMode;
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
                // Themed particles streaming upward.
                _ParticleLayer(
                  controller: _particleController,
                  particles: _particles,
                  theme: theme,
                ),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final isSmallScreen = constraints.maxHeight < 700;
                    final logoSize = isSmallScreen ? 120.0 : 150.0;

                    return Column(
                      children: [
                        _buildTopBanner(theme, isSmallScreen),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: isSmallScreen ? 8 : 16,
                            ),
                            child: Column(
                              children: [
                                SizedBox(height: isSmallScreen ? 8 : 20),
                                _buildHeroLogo(theme, logoSize),
                                SizedBox(height: isSmallScreen ? 18 : 28),
                                _buildModeCard(
                                  theme,
                                  activeMode,
                                  settingsMode,
                                ),
                                SizedBox(height: isSmallScreen ? 14 : 20),
                                _buildControlChip(theme, dPadEnabled),
                                SizedBox(height: isSmallScreen ? 16 : 24),
                                _buildStatsStrip(theme, highScore),
                                SizedBox(height: isSmallScreen ? 16 : 24),
                                _buildTipCard(theme),
                              ],
                            ),
                          ),
                        ),
                        _buildProgressFooter(theme, isSmallScreen),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBanner(GameTheme theme, bool isSmallScreen) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, isSmallScreen ? 8 : 14, 20, 4),
      child: Row(
        children: [
          // Small breathing dot — same idiom as the existing app-load
          // screen so the two feel like siblings.
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final t = _pulseController.value;
              return Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.foodColor,
                  boxShadow: [
                    BoxShadow(
                      color:
                          theme.foodColor.withValues(alpha: 0.4 + 0.4 * t),
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
            'PREPARING LAUNCH',
            style: TextStyle(
              fontSize: isSmallScreen ? 11 : 13,
              fontWeight: FontWeight.w800,
              color: theme.accentColor.withValues(alpha: 0.85),
              letterSpacing: 2.2,
            ),
          ).gameEntrance(),
          const Spacer(),
          // Theme name badge — tells the player which world is loading.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              theme.name.toUpperCase(),
              style: TextStyle(
                color: theme.accentColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ).gameEntrance(delay: 120.ms),
        ],
      ),
    );
  }

  Widget _buildHeroLogo(GameTheme theme, double size) {
    return AnimatedBuilder(
      animation: _logoController,
      builder: (context, _) {
        final t = _logoController.value;
        final pulse = 1.0 + (sin(t * 2 * pi) * 0.04);
        return Transform.scale(
          scale: pulse,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  theme.accentColor.withValues(alpha: 0.25),
                  theme.accentColor.withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.accentColor.withValues(alpha: 0.35),
                  blurRadius: 40,
                  spreadRadius: 6,
                ),
                BoxShadow(
                  color: theme.foodColor.withValues(alpha: 0.18),
                  blurRadius: 60,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              // The official brand mark — same rocket glyph as the loading
              // screen / home / About (the transparent PNG never shipped).
              child: Icon(
                Icons.rocket_launch,
                size: size * 0.55,
                color: theme.accentColor,
              ),
            ),
          ),
        );
      },
    ).gameZoomIn();
  }

  Widget _buildModeCard(
    GameTheme theme,
    GameMode activeMode,
    GameMode settingsMode,
  ) {
    // If the cubit's mode differs from settings, it's a tournament override.
    // Surface that so the player knows the rules are not their picked mode.
    final isOverride = activeMode != settingsMode;

    return GlassPanel(
      theme: theme,
      glow: true,
      radius: GameTokens.radiusLg,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.backgroundColor.withValues(alpha: 0.55),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              activeMode.icon,
              style: const TextStyle(fontSize: 26),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      isOverride ? 'TOURNAMENT MODE' : 'GAME MODE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.accentColor.withValues(alpha: 0.75),
                        letterSpacing: 1.6,
                      ),
                    ),
                    if (isOverride) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.emoji_events_rounded,
                        size: 12,
                        color: Colors.amber.withValues(alpha: 0.9),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  activeMode.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: theme.primaryColor,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  activeMode.description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: theme.accentColor.withValues(alpha: 0.78),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    ).gameEntrance(delay: 150.ms);
  }

  Widget _buildControlChip(GameTheme theme, bool dPadEnabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.backgroundColor.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.accentColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            dPadEnabled ? Icons.gamepad_rounded : Icons.swipe_rounded,
            size: 16,
            color: theme.accentColor,
          ),
          const SizedBox(width: 8),
          Text(
            dPadEnabled ? 'D-Pad Controls' : 'Swipe Controls',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.accentColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    ).gameEntrance(delay: 220.ms);
  }

  /// Compact "your record" strip — gives the pre-game moment some stakes by
  /// surfacing the player's lifetime level, personal best, and games played.
  /// All three come from already-hydrated singletons/cubits (no async read).
  Widget _buildStatsStrip(GameTheme theme, int highScore) {
    final level = ProgressionService().level;
    final games = StatisticsService().statistics.totalGamesPlayed;

    return GlassPanel(
      theme: theme,
      radius: GameTokens.radiusPanel,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
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
              _compactNumber(highScore),
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
      ),
    ).gameEntrance(delay: 260.ms);
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

  Widget _buildTipCard(GameTheme theme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
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
      child: GlassPanel(
        key: ValueKey<int>(_tipIndex),
        theme: theme,
        radius: GameTokens.radiusPanel,
        width: double.infinity,
        borderColor: theme.foodColor.withValues(alpha: 0.35),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_rounded,
                  size: 16,
                  color: Colors.amber.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 8),
                Text(
                  'PRO TIP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.amber.withValues(alpha: 0.9),
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _tips[_tipIndex],
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: theme.primaryColor.withValues(alpha: 0.92),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressFooter(GameTheme theme, bool isSmallScreen) {
    return Padding(
      padding: EdgeInsets.fromLTRB(28, 8, 28, isSmallScreen ? 18 : 28),
      child: AnimatedBuilder(
        animation: _progressController,
        builder: (context, _) {
          final progress = _progressController.value;
          final label = _statusFor(progress);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.primaryColor.withValues(alpha: 0.92),
                        letterSpacing: 0.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.accentColor.withValues(alpha: 0.32),
                      ),
                    ),
                    child: Text(
                      '${(progress * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: theme.accentColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.backgroundColor.withValues(alpha: 0.55),
                    border: Border.all(
                      color: theme.accentColor.withValues(alpha: 0.22),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Travel the shimmer across the actual progress-bar
                      // width, not the whole screen — otherwise the streak
                      // overshoots the bar (which is screen-width minus the
                      // card padding).
                      final barWidth = constraints.maxWidth;
                      return Stack(
                    children: [
                      FractionallySizedBox(
                        widthFactor: progress,
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
                      // Sliding shimmer streak across the fill.
                      AnimatedBuilder(
                        animation: _shimmerController,
                        builder: (context, _) {
                          return Positioned(
                            left: _shimmerController.value * barWidth - 60,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                width: 60,
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
                          );
                        },
                      ),
                    ],
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
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
