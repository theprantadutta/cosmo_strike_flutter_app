import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/progression_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// Compact lifetime-level chip for the home header: "Lv N" + a thin XP bar.
/// Rebuilds reactively off [ProgressionService].
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
    return ListenableBuilder(
      listenable: progression,
      builder: (context, _) {
        final level = progression.level;
        final progress = progression.levelProgress;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 8 : 10,
            vertical: isSmallScreen ? 5 : 6,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.accentColor.withValues(alpha: 0.18),
                theme.accentColor.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(isSmallScreen ? 14 : 18),
            border: Border.all(
              color: theme.accentColor.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.military_tech_rounded,
                color: theme.accentColor,
                size: isSmallScreen ? 16 : 18,
              ),
              SizedBox(width: isSmallScreen ? 3 : 5),
              Text(
                'Lv $level',
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: isSmallScreen ? 13 : 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: isSmallScreen ? 5 : 7),
              SizedBox(
                width: isSmallScreen ? 26 : 34,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor:
                        theme.accentColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(theme.accentColor),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Home-bar identity chip: profile avatar (gradient ring) + "Lv N" + a thin
/// XP bar. Tapping it opens the profile. Rebuilds reactively off
/// [ProgressionService]. Replaces the old separate profile button + center
/// level badge.
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
    final avatarSize = isSmallScreen ? 36.0 : 44.0;
    final iconSize = isSmallScreen ? 20.0 : 26.0;
    // The progress gauge ring sits just outside the avatar.
    final ringSize = avatarSize + 8;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ListenableBuilder(
        listenable: progression,
        builder: (context, _) {
          final level = progression.level;
          final progress = progression.levelProgress.clamp(0.0, 1.0);
          return SizedBox(
            width: ringSize,
            // Extra vertical room so the "LV" badge can overhang the bottom.
            height: ringSize + 6,
            child: Stack(
              alignment: Alignment.topCenter,
              clipBehavior: Clip.none,
              children: [
                // Circular XP gauge — fills like a battery ring as the
                // player levels up. Replaces the old loose "Lv N + bar".
                SizedBox(
                  width: ringSize,
                  height: ringSize,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    strokeCap: StrokeCap.round,
                    backgroundColor: theme.accentColor.withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation(theme.foodColor),
                  ),
                ),
                // Avatar nested inside the gauge, with its own gradient ring.
                Positioned(
                  top: 4,
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
                    // Gradient ring frames a real profile photo; with only the
                    // fallback icon we drop the ring for the cleaner look.
                    padding: photoUrl != null
                        ? const EdgeInsets.all(2)
                        : EdgeInsets.zero,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: photoUrl != null
                          ? LinearGradient(
                              colors: [theme.accentColor, theme.foodColor],
                            )
                          : null,
                    ),
                    child: ClipOval(
                      child: photoUrl != null
                          ? Image.network(
                              photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _fallbackAvatar(iconSize),
                            )
                          : _fallbackAvatar(iconSize),
                    ),
                  ),
                ),
                // "LV N" badge pill overhanging the bottom of the gauge —
                // mirrors the rounded, gradient look of the coins pill.
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 5 : 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [theme.accentColor, theme.foodColor],
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.backgroundColor,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        'LV $level',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmallScreen ? 8.5 : 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _fallbackAvatar(double iconSize) => Container(
        color: theme.backgroundColor,
        alignment: Alignment.center,
        child: Icon(Icons.person_rounded, color: Colors.white, size: iconSize),
      );
}

/// Fuller progression card for the profile screen: level, XP-to-next bar,
/// and lifetime total XP. Rebuilds reactively off [ProgressionService].
class PlayerProgressionCard extends StatelessWidget {
  final GameTheme theme;

  const PlayerProgressionCard({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final progression = getIt<ProgressionService>();
    return ListenableBuilder(
      listenable: progression,
      builder: (context, _) {
        final level = progression.level;
        final into = progression.xpIntoLevel;
        final needed = progression.xpForNextLevel;
        final total = progression.totalXp;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.accentColor.withValues(alpha: 0.14),
                theme.accentColor.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.accentColor.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [theme.accentColor, theme.foodColor],
                      ),
                    ),
                    child: const Icon(
                      Icons.military_tech_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Level $level',
                        style: TextStyle(
                          color: theme.accentColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '$total XP earned',
                        style: TextStyle(
                          color: theme.accentColor.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: needed <= 0 ? 0 : (into / needed).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: theme.accentColor.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(theme.accentColor),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$into / $needed XP to Level ${level + 1}',
                  style: TextStyle(
                    color: theme.accentColor.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
