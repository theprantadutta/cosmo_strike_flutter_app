import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flutter/painting.dart';

import '../cosmo_palette.dart';
import '../cosmo_strike_game.dart';
import '../game_assets.dart';

/// Prism Noir background: two very soft radial washes (accent on the left,
/// secondary on the right — they follow the purchased colour theme via
/// [CosmoPalette.applySkin]) under a 3-layer parallax of transparent star
/// tiles drifting left at different speeds.
///
/// Render cost: 2 bounded gradient rects + ≤12 `drawImageRect`s per frame.
/// Shaders are rebuilt only on resize / skin change, never per frame.
class Starfield extends PositionComponent with HasGameReference<CosmoStrikeGame> {
  Starfield() : super(priority: -100);

  static const List<double> _speeds = [8, 20, 40]; // far, mid, near (px/s)
  static const List<double> _alphas = [0.85, 0.9, 1.0];

  late final List<ui.Image> _tiles;
  final List<double> _offsets = [0, 0, 0];
  final List<Paint> _layerPaints =
      List.generate(3, (i) => Paint()..filterQuality = FilterQuality.medium);

  final Paint _washLeft = Paint();
  final Paint _washRight = Paint();
  Rect _washLeftRect = Rect.zero;
  Rect _washRightRect = Rect.zero;
  int _skinVersion = -1;

  /// Biome tint for the near star layer (far/mid stay neutral white).
  Color _tint = CosmoPalette.ink;

  /// Recolor the near stars for the active biome (called on level change).
  void setTint(Color tint) {
    _tint = tint;
    _applyLayerPaints();
  }

  void _applyLayerPaints() {
    for (var i = 0; i < 3; i++) {
      final c = i == 2 ? _tint : const Color(0xFFFFFFFF);
      _layerPaints[i].colorFilter = ColorFilter.mode(
          c.withValues(alpha: _alphas[i]), BlendMode.modulate);
    }
  }

  @override
  Future<void> onLoad() async {
    size = game.size;
    _tiles = [
      Flame.images.fromCache(GameAssets.starfieldFar),
      Flame.images.fromCache(GameAssets.starfieldMid),
      Flame.images.fromCache(GameAssets.starfieldNear),
    ];
    _applyLayerPaints();
    _rebuildWashes();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
    if (isLoaded) _rebuildWashes();
  }

  void _rebuildWashes() {
    _skinVersion = CosmoPalette.skinVersion;
    final w = size.x, h = size.y;
    final r = math.max(w, h) * 0.34;
    final left = Offset(w * 0.12, h * 0.5);
    final right = Offset(w * 0.84, h * 0.5);
    _washLeftRect = Rect.fromCircle(center: left, radius: r);
    _washRightRect = Rect.fromCircle(center: right, radius: r);
    _washLeft.shader = ui.Gradient.radial(left, r, [
      CosmoPalette.accent.withValues(alpha: 0.10),
      CosmoPalette.accent.withValues(alpha: 0.0),
    ]);
    _washRight.shader = ui.Gradient.radial(right, r, [
      CosmoPalette.secondary.withValues(alpha: 0.12),
      CosmoPalette.secondary.withValues(alpha: 0.0),
    ]);
  }

  @override
  void update(double dt) {
    if (_skinVersion != CosmoPalette.skinVersion) _rebuildWashes();
    final tile = size.y;
    if (tile <= 0) return;
    for (var i = 0; i < 3; i++) {
      _offsets[i] = (_offsets[i] + _speeds[i] * dt) % tile;
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(_washLeftRect, _washLeft);
    canvas.drawRect(_washRightRect, _washRight);
    // Square tiles scaled to the field height, wrapped horizontally.
    final tile = size.y;
    if (tile <= 0) return;
    for (var i = 0; i < 3; i++) {
      final img = _tiles[i];
      final src =
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      for (double x = -_offsets[i]; x < size.x; x += tile) {
        canvas.drawImageRect(
            img, src, Rect.fromLTWH(x, 0, tile, tile), _layerPaints[i]);
      }
    }
  }
}
