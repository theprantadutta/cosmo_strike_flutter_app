import 'package:material_ui/material_ui.dart';

import '../../theme/cosmo_theme.dart';
import 'cs_motion.dart';

/// Formats [value] with a thousands [separator]: `12450` → `12,450`.
String csGroupDigits(int value, {String separator = ','}) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(separator);
    b.write(digits[i]);
  }
  return negative ? '-$b' : b.toString();
}

/// An animated number: each character that changes rolls through its own
/// clipped slot. Characters are matched from the RIGHT, so `999 → 1,000`
/// rolls the last three digits and the new leading slots roll in. When the
/// value goes up the new glyph rises from below; when it goes down it drops
/// from above.
///
/// Defaults to thousands separators; pass [format] for anything else (a
/// prefix like `+`, a unit suffix, no grouping). Style it with the numeric
/// style, which has tabular figures so slots never jitter:
///
/// ```dart
/// CsOdometer(value: coins, style: context.type.number(24, color: CsColors.gold))
/// ```
///
/// Cost: one RepaintBoundary around the row; each rolling slot is a
/// hard-edge ClipRect plus two translated glyphs (no opacity, no saveLayer),
/// and slots that didn't change don't animate at all. Reduce motion: the
/// new value appears instantly.
class CsOdometer extends StatefulWidget {
  const CsOdometer({
    super.key,
    required this.value,
    this.style,
    this.format,
    this.duration = CsMotion.roll,
    this.curve = CsMotion.easeOutSoft,
    this.reduceMotion,
    this.semanticsLabel,
    this.from,
  });

  final int value;

  /// When set (and different from [value]) the FIRST build rolls from this
  /// value to [value] instead of showing [value] statically. Lets a plain
  /// `Text` hand over to an odometer the moment its number changes (see
  /// [CsRollingText]). Ignored after the first build.
  final int? from;

  /// Defaults to `context.type.statValue`.
  final TextStyle? style;

  /// Turns [value] into the displayed string. Default: [csGroupDigits].
  final String Function(int value)? format;
  final Duration duration;
  final Curve curve;

  /// Overrides [CsReduceMotion.of] (tests).
  final bool? reduceMotion;

  /// Screen-reader label; defaults to the formatted text.
  final String? semanticsLabel;

  @override
  State<CsOdometer> createState() => _CsOdometerState();
}

class _CsOdometerState extends State<CsOdometer> {
  /// Direction of the latest change: +1 up (value grew), -1 down.
  int _direction = 1;

  /// False during the very first build so the initial value doesn't roll in.
  bool _built = false;

  @override
  void initState() {
    super.initState();
    final from = widget.from;
    if (from != null && from != widget.value) _direction = widget.value > from ? 1 : -1;
  }

  @override
  void didUpdateWidget(CsOdometer old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) _direction = widget.value > old.value ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final text = (widget.format ?? csGroupDigits)(widget.value);
    final style = widget.style ?? context.type.statValue;
    final reduce = CsReduceMotion.of(context, override: widget.reduceMotion);
    final rollIn = _built;
    final from = widget.from;
    final fromText = !_built && from != null && from != widget.value ? (widget.format ?? csGroupDigits)(from) : null;
    _built = true;

    final Widget body;
    if (reduce) {
      body = Text(text, style: style, maxLines: 1, softWrap: false);
    } else {
      final n = text.length;
      body = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < n; i++)
            _OdometerSlot(
              // Keyed by distance from the right so a length change keeps
              // every digit on its own track.
              key: ValueKey<int>(n - 1 - i),
              char: text[i],
              style: style,
              direction: _direction,
              duration: widget.duration,
              curve: widget.curve,
              rollIn: rollIn,
              // The glyph at the same distance from the right in the old
              // text ('' when the number grew a digit).
              initialFrom: fromText == null
                  ? null
                  : (n - 1 - i < fromText.length ? fromText[fromText.length - n + i] : ''),
            ),
        ],
      );
    }
    return Semantics(
      label: widget.semanticsLabel ?? text,
      excludeSemantics: true,
      child: RepaintBoundary(child: body),
    );
  }
}

class _OdometerSlot extends StatefulWidget {
  const _OdometerSlot({
    super.key,
    required this.char,
    required this.style,
    required this.direction,
    required this.duration,
    required this.curve,
    required this.rollIn,
    this.initialFrom,
  });

  /// The glyph this slot showed before it was built ([CsOdometer.from]); the
  /// slot rolls from it to [char] on mount when they differ.
  final String? initialFrom;

  final String char;
  final TextStyle style;
  final int direction;
  final Duration duration;
  final Curve curve;

  /// A slot created after the first build (the number grew a digit) rolls in
  /// from empty instead of just appearing.
  final bool rollIn;

  @override
  State<_OdometerSlot> createState() => _OdometerSlotState();
}

