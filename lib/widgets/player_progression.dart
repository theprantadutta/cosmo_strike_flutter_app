import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/progression_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// Compact lifetime-level chip: mono "LV N" + a short 2px XP line.
/// Rebuilds reactively off [ProgressionService].
///
/// [theme] is kept for API compatibility; menus are always Prism Noir.
class PlayerLevelBadge extends StatelessWidget {
  final GameTheme theme;
  final bool isSmallScreen;

  const PlayerLevelBadge({
    super.key,
    required this.theme,
    this.isSmallScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final progression = getIt<ProgressionService>();
    final cs = context.cs;
    return ListenableBuilder(
      listenable: progression,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'LV ${progression.level}',
              maxLines: 1,
              style: cs.type.mono(isSmallScreen ? 10 : 11, color: CsColors.ink),
            ),
            SizedBox(width: cs(8)),
            CsProgressLine(
              value: progression.levelProgress,
              width: cs(isSmallScreen ? 26 : 34),
            ),
          ],
        );
      },
    );
  }
}

/// Home-bar identity chip: avatar inside a circular XP ring + a mono "LV N"
/// tag. Tapping it opens the profile. Rebuilds reactively off
/// [ProgressionService].
///
/// [theme] is kept for API compatibility; menus are always Prism Noir.
class PlayerIdentityBadge extends StatelessWidget {
  final GameTheme theme;
  final bool isSmallScreen;
  final String? photoUrl;
  final VoidCallback onTap;

  const PlayerIdentityBadge({
    super.key,
    required this.theme,
    required this.onTap,
    this.photoUrl,
    this.isSmallScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    final progression = getIt<ProgressionService>();
    final cs = context.cs;
    final ring = cs(isSmallScreen ? 42 : 50);
    final avatar = ring - cs(10);
    return CsPressable(
      onTap: onTap,
      semanticLabel: 'Profile',
      child: ListenableBuilder(
        listenable: progression,
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CsRingProgress(
                value: progression.levelProgress,
                size: ring,
                stroke: 2,
                child: Container(
                  width: avatar,
                  height: avatar,
                  decoration: const BoxDecoration(
                    color: CsColors.raised,
                    shape: BoxShape.circle,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photoUrl != null
                      ? Image.network(
                          photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _fallback(avatar),
                        )
                      : _fallback(avatar),
                ),
              ),
              SizedBox(height: cs(3)),
              Text(
                'LV ${progression.level}',
                maxLines: 1,
                style: cs.type.mono(9, color: CsColors.ink, em: 0.12),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _fallback(double size) => Center(
        child: Icon(Symbols.person_rounded, color: CsColors.ink70, size: size * 0.55),
      );
}

/// Progression block for the profile screen: mono LV, lifetime XP, and a
/// prism XP-to-next line. Hairline-free so it sits inside any column.
/// Rebuilds reactively off [ProgressionService].
///
/// [theme] is kept for API compatibility; menus are always Prism Noir.
class PlayerProgressionCard extends StatelessWidget {
  final GameTheme theme;

  const PlayerProgressionCard({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final progression = getIt<ProgressionService>();
    final cs = context.cs;
    final t = cs.type;
    return ListenableBuilder(
      listenable: progression,
      builder: (context, _) {
        final level = progression.level;
        final into = progression.xpIntoLevel;
        final needed = progression.xpForNextLevel;
        final total = progression.totalXp;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('LV $level', maxLines: 1, style: t.mono(13, color: CsColors.ink, weight: FontWeight.w600)),
                const Spacer(),
                Flexible(
                  flex: 4,
                  child: Text(
                    '$total XP EARNED',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: t.mono(10, color: CsColors.xp),
                  ),
                ),
              ],
            ),
            SizedBox(height: cs(8)),
            CsProgressLine(
              value: needed <= 0 ? 0 : into / needed,
              gradient: CsGradients.prism,
            ),
            SizedBox(height: cs(6)),
            Text(
              '$into / $needed XP TO LV ${level + 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.mono(10, color: CsColors.ink45),
            ),
          ],
        );
      },
    );
  }
}
