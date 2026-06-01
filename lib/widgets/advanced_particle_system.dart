import 'dart:math' as math;
import 'package:flutter/material.dart';

enum ParticleType {
  explosion,
  sparkle,
  trail,
  food,
  score,
  powerUp,
  smoke,
  glow,
}

enum ParticleBlendMode { normal, additive, multiply, screen }

class ParticleConfig {
  final ParticleType type;
  final int count;
  final Duration lifetime;
  final double minSize;
  final double maxSize;
  final double minSpeed;
  final double maxSpeed;
  final List<Color> colors;
  final ParticleBlendMode blendMode;
  final bool hasTrail;
  final double gravity;
  final double friction;
  final bool fadeSizeOverTime;
  final bool fadeAlphaOverTime;
  final double emissionAngleRange; // In radians
  final bool useRandomDirections;

  const ParticleConfig({
    required this.type,
    this.count = 20,
    this.lifetime = const Duration(milliseconds: 1000),
    this.minSize = 2.0,
    this.maxSize = 6.0,
    this.minSpeed = 50.0,
    this.maxSpeed = 150.0,
    this.colors = const [Colors.white],
    this.blendMode = ParticleBlendMode.normal,
    this.hasTrail = false,
    this.gravity = 0.0,
    this.friction = 0.98,
    this.fadeSizeOverTime = true,
    this.fadeAlphaOverTime = true,
    this.emissionAngleRange = math.pi * 2, // Full circle by default
    this.useRandomDirections = true,
  });

