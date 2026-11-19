import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// App harness; [reduce] puts a CsReduceMotion scope above the Navigator so
/// routes and overlay entries (dialogs, toasts) see it too.
Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, nav) => CsReduceMotion(reduceMotion: reduce, child: nav!),
      home: Scaffold(body: Center(child: child)),
    );

/// Rebuilds [builder] with a value the test can change.
class _Host<V> extends StatefulWidget {
  const _Host({required this.initial, required this.builder});
  final V initial;
  final Widget Function(V value, ValueChanged<V> set) builder;
  @override
  State<_Host<V>> createState() => _HostState<V>();
}

class _HostState<V> extends State<_Host<V>> {
  late V value = widget.initial;
  void set(V v) => setState(() => value = v);
  @override
  Widget build(BuildContext context) => widget.builder(value, set);
}

Future<void> _set<V>(WidgetTester tester, V v) async {
  tester.state<_HostState<V>>(find.byType(_Host<V>)).set(v);
  await tester.pump();
}

/// The rrect the segmented control's pill painter draws right now.
RRect? _pillRRect(WidgetTester tester) {
  RRect? captured;
  final paint = find.descendant(of: find.byType(CsSegmented<String>), matching: find.byType(CustomPaint)).first;
  expect(
    paint,
    paints
      ..everything((method, args) {
        if (method == #drawRRect) captured = args[0] as RRect;
        return true;
      }),
  );
  return captured;
}

/// The segment [label]'s rect in the pill painter's coordinates.
Rect _segmentRect(WidgetTester tester, String label) {
  final paint = find.descendant(of: find.byType(CsSegmented<String>), matching: find.byType(CustomPaint)).first;
  final origin = tester.getTopLeft(paint);
  final seg = find.ancestor(of: find.text(label), matching: find.byType(CsPressable)).first;
  return tester.getRect(seg).shift(-origin);
}

void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 0.01));
  expect(actual.top, closeTo(expected.top, 0.01));
  expect(actual.right, closeTo(expected.right, 0.01));
  expect(actual.bottom, closeTo(expected.bottom, 0.01));
}

