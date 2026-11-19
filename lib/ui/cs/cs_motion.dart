// Cosmo Strike motion foundation: reduce-motion lookup, haptic intents and
// the small reusable motion widgets (fade-up entrance, one-shot pop, beat
// sheet timelines). The rules and the per-interaction table live in
// docs/motion/MOTION_SPEC.md.
//
// Performance contract for everything in this file:
//  * opacity goes through FadeTransition (a composited OpacityLayer that skips
//    itself at 0 and 1), never an `Opacity` widget rebuilt every frame;
//  * per-frame values drive Transforms through AnimatedBuilder with a cached
//    `child`, so the subtree is built once and only repainted;
//  * nothing here blurs, clips with anti-aliasing, or calls saveLayer.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../services/haptic_service.dart';
import '../../services/preferences_service.dart';
import '../../theme/cosmo_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Reduce motion
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves whether motion should be reduced at a point in the tree.
///
/// Motion is reduced when ANY of these is true (first match wins for the
/// explicit override):
///  1. an explicit `override` argument (a widget's own `reduceMotion` param);
///  2. the nearest [CsReduceMotion] scope (tests, or a subtree that must stay
///     still);
///  3. the in-app setting, Settings → Access → Reduce motion
///     (`PreferencesService.reduceMotion`, provided above `MaterialApp` by the
///     root `MultiProvider`; the lookup subscribes, so flipping the switch
///     rebuilds dependants);
///  4. the OS flag, `MediaQuery.disableAnimations`.
///
/// ```dart
/// final reduce = CsReduceMotion.of(context);
/// ```
///
/// Haptics are NOT governed by this; they have their own toggle (see
/// [CsHaptic]).
class CsReduceMotion extends InheritedWidget {
  /// Forces [reduceMotion] for [child]. A scope can only ADD reduction: with
  /// `reduceMotion: false` the in-app setting and OS flag still apply below it.
  const CsReduceMotion({super.key, required this.reduceMotion, required super.child});

  final bool reduceMotion;

  /// Whether motion should be reduced here. Call from `build` or
  /// `didChangeDependencies` (it registers a dependency so the caller rebuilds
  /// when the setting changes). Pass `listen: false` from callbacks and
  /// `initState`.
  static bool of(BuildContext context, {bool? override, bool listen = true}) {
    if (override != null) return override;
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<CsReduceMotion>()
        : context.getInheritedWidgetOfExactType<CsReduceMotion>();
    if (scope != null && scope.reduceMotion) return true;
    if (_appSetting(context, listen)) return true;
    if (!listen) {
      // No dependency, so this is safe from initState and callbacks.
      return context.getInheritedWidgetOfExactType<MediaQuery>()?.data.disableAnimations ?? false;
    }
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  static bool _appSetting(BuildContext context, bool listen) {
    try {
      return Provider.of<PreferencesService>(context, listen: listen).reduceMotion;
    } on ProviderNotFoundException {
      // Test harnesses and previews have no PreferencesService above them.
      return false;
    }
  }

  /// [full] normally, or [reduced] (default: zero) when motion is reduced.
  ///
  /// ```dart
  /// AnimatedScale(duration: CsReduceMotion.duration(context, CsMotion.gentle), …)
  /// ```
  static Duration duration(
    BuildContext context,
    Duration full, {
    Duration reduced = Duration.zero,
  }) =>
      of(context) ? reduced : full;

  /// [full] normally, or `Curves.linear` when motion is reduced, so an
  /// overshooting spring never plays as a short jolt.
  static Curve curve(BuildContext context, Curve full) =>
      of(context) ? Curves.linear : full;

  @override
  bool updateShouldNotify(CsReduceMotion oldWidget) => oldWidget.reduceMotion != reduceMotion;
}

// ─────────────────────────────────────────────────────────────────────────────
// Haptics
// ─────────────────────────────────────────────────────────────────────────────

/// A haptic intent for UI interactions. Plays through the [HapticService]
/// singleton, which honours the player's Haptics toggle (hydrated from the
/// Drift settings row at startup and flipped by Settings / the pause menu), so
/// callers never check the setting themselves.
///
/// ```dart
/// CsHaptic.selection.play();
/// ```
enum CsHaptic {
  /// No feedback.
  none,

  /// Tiny tick: toggles, segments, tabs, list selection.
  selection,

  /// Light tap: buttons.
  light,

  /// Firmer tap: confirming something weighty (start run, buy).
  medium,

  /// Short ascending pattern: reward claimed, level clear.
  success;

