import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../cosmo_strike_game.dart';
import '../game_audio.dart';
import '../levels/level_def.dart';
import 'fx.dart';
import 'player_ship.dart';

/// A scrolling, horizontally-tileable terrain band (floor or ceiling).
///
/// Rendering: the 1024x192 strip is drawn twice with a wrapping scroll
/// offset — the scroll is render-only. Collision: ONE static
/// [RectangleHitbox] spanning the full width, inset to the strip's solid
/// band so grazing the jagged silhouette never registers. The crash rule
/// (damage + bounce + anti-grind invulnerability) lives in
/// [CosmoStrikeGame.onTerrainCrash].
class TerrainStrip extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  TerrainStrip({
    required this.asset,
    required this.isCeiling,
    required this.bandHeight,
    this.scrollSpeed = 140,
  }) : super(priority: -50);

  final String asset;
  final bool isCeiling;
  final double bandHeight;
  final double scrollSpeed;

  double _scrollX = 0;
  late final Sprite _sprite = Sprite(Flame.images.fromCache(asset));
  late double _tileWidth;

  @override
  Future<void> onLoad() async {
    _layout(game.size);
    // Solid band: the art's silhouette occupies roughly the inner 2/3 of
    // the strip; inset the hitbox so only a real-looking impact counts.
    final inset = bandHeight * 0.35;
    add(RectangleHitbox(
      collisionType: CollisionType.passive,
      position: Vector2(0, isCeiling ? 0 : inset),
      size: Vector2(size.x, bandHeight - inset),
    ));
  }

  void _layout(Vector2 gameSize) {
    size = Vector2(gameSize.x, bandHeight);
    position = Vector2(0, isCeiling ? 0 : gameSize.y - bandHeight);
    // Keep the art's aspect: scale the 1024x192 strip to the band height.
    final image = Flame.images.fromCache(asset);
    _tileWidth = bandHeight * (image.width / image.height);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _layout(size);
  }

  @override
  void update(double dt) {
    _scrollX = (_scrollX + scrollSpeed * dt * game.enemyTimeScale) % _tileWidth;
  }

  @override
  void render(Canvas canvas) {
    if (isCeiling) {
      // Flip the floor-style art upside down for ceiling bands.
      canvas.save();
      canvas.translate(0, size.y);
      canvas.scale(1, -1);
    }
    // Draw enough tiles to cover the width plus the wrap seam.
    for (double x = -_scrollX; x < size.x; x += _tileWidth) {
      _sprite.render(
        canvas,
        position: Vector2(x, 0),
        size: Vector2(_tileWidth, bandHeight),
      );
    }
    if (isCeiling) canvas.restore();
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerShip) {
      game.onTerrainCrash(this);
    }
  }
}

/// A biome obstacle: grounded hazards ride the floor strip; drifting ones
/// (asteroids) float through open space with a slow sine bob + rotation.
/// Destructible specs (hp > 0) can be shot for points; hp == 0 hazards are
/// indestructible scenery you simply must not touch.
class TerrainObstacle extends PositionComponent
    with CollisionCallbacks, HasGameReference<CosmoStrikeGame> {
  TerrainObstacle({required this.spec, required Vector2 spawn})
      : hp = spec.hp,
        super(
          position: spawn,
          size: Vector2(spec.width, spec.height),
          anchor: Anchor.center,
          priority: 7,
        );

  final ObstacleSpec spec;
  int hp;

  double _age = 0;
  late final double _baseY = position.y;
  late final double _spin =
      spec.grounded ? 0 : (game.rng.nextDouble() - 0.5) * 1.2;
  late final Sprite _sprite = Sprite(Flame.images.fromCache(spec.asset));

  bool get destructible => spec.hp > 0;

  @override
  Future<void> onLoad() async {
    if (spec.grounded) {
      add(RectangleHitbox(
        collisionType: CollisionType.passive,
        size: Vector2(size.x * 0.6, size.y * 0.7),
        position: Vector2(size.x * 0.2, size.y * 0.3),
      ));
    } else {
      add(CircleHitbox(
        collisionType: CollisionType.passive,
        radius: size.x * 0.38,
        position: size / 2 - Vector2.all(size.x * 0.38),
      ));
    }
  }

  @override
  void update(double dt) {
    dt *= game.enemyTimeScale;
    _age += dt;
    if (spec.grounded) {
      // Ride the floor strip at terrain scroll speed.
      position.x -= 140 * dt;
      position.y = game.floorSurfaceY - size.y * 0.42;
    } else {
      position.x -= 126 * dt;
      position.y = _baseY + math.sin(_age * 1.4) * 14;
      angle += _spin * dt;
    }
    if (position.x < -size.x) removeFromParent();
  }

  void takeDamage(int dmg) {
    if (!destructible) return;
    hp -= dmg;
    if (hp <= 0) {
      GameAudio.enemyDown();
      game.add(explosionSmall(position));
      game.addScore(spec.points);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    _sprite.render(canvas, size: size);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is PlayerShip) {
      game.onTerrainCrash(this);
    }
  }
}

/// Spawns biome obstacles on a density budget ([LevelDef.obstaclesPerTenSeconds]),
/// hard-capped at [maxAlive] live obstacles so terrain never floods the
/// collision broadphase or the screen.
class ObstacleSpawner extends Component with HasGameReference<CosmoStrikeGame> {
  ObstacleSpawner({required this.biome, required this.perTenSeconds});

  final BiomeDef biome;
  final double perTenSeconds;

  static const int maxAlive = 6;

  double _accumulator = 0;

  @override
  void update(double dt) {
    if (game.phase != GamePhase.playing || biome.obstacles.isEmpty) return;
    _accumulator += dt * game.enemyTimeScale * (perTenSeconds / 10);
    if (_accumulator < 1) return;
    _accumulator -= 1;

    if (game.children.whereType<TerrainObstacle>().length >= maxAlive) return;

    final spec = _pickSpec();
    final Vector2 spawn;
    if (spec.grounded) {
      spawn = Vector2(game.size.x + spec.width, game.floorSurfaceY);
    } else {
      final top = game.playfieldTop + spec.height / 2;
      final bottom = game.playfieldBottom - spec.height / 2;
      spawn = Vector2(
        game.size.x + spec.width,
        top + game.rng.nextDouble() * math.max(1, bottom - top),
      );
    }
    game.add(TerrainObstacle(spec: spec, spawn: spawn));
  }

  ObstacleSpec _pickSpec() {
    final total = biome.obstacles.fold<double>(0, (s, o) => s + o.weight);
    var roll = game.rng.nextDouble() * total;
    for (final spec in biome.obstacles) {
      roll -= spec.weight;
      if (roll <= 0) return spec;
    }
    return biome.obstacles.last;
  }
}
