import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../services/analytics/test_device.dart';
import '../ui/cs.dart';

/// Hidden developer switch: tapping [child] (the version chip in About &
/// Credits) [tapsNeeded] times in a row marks / unmarks this device as a
/// test device (see [TestDevice]). Taps more than [maxGap] apart restart
/// the count. Nothing is shown until the switch flips.
class TestDeviceTapTarget extends StatefulWidget {
  const TestDeviceTapTarget({
    super.key,
    required this.child,
    this.tapsNeeded = 7,
    this.maxGap = const Duration(milliseconds: 1500),
  });

  final Widget child;
  final int tapsNeeded;
  final Duration maxGap;

  @override
  State<TestDeviceTapTarget> createState() => _TestDeviceTapTargetState();
}

class _TestDeviceTapTargetState extends State<TestDeviceTapTarget> {
  int _taps = 0;
  DateTime? _lastTap;

  Future<void> _onTap() async {
    final now = DateTime.now();
    final last = _lastTap;
    _taps = (last == null || now.difference(last) > widget.maxGap)
        ? 1
        : _taps + 1;
    _lastTap = now;
    if (_taps < widget.tapsNeeded) return;
    _taps = 0;
    _lastTap = null;
    final on = await TestDevice.instance.toggle();
    if (!mounted) return;
    showCsToast(
      context,
      on ? 'Test device: on (analytics off)' : 'Test device: off',
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => unawaited(_onTap()),
    child: widget.child,
  );
}
