import 'package:cosmo_strike_flutter_app/services/haptic_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:flutter/gestures.dart' show kPressTimeout;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

/// A widget whose value can be changed from the test.
class _Host extends StatefulWidget {
  const _Host({required this.builder, required this.initial});
  final Widget Function(int value) builder;
  final int initial;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int value = widget.initial;
  void set(int v) => setState(() => value = v);
  @override
  Widget build(BuildContext context) => widget.builder(value);
}

Future<void> _setValue(WidgetTester tester, int v) async {
  tester.state<_HostState>(find.byType(_Host)).set(v);
  await tester.pump();
}

void main() {
  group('CsReduceMotion', () {
    Future<bool> resolve(WidgetTester tester, Widget Function(Widget probe) wrap, {bool os = false}) async {
      late bool result;
      await tester.pumpWidget(_app(
        wrap(Builder(builder: (context) {
          result = CsReduceMotion.of(context);
          return const SizedBox();
        })),
        disableAnimations: os,
      ));
      return result;
    }

    testWidgets('off by default', (tester) async {
      expect(await resolve(tester, (p) => p), isFalse);
    });

    testWidgets('follows the OS disableAnimations flag', (tester) async {
      expect(await resolve(tester, (p) => p, os: true), isTrue);
    });

    testWidgets('a scope forces it on', (tester) async {
      expect(await resolve(tester, (p) => CsReduceMotion(reduceMotion: true, child: p)), isTrue);
    });

    testWidgets('a false scope cannot cancel the OS flag', (tester) async {
      expect(await resolve(tester, (p) => CsReduceMotion(reduceMotion: false, child: p), os: true), isTrue);
    });

    testWidgets('an explicit override wins', (tester) async {
      late bool result;
      await tester.pumpWidget(_app(
        Builder(builder: (context) {
          result = CsReduceMotion.of(context, override: false);
          return const SizedBox();
        }),
        disableAnimations: true,
      ));
      expect(result, isFalse);
    });

    testWidgets('duration() falls back when reduced', (tester) async {
      late Duration d;
      await tester.pumpWidget(_app(
        CsReduceMotion(
          reduceMotion: true,
          child: Builder(builder: (context) {
            d = CsReduceMotion.duration(context, CsMotion.gentle, reduced: CsMotion.instant);
            return const SizedBox();
          }),
        ),
      ));
      expect(d, CsMotion.instant);
    });
  });

  group('CsOdometer', () {
    Widget odometer({bool? reduce}) => _Host(
          initial: 5,
          builder: (v) => CsOdometer(value: v, reduceMotion: reduce, style: const TextStyle(fontSize: 20)),
        );

    testWidgets('formats with thousands separators', (tester) async {
      expect(csGroupDigits(1234567), '1,234,567');
      expect(csGroupDigits(-1200), '-1,200');
      expect(csGroupDigits(999), '999');
    });

    testWidgets('rolls up when the value increases', (tester) async {
      await tester.pumpWidget(_app(odometer()));
      await _setValue(tester, 6);
      await tester.pump(const Duration(milliseconds: 120));
      // Old glyph leaving through the top, new one rising from below.
      expect(find.text('5'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(tester.getTopLeft(find.text('6')).dy, greaterThan(tester.getTopLeft(find.text('5')).dy));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsNothing);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('rolls down when the value decreases', (tester) async {
      await tester.pumpWidget(_app(odometer()));
      await _setValue(tester, 4);
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.getTopLeft(find.text('4')).dy, lessThan(tester.getTopLeft(find.text('5')).dy));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsNothing);
    });

    testWidgets('matches characters from the right', (tester) async {
      await tester.pumpWidget(_app(_Host(
        initial: 128,
        builder: (v) => CsOdometer(value: v, style: const TextStyle(fontSize: 20)),
      )));
      await _setValue(tester, 1128); // "128" -> "1,128"
      await tester.pump(const Duration(milliseconds: 100));
      // The trailing "128" keeps its slots and doesn't roll; only the new
      // leading "1," rolls in. Left-aligned matching would show leftover
      // glyphs ("2" and "8" twice) mid-roll.
      expect(find.text('8'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(2));
      expect(find.text(','), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('1,128'), findsOneWidget);
    });

    testWidgets('reduce motion swaps instantly', (tester) async {
      await tester.pumpWidget(_app(odometer(reduce: true)));
      await _setValue(tester, 6);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('5'), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('OS disableAnimations also swaps instantly', (tester) async {
      await tester.pumpWidget(_app(odometer(), disableAnimations: true));
      await _setValue(tester, 6);
      expect(find.text('5'), findsNothing);
      expect(find.text('6'), findsOneWidget);
    });
  });

  group('CsFadeUp', () {
    FadeTransition fade(WidgetTester tester) => tester.widget<FadeTransition>(
        find.descendant(of: find.byType(CsFadeUp), matching: find.byType(FadeTransition)).first);

    testWidgets('starts hidden and lowered, ends visible and in place', (tester) async {
      await tester.pumpWidget(_app(const CsFadeUp(child: Text('row'))));
      expect(fade(tester).opacity.value, 0);
      final y0 = tester.getTopLeft(find.text('row')).dy;
      await tester.pumpAndSettle();
      expect(fade(tester).opacity.value, 1);
      expect(tester.getTopLeft(find.text('row')).dy, lessThan(y0));
    });

    testWidgets('index staggers the start', (tester) async {
      await tester.pumpWidget(_app(const CsFadeUp(index: 4, child: Text('row'))));
      await tester.pump(const Duration(milliseconds: 150)); // < 4 × 55 ms
      expect(fade(tester).opacity.value, 0);
      await tester.pumpAndSettle();
      expect(fade(tester).opacity.value, 1);
    });

    testWidgets('does not replay on rebuild', (tester) async {
      await tester.pumpWidget(_app(const CsFadeUp(child: Text('row'))));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_app(const CsFadeUp(index: 3, child: Text('row'))));
      expect(fade(tester).opacity.value, 1);
    });

    testWidgets('reduce motion: short fade, no slide, no stagger', (tester) async {
      await tester.pumpWidget(_app(const CsFadeUp(index: 6, reduceMotion: true, child: Text('row'))));
      final y0 = tester.getTopLeft(find.text('row')).dy;
      await tester.pump(CsMotion.instant);
      expect(fade(tester).opacity.value, 1);
      expect(tester.getTopLeft(find.text('row')).dy, y0);
      expect(find.descendant(of: find.byType(CsFadeUp), matching: find.byType(Transform)), findsNothing);
    });
  });

  group('CsPressable', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      HapticService().setEnabled(true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call);
        return null;
      });
    });

    tearDown(() {
      HapticService().setEnabled(true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Widget pressable({CsHaptic haptic = CsHaptic.light, VoidCallback? onTap}) => CsPressable(
          onTap: onTap ?? () {},
          haptic: haptic,
          child: const SizedBox(width: 100, height: 50),
        );

    testWidgets('fires the haptic once per tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(pressable(onTap: () => taps++)));
      await tester.tap(find.byType(CsPressable));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(calls, hasLength(1));
      expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
      await tester.tap(find.byType(CsPressable));
      await tester.pumpAndSettle();
      expect(calls, hasLength(2));
    });

    testWidgets('selection haptic sends a selection click', (tester) async {
      await tester.pumpWidget(_app(pressable(haptic: CsHaptic.selection)));
      await tester.tap(find.byType(CsPressable));
      await tester.pumpAndSettle();
      expect(calls.single.arguments, 'HapticFeedbackType.selectionClick');
    });

    testWidgets('no haptic when the player turned haptics off', (tester) async {
      HapticService().setEnabled(false);
      var taps = 0;
      await tester.pumpWidget(_app(pressable(onTap: () => taps++)));
      await tester.tap(find.byType(CsPressable));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(calls, isEmpty);
    });

    testWidgets('no haptic with CsHaptic.none or when disabled', (tester) async {
      await tester.pumpWidget(_app(Column(children: [
        pressable(haptic: CsHaptic.none),
        const CsPressable(haptic: CsHaptic.light, child: SizedBox(width: 100, height: 50, key: Key('off'))),
      ])));
      await tester.tap(find.byType(CsPressable).first);
      await tester.tap(find.byKey(const Key('off')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
    });

    testWidgets('scales down while held and springs back', (tester) async {
      await tester.pumpWidget(_app(pressable()));
      ScaleTransition scale() => tester.widget<ScaleTransition>(
          find.descendant(of: find.byType(CsPressable), matching: find.byType(ScaleTransition)));
      final g = await tester.startGesture(tester.getCenter(find.byType(CsPressable)));
      await tester.pump(kPressTimeout); // the tap-down fires after this delay
      await tester.pump(CsMotion.quick);
      await tester.pump(const Duration(milliseconds: 16));
      expect(scale().scale.value, closeTo(0.97, 0.001));
      await g.up();
      await tester.pumpAndSettle();
      expect(scale().scale.value, closeTo(1, 0.0001));
    });

    testWidgets('CsButton.primary taps with a light haptic by default', (tester) async {
      await tester.pumpWidget(_app(CsButton.primary(label: 'Launch', onPressed: () {})));
      await tester.tap(find.byType(CsButton));
      await tester.pumpAndSettle();
      expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
    });
  });

  group('CsPop', () {
    ScaleTransition scale(WidgetTester tester) => tester.widget<ScaleTransition>(
        find.descendant(of: find.byType(CsPop), matching: find.byType(ScaleTransition)));

    testWidgets('pops when the trigger changes and settles at 1', (tester) async {
      await tester.pumpWidget(_app(_Host(initial: 0, builder: (v) => CsPop(trigger: v, child: Text('$v')))));
      expect(scale(tester).scale.value, 1);
      await _setValue(tester, 1);
      await tester.pump(const Duration(milliseconds: 150));
      expect(scale(tester).scale.value, greaterThan(1.05));
      await tester.pumpAndSettle();
      expect(scale(tester).scale.value, closeTo(1, 0.0001));
    });

    testWidgets('reduce motion: no pop', (tester) async {
      await tester.pumpWidget(_app(_Host(
        initial: 0,
        builder: (v) => CsPop(trigger: v, reduceMotion: true, child: Text('$v')),
      )));
      await _setValue(tester, 1);
      await tester.pump(const Duration(milliseconds: 150));
      expect(scale(tester).scale.value, 1);
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('CsBeatSheet', () {
    testWidgets('beats map to intervals, cues fire once, skipToEnd jumps', (tester) async {
      final fired = <String>[];
      late CsBeatSheet sheet;
      await tester.pumpWidget(_app(_SheetHost(onCreate: (vsync) {
        sheet = CsBeatSheet(vsync: vsync, beats: {
          'a': CsBeat(at: 0, duration: 200, onStart: () => fired.add('a')),
          'b': CsBeat(at: 300, duration: 200, curve: CsMotion.springPop, onStart: () => fired.add('b')),
        });
        return sheet;
      })));
      expect(sheet.totalMs, 500);
      expect(tester.state<_SheetHostState>(find.byType(_SheetHost)).reducedAtInit, isFalse);
      sheet.play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(sheet['a'].value, 1);
      expect(sheet['b'].value, 0);
      expect(fired, ['a']);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fired, ['a', 'b']);
      await tester.pumpAndSettle();
      expect(sheet.isComplete, isTrue);
      expect(fired, ['a', 'b']);

      fired.clear();
      sheet.play();
      await tester.pump();
      sheet.skipToEnd();
      await tester.pump();
      expect(sheet['b'].value, 1);
      expect(sheet.opacity('b').value, 1);
      expect(fired, ['a']); // 'b' was skipped, so its cue never fires.
    });

    testWidgets('reduce motion lands on the final frame', (tester) async {
      late CsBeatSheet sheet;
      await tester.pumpWidget(_app(_SheetHost(onCreate: (vsync) {
        return sheet = CsBeatSheet(vsync: vsync, beats: {'a': const CsBeat(at: 100, duration: 300)});
      })));
      sheet.play(reduceMotion: true);
      expect(sheet['a'].value, 1);
      expect(sheet.isComplete, isTrue);
    });
  });
}

class _SheetHost extends StatefulWidget {
  const _SheetHost({required this.onCreate});
  final CsBeatSheet Function(TickerProvider vsync) onCreate;
  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> with SingleTickerProviderStateMixin {
  late final CsBeatSheet _sheet = widget.onCreate(this);
  bool? reducedAtInit;

  @override
  void initState() {
    super.initState();
    _sheet; // create now
    // Safe to resolve from initState with listen: false.
    reducedAtInit = CsReduceMotion.of(context, listen: false);
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
