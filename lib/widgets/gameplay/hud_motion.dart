// The in-run HUD's animated readouts (score odometer, chain readout, lives,
// timed-effect chips, the action buttons' pop). Each one listens to its own
// game notifier and rebuilds only itself; opacity goes through
// FadeTransition and motion through Transforms, so nothing here rebuilds a
// big subtree per frame or uses an Opacity/saveLayer. Rules:
// docs/motion/MOTION_SPEC.md (HUD pops, number roll, performance).
import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../game/combo_graze.dart';
import '../../game/cosmo_strike_game.dart';
import '../../ui/cs.dart';

/// The run score as a rolling [CsOdometer] in the `hudScore` numeric style.
///
/// The score can change several times a frame in a busy wave, so updates are
/// coalesced: the odometer gets a new value at most once per [_window] and
/// always ends on the latest score. Each roll ([_roll]) is about as long as
/// the window, so a slot is nearly settled before it retargets and rolls never
/// pile up. Only this widget rebuilds (the HUD around it never does), and the
/// caller wraps it in a RepaintBoundary. Reduce motion: plain instant text.
class HudScore extends StatefulWidget {
  const HudScore({super.key, required this.game});
  final CosmoStrikeGame game;

  @override
  State<HudScore> createState() => _HudScoreState();
}

class _HudScoreState extends State<HudScore> {
  static const Duration _window = CsMotion.quick; // 180 ms
  static const Duration _roll = CsMotion.base; // 200 ms

  late int _shown = widget.game.scoreNotifier.value;
  Timer? _cooldown;
  bool _dirty = false;

  static String _plain(int v) => '$v';

  @override
  void initState() {
    super.initState();
    widget.game.scoreNotifier.addListener(_onScore);
  }

  @override
  void dispose() {
    widget.game.scoreNotifier.removeListener(_onScore);
    _cooldown?.cancel();
    super.dispose();
  }

  void _onScore() {
    if (!mounted) return;
    if (CsReduceMotion.of(context, listen: false)) {
      final v = widget.game.scoreNotifier.value;
      if (v != _shown) setState(() => _shown = v);
      return;
    }
    if (_cooldown != null) {
      _dirty = true;
      return;
    }
    _push();
  }

  void _push() {
    _dirty = false;
    final v = widget.game.scoreNotifier.value;
    if (!mounted || v == _shown) return;
    setState(() => _shown = v);
    _cooldown = Timer(_window, () {
      _cooldown = null;
      if (_dirty) _push();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CsOdometer(
      value: _shown,
      style: context.type.hudScore,
      format: _plain,
      duration: _roll,
      semanticsLabel: 'Score $_shown',
    );
  }
}

/// The active timed-effect chips. A chip pops in (fade + [CsPop]) when its
/// effect starts and fades out on the exit curve when it ends; the chip's
/// remaining-time line keeps tracking the notifier in between.
class HudEffectChips extends StatefulWidget {
  const HudEffectChips({super.key, required this.game});
  final CosmoStrikeGame game;

  @override
  State<HudEffectChips> createState() => _HudEffectChipsState();
}

class _HudEffectChipsState extends State<HudEffectChips> {
  /// Display order (ids), live and leaving chips together.
  final List<String> _order = [];

  /// Latest data per id, live or leaving.
  final Map<String, ActiveEffectHud> _data = {};

  /// Ids whose effect ended and whose chip is fading out.
  final Set<String> _leaving = {};

  @override
  void initState() {
    super.initState();
    _sync(widget.game.effectsNotifier.value, reduce: true);
    widget.game.effectsNotifier.addListener(_onEffects);
  }

  @override
  void dispose() {
    widget.game.effectsNotifier.removeListener(_onEffects);
    super.dispose();
  }

  void _onEffects() {
    if (!mounted) return;
    final effects = widget.game.effectsNotifier.value;
    // Published at ~4 Hz even when nothing is active: skip the no-op rebuild.
    if (effects.isEmpty && _order.isEmpty) return;
    final reduce = CsReduceMotion.of(context, listen: false);
    setState(() => _sync(effects, reduce: reduce));
  }

  void _sync(List<ActiveEffectHud> effects, {required bool reduce}) {
    final live = {for (final e in effects) e.id};
    for (final id in List<String>.of(_order)) {
      if (live.contains(id) || _leaving.contains(id)) continue;
      if (reduce) {
        _order.remove(id);
        _data.remove(id);
      } else {
        _leaving.add(id);
      }
    }
    for (final e in effects) {
      _data[e.id] = e;
      _leaving.remove(e.id);
      if (!_order.contains(e.id)) _order.add(e.id);
    }
  }

  void _gone(String id) {
    if (!mounted || !_leaving.contains(id)) return;
    setState(() {
      _leaving.remove(id);
      _order.remove(id);
      _data.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_order.isEmpty) return const SizedBox.shrink();
    final gap = context.cs(6);
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final id in _order)
          _EffectChipSlot(
            key: ValueKey(id),
            effect: _data[id]!,
            leaving: _leaving.contains(id),
            onGone: () => _gone(id),
          ),
      ],
    );
  }
}

