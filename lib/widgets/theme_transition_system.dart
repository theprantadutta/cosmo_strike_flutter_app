import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

enum TransitionType { fade, slide, morph, particle, ripple, spiral, wave }

class ThemeTransitionController extends ChangeNotifier {
  final TickerProvider vsync;
  late AnimationController _controller;
  late Animation<double> _animation;

  GameTheme? _fromTheme;
  GameTheme? _toTheme;
  TransitionType _transitionType = TransitionType.fade;
  bool _isTransitioning = false;

  VoidCallback? onTransitionComplete;

  ThemeTransitionController({required this.vsync}) {
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: vsync,
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _isTransitioning = false;
        onTransitionComplete?.call();
        notifyListeners();
      }
    });

    _controller.addListener(() {
      notifyListeners();
    });
  }

  bool get isTransitioning => _isTransitioning;
  double get progress => _animation.value;
  GameTheme? get fromTheme => _fromTheme;
  GameTheme? get toTheme => _toTheme;
  TransitionType get transitionType => _transitionType;

  Future<void> transitionToTheme(
    GameTheme newTheme, {
    TransitionType type = TransitionType.fade,
    Duration? duration,
  }) async {
    if (_isTransitioning) return;

    _fromTheme = _toTheme ?? GameTheme.classic;
    _toTheme = newTheme;
    _transitionType = type;
    _isTransitioning = true;

    if (duration != null) {
      _controller.duration = duration;
    }

    _controller.reset();
    await _controller.forward();
  }

  Color lerpColor(Color fromColor, Color toColor) {
    return Color.lerp(fromColor, toColor, progress) ?? fromColor;
  }

  double lerpDouble(double from, double to) {
    return from + (to - from) * progress;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class ThemeTransitionWidget extends StatefulWidget {
  final Widget child;
  final ThemeTransitionController controller;
  final GameTheme currentTheme;

  const ThemeTransitionWidget({
    super.key,
    required this.child,
    required this.controller,
    required this.currentTheme,
  });

  @override
  State<ThemeTransitionWidget> createState() => _ThemeTransitionWidgetState();
}

class _ThemeTransitionWidgetState extends State<ThemeTransitionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _effectController;
  late Animation<double> _effectAnimation;

  @override
  void initState() {
    super.initState();

    _effectController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _effectAnimation = CurvedAnimation(
      parent: _effectController,
      curve: Curves.easeInOut,
    );

    widget.controller.addListener(_onTransitionUpdate);
  }

  @override
  void dispose() {
    _effectController.dispose();
    widget.controller.removeListener(_onTransitionUpdate);
    super.dispose();
  }

  void _onTransitionUpdate() {
    setState(() {});

    if (widget.controller.isTransitioning && !_effectController.isAnimating) {
      _effectController.forward(from: 0.0);
    }

    if (!widget.controller.isTransitioning && _effectController.isAnimating) {
      _effectController.stop();
      _effectController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isTransitioning) {
      return widget.child;
    }

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: CustomPaint(
            painter: TransitionEffectPainter(
              progress: widget.controller.progress,
              fromTheme: widget.controller.fromTheme ?? widget.currentTheme,
              toTheme: widget.controller.toTheme ?? widget.currentTheme,
              transitionType: widget.controller.transitionType,
              effectProgress: _effectAnimation.value,
            ),
          ),
        ),
      ],
    );
  }
}

class TransitionEffectPainter extends CustomPainter {
  final double progress;
  final GameTheme fromTheme;
  final GameTheme toTheme;
  final TransitionType transitionType;
  final double effectProgress;

