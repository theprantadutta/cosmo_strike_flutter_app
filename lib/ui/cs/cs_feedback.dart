import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/cosmo_theme.dart';
import 'cs_buttons.dart';
import 'cs_prism.dart';

/// Centered landscape dialog card: #141419, 22 radius, subtle border, over the
/// 82% near-black scrim. Max width scales with the device; content scrolls
/// only if it genuinely can't fit (short phones + big text).
class CsDialog extends StatelessWidget {
  const CsDialog({
    super.key,
    this.eyebrow,
    this.title,
    this.titleWidget,
    this.message,
    this.content,
    this.actions = const [],
    this.maxWidth = 520,
    this.icon,
    this.iconColor = CsColors.ink,
    this.dismissible = true,
  });

  /// Mono label above the title ("CONFIRM", "LEVEL 03").
  final String? eyebrow;
  final String? title;
  final Widget? titleWidget;
  final String? message;
  final Widget? content;

  /// Usually CsButtons; laid out in a row, primary last (right).
  final List<Widget> actions;
  final double maxWidth;
  final IconData? icon;
  final Color iconColor;
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height - mq.padding.vertical - cs(40);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: cs(32), vertical: cs(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cs(maxWidth), maxHeight: maxH),
          child: Material(
            color: CsColors.raised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CsRadius.card),
              side: const BorderSide(color: CsColors.lineSubtle),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: EdgeInsets.all(cs(24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: cs(28), color: iconColor),
                            SizedBox(height: cs(12)),
                          ],
                          if (eyebrow != null) ...[
                            Text(eyebrow!.toUpperCase(), style: t.mono(11, em: .16)),
                            SizedBox(height: cs(6)),
                          ],
                          if (titleWidget != null)
                            titleWidget!
                          else if (title != null)
                            Text(title!, style: t.display(26, em: -0.03, height: 1.05)),
                          if (message != null) ...[
                            SizedBox(height: cs(10)),
                            Text(message!, style: t.body.copyWith(fontSize: cs(14))),
                          ],
                          if (content != null) ...[SizedBox(height: cs(16)), content!],
                        ],
                      ),
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    SizedBox(height: cs(22)),
                    // Align: a bare Wrap would shrink to its content inside
                    // the start-aligned column and ignore WrapAlignment.end.
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: cs(10),
                        runSpacing: cs(10),
                        children: actions,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows [dialog] (usually a [CsDialog]) with the Prism Noir scrim + a 200ms
/// fade/scale entrance.
Future<T?> showCsDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: CsColors.scrim,
    useRootNavigator: useRootNavigator,
    transitionDuration: CsMotion.base,
    pageBuilder: (ctx, _, _) => SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (ctx, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: CsMotion.standard);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: .97, end: 1.0).animate(c), child: child),
      );
    },
  );
}

/// Confirm helper: returns true when the primary action is chosen.
Future<bool> showCsConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String? eyebrow,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final r = await showCsDialog<bool>(
    context,
    builder: (ctx) => CsDialog(
      eyebrow: eyebrow,
      title: title,
      message: message,
      actions: [
        CsButton.text(label: cancelLabel, onPressed: () => Navigator.of(ctx).pop(false)),
        CsButton.primary(label: confirmLabel, onPressed: () => Navigator.of(ctx).pop(true)),
      ],
    ),
  );
  return r ?? false;
}

enum CsToastKind { info, success, reward, error }