  /// Fire this haptic (no-op for [none] or when haptics are off).
  void play() {
    final h = HapticService();
    switch (this) {
      case CsHaptic.none:
        return;
      case CsHaptic.selection:
        unawaited(h.selectionClick());
      case CsHaptic.light:
        unawaited(h.lightImpact());
      case CsHaptic.medium:
        unawaited(h.mediumImpact());
      case CsHaptic.success:
        unawaited(h.customHaptic(HapticIntensity.success));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CsFadeUp — staggered entrance
// ─────────────────────────────────────────────────────────────────────────────

/// Fades [child] in while it rises [distance] design px (scaled by
/// `context.cs`), once, when it first mounts. Use [index] for list stagger:
/// slot `i` waits `CsMotion.stagger(i)` (55 ms per slot, capped at slot 8).
///
/// Rebuilding with new props never replays it; give it a new `key` to replay.
/// Reduce motion: no slide and no stagger, a plain 120 ms fade.
///
/// ```dart
/// for (final (i, row) in rows.indexed) CsFadeUp(index: i, child: row)
/// ```
class CsFadeUp extends StatefulWidget {
  const CsFadeUp({
    super.key,
    required this.child,
    this.index = 0,
    this.delay,
    this.distance = 10,
    this.duration = CsMotion.gentle,
    this.curve = CsMotion.easeOutSoft,
    this.reduceMotion,
  });

  final Widget child;

  /// Stagger slot; ignored when [delay] is given.
  final int index;

  /// Explicit start delay (overrides [index]).
  final Duration? delay;

  /// Rise in design px at the 960×432 frame (scaled per device).
  final double distance;
  final Duration duration;
  final Curve curve;

  /// Overrides [CsReduceMotion.of] (tests).
  final bool? reduceMotion;

  @override
  State<CsFadeUp> createState() => _CsFadeUpState();
}

class _CsFadeUpState extends State<CsFadeUp> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late Animation<double> _fade;
  late Animation<double> _rise;
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return; // Decided once, on first mount.
    _reduce = CsReduceMotion.of(context, override: widget.reduceMotion, listen: false);
    final delay = _reduce ? Duration.zero : (widget.delay ?? CsMotion.stagger(widget.index));
    final run = _reduce ? CsMotion.instant : widget.duration;
    final total = delay + run;
    final start = total.inMicroseconds == 0 ? 0.0 : delay.inMicroseconds / total.inMicroseconds;
    final c = AnimationController(vsync: this, duration: total);
    _c = c;
    _fade = CurvedAnimation(parent: c, curve: Interval(start, 1, curve: _reduce ? Curves.linear : CsMotion.easeOutSoft));
    _rise = CurvedAnimation(parent: c, curve: Interval(start, 1, curve: widget.curve));
    c.forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final faded = FadeTransition(opacity: _fade, child: widget.child);
    if (_reduce) return faded;
    final d = context.cs(widget.distance);
    return AnimatedBuilder(
      animation: _rise,
      child: faded,
      builder: (context, child) =>
          Transform.translate(offset: Offset(0, d * (1 - _rise.value)), child: child),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CsPop — one-shot scale pop
// ─────────────────────────────────────────────────────────────────────────────

/// Plays a one-shot scale pop on [child] every time [trigger] changes (by
/// `==`): it swells to [peak] over the first 35% (easeOutSoft) and settles
/// back to 1 on `springPop`, dipping just under 1 before resting. Use for
/// pickups, the chain counter, stars landing, claimed rewards.
///
/// Wrapped in a RepaintBoundary so a HUD pop never repaints its neighbours.
/// Reduce motion: no pop, the child just updates.
///
/// ```dart
/// CsPop(trigger: chain, child: Text('×$chain', style: t.hudScore))
/// ```
class CsPop extends StatefulWidget {
  const CsPop({
    super.key,
    required this.trigger,
    required this.child,
    this.peak = 1.12,
    this.duration = CsMotion.pop,
    this.playOnMount = false,
    this.alignment = Alignment.center,
    this.reduceMotion,
  });

  /// Any value; a change (by `==`) plays the pop.
  final Object? trigger;
  final Widget child;

  /// Maximum scale (1.12 = 12% bigger).
  final double peak;
  final Duration duration;

  /// Also pop when first built (a star appearing, a reward card arriving).
  final bool playOnMount;
  final Alignment alignment;

  /// Overrides [CsReduceMotion.of] (tests).
  final bool? reduceMotion;

  @override
  State<CsPop> createState() => _CsPopState();
}

class _CsPopState extends State<CsPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration, value: 1);
  late Animation<double> _scale = _buildScale();
  bool _mountChecked = false;

  Animation<double> _buildScale() => TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: 1.0, end: widget.peak).chain(CurveTween(curve: CsMotion.easeOutSoft)),
          weight: 35,
        ),
        TweenSequenceItem(
          tween: Tween(begin: widget.peak, end: 1.0).chain(_UnclampedCurveTween(CsMotion.springPop)),
          weight: 65,
        ),
      ]).animate(_c);

  bool get _reduce => CsReduceMotion.of(context, override: widget.reduceMotion, listen: false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mountChecked) return;
    _mountChecked = true;
    if (widget.playOnMount && !_reduce) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(CsPop old) {
    super.didUpdateWidget(old);
    if (old.peak != widget.peak) _scale = _buildScale();
    if (old.duration != widget.duration) _c.duration = widget.duration;
    if (old.trigger != widget.trigger && !_reduce) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ScaleTransition(scale: _scale, alignment: widget.alignment, child: widget.child),
    );
  }
}

