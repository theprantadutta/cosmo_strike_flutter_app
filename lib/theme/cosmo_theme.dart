// Cosmo Strike — Prism Noir design tokens + ThemeData.
//
// Every value is in logical px at the 960x432 reference frame (a ~2412x1080
// landscape phone). Screens never read these raw sizes directly for layout —
// they go through `context.cs` (CsLayout), which scales them to the device so
// small phones, iPhones, tablets and iPads all get the same composition.
import 'dart:math' as math;

import 'package:flutter/material.dart';

class CsColors {
  CsColors._();

  static const bg = Color(0xFF0A0A0D);
  static const bgGame = Color(0xFF08080B);
  static const raised = Color(0xFF141419);
  static const raised2 = Color(0xFF1E1E26);
  static const scrim = Color(0xD10A0A0D);

  static const ink = Color(0xFFF4F3F7);
  static const ink70 = Color(0xB3F4F3F7);
  static const ink60 = Color(0x99F4F3F7);
  static const ink55 = Color(0x8CF4F3F7);
  static const ink45 = Color(0x73F4F3F7);
  static const ink30 = Color(0x4DF4F3F7);
  static const ink25 = Color(0x40F4F3F7);
  static const onLight = Color(0xFF0A0A0D);

  static const hairline = Color(0x1AFFFFFF);
  static const track = Color(0x1FFFFFFF);
  static const lineSubtle = Color(0x29FFFFFF);
  static const lineStrong = Color(0x40FFFFFF);
  static const fill03 = Color(0x08FFFFFF);
  static const fill04 = Color(0x0AFFFFFF);
  static const fill07 = Color(0x12FFFFFF);

  static const cyan = Color(0xFF7CF5FF);
  static const violet = Color(0xFFA78BFA);
  static const pink = Color(0xFFFF8AD8);
  static const gold = Color(0xFFFFD58A);
  static const mint = Color(0xFF9BFFC8);

  // Semantic aliases — use these names in screens so meaning stays consistent.
  static const success = mint;
  static const reward = gold;
  static const danger = pink;
  static const info = cyan;
  static const xp = violet;
  static const rank2 = Color(0xFFD9D8E3);
  static const rank3 = Color(0xFFE9A07A);
}

class CsGradients {
  CsGradients._();

  static const prism = LinearGradient(
    colors: [CsColors.cyan, CsColors.violet, CsColors.pink, CsColors.gold],
    stops: [0, .35, .65, 1],
  );
  static const prismText = LinearGradient(
    colors: [CsColors.cyan, CsColors.pink, CsColors.gold],
  );
  static const progress = LinearGradient(colors: [CsColors.cyan, CsColors.pink]);
  static const complete = LinearGradient(colors: [CsColors.mint, CsColors.cyan]);
  static const gold = LinearGradient(colors: [CsColors.gold, Color(0xFFFFB86B)]);

  /// Conic "prism" sweep used for rings (CSS `conic-gradient(from 200deg …)`).
  static SweepGradient sweep({double rotation = 0}) => SweepGradient(
        colors: const [
          CsColors.cyan,
          CsColors.violet,
          CsColors.pink,
          CsColors.gold,
          CsColors.mint,
          CsColors.cyan,
        ],
        transform: GradientRotation(1.92 + rotation),
      );
}

class CsSpace {
  CsSpace._();
  static const xxs = 4.0,
      xs = 6.0,
      sm = 8.0,
      md = 12.0,
      lg = 16.0,
      xl = 20.0,
      xxl = 24.0,
      padX = 32.0,
      padTop = 24.0,
      padBottom = 22.0,
      hud = 28.0;
}

class CsRadius {
  CsRadius._();
  static const tile = 14.0, card = 22.0, pill = 999.0, chip = 999.0;
}

class CsMotion {
  CsMotion._();
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const screen = Duration(milliseconds: 280);
  static const countUp = Duration(milliseconds: 600);
  static const ringTurn = Duration(seconds: 6);
  static const standard = Cubic(0.2, 0, 0, 1);
  static const emphasis = Cubic(0.3, 0, 0, 1.2);
}

class CsFonts {
  CsFonts._();
  static const display = 'Syne';
  static const mono = 'IBMPlexMono';
}

