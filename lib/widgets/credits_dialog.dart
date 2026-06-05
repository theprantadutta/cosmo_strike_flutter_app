import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// "About / Credits" dialog for Cosmo Strike. Reached from the home top bar's
/// about tool (and the Settings screen).
///
/// Clean Command-HUD styling for the wide landscape viewport: a two-region
/// sheet — brand identity on the LEFT, credits on the RIGHT — on a dark
/// surface framed purely by neon glow. No borders anywhere.
Future<void> showCreditsDialog(BuildContext context, GameTheme theme) async {
  final currentYear = DateTime.now().year;
  final packageInfo = await PackageInfo.fromPlatform();
  if (!context.mounted) return;

  showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                theme.primaryColor.withValues(alpha: 0.06),
                theme.backgroundColor,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: theme.accentColor.withValues(alpha: 0.22),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
            child: Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // LEFT — brand identity.
                    Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                colors: [
                                  theme.primaryColor.withValues(alpha: 0.22),
                                  Colors.transparent,
                                ],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.accentColor
                                      .withValues(alpha: 0.30),
                                  blurRadius: 20,
                                  spreadRadius: -2,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Image.asset(
                              'assets/images/cosmo_strike_transparent.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [
                                theme.primaryColor,
                                theme.accentColor,
                              ],
                            ).createShader(bounds),
                            child: const Text(
                              'COSMO STRIKE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 19,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'A premium space shooter experience.',
                            style: TextStyle(
                              color: theme.textMuted,
                              fontSize: 11.5,
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  theme.accentColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'v${packageInfo.version} · build ${packageInfo.buildNumber}',
                              style: TextStyle(
                                color: theme.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // RIGHT — credits.
                    Expanded(
                      flex: 6,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CRAFTED BY',
                            style: TextStyle(
                              color: theme.accentColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pranta Dutta',
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 8),
                          InkWell(
                            onTap: () async {
                              final url = Uri.parse('https://pranta.dev');
                              if (await canLaunchUrl(url)) {
                                await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: theme.primaryColor
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.language_rounded,
                                    color: theme.accentColor,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'pranta.dev',
                                    style: TextStyle(
                                      color: theme.accentColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Icon(
                                    Icons.open_in_new_rounded,
                                    color: theme.accentColor
                                        .withValues(alpha: 0.8),
                                    size: 11,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'POWERED BY',
                            style: TextStyle(
                              color: theme.accentColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.local_fire_department_rounded,
                                color: Colors.orange.shade400,
                                size: 14,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Flame Game Engine',
                                style: TextStyle(
                                  color: theme.textMuted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '© $currentYear Pranta Dutta · All rights reserved',
                            style: TextStyle(
                              color: theme.textMuted.withValues(alpha: 0.7),
                              fontSize: 10,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Close — floats over the top-right corner.
                Positioned(
                  top: 0,
                  right: 0,
                  child: InkResponse(
                    onTap: () => Navigator.of(dialogContext).pop(),
                    radius: 20,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.accentColor.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: theme.accentColor.withValues(alpha: 0.8),
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