/// CurveTween asserts its output stays in 0..1; spring curves overshoot on
/// purpose, so map through the curve without that check.
class _UnclampedCurveTween extends Animatable<double> {
  const _UnclampedCurveTween(this.curve);
  final Curve curve;

  @override
  double transform(double t) => curve.transform(t);
}

// ─────────────────────────────────────────────────────────────────────────────
// CsBeatSheet — choreographed timelines
// ─────────────────────────────────────────────────────────────────────────────

/// One beat of a [CsBeatSheet]: starts [at] ms after the sheet starts and runs
/// for [duration] ms on [curve]. [onStart] fires once when playback crosses
/// [at] (haptics, sounds), never when the sheet is skipped.
@immutable
class CsBeat {
  const CsBeat({
    required this.at,
    required this.duration,
    this.curve = CsMotion.easeOutSoft,
    this.onStart,
  });

  /// Start, in absolute ms from the beginning of the sheet.
  final int at;

  /// Length in ms.
  final int duration;
  final Curve curve;
  final VoidCallback? onStart;

  int get end => at + duration;
}

/// A choreographed timeline: ONE AnimationController, many named beats laid
/// out in absolute milliseconds and exposed as `Interval` animations.
///
/// Create it in `initState` with the State's ticker, read beats with
/// `sheet['name']` (a 0→1 Animation, may overshoot for spring curves), drive
/// FadeTransition / ScaleTransition / AnimatedBuilder with them, and
/// `dispose()` it with the State. A tap anywhere should call [skipToEnd].
///
/// ```dart
/// late final sheet = CsBeatSheet(vsync: this, beats: {
///   'title': const CsBeat(at: 0, duration: 400),
///   'score': const CsBeat(at: 250, duration: 600),
///   'stars': CsBeat(at: 700, duration: 450, curve: CsMotion.springPop,
///       onStart: CsHaptic.success.play),
/// })..play(reduceMotion: CsReduceMotion.of(context, listen: false));
///
/// FadeTransition(opacity: sheet.opacity('title'), child: title)
/// ```
class CsBeatSheet {
  CsBeatSheet({required TickerProvider vsync, required Map<String, CsBeat> beats})
      : assert(beats.isNotEmpty, 'A beat sheet needs at least one beat'),
        _beats = Map.unmodifiable(beats),
        totalMs = beats.values.fold<int>(0, (m, b) => b.end > m ? b.end : m) {
    controller = AnimationController(
      vsync: vsync,
      duration: Duration(milliseconds: totalMs < 1 ? 1 : totalMs),
    )..addListener(_fireCues);
  }

  final Map<String, CsBeat> _beats;

  /// Length of the whole sheet in ms (the latest beat end).
  final int totalMs;

  /// The single driver. Exposed for `AnimatedBuilder(animation: sheet.controller)`
  /// and status listeners; prefer [play] / [skipToEnd] to drive it.
  late final AnimationController controller;

  final Map<String, Animation<double>> _cache = {};
  final Map<String, Animation<double>> _opacityCache = {};
  final Set<String> _fired = {};
  bool _skipping = false;

  /// The beat names, in insertion order.
  Iterable<String> get names => _beats.keys;

  /// True once the sheet has reached its end (played or skipped).
  bool get isComplete => controller.status == AnimationStatus.completed;

  /// The 0→1 progress of beat [name] on its curve (overshoots for springs).
  Animation<double> operator [](String name) => _cache.putIfAbsent(name, () {
        final b = _beats[name];
        assert(b != null, 'No beat named "$name"');
        final total = totalMs < 1 ? 1 : totalMs;
        return CurvedAnimation(
          parent: controller,
          curve: Interval(b!.at / total, (b.end / total).clamp(0.0, 1.0), curve: b.curve),
        );
      });

  /// Beat [name] clamped to 0..1, safe for FadeTransition.
  Animation<double> opacity(String name) => _opacityCache.putIfAbsent(
        name,
        () => this[name].drive(Animatable<double>.fromCallback((v) => v.clamp(0.0, 1.0))),
      );

  /// Plays from the start. With [reduceMotion] it jumps straight to the final
  /// frame (callers that want a short fade wrap the whole result in one
  /// FadeTransition instead). Returns when the sheet finishes.
  TickerFuture play({bool reduceMotion = false}) {
    _fired.clear();
    if (reduceMotion) {
      skipToEnd();
      return TickerFuture.complete();
    }
    return controller.forward(from: 0);
  }

  /// Jumps every beat to its end state without firing pending cues.
  void skipToEnd() {
    _skipping = true;
    controller.value = 1;
    _fired.addAll(_beats.keys);
    _skipping = false;
  }

  void _fireCues() {
    if (_skipping) return;
    final nowMs = controller.value * totalMs;
    for (final e in _beats.entries) {
      final cue = e.value.onStart;
      if (cue == null || _fired.contains(e.key)) continue;
      if (nowMs >= e.value.at) {
        _fired.add(e.key);
        cue();
      }
    }
  }

  void dispose() => controller.dispose();
}
