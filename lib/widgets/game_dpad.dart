import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:flutter/material.dart';

/// On-screen analog d-pad for gameplay, Prism Noir style: an outlined base
/// circle with four ink direction glyphs and an outlined nub that follows the
/// thumb. Pressing brightens the ring and the glyph(s) you're pushing toward.
/// Emits the normalized offset-from-center (8-way analog) on every drag
/// update and `Offset.zero` on release.
///
/// [diameter] is in logical px and deliberately NOT design-scaled — it's a
/// thumb target, so it stays the same physical size on every device.
class GameDPad extends StatefulWidget {
  const GameDPad({super.key, required this.onDirection, this.diameter = defaultDiameter});

  static const double defaultDiameter = 132;

  /// Called with a normalized direction vector (length ≤ 1); zero on release.
  final ValueChanged<Offset> onDirection;
  final double diameter;

  @override
  State<GameDPad> createState() => _GameDPadState();
}

class _GameDPadState extends State<GameDPad> {
  Offset _nub = Offset.zero; // normalized -1..1 per axis
  bool _pressed = false;

  static const double _nubSize = 44;

  void _track(Offset local) {
    final radius = widget.diameter / 2;
    final centered = local - Offset(radius, radius);
    var dir = centered / radius;
    if (dir.distance > 1) dir = dir / dir.distance;
    setState(() {
      _nub = dir;
      _pressed = true;
    });
    widget.onDirection(dir);
  }

  void _release() {
    setState(() {
      _nub = Offset.zero;
      _pressed = false;
    });
    widget.onDirection(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;
    final radius = d / 2;
    final travel = radius - _nubSize / 2 - 4;
    final glyph = d * 0.17;

    Widget arrow(IconData icon, Alignment at, bool active) => Align(
          alignment: at,
          child: Padding(
            padding: EdgeInsets.all(d * 0.035),
            child: Icon(icon, size: glyph, color: active ? CsColors.ink : CsColors.ink45),
          ),
        );

    const threshold = 0.35;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (e) => _track(e.localPosition),
      onPanUpdate: (e) => _track(e.localPosition),
      onPanEnd: (_) => _release(),
      onPanCancel: _release,
      child: RepaintBoundary(
        child: SizedBox(
          width: d,
          height: d,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Base: outlined circle on a faint near-black fill so it reads
              // over any biome without becoming a box.
              AnimatedContainer(
                duration: CsMotion.fast,
                curve: CsMotion.standard,
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _pressed ? const Color(0x660A0A0D) : const Color(0x400A0A0D),
                  border: Border.all(color: _pressed ? CsColors.lineStrong : CsColors.lineSubtle),
                ),
              ),
              arrow(Symbols.keyboard_arrow_up_rounded, Alignment.topCenter, _nub.dy < -threshold),
              arrow(Symbols.keyboard_arrow_down_rounded, Alignment.bottomCenter, _nub.dy > threshold),
              arrow(Symbols.keyboard_arrow_left_rounded, Alignment.centerLeft, _nub.dx < -threshold),
              arrow(Symbols.keyboard_arrow_right_rounded, Alignment.centerRight, _nub.dx > threshold),
              // Thumb nub: outlined disc that follows the drag.
              Transform.translate(
                offset: Offset(_nub.dx * travel, _nub.dy * travel),
                child: AnimatedContainer(
                  duration: CsMotion.fast,
                  curve: CsMotion.standard,
                  width: _nubSize,
                  height: _nubSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _pressed ? CsColors.raised2 : CsColors.raised,
                    border: Border.all(
                      color: _pressed ? CsColors.ink : CsColors.lineStrong,
                      width: _pressed ? 1.5 : 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