/// One effect chip's enter / exit: fades in with a [CsPop] on mount, fades
/// out (exit curve) when [leaving] flips, then reports [onGone]. Fades go
/// through FadeTransition so the chip is never an `Opacity` rebuilt per frame.
class _EffectChipSlot extends StatefulWidget {
  const _EffectChipSlot({
    super.key,
    required this.effect,
    required this.leaving,
    required this.onGone,
  });

  final ActiveEffectHud effect;
  final bool leaving;
  final VoidCallback onGone;

  @override
  State<_EffectChipSlot> createState() => _EffectChipSlotState();
}

class _EffectChipSlotState extends State<_EffectChipSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: CsMotion.fast);
  bool _started = false;

  bool get _reduce => CsReduceMotion.of(context, listen: false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduce) {
      _fade.value = 1;
    } else {
      _fade.forward();
    }
  }

  @override
  void didUpdateWidget(_EffectChipSlot old) {
    super.didUpdateWidget(old);
    if (widget.leaving == old.leaving) return;
    if (widget.leaving) {
      _fade
          .animateBack(0, duration: CsMotion.quick, curve: CsMotion.exit)
          // A TickerFuture only completes when the run finishes, so a chip
          // that comes back mid-fade (forward below) never reports gone.
          .whenComplete(widget.onGone);
    } else {
      _fade.forward();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: CsPop(
        trigger: 0,
        playOnMount: true,
        peak: 1.12,
        child: _EffectChip(effect: widget.effect),
      ),
    );
  }
}

/// Lives as small ship icons: filled ink = in reserve, hollow 38% = lost. A
/// lost ship flashes pink, swells and shrinks out of its slot (leaving the
/// hollow outline) with a mono "SHIP DOWN" tag dropping in below; a gained
/// ship (revive / +1) pops into its slot. Losing a life is never silent.
class HudLifePips extends StatefulWidget {
  const HudLifePips({super.key, required this.game});
  final CosmoStrikeGame game;

  @override
  State<HudLifePips> createState() => _HudLifePipsState();
}

class _HudLifePipsState extends State<HudLifePips> {
  late int _shown;
  int _lossEvents = 0;

  /// False during the first build, so the starting ships don't pop in.
  bool _built = false;

  @override
  void initState() {
    super.initState();
    _shown = widget.game.livesNotifier.value;
    widget.game.livesNotifier.addListener(_onLivesChanged);
  }

  @override
  void dispose() {
    widget.game.livesNotifier.removeListener(_onLivesChanged);
    super.dispose();
  }

  void _onLivesChanged() {
    final now = widget.game.livesNotifier.value;
    if (!mounted || now == _shown) return;
    setState(() {
      if (now < _shown) _lossEvents++;
      _shown = now;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final total = math.max(widget.game.mode.runLives, _shown).clamp(1, 6);
    // Small ship silhouettes (nose right, like the player's ship): filled
    // = a ship in reserve, hollow = lost. Reads as "lives" without a label.
    final w = cs(17).clamp(13.0, 24.0);
    final h = w * 0.72;
    final popIn = _built;
    _built = true;

    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Semantics(
            label: 'Ships $_shown of $total',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < total; i++) ...[
                  if (i > 0) SizedBox(width: cs(5)),
                  _ShipSlot(
                    key: ValueKey(i),
                    lit: i < _shown,
                    size: Size(w, h),
                    popIn: popIn,
                  ),
                ],
              ],
            ),
          ),
          if (_lossEvents > 0)
            Positioned(
              right: 0,
              top: h + cs(8),
              child: _ShipDownTag(key: ValueKey(_lossEvents)),
            ),
        ],
      ),
    );
  }
}

enum _ShipMotion { idle, losing, gaining }

/// One lives slot. Lost: a pink ship swells to 1.3 and shrinks to nothing
/// over the hollow outline. Gained: the filled ship pops in on `springPop`.
/// Reduce motion: the slot just switches.
class _ShipSlot extends StatefulWidget {
  const _ShipSlot({
    super.key,
    required this.lit,
    required this.size,
    required this.popIn,
  });

  final bool lit;
  final Size size;