/// Responsive metrics for the current screen.
///
/// `s` is the scale from the 960x432 design frame to this device, taken from
/// whichever axis is tighter so a composition never overflows:
///   small phone 640x360 → ~0.72 · Galaxy/iPhone 850-930 wide → ~0.9-0.97
///   iPad 11" 1194x834 → 1.24 · large tablets → capped at 1.4.
/// Tablets keep the phone composition but get more breathing room vertically,
/// so layouts should distribute height with Spacer/Expanded rather than fixed
/// offsets.
class CsLayout {
  CsLayout._(this.size, this.s);

  factory CsLayout.of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final raw = math.min(size.width / 960, size.height / 432);
    return CsLayout._(size, raw.clamp(0.72, 1.4).toDouble());
  }

  final Size size;
  final double s;

  /// Scale a design-frame value to this device.
  double call(double v) => v * s;

  /// Tablet / iPad class device (much taller than a phone in landscape).
  bool get isTablet => size.shortestSide >= 600;

  /// Short phones (iPhone SE / 640x360 class) — trim secondary content.
  bool get isCompact => size.height < 380;

  /// Width-to-height ratio; phones are ~2.0-2.2, tablets ~1.33-1.6.
  double get aspect => size.width / size.height;

  EdgeInsets get screenPadding => EdgeInsets.fromLTRB(
        CsSpace.padX * s,
        CsSpace.padTop * s,
        CsSpace.padX * s,
        CsSpace.padBottom * s,
      );

  double get gap => CsSpace.lg * s;
  double get groupGap => CsSpace.xxl * s;

  /// Width of the left summary column on the standard two-region layout.
  double get sideColumn => (isTablet ? 320 : 290) * s;

  CsType get type => CsType(s);
}

/// The type scale, pre-scaled for the current device. Get it with
/// `context.type` (or `context.cs.type`).
class CsType {
  const CsType(this.s);
  final double s;

  TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w800,
    double em = -0.03,
    double? height,
    Color color = CsColors.ink,
  }) =>
      TextStyle(
        fontFamily: CsFonts.display,
        fontSize: size * s,
        fontWeight: weight,
        letterSpacing: size * s * em,
        height: height,
        color: color,
      );

  TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w500,
    double em = 0.14,
    Color color = CsColors.ink60,
    double? height,
  }) =>
      TextStyle(
        fontFamily: CsFonts.mono,
        fontSize: size * s,
        fontWeight: weight,
        letterSpacing: size * s * em,
        color: color,
        height: height,
      );

  TextStyle get hero => display(76, em: -0.04, height: 0.9);
  TextStyle get scoreGiant => display(84, em: -0.05, height: 0.9);
  TextStyle get title => display(40, em: -0.04, height: 1);
  TextStyle get section => display(36, em: -0.03, height: 1.05);
  TextStyle get hudScore => display(44, em: -0.03, height: 1);
  TextStyle get statValue => display(24, em: 0, height: 1.1);
  TextStyle get rowTitle => display(16, weight: FontWeight.w700, em: 0, height: 1.2);
  TextStyle get body => display(13, weight: FontWeight.w400, em: 0, height: 1.35, color: CsColors.ink60);
  TextStyle get button => display(14, weight: FontWeight.w700, em: 0.12, height: 1);
  TextStyle get nav => display(12, weight: FontWeight.w600, em: 0.14, height: 1, color: CsColors.ink70);
  TextStyle get label => mono(11, color: CsColors.ink55);
  TextStyle get micro => mono(9, color: CsColors.ink45);
}

extension CsContext on BuildContext {
  CsLayout get cs => CsLayout.of(this);
  CsType get type => CsType(CsLayout.of(this).s);
}

