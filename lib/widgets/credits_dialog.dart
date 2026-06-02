import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:url_launcher/url_launcher.dart';

/// "About / Credits" dialog for Cosmo Strike. Reached from the Settings
/// screen (it used to live in the home top bar before the bar was slimmed
/// down to identity + wallet + tools).
Future<void> showCreditsDialog(BuildContext context, GameTheme theme) async {
  final currentYear = DateTime.now().year;
  final packageInfo = await PackageInfo.fromPlatform();
  if (!context.mounted) return;

  showDialog(
    context: context,
    builder: (BuildContext dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.backgroundColor,
                  Color.alphaBlend(
                    theme.primaryColor.withValues(alpha: 0.10),
                    theme.backgroundColor,
                  ),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: theme.accentColor.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.accentColor.withValues(alpha: 0.18),
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            theme.primaryColor.withValues(alpha: 0.28),
                            theme.accentColor.withValues(alpha: 0.08),
                          ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.accentColor.withValues(alpha: 0.25),
                        ),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(
                        'assets/images/cosmo_strike_transparent.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [
                                theme.primaryColor,
                                theme.accentColor,
                              ],
                            ).createShader(bounds),
                            child: const Text(
                              'Cosmo Strike',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'v${packageInfo.version} · build ${packageInfo.buildNumber}',
                            style: TextStyle(
                              color: theme.accentColor.withValues(alpha: 0.65),
                              fontSize: 11,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkResponse(
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
                  ],
                ),

                const SizedBox(height: 14),

                Text(
                  'The classic ship game, reimagined.',
                  style: TextStyle(
                    color: theme.accentColor.withValues(alpha: 0.75),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 14),

                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildAboutChip('Modes', Icons.sports_esports, theme),
                    _buildAboutChip('Achievements', Icons.emoji_events, theme),
                    _buildAboutChip('Daily', Icons.today, theme),
                    _buildAboutChip('Leaderboards', Icons.leaderboard, theme),
                    _buildAboutChip('Cosmetics', Icons.palette, theme),
                  ],
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.accentColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.accentColor.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.code_rounded,
                          color: theme.accentColor,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Crafted by',
                              style: TextStyle(
                                color: theme.accentColor.withValues(alpha: 0.55),
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Pranta Dutta',
                              style: TextStyle(
                                color: theme.accentColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.primaryColor.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'pranta.dev',
                                style: TextStyle(
                                  color: theme.accentColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.open_in_new_rounded,
                                color: theme.accentColor.withValues(alpha: 0.8),
                                size: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  '© $currentYear Pranta Dutta · All rights reserved',
                  style: TextStyle(
                    color: theme.accentColor.withValues(alpha: 0.45),
                    fontSize: 10,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _buildAboutChip(String label, IconData icon, GameTheme theme) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: theme.accentColor.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: theme.accentColor.withValues(alpha: 0.22),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: theme.accentColor.withValues(alpha: 0.85)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: theme.accentColor.withValues(alpha: 0.9),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
