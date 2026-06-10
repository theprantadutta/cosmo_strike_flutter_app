import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/painting.dart';

import '../game_assets.dart';

enum CosmoExplosionKind { enemy, player, boss }

/// Builds a non-looping animation from a single-row horizontal strip of
/// square frames (shared by the one-shot components and the FX pools).
SpriteAnimation oneShotAnimation(String sheet, int frames, {double fps = 18}) {
  final image = Flame.images.fromCache(sheet);
  return SpriteAnimation.fromFrameData(
    image,
    SpriteAnimationData.sequenced(
      amount: frames,
      stepTime: 1 / fps,
      textureSize: Vector2(image.width / frames, image.height.toDouble()),
      loop: false,
    ),
  );
}

/// One-shot sprite-sheet animation (explosions, warp flashes). The
/// component removes itself when the loop finishes. High-churn FX
/// (hit sparks, muzzle flashes) go through [PooledFx] instead.
SpriteAnimationComponent oneShotFx(
  String sheet,
  int frames,
  Vector2 at,
  Vector2 size, {
  double fps = 18,
  int priority = 50,
}) {
  return SpriteAnimationComponent(
    animation: oneShotAnimation(sheet, frames, fps: fps),
    position: at.clone(),
    size: size,
    anchor: Anchor.center,
    priority: priority,
    removeOnFinish: true,
  );
}

SpriteAnimationComponent explosionSmall(Vector2 at, {double scale = 1}) =>
    oneShotFx(GameAssets.explosionSmallSheet, 6, at, Vector2.all(48 * scale));

SpriteAnimationComponent explosionBig(Vector2 at, {double scale = 1}) =>
    oneShotFx(GameAssets.explosionBigSheet, 8, at, Vector2.all(96 * scale),
        fps: 16);

/// A reusable one-shot FX slot: stays mounted forever, plays an animation
/// on demand, and parks itself off-screen when the loop completes (never
/// removed/re-added — pooling keeps the FX churn out of the GC and the
/// component lifecycle).
class PooledFx extends PositionComponent {
  PooledFx({super.priority = 50}) : super(anchor: Anchor.center) {
    position.setValues(-9999, -9999);
  }

  bool active = false;
  SpriteAnimationTicker? _ticker;

  void play(SpriteAnimation animation, Vector2 at, Vector2 displaySize) {
    _ticker = animation.createTicker()..onComplete = stop;
    position.setFrom(at);
    size.setFrom(displaySize);
    active = true;
  }

  void stop() {
    active = false;
    position.setValues(-9999, -9999);
  }

  @override
  void update(double dt) {
    if (!active) return;
    _ticker?.update(dt);
  }

  @override
  void render(Canvas canvas) {
    if (!active) return;
    _ticker?.getSprite().render(canvas, size: size);
  }
}

SpriteAnimationComponent warpFlash(Vector2 at) =>
    oneShotFx(GameAssets.warpFlashSheet, 5, at, Vector2.all(64), fps: 20);

/// Looping sprite-sheet animation builder (exhaust trail, mine rotation).
SpriteAnimation loopAnimation(String sheet, int frames, {double fps = 12}) {
  final image = Flame.images.fromCache(sheet);
  return SpriteAnimation.fromFrameData(
    image,
    SpriteAnimationData.sequenced(
      amount: frames,
      stepTime: 1 / fps,
      textureSize: Vector2(image.width / frames, image.height.toDouble()),
    ),
  );
}
