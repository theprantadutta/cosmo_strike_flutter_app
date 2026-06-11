import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../router/app_router.dart';
import '../services/audio_service.dart';
import '../services/haptic_service.dart';
import '../ui/design.dart';
import '../utils/logger.dart';

/// The app-wide "you got rewarded!" toast: a borderless neon banner that
/// floats top-center above EVERYTHING (root overlay — gameplay, pause /
/// game-over overlays, dialogs, any screen), pops in, holds, fades out.
/// Never blocks input.
///
/// Call from anywhere — no BuildContext needed:
/// ```dart
/// RewardToast.show(amount: '+30 COINS');
/// RewardToast.show(title: 'COINS DOUBLED', amount: '+120 COINS');
/// RewardToast.show(icon: Icons.bolt, amount: '+1 SPEED BOOST');
/// ```
/// Consecutive calls queue FIFO (and the active toast shortens its hold so
/// a backlog drains fast). Sound + haptic self-gate on the user's settings
/// inside their services.
class RewardToast {
  RewardToast._();

  /// App-wide reward gold.
  static const Color gold = Color(0xFFFFD37B);

  static final Queue<_ToastData> _queue = Queue();
  static bool _active = false;

  /// Backlog cap — rewards are rare; anything beyond this is dropped.
  static const int _maxPending = 3;

  static void show({
    required String amount,
    String title = 'REWARD CLAIMED',
    IconData icon = Icons.monetization_on,
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
  static const int _inMs = 280;
  static const int _outMs = 350;

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
    final inEnd = _inMs / _totalMs;
    final outStart = (_inMs + widget.holdMs) / _totalMs;

    final scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.8, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: inEnd,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 1 - inEnd),
    ]).animate(_c);

    final opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: inEnd,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: outStart - inEnd),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 1 - outStart,
      ),
    ]).animate(_c);

    final lift = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: outStart),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -10.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 1 - outStart,
      ),
    ]).animate(_c);

    final d = widget.data;

    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: GameTokens.space16),
            child: Material(
              type: MaterialType.transparency,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) => Opacity(
                  opacity: opacity.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, lift.value),
                    child: Transform.scale(scale: scale.value, child: _row(d)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Borderless per the clean Command-HUD rules: neon icon disc + glowing
  // type, dark legibility shadows instead of a background box.
  Widget _row(_ToastData d) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: d.accent.withValues(alpha: 0.16),
            boxShadow: neonGlow(d.accent, intensity: 0.7),
          ),
          child: Icon(d.icon, size: 19, color: d.accent),
        ),
        const SizedBox(width: GameTokens.space12),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d.title,
              style: TextStyle(
                color: d.accent,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                shadows: [
                  Shadow(
                    color: d.accent.withValues(alpha: 0.6),
                    blurRadius: 14,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              d.amount,
              style: const TextStyle(
                color: Color(0xFFEAF6FF),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
                shadows: [
                  Shadow(color: Color(0xCC05060F), blurRadius: 8),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
