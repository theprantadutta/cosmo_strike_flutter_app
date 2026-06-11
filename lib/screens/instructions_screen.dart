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
    (Icons.military_tech, 'Combat'),
    (Icons.flare, 'Power-Ups'),
    (Icons.warning_amber, 'Bosses & Terrain'),
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
            'Fight through a 12-level campaign across 4 alien biomes. '
            'Each level is a choreographed gauntlet of enemy waves and '
            'formations that ends in a boss fight — bring the boss down '
            'to clear the level and unlock the next.',
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 15,
              height: 1.6,
            ),
          ).gameListItem(0),
          const SizedBox(height: 12),
          _buildRuleItem(
            'Clearing a level unlocks the next — progress is saved the '
            'moment the boss falls',
            theme,
            1,
          ),
          _buildRuleItem(
            'Game modes (Settings) change the rules: lives, pacing, '
            'enemy fire, one-hit runs, or a Time Attack clock',
            theme,
            2,
          ),
          _buildRuleItem(
            'Earn coins every run — more for kills, bosses, and '
            'first-time level clears',
            theme,
            3,
          ),
        ];
      case 1:
        return [
          _sectionLabel(theme, 'CONTROLS'),
          const SizedBox(height: 12),
          _buildControlItem(
            'Drag Anywhere',
            'Steer — your ship mirrors your finger, so your thumb '
                'never covers it',
            theme,
            0,
          ),
          _buildControlItem(
            'Auto-Fire',
            'Your cannon fires by itself — focus on flying',
            theme,
            1,
          ),
          _buildControlItem(
            'Double-Tap',
            'Launch a missile (or use the missile button)',
            theme,
            2,
          ),
          _buildControlItem(
            'Pause Button',
            'Pause the run — resume or quit safely',
            theme,
            3,
          ),
          _buildControlItem(
            'D-Pad (optional)',
            'Prefer old-school? Enable the on-screen D-pad in Settings',
            theme,
            4,
          ),
        ];
      case 2:
        return [
          _sectionLabel(theme, 'COMBAT SYSTEMS'),
          const SizedBox(height: 12),
          _buildFoodItem(
            'Combo Chain',
            'up to ×4 score',
            const Color(0xFFFF7BD5),
            theme,
            0,
          ),
          _buildRuleItem(
            'Chain kills without getting hit to raise your score '
            'multiplier — one landed hit breaks the chain',
            theme,
            1,
          ),
          const SizedBox(height: 8),
          _buildFoodItem(
            'Graze',
            '+15 & meter',
            const Color(0xFF7DE8FF),
            theme,
            2,
          ),
          _buildRuleItem(
            'Let enemy bullets just miss your hull: each near miss pays '
            'points and charges the graze meter — a full meter loads '
            '+1 missile',
            theme,
            3,
          ),
          const SizedBox(height: 8),
          _buildFoodItem(
            'Formation Wipe',
            'bonus + orb',
            const Color(0xFFFFD37B),
            theme,
            4,
          ),
          _buildRuleItem(
            'Destroy an entire enemy formation quickly for a wipe bonus '
            'and a guaranteed power-up drop',
            theme,
            5,
          ),
        ];
      case 3:
        return [
          _sectionLabel(theme, 'POWER-UP DROPS'),
          const SizedBox(height: 12),
          _buildRuleItem(
            'Destroyed enemies sometimes drop power-up orbs — fly into '
            'them to collect',
            theme,
            0,
          ),
          _buildFoodItem('Weapon', 'tier up', const Color(0xFF7DE8FF), theme, 1),
          _buildFoodItem('Shield', 'blocks 1 hit', const Color(0xFF8AB4FF), theme, 2),
          _buildFoodItem('Missiles', '+3 ammo', const Color(0xFFFFD37B), theme, 3),
          _buildFoodItem('Speed', 'move faster', const Color(0xFF9CFF8A), theme, 4),
          _buildFoodItem('×2 Score', '10 seconds', const Color(0xFFFF7BD5), theme, 5),
          _buildFoodItem('Slow-Mo', 'slows enemies', const Color(0xFFC59CFF), theme, 6),
          _buildFoodItem('Magnet', 'pulls orbs in', const Color(0xFFFFB37B), theme, 7),
          _buildFoodItem('Ghost', 'phase through', const Color(0xFFB0BEC5), theme, 8),
          _buildFoodItem('Bomb', 'clears screen', const Color(0xFFFF8A8A), theme, 9),
          _buildFoodItem('Extra Life', '+1 ship', const Color(0xFFFF6E9C), theme, 10),
        ];
      case 4:
        return [
          _sectionLabel(theme, 'BOSSES & TERRAIN'),
          const SizedBox(height: 12),
          _buildRuleItem(
            'Every boss attack is telegraphed — a warning flash shows '
            'where it will hit before it fires. Watch, then move',
            theme,
            0,
          ),
          _buildRuleItem(
            'Bosses fight in phases: each phase flip clears their '
            'bullets and changes their attack pattern',
            theme,
            1,
          ),
          _buildRuleItem(
            'Terrain is a threat: clipping the floor, ceiling, or an '
            'obstacle damages your ship and bounces you away',
            theme,
            2,
          ),
          _buildRuleItem(
            'Watch for canyon squeezes — the corridor narrows during '
            'set pieces, and wall-mounted turrets pour aimed fire',
            theme,
            3,
          ),
          _buildRuleItem(
            'Out of lives? You get ONE revive per run — watch an ad or '
            'spend 200 coins to keep the run alive',
            theme,
            4,
          ),
        ];
      default:
        return [
          _sectionLabel(theme, 'PRO TIPS'),
          const SizedBox(height: 12),
          _buildTipItem(
            'Wipe whole formations fast — the bonus and guaranteed orb '
            'beat picking off stragglers',
            theme,
            0,
          ),
          _buildTipItem(
            'Graze on purpose: skimming bullet streams is the fastest '
            'way to bank missiles',
            theme,
            1,
          ),
          _buildTipItem(
            'Save missiles for armored hulls and boss phases',
            theme,
            2,
          ),
          _buildTipItem(
            'Protect your combo — backing off for a second beats '
            'breaking a ×4 chain',
            theme,
            3,
          ),
          _buildTipItem(
            'Arm a store power-up before launch for a head start '
            '(loadout chip on the home screen)',
            theme,
            4,
          ),
          _buildTipItem(
            'Learn each boss\'s telegraphs — every attack has a tell',
            theme,
            5,
          ),
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
