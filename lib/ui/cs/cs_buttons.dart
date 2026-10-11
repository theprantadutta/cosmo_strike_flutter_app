import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/cosmo_theme.dart';
import 'cs_prism.dart';

enum CsButtonVariant {
  /// Solid white pill, black text. ONE per screen — the main action.
  primary,

  /// 1px outlined pill.
  secondary,

  /// Text only, 55% ink.
  text,

  /// Gold pill for premium / upsell.
  premium,

  /// Prism-ringed pill (e.g. CLAIM ALL chip on game over).
  prism,
}

enum CsButtonSize {
  /// 48px tall — screen actions.
  regular,

  /// ~34px — inline row actions (CLAIM, UNLOCK).
  small,
}

/// Scale-on-press wrapper (0.97) used by every tappable in the system.
class CsPressable extends StatefulWidget {
  const CsPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? semanticLabel;

  @override
  State<CsPressable> createState() => _CsPressableState();
}

class _CsPressableState extends State<CsPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: CsMotion.fast,
          curve: CsMotion.standard,
          child: widget.child,
        ),
      ),
    );
  }
}

class CsButton extends StatelessWidget {
  const CsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = CsButtonVariant.primary,
    this.size = CsButtonSize.regular,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.loading = false,
    this.trailing,
  });

  const CsButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = CsButtonSize.regular,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.loading = false,
    this.trailing,
  }) : variant = CsButtonVariant.primary;

  const CsButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.size = CsButtonSize.regular,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.loading = false,
    this.trailing,
  }) : variant = CsButtonVariant.secondary;

  const CsButton.text({
    super.key,
    required this.label,
    this.onPressed,
    this.size = CsButtonSize.regular,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.loading = false,
    this.trailing,
  }) : variant = CsButtonVariant.text;

  const CsButton.premium({
    super.key,
    required this.label,
    this.onPressed,
    this.size = CsButtonSize.regular,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.loading = false,
    this.trailing,
  }) : variant = CsButtonVariant.premium;

  const CsButton.prism({
    super.key,
    required this.label,
    this.onPressed,
    this.size = CsButtonSize.small,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.loading = false,
    this.trailing,
  }) : variant = CsButtonVariant.prism;

  final String label;
  final VoidCallback? onPressed;
  final CsButtonVariant variant;
  final CsButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool expand;
  final bool loading;

  /// Extra widget after the label (e.g. a mono price).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final small = size == CsButtonSize.small;
    final enabled = onPressed != null && !loading;

    final Color fg = switch (variant) {
      CsButtonVariant.primary || CsButtonVariant.premium => CsColors.onLight,
      CsButtonVariant.text => CsColors.ink55,
      _ => CsColors.ink,
    };
    final textStyle = (small ? t.display(11, weight: FontWeight.w700, em: 0.1, height: 1) : t.button)
        .copyWith(color: fg);
    final iconSize = cs(small ? 16 : 20);
    // Regular buttons keep a ≥48dp target on every device; small ones ≥36.
    final minH = small ? cs(34).clamp(34.0, 44.0) : cs(48).clamp(44.0, 64.0);
    final padH = cs(small ? 16 : (variant == CsButtonVariant.text ? 16 : 26));

    Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          Padding(
            padding: EdgeInsets.only(right: cs(10)),
            child: SizedBox.square(
              dimension: iconSize * 0.8,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            ),
          )
        else if (icon != null)
          Padding(
            padding: EdgeInsets.only(right: cs(10)),
            child: Icon(icon, size: iconSize, color: fg),
          ),
        Flexible(
          child: Text(
            label.toUpperCase(),
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[SizedBox(width: cs(8)), trailing!],
        if (trailingIcon != null)
          Padding(
            padding: EdgeInsets.only(left: cs(10)),
            child: Icon(trailingIcon, size: iconSize, color: fg),
          ),
      ],
    );

    content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minH),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padH),
        child: content,
      ),
    );

    final Widget body = switch (variant) {
      CsButtonVariant.primary => DecoratedBox(
          decoration: const ShapeDecoration(color: CsColors.ink, shape: StadiumBorder()),
          child: content,
        ),
      CsButtonVariant.premium => DecoratedBox(
          decoration: const ShapeDecoration(color: CsColors.gold, shape: StadiumBorder()),
          child: content,
        ),
      CsButtonVariant.secondary => DecoratedBox(
          decoration: const ShapeDecoration(
            shape: StadiumBorder(side: BorderSide(color: CsColors.lineStrong)),
          ),
          child: content,
        ),
      CsButtonVariant.prism => CsPrismRing(
          radius: CsRadius.pill,
          fill: CsColors.bg,
          width: 1.2,
          child: content,
        ),
      CsButtonVariant.text => content,
    };

    return Opacity(
      opacity: enabled || loading ? 1 : 0.4,
      child: CsPressable(
        onTap: enabled ? onPressed : null,
        semanticLabel: label,
        child: body,
      ),
    );
  }
}

/// 42px round outlined icon button (pause, refresh, close…). The hit target
/// is always ≥ 44dp even when the visual is smaller.
class CsIconButton extends StatelessWidget {
  const CsIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 42,
    this.bordered = true,
    this.color = CsColors.ink,
    this.tooltip,
    this.badge,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final bool bordered;
  final Color color;
  final String? tooltip;

  /// Small dot/count shown top-right (e.g. unread friend requests).
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final d = cs(size);
    final hit = d < 44 ? 44.0 : d;
    Widget w = SizedBox.square(
      dimension: hit,
      child: Center(
        child: Container(
          width: d,
          height: d,
          decoration: bordered
              ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: CsColors.lineStrong))
              : null,
          alignment: Alignment.center,
          child: Icon(icon, size: d * 0.52, color: color),
        ),
      ),
    );
    if (badge != null) {
      w = Stack(clipBehavior: Clip.none, children: [w, Positioned(top: 4, right: 4, child: badge!)]);
    }
    w = Opacity(opacity: onPressed == null ? 0.4 : 1, child: CsPressable(onTap: onPressed, semanticLabel: tooltip, child: w));
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// Back arrow used in [CsTopBar]; bare glyph with a 44dp target.
class CsBackButton extends StatelessWidget {
  const CsBackButton({super.key, this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return CsPressable(
      semanticLabel: 'Back',
      onTap: onPressed ?? () => Navigator.of(context).maybePop(),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(Symbols.arrow_back_rounded, size: cs(24).clamp(22.0, 30.0), color: CsColors.ink),
        ),
      ),
    );
  }
}
