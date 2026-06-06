import 'package:flutter/material.dart';

import '../game/cosmo_palette.dart';

/// On-screen analog d-pad for gameplay. Borderless Command-HUD style: a
/// translucent disc with a glowing nub that follows the thumb. Emits the
/// normalized offset-from-center (8-way analog) on every drag update and
/// `Offset.zero` on release.
class GameDPad extends StatefulWidget {
  const GameDPad({super.key, required this.onDirection, this.diameter = 132});

  /// Called with a normalized direction vector (length ≤ 1); zero on release.
  final ValueChanged<Offset> onDirection;
  final double diameter;

  @override
  State<GameDPad> createState() => _GameDPadState();
}

class _GameDPadState extends State<GameDPad> {
  Offset _nub = Offset.zero; // normalized -1..1 per axis

  void _track(Offset local) {
    final radius = widget.diameter / 2;
    final centered = local - Offset(radius, radius);
    var dir = centered / radius;
    if (dir.distance > 1) dir = dir / dir.distance;
    setState(() => _nub = dir);
    widget.onDirection(dir);
  }

  void _release() {
    setState(() => _nub = Offset.zero);
    widget.onDirection(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.diameter / 2;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) => _track(d.localPosition),
      onPanUpdate: (d) => _track(d.localPosition),
      onPanEnd: (_) => _release(),
      onPanCancel: _release,
      child: SizedBox(
        width: widget.diameter,
        height: widget.diameter,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Base disc — translucent, no border (definition via glow).
            Container(
              width: widget.diameter,
              height: widget.diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: CosmoPalette.bgHigh.withValues(alpha: 0.30),
              ),
            ),
            // Direction nub with neon glow.
            Transform.translate(
              offset: Offset(_nub.dx * (radius - 26), _nub.dy * (radius - 26)),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: CosmoPalette.hull.withValues(alpha: 0.85),
                  boxShadow: [
                    BoxShadow(
                      color: CosmoPalette.hull.withValues(alpha: 0.5),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