ThemeData buildCosmoTheme() {
  const t = CsType(1);
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: CsFonts.display,
  );
  return base.copyWith(
    scaffoldBackgroundColor: CsColors.bg,
    canvasColor: CsColors.bg,
    colorScheme: const ColorScheme.dark(
      surface: CsColors.bg,
      surfaceContainer: CsColors.raised,
      surfaceContainerHigh: CsColors.raised2,
      primary: CsColors.ink,
      onPrimary: CsColors.onLight,
      secondary: CsColors.cyan,
      onSecondary: CsColors.onLight,
      tertiary: CsColors.pink,
      error: CsColors.pink,
      onError: CsColors.onLight,
      onSurface: CsColors.ink,
      onSurfaceVariant: CsColors.ink60,
      outline: CsColors.lineStrong,
      outlineVariant: CsColors.hairline,
    ),
    dividerColor: CsColors.hairline,
    dividerTheme: const DividerThemeData(color: CsColors.hairline, thickness: 1, space: 1),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    hoverColor: CsColors.fill04,
    iconTheme: const IconThemeData(color: CsColors.ink, size: 22, fill: 1, weight: 500),
    textTheme: base.textTheme
        .apply(fontFamily: CsFonts.display, bodyColor: CsColors.ink, displayColor: CsColors.ink),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: CsColors.cyan,
      selectionColor: Color(0x557CF5FF),
      selectionHandleColor: CsColors.cyan,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: false,
      labelStyle: t.label,
      floatingLabelStyle: t.label.copyWith(color: CsColors.ink),
      hintStyle: t.body.copyWith(color: CsColors.ink30),
      helperStyle: t.micro,
      errorStyle: t.micro.copyWith(color: CsColors.pink),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      border: const UnderlineInputBorder(borderSide: BorderSide(color: CsColors.lineSubtle)),
      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: CsColors.lineSubtle)),
      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: CsColors.ink, width: 1.5)),
      errorBorder: const UnderlineInputBorder(borderSide: BorderSide(color: CsColors.pink)),
      focusedErrorBorder: const UnderlineInputBorder(borderSide: BorderSide(color: CsColors.pink, width: 1.5)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: CsColors.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      barrierColor: CsColors.scrim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CsRadius.card),
        side: const BorderSide(color: CsColors.lineSubtle),
      ),
      titleTextStyle: t.display(22),
      contentTextStyle: t.body,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: CsColors.raised,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: CsColors.scrim,
      elevation: 0,
      showDragHandle: false,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(CsRadius.card)),
        side: BorderSide(color: CsColors.lineSubtle),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: CsColors.raised2,
      elevation: 0,
      contentTextStyle: t.mono(12, color: CsColors.ink, em: 0.06),
      actionTextColor: CsColors.gold,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CsRadius.pill),
        side: const BorderSide(color: CsColors.lineSubtle),
      ),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 2,
      activeTrackColor: CsColors.ink,
      inactiveTrackColor: CsColors.track,
      thumbColor: CsColors.ink,
      overlayColor: Color(0x14FFFFFF),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 0, pressedElevation: 0),
      trackShape: RectangularSliderTrackShape(),
      showValueIndicator: ShowValueIndicator.never,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? CsColors.onLight : CsColors.ink45,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? CsColors.ink : Colors.transparent,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? CsColors.ink : CsColors.lineStrong,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? CsColors.ink : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(CsColors.onLight),
      side: const BorderSide(color: CsColors.lineStrong),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? CsColors.ink : CsColors.lineStrong,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CsColors.ink,
      linearTrackColor: CsColors.track,
      circularTrackColor: Colors.transparent,
      linearMinHeight: 2,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: CsColors.raised2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CsColors.lineSubtle),
      ),
      textStyle: t.mono(11, color: CsColors.ink),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: CsColors.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      textStyle: t.rowTitle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CsRadius.tile),
        side: const BorderSide(color: CsColors.lineSubtle),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: CsColors.ink,
      unselectedLabelColor: CsColors.ink45,
      labelStyle: t.nav,
      unselectedLabelStyle: t.nav,
      indicatorColor: CsColors.ink,
      dividerColor: CsColors.hairline,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CsColors.ink60,
        textStyle: t.button,
        shape: const StadiumBorder(),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: CsColors.ink,
        foregroundColor: CsColors.onLight,
        elevation: 0,
        textStyle: t.button,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CsColors.ink,
        side: const BorderSide(color: CsColors.lineStrong),
        textStyle: t.button,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(backgroundColor: CsColors.bg),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(backgroundColor: CsColors.bg),
      },
    ),
  );
}