  TransitionEffectPainter({
    required this.progress,
    required this.fromTheme,
    required this.toTheme,
    required this.transitionType,
    required this.effectProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (transitionType) {
      case TransitionType.fade:
        _paintFadeTransition(canvas, size);
        break;
      case TransitionType.slide:
        _paintSlideTransition(canvas, size);
        break;
      case TransitionType.morph:
        _paintMorphTransition(canvas, size);
        break;
      case TransitionType.particle:
        _paintParticleTransition(canvas, size);
        break;
      case TransitionType.ripple:
        _paintRippleTransition(canvas, size);
        break;
      case TransitionType.spiral:
        _paintSpiralTransition(canvas, size);
        break;
      case TransitionType.wave:
        _paintWaveTransition(canvas, size);
        break;
    }
  }

  void _paintFadeTransition(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = toTheme.backgroundColor.withValues(alpha: progress)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintSlideTransition(Canvas canvas, Size size) {
    // Draw sliding color bars
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 5; i++) {
      final barHeight = size.height / 5;
      final y = i * barHeight;
      final delay = i * 0.1;
      final barProgress = ((progress - delay) / (1.0 - delay)).clamp(0.0, 1.0);

      paint.color =
          Color.lerp(
            fromTheme.backgroundColor,
            toTheme.backgroundColor,
            barProgress,
          ) ??
          toTheme.backgroundColor;

      final barWidth = size.width * barProgress;
      canvas.drawRect(Rect.fromLTWH(0, y, barWidth, barHeight), paint);
    }
  }

  void _paintMorphTransition(Canvas canvas, Size size) {
    final morphProgress = Curves.elasticOut.transform(progress);

    // Create morphing shapes that blend between themes
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color =
          Color.lerp(
            fromTheme.accentColor,
            toTheme.accentColor,
            morphProgress,
          ) ??
          toTheme.accentColor;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    final radius = maxRadius * morphProgress;

    // Draw expanding circle with morphing color
    canvas.drawCircle(center, radius, paint);

    // Add morphing accent shapes
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * math.pi * 2;
      final shapeRadius = radius * 0.3;
      final shapeCenter = Offset(
        center.dx + math.cos(angle) * radius * 0.7,
        center.dy + math.sin(angle) * radius * 0.7,
      );

      if (shapeRadius > 0) {
        paint.color =
            Color.lerp(
              fromTheme.foodColor,
              toTheme.foodColor,
              morphProgress,
            )?.withValues(alpha: 0.6) ??
            toTheme.foodColor.withValues(alpha: 0.6);

        canvas.drawCircle(shapeCenter, shapeRadius * 0.5, paint);
      }
    }
  }