  /// The slot was created after the first build (a ship was added), so a
  /// lit slot pops in instead of just appearing.
  final bool popIn;

  @override
  State<_ShipSlot> createState() => _ShipSlotState();
}

class _ShipSlotState extends State<_ShipSlot>
    with SingleTickerProviderStateMixin {
  static const Color _lost = Color(0x61F4F3F7); // 38% ink, hollow

  late final AnimationController _c = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _motion = _ShipMotion.idle);
      }
    });

  late final Animation<double> _gain =
      CurvedAnimation(parent: _c, curve: CsMotion.springPop);

  late final Animation<double> _loss = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.3)
          .chain(CurveTween(curve: CsMotion.easeOutSoft)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.3, end: 0.0).chain(CurveTween(curve: CsMotion.exit)),
      weight: 70,
    ),
  ]).animate(_c);

  _ShipMotion _motion = _ShipMotion.idle;
  bool _started = false;

  bool get _reduce => CsReduceMotion.of(context, listen: false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.lit && widget.popIn) _play(_ShipMotion.gaining);
  }

  @override
  void didUpdateWidget(_ShipSlot old) {
    super.didUpdateWidget(old);
    if (widget.lit != old.lit) {
      _play(widget.lit ? _ShipMotion.gaining : _ShipMotion.losing);
    }
  }

  void _play(_ShipMotion m) {
    if (_reduce) {
      _motion = _ShipMotion.idle;
      return;
    }
    _motion = m;
    _c
      ..duration = m == _ShipMotion.gaining ? CsMotion.pop : CsMotion.gentle
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _ship(Color color, {required bool filled}) => CustomPaint(
        size: widget.size,
        painter: _ShipIconPainter(color: color, filled: filled),
      );

  @override
  Widget build(BuildContext context) {
    final lit = widget.lit;
    switch (_motion) {
      case _ShipMotion.idle:
        return lit ? _ship(CsColors.ink, filled: true) : _ship(_lost, filled: false);
      case _ShipMotion.gaining:
        return Stack(
          alignment: Alignment.center,
          children: [
            _ship(_lost, filled: false),
            ScaleTransition(scale: _gain, child: _ship(CsColors.ink, filled: true)),
          ],
        );
      case _ShipMotion.losing:
        return Stack(
          alignment: Alignment.center,
          children: [
            _ship(_lost, filled: false),
            ScaleTransition(scale: _loss, child: _ship(CsColors.pink, filled: true)),
          ],
        );
    }
  }
}

/// "SHIP DOWN": drops in fast, holds, fades at the tail (one controller,
/// FadeTransition + a translated child, no per-frame Opacity).
class _ShipDownTag extends StatefulWidget {
  const _ShipDownTag({super.key});

  @override
  State<_ShipDownTag> createState() => _ShipDownTagState();
}

class _ShipDownTagState extends State<_ShipDownTag>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  late final Animation<double> _fade = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.0, end: 1.0)
          .chain(CurveTween(curve: CsMotion.easeOutSoft)),
      weight: 17,
    ),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 58),
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: CsMotion.exit)),
      weight: 25,
    ),
  ]).animate(_c);

  late final Animation<double> _drop = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.17, curve: CsMotion.dropIn),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final text = Text(
      'SHIP DOWN',
      maxLines: 1,
      style: cs.type.mono(10, em: 0.16, color: CsColors.pink),
    );
    if (CsReduceMotion.of(context)) {
      return FadeTransition(opacity: _fade, child: text);
    }
    return FadeTransition(
      opacity: _fade,
      child: AnimatedBuilder(
        animation: _drop,
        child: text,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, (1 - _drop.value) * -6),
          child: child,
        ),
      ),
    );
  }
}

/// The lives HUD ship: an arrowhead pointing right (the player's heading)
/// with a notched tail — filled when in reserve, a 1.4px outline when lost.
class _ShipIconPainter extends CustomPainter {
  const _ShipIconPainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const stroke = 1.4;
    final path = Path()
      ..moveTo(stroke, stroke)
      ..lineTo(w - stroke, h / 2)
      ..lineTo(stroke, h - stroke)
      ..lineTo(w * 0.3, h / 2)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..isAntiAlias = true
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ShipIconPainter old) =>
      old.color != color || old.filled != filled;
}

/// Kill-chain readout: prism "×2" (ink at ×1) + mono "CHAIN 12". Appears
/// from a 2-chain on. The count pops on every link, the whole readout pops
/// harder (and settles a touch bigger) as the multiplier tier rises, and it
/// fades out on the exit curve when the chain breaks, holding its last
/// values while it goes. Reduce motion: no pops or growth, instant show/hide.
class HudChainReadout extends StatefulWidget {
  const HudChainReadout({super.key, required this.game});
  final CosmoStrikeGame game;

