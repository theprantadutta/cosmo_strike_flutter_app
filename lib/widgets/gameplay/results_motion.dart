// Motion helpers for the results overlays (level clear / game over): a thin
// wrapper around ONE CsBeatSheet per overlay plus the small widgets that read
// it. Everything goes through FadeTransition / ScaleTransition / Transform
// driven by the sheet's controller with a cached child, so a beat repaints
// only its own piece (each is behind a RepaintBoundary) and nothing rebuilds a
// large subtree per frame. Rules: docs/motion/MOTION_SPEC.md.
//
// The timeline runs on the overlay's own Ticker, never on game ticks: the
// Flame engine freezes ~0.8 s after levelClear / gameOver
// (`_freezeUnderResultOverlay`) while this keeps playing.
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/audio_service.dart';

/// Plays a results sound cue through [AudioService] (honours the Sound
/// setting; a no-op until the service is initialised, e.g. in tests).
void playResultsCue(String sound) {
  try {
    AudioService().playSound(sound);
  } catch (_) {
    // Audio is decoration; never let it break the debrief.
  }
}

/// One results choreography: a [CsBeatSheet] plus the "settled" flag (the
/// end state is showing without motion because motion is reduced or the
/// player skipped) and the tap-to-skip rule.
///
/// Create it in `initState` with the State's ticker, call [start] once from
/// `didChangeDependencies`, [dispose] it with the State.
class ResultsBeats {
  ResultsBeats({
    required TickerProvider vsync,
    required Map<String, CsBeat> beats,
    this.skipAfterMs = 1000,
  })  : _beats = Map.unmodifiable(beats),
        sheet = CsBeatSheet(vsync: vsync, beats: beats) {
    listenable = Listenable.merge([sheet.controller, settled]);
  }

  final Map<String, CsBeat> _beats;

  /// The single timeline.
  final CsBeatSheet sheet;

  /// Taps before this point (ms into the sheet) don't skip, so a tap still in
  /// flight from gameplay can't swallow the whole celebration.
  final int skipAfterMs;

  /// True when the final state shows without motion (reduce motion, or the
  /// player skipped). Odometers render plain text once settled.
  final ValueNotifier<bool> settled = ValueNotifier(false);

  /// Fires on every sheet tick and when [settled] flips.
  late final Listenable listenable;

  bool _started = false;

  /// Plays the sheet once; with [reduceMotion] jumps straight to the end.
  void start({required bool reduceMotion}) {
    if (_started) return;
    _started = true;
    if (reduceMotion) settled.value = true;
    sheet.play(reduceMotion: reduceMotion);
  }

  /// Current playhead in ms.
  double get nowMs => sheet.controller.value * sheet.totalMs;

  /// Whether the playhead has crossed beat [name]'s start (always true once
  /// the sheet is complete).
  bool reached(String name) {
    if (sheet.isComplete) return true;
    final b = _beats[name];
    assert(b != null, 'No beat named "$name"');
    return nowMs >= b!.at;
  }

  /// Whether a tap would skip right now.
  bool get canSkip => _started && !sheet.isComplete && nowMs >= skipAfterMs;

  /// Jumps to the end state (no pending cues fire). Returns whether it
  /// skipped.
  bool skip() {
    if (!canSkip) return false;
    settled.value = true;
    sheet.skipToEnd();
    return true;
  }

  void dispose() {
    sheet.dispose();
    settled.dispose();
  }
}

/// Tap anywhere (after [ResultsBeats.skipAfterMs]) skips to the end state.
/// A translucent pointer listener, so buttons under the finger still work.
class ResultsTapToSkip extends StatelessWidget {
  const ResultsTapToSkip({super.key, required this.beats, required this.child});

  final ResultsBeats beats;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => beats.skip(),
      child: child,
    );
  }
}

/// Fades [child] in on beat [name], optionally travelling [rise] design px
/// (positive: rises from below, negative: drops from above) or [slideX]
/// (positive: slides in from the right). The child is built once and cached
/// behind a RepaintBoundary.
class BeatFade extends StatelessWidget {
  const BeatFade({
    super.key,
    required this.beats,
    required this.name,
    required this.child,
    this.rise = 10,
    this.slideX = 0,
  });

