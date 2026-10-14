import 'package:flutter/material.dart';

import '../../theme/cosmo_theme.dart';

/// The prism rocket mark. Uses the flat (no glow) art below 48px.
class CsLogoMark extends StatelessWidget {
  const CsLogoMark({super.key, this.size = 26});
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = context.cs(size);
    return Image.asset(
      d < 48
          ? 'assets/images/brand/logo-mark-prism-flat.png'
          : 'assets/images/brand/logo-mark-prism.png',
      width: d,
      height: d,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// "COSMO/STRIKE" wordmark set live in Syne 800 with the prism slash, so it
/// stays crisp at every scale.
class CsWordmark extends StatelessWidget {
  const CsWordmark({super.key, this.size = 14, this.spacing = 0.18});
  final double size;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final st = context.type.display(size, em: spacing, height: 1);
    // Scales down as a unit in narrow slots rather than clipping "STRIKE".
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: 'COSMO', style: st),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (b) => const LinearGradient(
                  colors: [CsColors.cyan, CsColors.pink],
                ).createShader(Offset.zero & b.size),
                child: Text('/', style: st.copyWith(color: Colors.white)),
              ),
            ),
            TextSpan(text: 'STRIKE', style: st),
          ],
        ),
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}

/// Mark + wordmark, as on the main menu top-left.
class CsLogoLockup extends StatelessWidget {
  const CsLogoLockup({super.key, this.markSize = 26, this.textSize = 14});
  final double markSize;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CsLogoMark(size: markSize),
        SizedBox(width: context.cs(10)),
        CsWordmark(size: textSize),
      ],
    );
  }
}
