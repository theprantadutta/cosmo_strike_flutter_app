import 'dart:async';
import 'dart:collection';

import 'package:material_ui/material_ui.dart';

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

/// Motion: drops in on `springSoft` with an `easeOutSoft` fade
/// (`CsMotion.gentle`), the amount pops ([CsPop]) as the pill lands, it
/// holds, then fades and lifts away on `exit` in `CsMotion.release`.
/// One controller drives in and out; opacity is a FadeTransition and the
/// slide a Transform over a cached child, all inside a RepaintBoundary so a
/// toast over gameplay never repaints the HUD. Reduce motion: 120 ms fades,
/// no movement, no pop.
class _RewardToastViewState extends State<_RewardToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: CsMotion.gentle,
    reverseDuration: CsMotion.release,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: CsMotion.easeOutSoft,
    reverseCurve: CsMotion.exit,
  );
  late final Animation<double> _slide = CurvedAnimation(
    parent: _c,
    curve: CsMotion.springSoft,
    reverseCurve: CsMotion.exit,
  );

  bool _started = false;
  bool _reduce = false;
  Timer? _hold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduce = CsReduceMotion.of(context, listen: false);
    if (_reduce) {
      _c
        ..duration = CsMotion.instant
        ..reverseDuration = CsMotion.instant;
    }
    _c.forward().whenComplete(() {
      if (!mounted) return;
      _hold = Timer(Duration(milliseconds: widget.holdMs), () async {
        if (!mounted) return;
        await _c.reverse();
        if (mounted) widget.onDone();
      });
    });
  }

  @override
  void dispose() {
    _hold?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final drop = cs(14);
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.only(top: cs(16)),
            child: Material(
              type: MaterialType.transparency,
              child: RepaintBoundary(
                child: FadeTransition(
                  opacity: _fade,
                  child: AnimatedBuilder(
                    animation: _slide,
                    builder: (_, child) => _reduce
                        ? child!
                        : Transform.translate(
                            // In: drops from above. Out: the reverse lifts
                            // it back up as it fades.
                            offset: Offset(0, -drop * (1 - _slide.value)),
                            child: child,
                          ),
                    child: _pill(context, widget.data),
                  ),
                ),
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
          // Pops as the pill lands (most of the drop is done by ~180 ms).
          CsPop(
            trigger: null,
            playOnMount: true,
            delay: CsMotion.quick,
            peak: 1.18,
            child: Text(
              d.amount,
              maxLines: 1,
              style: t.mono(12, weight: FontWeight.w600, em: 0.06, color: d.accent),
            ),
          ),
        ],
      ),
    );
  }
}