void main() {
  group('showCsDialog', () {
    Future<void> open(WidgetTester tester, {bool reduce = false}) async {
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCsDialog<void>(context, builder: (_) => const CsDialog(title: 'Hello pilot')),
            child: const Text('open'),
          ),
        ),
        reduce: reduce,
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
    }

    ScaleTransition? cardScale(WidgetTester tester) {
      final f = find.ancestor(of: find.text('Hello pilot'), matching: find.byType(ScaleTransition));
      return f.evaluate().isEmpty ? null : tester.widget<ScaleTransition>(f.first);
    }

    FadeTransition cardFade(WidgetTester tester) =>
        tester.widget<FadeTransition>(find.ancestor(of: find.text('Hello pilot'), matching: find.byType(FadeTransition)).first);

    testWidgets('card fades and scales in from 0.94 and lands at 1', (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 60));
      expect(cardScale(tester)!.scale.value, inExclusiveRange(0.94, 1.0));
      expect(cardFade(tester).opacity.value, inExclusiveRange(0.0, 1.0));

      await tester.pump(CsMotion.slow);
      expect(cardScale(tester)!.scale.value, 1.0);
      expect(cardFade(tester).opacity.value, 1.0);
    });

    testWidgets('leaves faster than it arrives', (tester) async {
      await open(tester);
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Hello pilot'))).pop();
      await tester.pump();
      await tester.pump(CsMotion.quick + const Duration(milliseconds: 20));
      expect(find.text('Hello pilot'), findsNothing);
    });

    testWidgets('reduce motion: a short fade, no scale', (tester) async {
      await open(tester, reduce: true);
      expect(cardScale(tester), isNull);
      await tester.pump(CsMotion.instant);
      expect(cardFade(tester).opacity.value, 1.0);
    });
  });

  group('CsSegmented', () {
    Widget seg({bool reduce = false}) => _app(
          _Host<String>(
            initial: 'a',
            builder: (v, set) => CsSegmented<String>(
              segments: const {'a': 'Global', 'b': 'Weekly', 'c': 'Friends of the squad'},
              selected: v,
              onChanged: set,
            ),
          ),
          reduce: reduce,
        );

    testWidgets('pill sits under the selected segment', (tester) async {
      await tester.pumpWidget(seg());
      _expectRect(_pillRRect(tester)!.outerRect, _segmentRect(tester, 'GLOBAL'));
    });

    testWidgets('pill travels to the new segment and lands on it', (tester) async {
      await tester.pumpWidget(seg());
      final start = _segmentRect(tester, 'GLOBAL');
      final end = _segmentRect(tester, 'FRIENDS OF THE SQUAD');

      await tester.tap(find.text('FRIENDS OF THE SQUAD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      final mid = _pillRRect(tester)!.outerRect;
      expect(mid.left, greaterThan(start.left));
      expect(mid.left, lessThan(end.left));

      await tester.pumpAndSettle();
      _expectRect(_pillRRect(tester)!.outerRect, end);
    });

    testWidgets('reduce motion: the pill jumps', (tester) async {
      await tester.pumpWidget(seg(reduce: true));
      await tester.tap(find.text('WEEKLY'));
      await tester.pump();
      await tester.pump();
      _expectRect(_pillRRect(tester)!.outerRect, _segmentRect(tester, 'WEEKLY'));
      await tester.pumpAndSettle();
    });
  });

  group('CsRollingText / CsStatGrid / CsCoins', () {
    testWidgets('static on first build, rolls once the number changes', (tester) async {
      await tester.pumpWidget(_app(_Host<int>(
        initial: 1250,
        builder: (v, _) => CsRollingText(csGroupDigits(v), style: const TextStyle(fontSize: 12)),
      )));
      expect(find.byType(CsOdometer), findsNothing);
      expect(find.text('1,250'), findsOneWidget);

      await _set(tester, 1300);
      expect(find.byType(CsOdometer), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('1,300'), findsOneWidget);
    });

    testWidgets('a non-number change stays a plain Text', (tester) async {
      await tester.pumpWidget(_app(_Host<String>(
        initial: '12',
        builder: (v, _) => CsRollingText(v, style: const TextStyle(fontSize: 12)),
      )));
      await _set(tester, 'STABLE');
      expect(find.byType(CsOdometer), findsNothing);
      expect(find.text('STABLE'), findsOneWidget);
    });

    testWidgets('CsStatGrid rolls changed values only after the first build', (tester) async {
      await tester.pumpWidget(_app(SizedBox(
        width: 600,
        child: _Host<int>(
          initial: 10,
          builder: (v, _) => CsStatGrid(stats: [CsStat('$v', 'Kills'), const CsStat('x3', 'Chain')]),
        ),
      )));
      expect(find.byType(CsOdometer), findsNothing);
      await _set(tester, 11);
      expect(find.byType(CsOdometer), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('CsCoins rolls the balance on change; reduce motion swaps instantly', (tester) async {
      await tester.pumpWidget(_app(_Host<int>(initial: 90, builder: (v, _) => CsCoins(v)), reduce: true));
      await _set(tester, 120);
      // Reduce motion: the odometer renders the new value as one Text.
      expect(find.text('120'), findsOneWidget);
    });
  });

  group('CsProgressLine / CsRingProgress', () {
    double widthFactor(WidgetTester tester) =>
        tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).widthFactor!;

    testWidgets('fill animates to the new value and settles', (tester) async {
      await tester.pumpWidget(_app(SizedBox(
        width: 200,
        child: _Host<double>(initial: 0.2, builder: (v, _) => CsProgressLine(value: v)),
      )));
      expect(widthFactor(tester), 0.2);
      await _set(tester, 0.8);
      await tester.pump(const Duration(milliseconds: 100));
      expect(widthFactor(tester), inExclusiveRange(0.2, 0.8));
      await tester.pumpAndSettle();
      expect(widthFactor(tester), closeTo(0.8, 1e-9));
    });

    testWidgets('reduce motion: lands within 120 ms', (tester) async {
      await tester.pumpWidget(_app(
        SizedBox(width: 200, child: _Host<double>(initial: 0.2, builder: (v, _) => CsProgressLine(value: v))),
        reduce: true,
      ));
      await _set(tester, 0.8);
      await tester.pump(CsMotion.instant);
      expect(widthFactor(tester), closeTo(0.8, 1e-9));
    });

    testWidgets('popOnComplete pops when the value reaches 1', (tester) async {
      await tester.pumpWidget(_app(_Host<double>(
        initial: 0.5,
        builder: (v, _) => CsRingProgress(value: v, size: 60, popOnComplete: true, child: const Text('ring')),
      )));
      double scale() => tester
          .widget<ScaleTransition>(find.ancestor(of: find.text('ring'), matching: find.byType(ScaleTransition)).first)
          .scale
          .value;
      expect(scale(), 1.0);
      await _set(tester, 1.0);
      // The pop waits for the fill to nearly land (60% of the 320 ms fill).
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 100));
      expect(scale(), greaterThan(1.0));
      await tester.pumpAndSettle();
      expect(scale(), closeTo(1.0, 1e-6));
    });

    testWidgets('ring: short easeOutSoft by default, instant with reduce motion', (tester) async {
      Widget ring(bool reduce) => _app(
            _Host<double>(initial: 0.2, builder: (v, _) => CsRingProgress(value: v, size: 60)),
            reduce: reduce,
          );
      TweenAnimationBuilder<double> tween() => tester.widget<TweenAnimationBuilder<double>>(
            find.descendant(of: find.byType(CsRingProgress), matching: find.byType(TweenAnimationBuilder<double>)),
          );

      await tester.pumpWidget(ring(false));
      expect(tween().duration, CsMotion.slow);
      expect(tween().curve, CsMotion.easeOutSoft);

      await tester.pumpWidget(ring(true));
      expect(tween().duration, Duration.zero);
    });
  });

  group('CsSwitch', () {
    testWidgets('tap flips the value', (tester) async {
      await tester.pumpWidget(_app(_Host<bool>(
        initial: false,
        builder: (v, set) => CsSwitch(value: v, onChanged: set, haptic: CsHaptic.none),
      )));
      await tester.tap(find.byType(CsSwitch));
      await tester.pumpAndSettle();
      expect(tester.widget<CsSwitch>(find.byType(CsSwitch)).value, isTrue);
    });
  });

  group('showCsToast', () {
    testWidgets('drops in, holds, leaves and removes itself', (tester) async {
      await tester.pumpWidget(_app(Builder(
        builder: (context) => TextButton(
          onPressed: () => showCsToast(context, 'Saved', duration: const Duration(milliseconds: 1000)),
          child: const Text('go'),
        ),
      )));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(CsMotion.gentle);
      final fade = tester.widget<FadeTransition>(find.ancestor(of: find.text('Saved'), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, 1.0);
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(CsMotion.release + const Duration(milliseconds: 20));
      expect(find.text('Saved'), findsNothing);
    });

    testWidgets('reduce motion: fades in 120 ms without moving', (tester) async {
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showCsToast(context, 'Saved', duration: const Duration(milliseconds: 500)),
            child: const Text('go'),
          ),
        ),
        reduce: true,
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(CsMotion.instant);
      final fade = tester.widget<FadeTransition>(find.ancestor(of: find.text('Saved'), matching: find.byType(FadeTransition)).first);
      expect(fade.opacity.value, 1.0);
      final moved = find.ancestor(of: find.text('Saved'), matching: find.byType(Transform));
      for (final e in moved.evaluate()) {
        final m = (e.widget as Transform).transform;
        expect(m.getTranslation().y, 0.0);
      }
      await tester.pump(const Duration(milliseconds: 800));
    });
  });
}
