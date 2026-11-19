import 'package:material_ui/material_ui.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

/// First-open stagger for a screen's lazily built lists.
///
/// [CsFadeUp] plays whenever its element mounts, and lazy lists (ListView /
/// GridView) mount rows again as they scroll back into view. Hold one
/// [ListEntrance] per screen State and wrap rows with [wrap]: rows built in
/// the first moments after the first row was built (so lists whose data
/// arrives asynchronously still get it) get the full staggered fade-up;
/// rows mounted later (scrolling, a tab opened later, new data) only get the
/// short reduce-motion fade, so nothing rises or waits on scroll.
///
/// ```dart
/// final _entrance = ListEntrance();
/// for (final (i, row) in rows.indexed) _entrance.wrap(i, row)
/// ```
class ListEntrance {
  ListEntrance({this.window = const Duration(milliseconds: 900)});

  /// How long after the first [wrap] rows still get the full entrance.
  final Duration window;

  /// Starts on the first [wrap] call.
  final Stopwatch _clock = Stopwatch();

  /// True once the entrance window has passed.
  bool get settled => _clock.elapsed > window;

  /// Opens a new entrance window that starts with the next [wrap] (e.g.
  /// when switching to a tab whose rows will all mount fresh).
  void restart() => _clock
    ..stop()
    ..reset();

  /// Wraps [child] in a [CsFadeUp] at stagger slot [index] (capped by
  /// `CsMotion.stagger`). Reduce motion is still honoured by CsFadeUp.
  Widget wrap(int index, Widget child, {Key? key, double distance = 10}) {
    if (!_clock.isRunning) _clock.start();
    return CsFadeUp(
      key: key,
      index: index,
      distance: distance,
      reduceMotion: settled ? true : null,
      child: child,
    );
  }
}
