import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/utils/game_animations.dart';

/// How-to-play, clean landscape Command-HUD layout: a section rail on the
/// LEFT (Objective / Controls / Pickups / Rules / Pro Tips, no-background
/// glowing-dot selection) with the Back button beneath it, and the selected
/// section's content on the RIGHT. Everything floats borderless on the
/// starfield.
class InstructionsScreen extends StatefulWidget {
  const InstructionsScreen({super.key});

  @override
  State<InstructionsScreen> createState() => _InstructionsScreenState();
}

class _InstructionsScreenState extends State<InstructionsScreen> {
  int _selected = 0;

  static const _sections = [
    (Icons.flag, 'Objective'),
    (Icons.touch_app, 'Controls'),
    (Icons.flare, 'Pickups'),
    (Icons.rule, 'Rules'),
    (Icons.lightbulb, 'Pro Tips'),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        final theme = state.currentTheme;

        return CommandScaffold(
          theme: theme,
          title: 'How to Play',
          bottomBar: const ShipBannerAd(),
          bodyPadding: EdgeInsets.zero,
          body: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // LEFT — section rail + back button. Never scrolls.
                Expanded(
                  flex: 3,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: 210,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < _sections.length; i++)
                              _buildNavItem(theme, i),
                            const SizedBox(height: 14),
                            NeonButton(
                              onPressed: () => context.pop(),
                              label: 'Back to Game',
                              icon: Icons.arrow_back,
                              theme: theme,
                              expand: true,
                              height: 42,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // RIGHT — the selected section, cross-faded on change.
                Expanded(
                  flex: 7,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: ListView(
                      key: ValueKey<int>(_selected),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: _buildSectionContent(theme),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavItem(GameTheme theme, int i) {
    final selected = _selected == i;
    final (icon, label) = _sections[i];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selected = i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? theme.neonPrimary : theme.textMuted,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? theme.textPrimary : theme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (selected)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.neonPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: theme.neonPrimary.withValues(alpha: 0.7),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSectionContent(GameTheme theme) {
    switch (_selected) {
      case 0:
        return [
          _sectionLabel(theme, 'OBJECTIVE'),
          const SizedBox(height: 12),
          Text(
            'Pilot your ship to destroy enemies and survive as long as '
            'possible while dodging enemy fire and asteroids!',
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 15,
              height: 1.6,
            ),
          ).gameListItem(0),
        ];
      case 1:
        return [
          _sectionLabel(theme, 'CONTROLS'),
          const SizedBox(height: 12),
          _buildControlItem('Swipe Up ↑', 'Move ship up', theme, 0),
          _buildControlItem('Swipe Down ↓', 'Move ship down', theme, 1),
          _buildControlItem('Swipe Left ←', 'Move ship left', theme, 2),
          _buildControlItem('Swipe Right →', 'Move ship right', theme, 3),
          _buildControlItem('Tap Screen', 'Pause/Resume game', theme, 4),
          const SizedBox(height: 8),
          _buildControlItem(
            'Arrow Keys (Desktop)',
            'Change direction',
            theme,
            5,
          ),
          _buildControlItem('WASD (Desktop)', 'Change direction', theme, 6),
          _buildControlItem(
            'Spacebar (Desktop)',
            'Pause/Resume game',
            theme,
            7,
          ),
        ];
      case 2:
        return [
          _sectionLabel(theme, 'PICKUP TYPES'),
          const SizedBox(height: 12),
          _buildFoodItem('Pickup', '10 points', theme.foodColor, theme, 0),
          _buildFoodItem('Bonus Pickup', '25 points', Colors.orange, theme, 1),
          _buildFoodItem(
            'Power-Up',
            '50 points + Level Up',
            const Color(0xFFFFD700),
            theme,
            2,
          ),
        ];
      case 3:
        return [
          _sectionLabel(theme, 'RULES'),
          const SizedBox(height: 12),
          _buildRuleItem(
            'Destroy enemies to increase your score',
            theme,
            0,
          ),
          _buildRuleItem(
            'Enemy waves get faster as you level up',
            theme,
            1,
          ),
          _buildRuleItem('Game ends if your ship is destroyed', theme, 2),
          _buildRuleItem('A Power-Up appears every 10 pickups', theme, 3),
          _buildRuleItem('Bonus Pickups expire after 15 seconds', theme, 4),
        ];
      default:
        return [
          _sectionLabel(theme, 'PRO TIPS'),
          const SizedBox(height: 12),
          _buildTipItem(
            'Anticipate enemy waves before they arrive',
            theme,
            0,
          ),
          _buildTipItem('Grab power-ups to upgrade your weapons', theme, 1),
          _buildTipItem('Weave between asteroids and enemy fire', theme, 2),
          _buildTipItem('Learn each boss\'s attack patterns', theme, 3),
        ];
    }
  }

  Widget _sectionLabel(GameTheme theme, String title) {
    return Text(
      title,
      style: TextStyle(
        color: theme.accentColor,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.8,
      ),
    );
  }

  Widget _buildControlItem(
    String gesture,
    String action,
    GameTheme theme,
    int index,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          // Gesture chip — borderless tint.
          Container(
            width: 150,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              gesture,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              action,
              style: TextStyle(color: theme.textMuted, fontSize: 13.5),
            ),
          ),
        ],
      ),
    ).gameListItem(index);
  }

  Widget _buildFoodItem(
    String name,
    String points,
    Color color,
    GameTheme theme,
    int index,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Glowing pickup orb.
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                color: theme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.foodColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              points,
              style: TextStyle(
                color: theme.foodColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    ).gameListItem(index);
  }

  Widget _buildRuleItem(String rule, GameTheme theme, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 7, right: 10),
            decoration: BoxDecoration(
              color: theme.neonPrimary.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              rule,
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    ).gameListItem(index);
  }

  Widget _buildTipItem(String tip, GameTheme theme, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.star, color: theme.foodColor, size: 15),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(
                color: theme.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    ).gameListItem(index);
  }
}