  // Predefined particle configurations
  static const ParticleConfig foodExplosion = ParticleConfig(
    type: ParticleType.food,
    count: 25, // Increased from 15
    lifetime: Duration(milliseconds: 1200), // Extended duration
    minSize: 4.0, // Increased from 3.0
    maxSize: 12.0, // Increased from 8.0
    minSpeed: 100.0, // Increased from 80.0
    maxSpeed: 280.0, // Increased from 200.0
    colors: [
      Color(0xFFFFD700), // Gold
      Color(0xFFFF6B6B), // Red
      Color(0xFF4ECDC4), // Teal
      Color(0xFFFF69B4), // Hot pink
      Color(0xFF00FF7F), // Spring green
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: 180.0, // Reduced slightly for better spread
    friction: 0.94, // Reduced for longer travel
  );

  // Food explosion configurations - reduced for better snake visibility
  static const ParticleConfig appleFoodExplosion = ParticleConfig(
    type: ParticleType.food,
    count: 8, // Reduced from 20
    lifetime: Duration(milliseconds: 600), // Shorter
    minSize: 2.0,
    maxSize: 5.0, // Smaller particles
    minSpeed: 60.0,
    maxSpeed: 140.0,
    colors: [
      Color(0xFFDC143C), // Crimson red
      Color(0xFFFFD700), // Gold sparkle
      Color(0xFFFFA500), // Orange
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: 250.0, // Higher gravity = faster fall
    friction: 0.96,
  );

  static const ParticleConfig bonusFoodExplosion = ParticleConfig(
    type: ParticleType.food,
    count: 12, // Reduced from 35
    lifetime: Duration(milliseconds: 800), // Shorter
    minSize: 2.5,
    maxSize: 7.0, // Smaller
    minSpeed: 80.0,
    maxSpeed: 180.0,
    colors: [
      Color(0xFFFFD700), // Gold
      Color(0xFFFF1493), // Deep pink
      Color(0xFFFFFF00), // Yellow
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: 200.0,
    friction: 0.94,
    hasTrail: false, // Removed trails
  );

  static const ParticleConfig specialFoodExplosion = ParticleConfig(
    type: ParticleType.food,
    count: 18, // Reduced from 50
    lifetime: Duration(milliseconds: 1000), // Shorter
    minSize: 3.0,
    maxSize: 9.0, // Much smaller
    minSpeed: 100.0,
    maxSpeed: 220.0,
    colors: [
      Color(0xFFFFD700), // Gold
      Color(0xFFFF1493), // Deep pink
      Color(0xFF00FFFF), // Cyan
      Color(0xFF9370DB), // Medium orchid
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: 150.0,
    friction: 0.93,
    hasTrail: false, // Removed trails for clarity
  );

  static const ParticleConfig scorePopup = ParticleConfig(
    type: ParticleType.score,
    count: 8,
    lifetime: Duration(milliseconds: 1200),
    minSize: 4.0,
    maxSize: 12.0,
    minSpeed: 40.0,
    maxSpeed: 120.0,
    colors: [
      Color(0xFFFFD700), // Gold
      Color(0xFFFFA500), // Orange
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: -100.0, // Float upward
    friction: 0.92,
    emissionAngleRange: math.pi, // Semi-circle upward
  );

  static const ParticleConfig snakeTrail = ParticleConfig(
    type: ParticleType.trail,
    count: 5,
    lifetime: Duration(milliseconds: 600),
    minSize: 2.0,
    maxSize: 6.0,
    minSpeed: 10.0,
    maxSpeed: 30.0,
    colors: [
      Color(0xFF00FF00), // Green
      Color(0xFF00FFFF), // Cyan
    ],
    blendMode: ParticleBlendMode.additive,
    hasTrail: true,
    friction: 0.88,
    useRandomDirections: false,
  );

  static const ParticleConfig powerUpGlow = ParticleConfig(
    type: ParticleType.powerUp,
    count: 20, // Increased from 12
    lifetime: Duration(milliseconds: 2000), // Extended from 1500
    minSize: 8.0, // Increased from 6.0
    maxSize: 18.0, // Increased from 15.0
    minSpeed: 40.0, // Increased from 30.0
    maxSpeed: 120.0, // Increased from 80.0
    colors: [
      Color(0xFFFFD700), // Gold
      Color(0xFFFF69B4), // Hot pink
      Color(0xFF00FFFF), // Cyan
      Color(0xFF9370DB), // Medium orchid
      Color(0xFF00FF7F), // Spring green
      Color(0xFFFF4500), // Orange red
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: -80.0, // More upward movement
    friction: 0.92, // Less friction for more dramatic effect
    hasTrail: true,
  );

  // Enhanced power-up specific collection effects
  static const ParticleConfig speedBoostCollection = ParticleConfig(
    type: ParticleType.powerUp,
    count: 30,
    lifetime: Duration(milliseconds: 1800),
    minSize: 4.0,
    maxSize: 16.0,
    minSpeed: 80.0,
    maxSpeed: 250.0,
    colors: [
      Color(0xFFFFD700), // Gold
      Color(0xFFFFFF00), // Yellow
      Color(0xFFFFB347), // Peach
      Color(0xFFFFF8DC), // Cornsilk
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: -60.0,
    friction: 0.88,
    hasTrail: true,
  );

  static const ParticleConfig invincibilityCollection = ParticleConfig(
    type: ParticleType.powerUp,
    count: 25,
    lifetime: Duration(milliseconds: 2200),
    minSize: 6.0,
    maxSize: 20.0,
    minSpeed: 50.0,
    maxSpeed: 180.0,
    colors: [
      Color(0xFF00FFFF), // Cyan
      Color(0xFF87CEEB), // Sky blue
      Color(0xFFE0E0E0), // Light gray
      Color(0xFFFFFFFF), // White
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: -40.0,
    friction: 0.95,
    hasTrail: true,
  );

  static const ParticleConfig scoreMultiplierCollection = ParticleConfig(
    type: ParticleType.powerUp,
    count: 35,
    lifetime: Duration(milliseconds: 2500),
    minSize: 5.0,
    maxSize: 18.0,
    minSpeed: 60.0,
    maxSpeed: 200.0,
    colors: [
      Color(0xFFFFD700), // Gold
      Color(0xFFFF8C00), // Dark orange
      Color(0xFFDAA520), // Goldenrod
      Color(0xFFFFA500), // Orange
      Color(0xFFFFFF00), // Yellow
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: -100.0, // Strong upward movement for coins
    friction: 0.90,
    hasTrail: true,
  );

  static const ParticleConfig slowMotionCollection = ParticleConfig(
    type: ParticleType.powerUp,
    count: 28,
    lifetime: Duration(milliseconds: 3000), // Longest for slow motion effect
    minSize: 7.0,
    maxSize: 14.0,
    minSpeed: 20.0, // Slower movement to match theme
    maxSpeed: 100.0,
    colors: [
      Color(0xFF9370DB), // Medium orchid
      Color(0xFF8A2BE2), // Blue violet
      Color(0xFF9932CC), // Dark orchid
      Color(0xFFBA55D3), // Medium orchid
      Color(0xFFDDA0DD), // Plum
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: -30.0, // Gentle floating
    friction: 0.98, // Very low friction for smooth movement
    hasTrail: true,
  );

  static const ParticleConfig explosion = ParticleConfig(
    type: ParticleType.explosion,
    count: 25,
    lifetime: Duration(milliseconds: 1000),
    minSize: 4.0,
    maxSize: 12.0,
    minSpeed: 100.0,
    maxSpeed: 300.0,
    colors: [
      Color(0xFFFF4444), // Red
      Color(0xFFFF8800), // Orange
      Color(0xFFFFDD00), // Yellow
    ],
    blendMode: ParticleBlendMode.additive,
    gravity: 150.0,
    friction: 0.96,
  );

  static const ParticleConfig sparkle = ParticleConfig(
    type: ParticleType.sparkle,
    count: 10,
    lifetime: Duration(milliseconds: 800),
    minSize: 1.0,
    maxSize: 4.0,
    minSpeed: 20.0,
    maxSpeed: 60.0,
    colors: [
      Color(0xFFFFFFFF), // White
      Color(0xFFFFD700), // Gold
    ],
    blendMode: ParticleBlendMode.additive,
    friction: 0.90,
  );
}

class ParticleData {
  final ParticleConfig config;
  double x, y;
  double vx, vy; // Velocity
  double size;
  Color color;
  double life; // 0.0 to 1.0, 1.0 = just born
  final double initialSize;
  final Color initialColor;
  final double rotation;
  final double rotationSpeed;
  final List<Offset> trail;

  ParticleData({
    required this.config,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    this.life = 1.0,
    double? rotation,
    double? rotationSpeed,
  }) : initialSize = size,
       initialColor = color,
       rotation = rotation ?? 0.0,
       rotationSpeed = rotationSpeed ?? 0.0,
       trail = config.hasTrail ? <Offset>[] : <Offset>[];

  void update(double deltaTime) {
    // Update position
    x += vx * deltaTime;
    y += vy * deltaTime;

    // Apply gravity
    vy += config.gravity * deltaTime;

    // Apply friction
    vx *= config.friction;
    vy *= config.friction;

    // Update life
    life -= deltaTime / (config.lifetime.inMilliseconds / 1000.0);
    life = math.max(0.0, life);

    // Update visual properties based on life
    if (config.fadeSizeOverTime) {
      size = initialSize * life;
    }

    if (config.fadeAlphaOverTime) {
      color = initialColor.withValues(alpha: life);
    }

    // Update trail
    if (config.hasTrail && life > 0) {
      trail.add(Offset(x, y));
      if (trail.length > 10) {
        trail.removeAt(0);
      }
    }
  }

  bool get isDead => life <= 0.0;
}

class AdvancedParticleSystem extends StatefulWidget {
  final List<ParticleEmission> emissions;
  final bool autoRemoveEmissions;

  const AdvancedParticleSystem({
    super.key,
    required this.emissions,
    this.autoRemoveEmissions = true,
  });

  @override
  State<AdvancedParticleSystem> createState() => _AdvancedParticleSystemState();
}

class ParticleEmission {
  final ParticleConfig config;
  final Offset position;
  final DateTime createdAt;
  final Duration? duration;
  bool isActive;

  ParticleEmission({
    required this.config,
    required this.position,
    this.duration,
    this.isActive = true,
  }) : createdAt = DateTime.now();

  bool get shouldExpire {
    if (duration == null) return false;
    return DateTime.now().difference(createdAt) > duration!;
  }
}

class _AdvancedParticleSystemState extends State<AdvancedParticleSystem>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  final List<ParticleData> _particles = [];
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(
        seconds: 10,
      ), // Long duration for continuous animation
      vsync: this,
    )..repeat();

    _controller.addListener(_updateParticles);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateParticles() {
    final now = DateTime.now();
    final deltaTime = _lastUpdate != null
        ? now.difference(_lastUpdate!).inMilliseconds / 1000.0
        : 0.016; // ~60fps fallback
    _lastUpdate = now;

    // Add new particles from active emissions
    for (final emission in widget.emissions) {
      if (emission.isActive && !emission.shouldExpire) {
        _addParticlesFromEmission(emission);
        emission.isActive = false; // Only emit once per emission
      }
    }

    // Update existing particles
    _particles.removeWhere((particle) {
      particle.update(deltaTime);
      return particle.isDead;
    });

    // Remove expired emissions
    if (widget.autoRemoveEmissions) {
      widget.emissions.removeWhere((emission) => emission.shouldExpire);
    }

    // Performance: Stop the controller when there are no particles to animate.
    // This prevents 60fps setState calls when the particle system is idle.
    // The controller is restarted in didUpdateWidget when new emissions arrive.
    if (_particles.isEmpty) {
      _controller.stop();
      _lastUpdate = null;
      return;
    }

    setState(() {});
  }

  @override
  void didUpdateWidget(AdvancedParticleSystem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart the animation controller if new active emissions arrive while idle
    if (widget.emissions.any((e) => e.isActive) && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  void _addParticlesFromEmission(ParticleEmission emission) {
    final random = math.Random();
    final config = emission.config;

    for (int i = 0; i < config.count; i++) {
      // Determine particle direction
      double angle;
      if (config.useRandomDirections) {
        angle =
            random.nextDouble() * config.emissionAngleRange -
            (config.emissionAngleRange / 2);
      } else {
        angle =
            (i / config.count) * config.emissionAngleRange -
            (config.emissionAngleRange / 2);
      }

      // Calculate speed and direction
      final speed =
          config.minSpeed +
          random.nextDouble() * (config.maxSpeed - config.minSpeed);
      final vx = math.cos(angle) * speed;
      final vy = math.sin(angle) * speed;

      // Random size and color
      final size =
          config.minSize +
          random.nextDouble() * (config.maxSize - config.minSize);
      final color = config.colors[random.nextInt(config.colors.length)];

      // Random rotation
      final rotation = random.nextDouble() * math.pi * 2;
      final rotationSpeed = (random.nextDouble() - 0.5) * 4.0;

      _particles.add(
        ParticleData(
          config: config,
          x: emission.position.dx,
          y: emission.position.dy,
          vx: vx,
          vy: vy,
          size: size,
          color: color,
          rotation: rotation,
          rotationSpeed: rotationSpeed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: AdvancedParticlePainter(particles: _particles),
        size: Size.infinite,
      ),
    );
  }
}

class AdvancedParticlePainter extends CustomPainter {
  final List<ParticleData> particles;

  AdvancedParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      if (particle.life <= 0) continue;

      final paint = Paint()
        ..color = particle.color
        ..isAntiAlias = true;

      // Set blend mode based on particle config
      switch (particle.config.blendMode) {
        case ParticleBlendMode.additive:
          paint.blendMode = BlendMode.plus;
          break;
        case ParticleBlendMode.multiply:
          paint.blendMode = BlendMode.multiply;
          break;
        case ParticleBlendMode.screen:
          paint.blendMode = BlendMode.screen;
          break;
        case ParticleBlendMode.normal:
          paint.blendMode = BlendMode.srcOver;
          break;
      }

      // Draw trail if enabled
      if (particle.config.hasTrail && particle.trail.isNotEmpty) {
        _drawTrail(canvas, particle);
      }

      // Draw particle based on type
      switch (particle.config.type) {
        case ParticleType.sparkle:
          _drawSparkle(canvas, particle, paint);
          break;
        case ParticleType.explosion:
        case ParticleType.food:
        case ParticleType.score:
        case ParticleType.powerUp:
        case ParticleType.trail:
        case ParticleType.smoke:
        case ParticleType.glow:
          _drawCircleParticle(canvas, particle, paint);
          break;
      }
    }
  }

  void _drawCircleParticle(Canvas canvas, ParticleData particle, Paint paint) {
    // Add subtle glow effect for certain particle types
    if (particle.config.type == ParticleType.powerUp ||
        particle.config.type == ParticleType.explosion) {
      final glowPaint = Paint()
        ..color = particle.color.withValues(alpha: particle.color.a * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..isAntiAlias = true;

      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size * 1.5,
        glowPaint,
      );
    }

    canvas.drawCircle(Offset(particle.x, particle.y), particle.size, paint);

    // Add inner highlight for certain particles
    if (particle.config.type == ParticleType.food ||
        particle.config.type == ParticleType.score) {
      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.6 * particle.life)
        ..isAntiAlias = true;

      canvas.drawCircle(
        Offset(particle.x, particle.y),
        particle.size * 0.4,
        highlightPaint,
      );
    }
  }

  void _drawSparkle(Canvas canvas, ParticleData particle, Paint paint) {
    final center = Offset(particle.x, particle.y);
    final size = particle.size;

    // Draw cross-shaped sparkle
    final path = Path();

    // Vertical line
    path.moveTo(center.dx, center.dy - size);
    path.lineTo(center.dx, center.dy + size);

    // Horizontal line
    path.moveTo(center.dx - size, center.dy);
    path.lineTo(center.dx + size, center.dy);

    // Diagonal lines for 8-pointed star
    path.moveTo(center.dx - size * 0.7, center.dy - size * 0.7);
    path.lineTo(center.dx + size * 0.7, center.dy + size * 0.7);

    path.moveTo(center.dx + size * 0.7, center.dy - size * 0.7);
    path.lineTo(center.dx - size * 0.7, center.dy + size * 0.7);

    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2.0;
    canvas.drawPath(path, paint);
  }

  void _drawTrail(Canvas canvas, ParticleData particle) {
    if (particle.trail.length < 2) return;

    final path = Path();
    path.moveTo(particle.trail.first.dx, particle.trail.first.dy);

    for (int i = 1; i < particle.trail.length; i++) {
      path.lineTo(particle.trail[i].dx, particle.trail[i].dy);
    }

    final trailPaint = Paint()
      ..color = particle.color.withValues(alpha: particle.life * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = particle.size * 0.5
      ..isAntiAlias = true;

    canvas.drawPath(path, trailPaint);
  }

  @override
  bool shouldRepaint(covariant AdvancedParticlePainter oldDelegate) {
    return particles.length != oldDelegate.particles.length ||
        particles.any((p) => p.life > 0);
  }
}

// Helper class to manage particle emissions in widgets
class ParticleManager {
  final List<ParticleEmission> _emissions = [];

  List<ParticleEmission> get emissions => _emissions;

  void addEmission(ParticleEmission emission) {
    _emissions.add(emission);
  }

  void emitAt(Offset position, ParticleConfig config, {Duration? duration}) {
    addEmission(
      ParticleEmission(config: config, position: position, duration: duration),
    );
  }

  void clear() {
    _emissions.clear();
  }

  void removeExpired() {
    _emissions.removeWhere((emission) => emission.shouldExpire);
  }
}