  final ResultsBeats beats;
  final String name;
  final double rise;
  final double slideX;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sheet = beats.sheet;
    final faded = FadeTransition(
      opacity: sheet.opacity(name),
      child: RepaintBoundary(child: child),
    );
    if (rise == 0 && slideX == 0) return faded;
    final dy = context.cs(rise);
    final dx = context.cs(slideX);
    final travel = sheet[name];
    return AnimatedBuilder(
      animation: travel,
      child: faded,
      builder: (context, child) {
        final k = 1 - travel.value;
        return Transform.translate(offset: Offset(dx * k, dy * k), child: child);
      },
    );
  }
}

/// Scales [child] in on beat [name] from [from] to 1 (overshooting when the
/// beat runs on a spring curve). With [fade] it also fades in (clamped).
class BeatPop extends StatelessWidget {
  const BeatPop({
    super.key,
    required this.beats,
    required this.name,
    required this.child,
    this.from = 0,
    this.fade = false,
    this.alignment = Alignment.center,
  });

  final ResultsBeats beats;
  final String name;
  final double from;
  final bool fade;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sheet = beats.sheet;
    final t = sheet[name];
    final scale = from == 0 ? t : t.drive(Animatable<double>.fromCallback((v) => from + (1 - from) * v));
    Widget out = ScaleTransition(scale: scale, alignment: alignment, child: RepaintBoundary(child: child));
    if (fade) out = FadeTransition(opacity: sheet.opacity(name), child: out);
    return out;
  }
}

/// Rebuilds [builder] only when beat [name] is crossed or the sheet settles:
/// for content that switches value at a beat (an odometer flipping from 0 to
/// the score) rather than animating per frame.
class BeatGate extends StatefulWidget {
  const BeatGate({super.key, required this.beats, required this.name, required this.builder});

  final ResultsBeats beats;
  final String name;

  /// [reached]: the beat has started. [settled]: show the end state without
  /// motion.
  final Widget Function(BuildContext context, bool reached, bool settled) builder;

  @override
  State<BeatGate> createState() => _BeatGateState();
}

class _BeatGateState extends State<BeatGate> {
  late bool _reached = widget.beats.reached(widget.name);
  late bool _settled = widget.beats.settled.value;

  @override
  void initState() {
    super.initState();
    widget.beats.listenable.addListener(_tick);
  }

  @override
  void didUpdateWidget(BeatGate old) {
    super.didUpdateWidget(old);
    if (old.beats != widget.beats) {
      old.beats.listenable.removeListener(_tick);
      widget.beats.listenable.addListener(_tick);
      _tick();
    }
  }

  void _tick() {
    final r = widget.beats.reached(widget.name);
    final s = widget.beats.settled.value;
    if (r != _reached || s != _settled) {
      setState(() {
        _reached = r;
        _settled = s;
      });
    }
  }

  @override
  void dispose() {
    widget.beats.listenable.removeListener(_tick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _reached, _settled);
}

/// A [CsOdometer] that rolls up from 0 to [value] when it first appears
/// (and rolls between values afterwards). With [instant] it renders the
/// value as plain text, no roll.
class RollUpNumber extends StatefulWidget {
  const RollUpNumber({
    super.key,
    required this.value,
    this.style,
    this.format,
    this.instant = false,
    this.duration = CsMotion.roll,
    this.semanticsLabel,
  });

  final int value;
  final TextStyle? style;
  final String Function(int value)? format;
  final bool instant;
  final Duration duration;
  final String? semanticsLabel;

  @override
  State<RollUpNumber> createState() => _RollUpNumberState();
}

class _RollUpNumberState extends State<RollUpNumber> {
  late int _shown = widget.instant ? widget.value : 0;

  @override
  void initState() {
    super.initState();
    if (_shown != widget.value) {
      // First frame shows 0, the next one rolls to the value.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shown = widget.value);
      });
    }
  }

  @override
  void didUpdateWidget(RollUpNumber old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value || (widget.instant && _shown != widget.value)) {
      _shown = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CsOdometer(
      value: _shown,
      style: widget.style,
      format: widget.format,
      duration: widget.duration,
      reduceMotion: widget.instant ? true : null,
      semanticsLabel: widget.semanticsLabel,
    );
  }
}