  @override
  State<HudChainReadout> createState() => _HudChainReadoutState();
}

class _HudChainReadoutState extends State<HudChainReadout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade =
      AnimationController(vsync: this, duration: CsMotion.fast);
  late int _chain;
  late int _mult;

  ComboGrazeController get _combo => widget.game.combo;

  @override
  void initState() {
    super.initState();
    _chain = _combo.comboNotifier.value;
    _mult = _combo.multiplierNotifier.value;
    if (_chain >= 2) _fade.value = 1;
    _combo.comboNotifier.addListener(_onChange);
    _combo.multiplierNotifier.addListener(_onChange);
  }

  @override
  void dispose() {
    _combo.comboNotifier.removeListener(_onChange);
    _combo.multiplierNotifier.removeListener(_onChange);
    _fade.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final reduce = CsReduceMotion.of(context, listen: false);
    final chain = _combo.comboNotifier.value;
    if (chain >= 2) {
      final mult = _combo.multiplierNotifier.value;
      if (chain != _chain || mult != _mult) {
        setState(() {
          _chain = chain;
          _mult = mult;
        });
      }
      if (reduce) {
        _fade.value = 1;
      } else {
        _fade.forward();
      }
    } else if (!_fade.isDismissed) {
      // Chain broke: fade out, keeping the last chain on screen meanwhile.
      if (reduce) {
        _fade.value = 0;
      } else {
        _fade.animateBack(0, duration: CsMotion.slow, curve: CsMotion.exit);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final reduce = CsReduceMotion.of(context);
    final multStyle = t.display(26, height: 1);
    final tier = (_mult - 1).clamp(0, 3);
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _fade,
        child: AnimatedScale(
          // ×1 → 1.0 … ×4 → 1.12.
          scale: reduce ? 1 : 1 + tier * 0.04,
          duration: reduce ? Duration.zero : CsMotion.release,
          curve: CsMotion.springSoft,
          alignment: Alignment.centerLeft,
          child: CsPop(
            trigger: _mult,
            peak: 1.08 + tier * 0.02,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (_mult >= 2)
                  CsPrismText('×$_mult', style: multStyle)
                else
                  Text('×$_mult', style: multStyle),
                SizedBox(width: cs(10)),
                CsPop(
                  trigger: _chain,
                  peak: 1.08,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'CHAIN $_chain',
                    style: t.mono(12, em: 0.1, color: CsColors.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Active timed power-up: glyph + a tiny 2px remaining-time line. Not
/// tweened — the notifier already updates continuously.
class _EffectChip extends StatelessWidget {
  const _EffectChip({required this.effect});
  final ActiveEffectHud effect;

  static const Map<String, IconData> _icons = {
    'weapon': Symbols.bolt_rounded,
    'x2': Symbols.close_rounded, // x glyph
    'speed': Symbols.speed_rounded,
    'slowmo': Symbols.slow_motion_video_rounded,
    'magnet': Symbols.attractions_rounded,
    'ghost': Symbols.blur_on_rounded,
    'shield': Symbols.shield_rounded, // post-revive protection window
  };

  static const ShapeDecoration _chip = ShapeDecoration(
    color: Color(0xB30A0A0D),
    shape: StadiumBorder(side: BorderSide(color: CsColors.hairline)),
  );

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final barW = cs(26);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: cs(9), vertical: cs(5)),
      decoration: _chip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _icons[effect.id] ?? Symbols.star_rounded,
            size: cs(13),
            color: CsColors.ink,
          ),
          SizedBox(width: cs(6)),
          SizedBox(
            width: barW,
            height: 2,
            child: ColoredBox(
              color: CsColors.track,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: barW * effect.remaining01.clamp(0.0, 1.0),
                  height: 2,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(gradient: CsGradients.progress),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One [CsPop] (springPop, peak 1.12) each time [value] goes UP: the
/// missile ammo rising, or the Overdrive meter turning ready (0 → 1). Never
/// pops on the way down and never loops. Reduce motion: no pop.
class HudPopOnRise extends StatefulWidget {
  const HudPopOnRise({super.key, required this.value, required this.child});
  final num value;
  final Widget child;

  @override
  State<HudPopOnRise> createState() => _HudPopOnRiseState();
}

class _HudPopOnRiseState extends State<HudPopOnRise> {
  int _pops = 0;

  @override
  void didUpdateWidget(HudPopOnRise oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value > oldWidget.value) _pops++;
  }

  @override
  Widget build(BuildContext context) =>
      CsPop(trigger: _pops, peak: 1.12, child: widget.child);
}
