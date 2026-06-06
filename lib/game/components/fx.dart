import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import '../game_assets.dart';

enum CosmoExplosionKind { enemy, player, boss }

/// One-shot sprite-sheet animation (explosions, sparks, muzzle flashes,
/// warp flashes). All FX sheets are single-row horizontal strips of
/// square frames; the component removes itself when the loop finishes.
SpriteAnimationComponent oneShotFx(
  String sheet,
  int frames,
  Vector2 at,
  Vector2 size, {
  double fps = 18,
  int priority = 50,
}) {
  final image = Flame.images.fromCache(sheet);
  final animation = SpriteAnimation.fromFrameData(
    image,
    SpriteAnimationData.sequenced(
      amount: frames,
      stepTime: 1 / fps,
      textureSize: Vector2(image.width / frames, image.height.toDouble()),
      loop: false,
    ),
  );
  return SpriteAnimationComponent(
    animation: animation,
    position: at.clone(),
    size: size,
    anchor: Anchor.center,
    priority: priority,
    removeOnFinish: true,
  );
}

SpriteAnimationComponent explosionSmall(Vector2 at) =>
    oneShotFx(GameAssets.explosionSmallSheet, 6, at, Vector2.all(48));

SpriteAnimationComponent explosionBig(Vector2 at) =>
    oneShotFx(GameAssets.explosionBigSheet, 8, at, Vector2.all(96), fps: 16);

SpriteAnimationComponent hitSpark(Vector2 at) =>
    oneShotFx(GameAssets.hitSparkSheet, 4, at, Vector2.all(24), fps: 24);

SpriteAnimationComponent muzzleFlash(Vector2 at) =>
    oneShotFx(GameAssets.muzzleFlashSheet, 3, at, Vector2.all(20), fps: 30);

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