  void _paintParticleTransition(Canvas canvas, Size size) {
    final particleCount = 50;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < particleCount; i++) {
      final particleProgress = ((progress * 1.5 - i * 0.02).clamp(0.0, 1.0));
      if (particleProgress <= 0) continue;

      // Calculate particle position
      final startX = (i * 37) % size.width.toInt();
      final startY = (i * 67) % size.height.toInt();

      final targetX = size.width / 2;
      final targetY = size.height / 2;

      final currentX = startX + (targetX - startX) * particleProgress;
      final currentY = startY + (targetY - startY) * particleProgress;

      // Particle color transition
      paint.color =
          Color.lerp(
            fromTheme.shipColor,
            toTheme.shipColor,
            particleProgress,
          )?.withValues(alpha: particleProgress) ??
          toTheme.shipColor.withValues(alpha: particleProgress);

      final particleSize = (math.sin(particleProgress * math.pi) * 6).clamp(
        1.0,
        6.0,
      );
      canvas.drawCircle(Offset(currentX, currentY), particleSize, paint);
    }
  }

  void _paintRippleTransition(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.sqrt(
      size.width * size.width + size.height * size.height,
    );

    // Draw multiple ripples
    for (int i = 0; i < 3; i++) {
      final rippleDelay = i * 0.3;
      final rippleProgress = ((progress - rippleDelay) / (1.0 - rippleDelay))
          .clamp(0.0, 1.0);

      if (rippleProgress <= 0) continue;

      final rippleRadius = maxRadius * Curves.easeOut.transform(rippleProgress);
      final rippleOpacity = (1.0 - rippleProgress) * 0.5;

      final paint = Paint()
        ..color =
            Color.lerp(
              fromTheme.accentColor,
              toTheme.accentColor,
              rippleProgress,
            )?.withValues(alpha: rippleOpacity) ??
            toTheme.accentColor.withValues(alpha: rippleOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0;

      canvas.drawCircle(center, rippleRadius, paint);
    }
  }

  void _paintSpiralTransition(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final spiralTurns = 3;
    final maxRadius = math.min(size.width, size.height) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0;

    final path = Path();
    final steps = 100;

    for (int i = 0; i <= steps; i++) {
      final t = (i / steps) * progress;
      final angle = t * spiralTurns * 2 * math.pi;
      final radius = t * maxRadius;

      final x = center.dx + math.cos(angle) * radius;
      final y = center.dy + math.sin(angle) * radius;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Color gradient along spiral
    paint.color =
        Color.lerp(fromTheme.shipColor, toTheme.shipColor, progress) ??
        toTheme.shipColor;

    canvas.drawPath(path, paint);
  }

  void _paintWaveTransition(Canvas canvas, Size size) {
    final waveCount = 5;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int wave = 0; wave < waveCount; wave++) {
      final waveDelay = wave * 0.1;
      final waveProgress = ((progress - waveDelay) / (1.0 - waveDelay)).clamp(
        0.0,
        1.0,
      );

      if (waveProgress <= 0) continue;

      final path = Path();
      final waveHeight = size.height * waveProgress;

      path.moveTo(0, size.height);

      for (double x = 0; x <= size.width; x += 5) {
        final waveOffset =
            math.sin(
              (x / size.width + wave * 0.2 + effectProgress) * math.pi * 4,
            ) *
            20;
        final y = size.height - waveHeight + waveOffset;
        path.lineTo(x, y);
      }

      path.lineTo(size.width, size.height);
      path.close();

      paint.color =
          Color.lerp(
            fromTheme.backgroundColor,
            toTheme.backgroundColor,
            waveProgress,
          )?.withValues(alpha: 0.7) ??
          toTheme.backgroundColor.withValues(alpha: 0.7);

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant TransitionEffectPainter oldDelegate) {
    return progress != oldDelegate.progress ||
        fromTheme != oldDelegate.fromTheme ||
        toTheme != oldDelegate.toTheme ||
        transitionType != oldDelegate.transitionType ||
        effectProgress != oldDelegate.effectProgress;
  }
}

// Helper widget for theme-aware components during transitions
class TransitionAwareThemeBuilder extends StatelessWidget {
  final ThemeTransitionController controller;
  final GameTheme currentTheme;
  final Widget Function(
    BuildContext context,
    GameTheme effectiveTheme,
    bool isTransitioning,
  )
  builder;

  const TransitionAwareThemeBuilder({
    super.key,
    required this.controller,
    required this.currentTheme,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final effectiveTheme = controller.isTransitioning
            ? (controller.toTheme ?? currentTheme)
            : currentTheme;

        return builder(context, effectiveTheme, controller.isTransitioning);
      },
    );
  }
}

// Utility class for creating theme transition presets
class ThemeTransitionPresets {
  static const Map<GameTheme, TransitionType> themePreferredTransitions = {
    GameTheme.classic: TransitionType.fade,
    GameTheme.modern: TransitionType.slide,
    GameTheme.neon: TransitionType.particle,
    GameTheme.retro: TransitionType.spiral,
    GameTheme.space: TransitionType.ripple,
    GameTheme.ocean: TransitionType.wave,
    GameTheme.cyberpunk: TransitionType.particle,
    GameTheme.forest: TransitionType.morph,
    GameTheme.desert: TransitionType.wave,
    GameTheme.crystal: TransitionType.ripple,
  };

  static TransitionType getPreferredTransition(GameTheme theme) {
    return themePreferredTransitions[theme] ?? TransitionType.fade;
  }

  static Duration getTransitionDuration(TransitionType type) {
    switch (type) {
      case TransitionType.fade:
        return const Duration(milliseconds: 800);
      case TransitionType.slide:
        return const Duration(milliseconds: 1200);
      case TransitionType.morph:
        return const Duration(milliseconds: 1500);
      case TransitionType.particle:
        return const Duration(milliseconds: 2000);
      case TransitionType.ripple:
        return const Duration(milliseconds: 1000);
      case TransitionType.spiral:
        return const Duration(milliseconds: 1800);
      case TransitionType.wave:
        return const Duration(milliseconds: 1400);
    }
  }
}