class _OdometerSlotState extends State<_OdometerSlot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration, value: 1);
  late final CurvedAnimation _t = CurvedAnimation(parent: _c, curve: widget.curve);

  /// The glyph leaving the slot ('' when rolling in from empty).
  String? _previous;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialFrom;
    if (initial != null) {
      if (initial != widget.char) {
        _previous = initial;
        _c.forward(from: 0);
      }
    } else if (widget.rollIn) {
      _previous = '';
      _c.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(_OdometerSlot old) {
    super.didUpdateWidget(old);
    if (old.curve != widget.curve) _t.curve = widget.curve;
    if (old.char != widget.char) {
      _previous = old.char;
      _c
        ..duration = widget.duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  Text _glyph(String c) => Text(c, style: widget.style, maxLines: 1, softWrap: false);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: _glyph(widget.char),
      builder: (context, current) {
        final previous = _previous;
        if (previous == null || _c.isCompleted) return current!;
        final t = _t.value;
        // Up: the new glyph rises from one slot below (+1 → 0) while the old
        // one leaves through the top (0 → -1). Down mirrors it.
        final s = widget.direction.toDouble();
        return ClipRect(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (previous.isNotEmpty)
                FractionalTranslation(translation: Offset(0, -s * t), child: _glyph(previous)),
              FractionalTranslation(translation: Offset(0, s * (1 - t)), child: current),
            ],
          ),
        );
      },
    );
  }
}

/// A `Text` that turns into a [CsOdometer] the moment its number changes.
///
/// [text] is any display string. When it is `prefix + integer + suffix`
/// (`"1,250"`, `"+30"`, `"12 KILLS"`, `"x3"`) and a rebuild changes only the
/// integer, the number rolls from the old value to the new one. The first
/// build, and any change that isn't a pure number change, renders a plain
/// `Text` with exactly the same string, so opening a screen never rolls and
/// static labels cost no extra layers. Thousands separators are kept when the
/// new text uses them.
///
/// ```dart
/// CsRollingText('$coins', style: t.mono(12, color: CsColors.gold))
/// ```
///
/// Reduce motion: the new value appears instantly (via [CsOdometer]).
class CsRollingText extends StatefulWidget {
  const CsRollingText(
    this.text, {
    super.key,
    required this.style,
    this.enabled = true,
    this.duration = CsMotion.roll,
    this.reduceMotion,
  });

  final String text;
  final TextStyle style;

  /// False always renders a plain `Text`.
  final bool enabled;
  final Duration duration;

  /// Overrides [CsReduceMotion.of] (tests).
  final bool? reduceMotion;

  @override
  State<CsRollingText> createState() => _CsRollingTextState();
}

/// `prefix · integer (optionally grouped) · suffix`, split once.
class _NumberParts {
  const _NumberParts(this.prefix, this.value, this.suffix, this.grouped);
  final String prefix;
  final int value;
  final String suffix;
  final bool grouped;

  static final _re = RegExp(r'^(\D*?)(-?\d{1,3}(?:,\d{3})+|-?\d+)(\D*)$');

  static _NumberParts? parse(String text) {
    final m = _re.firstMatch(text);
    if (m == null) return null;
    final digits = m.group(2)!;
    final plain = digits.replaceAll(',', '');
    // A leading-zero number ("007") would not round-trip through the
    // formatter; keep it static.
    final abs = plain.startsWith('-') ? plain.substring(1) : plain;
    if (abs.length > 1 && abs.startsWith('0')) return null;
    final value = int.tryParse(plain);
    if (value == null) return null;
    return _NumberParts(m.group(1)!, value, m.group(3)!, digits.contains(','));
  }

  String format(int v) => '$prefix${grouped ? csGroupDigits(v) : '$v'}$suffix';
}

class _CsRollingTextState extends State<CsRollingText> {
  /// Set once the number has changed; from then on an odometer renders it.
  int? _rollFrom;
  _NumberParts? _parts;

  /// Bumped whenever the odometer must start fresh, so it never animates a
  /// format switch.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _parts = _NumberParts.parse(widget.text);
  }

  @override
  void didUpdateWidget(CsRollingText old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) return;
    final prev = _parts;
    final next = _NumberParts.parse(widget.text);
    _parts = next;
    if (!widget.enabled || prev == null || next == null || prev.prefix != next.prefix || prev.suffix != next.suffix) {
      _rollFrom = null;
      return;
    }
    if (_rollFrom == null) {
      // First change: hand over from the plain Text to an odometer that
      // starts on the old value.
      _rollFrom = prev.value;
      _generation++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = _parts;
    final from = _rollFrom;
    if (!widget.enabled || parts == null || from == null) {
      return Text(widget.text, style: widget.style, maxLines: 1, softWrap: false);
    }
    return CsOdometer(
      key: ValueKey<int>(_generation),
      value: parts.value,
      from: from,
      format: parts.format,
      style: widget.style,
      duration: widget.duration,
      reduceMotion: widget.reduceMotion,
      semanticsLabel: widget.text,
    );
  }
}
