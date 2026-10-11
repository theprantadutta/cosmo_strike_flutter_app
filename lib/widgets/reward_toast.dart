import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../router/app_router.dart';
import '../services/audio_service.dart';
import '../services/haptic_service.dart';
import '../ui/cs.dart';
import '../utils/logger.dart';

/// The app-wide "you got rewarded!" toast: a Prism Noir pill (raised fill,
/// subtle border, coin / given icon, Syne title + gold mono amount) that
/// floats top-center above EVERYTHING (root overlay — gameplay, pause /
/// game-over overlays, dialogs, any screen), slides in, holds, fades out.
/// Never blocks input.
///
/// Call from anywhere — no BuildContext needed:
/// ```dart
/// RewardToast.show(amount: '+30 COINS');
/// RewardToast.show(title: 'COINS DOUBLED', amount: '+120 COINS');
/// RewardToast.show(icon: Symbols.bolt_rounded, amount: '+1 SPEED BOOST');
/// ```
/// Consecutive calls queue FIFO (and the active toast shortens its hold so
/// a backlog drains fast). Sound + haptic self-gate on the user's settings
/// inside their services.
class RewardToast {
  RewardToast._();

  /// App-wide reward gold.
  static const Color gold = CsColors.gold;

  /// Default glyph — rendered as the coin art rather than the icon font.
  static const IconData _coinIcon = Symbols.paid_rounded;

  static final Queue<_ToastData> _queue = Queue();
  static bool _active = false;

  /// Backlog cap — rewards are rare; anything beyond this is dropped.
  static const int _maxPending = 3;

  static void show({
    required String amount,
    String title = 'REWARD CLAIMED',
    IconData icon = _coinIcon,
    Color accent = gold,
  }) {
    if (_queue.length >= _maxPending) return;
    _queue.add(_ToastData(
      title: title,
      amount: amount,
      icon: icon,
      accent: accent,
    ));
    _pump();
  }

  static void _pump() {
    if (_active || _queue.isEmpty) return;
    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      // Boot race / no navigator yet — drop, same posture as SyncEngine.
      AppLogger.warning('RewardToast: no root overlay — toast dropped');
      _queue.clear();
      return;
    }

    _active = true;
    final data = _queue.removeFirst();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _RewardToastView(
        data: data,
        // Drain fast when more rewards are waiting behind this one.
        holdMs: _queue.isEmpty ? 2200 : 1400,
        onDone: () {
          entry.remove();
          _active = false;
          _pump();
        },
      ),
    );
    overlay.insert(entry);

    AudioService().playSound('coin_collect');
    unawaited(HapticService().customHaptic(HapticIntensity.success));
  }
}

class _ToastData {
  const _ToastData({
    required this.title,
    required this.amount,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String amount;
  final IconData icon;
  final Color accent;
}

class _RewardToastView extends StatefulWidget {
  const _RewardToastView({
    required this.data,
    required this.holdMs,
    required this.onDone,
  });

  final _ToastData data;
  final int holdMs;
  final VoidCallback onDone;

  @override
  State<_RewardToastView> createState() => _RewardToastViewState();
}

class _RewardToastViewState extends State<_RewardToastView>
    with SingleTickerProviderStateMixin {
  static final int _inMs = CsMotion.slow.inMilliseconds;
  static final int _outMs = CsMotion.base.inMilliseconds;

  late final int _totalMs = _inMs + widget.holdMs + _outMs;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _totalMs),
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final inEnd = _inMs / _totalMs;
    final outStart = (_inMs + widget.holdMs) / _totalMs;

    final opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: CsMotion.standard)),
        weight: inEnd,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: outStart - inEnd),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: CsMotion.standard)),
        weight: 1 - outStart,
      ),
    ]).animate(_c);

    // Slides down into place, then lifts slightly as it fades out.
    final dy = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: -cs(14), end: 0.0).chain(CurveTween(curve: CsMotion.standard)),
        weight: inEnd,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: outStart - inEnd),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -cs(8)).chain(CurveTween(curve: CsMotion.standard)),
        weight: 1 - outStart,
      ),
    ]).animate(_c);

    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: cs(16)),
            child: Material(
              type: MaterialType.transparency,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, child) => Opacity(
                  opacity: opacity.value.clamp(0.0, 1.0),
                  child: Transform.translate(offset: Offset(0, dy.value), child: child),
                ),
                child: _pill(context, widget.data),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, _ToastData d) {
    final cs = context.cs;
    final t = cs.type;
    final glyph = d.icon == RewardToast._coinIcon
        ? Image.asset('assets/images/ui/coin.png', width: cs(20), height: cs(20))
        : Icon(d.icon, size: cs(20), color: d.accent);

    return Container(
      constraints: BoxConstraints(maxWidth: cs(560)),
      padding: EdgeInsets.fromLTRB(cs(14), cs(10), cs(20), cs(10)),
      decoration: const ShapeDecoration(
        color: CsColors.raised2,
        shape: StadiumBorder(side: BorderSide(color: CsColors.lineSubtle)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          glyph,
          SizedBox(width: cs(10)),
          Flexible(
            child: Text(
              d.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.display(13, weight: FontWeight.w700, em: 0.08, height: 1.1),
            ),
          ),
          SizedBox(width: cs(12)),
          Text(
            d.amount,
            maxLines: 1,
            style: t.mono(12, weight: FontWeight.w600, em: 0.06, color: d.accent),
          ),
        ],
      ),
    );
  }
}
