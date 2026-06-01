import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/painting.dart';

import '../cosmo_palette.dart';

enum CosmoExplosionKind { enemy, player, boss }

final math.Random _rng = math.Random();

/// Builds a one-shot particle burst for a destruction event. Programmatic —
/// no sprite sheet (see ASSETS_NEEDED.md for the real explosion frames).
ParticleSystemComponent buildExplosion(Vector2 at, CosmoExplosionKind kind) {
  final int count;
  final double spread;
  final double maxRadius;
  final List<Color> colors;
  switch (kind) {
    case CosmoExplosionKind.enemy:
      count = 16;
      spread = 150;
      maxRadius = 2.4;
      colors = const [CosmoPalette.hull, CosmoPalette.hostile, CosmoPalette.hullLight];
      break;
    case CosmoExplosionKind.player:
      count = 24;
      spread = 200;
      maxRadius = 3.0;
      colors = const [CosmoPalette.energy, CosmoPalette.highlight, CosmoPalette.hull];
      break;
    case CosmoExplosionKind.boss:
      count = 60;
      spread = 320;
      maxRadius = 4.0;
      colors = const [CosmoPalette.hull, CosmoPalette.hostile, CosmoPalette.highlight];
      break;
  }

  return ParticleSystemComponent(
    position: at.clone(),
    priority: 50,
    particle: Particle.generate(
      count: count,
      lifespan: 0.7,
      generator: (i) {
        final angle = _rng.nextDouble() * math.pi * 2;
        final speed = (0.4 + _rng.nextDouble()) * spread;
        final velocity = Vector2(math.cos(angle), math.sin(angle)) * speed;
        final color = colors[_rng.nextInt(colors.length)];
        return AcceleratedParticle(
          speed: velocity,
          acceleration: velocity * -0.8,
          child: CircleParticle(
            radius: (0.6 + _rng.nextDouble()) * maxRadius,
            paint: Paint()..color = color,
          ),
        );
      },
    ),
  );
}