/// Lightweight floating toast (top-center pill). Replaces SnackBars.
void showCsToast(
  BuildContext context,
  String message, {
  CsToastKind kind = CsToastKind.info,
  IconData? icon,
  Duration duration = const Duration(milliseconds: 2600),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CsToast(
      message: message,
      kind: kind,
      icon: icon,
      duration: duration,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _CsToast extends StatefulWidget {
  const _CsToast({required this.message, required this.kind, this.icon, required this.duration, required this.onDone});
  final String message;
  final CsToastKind kind;
  final IconData? icon;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_CsToast> createState() => _CsToastState();
}

class _CsToastState extends State<_CsToast> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: CsMotion.slow)..forward();
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(widget.duration, () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final (Color color, IconData icon) = switch (widget.kind) {
      CsToastKind.info => (CsColors.cyan, Symbols.info_rounded),
      CsToastKind.success => (CsColors.mint, Symbols.check_circle_rounded),
      CsToastKind.reward => (CsColors.gold, Symbols.paid_rounded),
      CsToastKind.error => (CsColors.pink, Symbols.error_rounded),
    };
    final curve = CurvedAnimation(parent: _c, curve: CsMotion.standard);
    return Positioned(
      top: MediaQuery.paddingOf(context).top + cs(16),
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -.4), end: Offset.zero).animate(curve),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: BoxConstraints(maxWidth: cs(560)),
                  padding: EdgeInsets.symmetric(horizontal: cs(18), vertical: cs(11)),
                  decoration: ShapeDecoration(
                    color: CsColors.raised2,
                    shape: const StadiumBorder(side: BorderSide(color: CsColors.lineSubtle)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(widget.icon ?? icon, size: cs(18), color: color),
                    SizedBox(width: cs(10)),
                    Flexible(
                      child: Text(
                        widget.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: cs.type.mono(12, color: CsColors.ink, em: 0.04),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Indeterminate 2px prism line (loading). A sweeping highlight on a track.
class CsLoadingLine extends StatefulWidget {
  const CsLoadingLine({super.key, this.width = 180});
  final double width;

  @override
  State<CsLoadingLine> createState() => _CsLoadingLineState();
}

class _CsLoadingLineState extends State<CsLoadingLine> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = context.cs(widget.width);
    return SizedBox(
      width: w,
      height: 2,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) {
            final x = Curves.easeInOut.transform(_c.value);
            return Stack(children: [
              const Positioned.fill(child: ColoredBox(color: CsColors.track)),
              Positioned(
                left: -w * .4 + x * w * 1.4,
                width: w * .4,
                top: 0,
                bottom: 0,
                child: const DecoratedBox(decoration: BoxDecoration(gradient: CsGradients.prism)),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// Centered loading state for lists/screens.
class CsLoadingState extends StatelessWidget {
  const CsLoadingState({super.key, this.label = 'Loading'});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CsLoadingLine(),
        SizedBox(height: cs(14)),
        Text(label.toUpperCase(), style: cs.type.mono(10, em: .2, color: CsColors.ink45)),
      ]),
    );
  }
}

/// Empty / error / offline state: icon, headline, body, optional action.
class CsEmptyState extends StatelessWidget {
  const CsEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Symbols.radar_rounded,
    this.action,
    this.iconColor = CsColors.ink45,
    this.compact = false,
  });

  const CsEmptyState.error({
    super.key,
    this.title = 'Something went wrong',
    this.message,
    this.action,
    this.compact = false,
  })  : icon = Symbols.error_rounded,
        iconColor = CsColors.pink;

  const CsEmptyState.offline({
    super.key,
    this.title = 'You\'re offline',
    this.message = 'Connect to the internet to see live data. Your progress is saved on this device.',
    this.action,
    this.compact = false,
  })  : icon = Symbols.cloud_off_rounded,
        iconColor = CsColors.ink45;

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;
  final Color iconColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cs(380)),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: cs(compact ? 26 : 34), color: iconColor),
            SizedBox(height: cs(12)),
            Text(title, textAlign: TextAlign.center, style: t.display(compact ? 18 : 22, em: -0.02)),
            if (message != null) ...[
              SizedBox(height: cs(8)),
              Text(message!, textAlign: TextAlign.center, style: t.body),
            ],
            if (action != null) ...[SizedBox(height: cs(18)), action!],
          ]),
        ),
      ),
    );
  }
}

/// Count-up number for results screens (600ms).
class CsCountUp extends StatelessWidget {
  const CsCountUp({super.key, required this.value, required this.style, this.format, this.duration = CsMotion.countUp});
  final int value;
  final TextStyle style;
  final String Function(int)? format;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: CsMotion.standard,
      builder: (_, v, _) {
        final n = v.round();
        return Text(format?.call(n) ?? '$n', style: style, maxLines: 1);
      },
    );
  }
}

/// Re-exported convenience: a progress line that turns mint when complete.
class CsGoalLine extends StatelessWidget {
  const CsGoalLine({super.key, required this.value});
  final double value;

  @override
  Widget build(BuildContext context) =>
      CsProgressLine(value: value, gradient: value >= 1 ? CsGradients.complete : CsGradients.progress);
}
