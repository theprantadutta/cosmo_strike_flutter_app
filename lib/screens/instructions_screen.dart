import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

/// How to play (Prism Noir): a section list on the LEFT styled like the
/// store's category list (selected = 7% white fill + gold icon) with a
/// "Back to game" action under it, and the selected section on the RIGHT —
/// mono eyebrow, Syne headline, then hairline rows with Symbols glyphs or
/// the real in-game sprites.
class InstructionsScreen extends StatefulWidget {
  const InstructionsScreen({super.key});

  @override
  State<InstructionsScreen> createState() => _InstructionsScreenState();
}

class _Section {
  const _Section(this.icon, this.label, this.headline, {this.sprite});
  final IconData icon;
  final String label;

  /// Two parts; the second is painted in prism.
  final List<String> headline;
  final String? sprite;
}

class _InstructionsScreenState extends State<InstructionsScreen> {
  int _selected = 0;

  static const _sections = [
    _Section(Symbols.flag_rounded, 'Objective', ['Bring the boss ', 'down.'],
        sprite: 'assets/game/player/player_ship.png'),
    _Section(Symbols.touch_app_rounded, 'Controls', ['Fly by ', 'feel.']),
    _Section(Symbols.military_tech_rounded, 'Combat', ['Chain, graze, ', 'counter.']),
    _Section(Symbols.flare_rounded, 'Power-Ups', ['Fly into the ', 'orbs.']),
    _Section(Symbols.warning_rounded, 'Bosses & Terrain', ['Read the ', 'tell.'],
        sprite: 'assets/game/bosses/boss_mothership.png'),
    _Section(Symbols.lightbulb_rounded, 'Field Notes', ['Fly like an ', 'ace.']),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return CsScaffold(
      title: 'How to Play',
      trailing: [
        CsMeta(
          '${(_selected + 1).toString().padLeft(2, '0')} / ${_sections.length.toString().padLeft(2, '0')}',
        ),
      ],
      body: CsSplit(
        leftWidth: cs.isTablet ? 270 : 240,
        left: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CsFitColumn(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: cs(4)),
                      child: _NavItem(
                        icon: _sections[i].icon,
                        label: _sections[i].label,
                        selected: _selected == i,
                        onTap: () => setState(() => _selected = i),
                      ),
                    ),
                ],
              ),
            ),
            // Short phones: the top-bar back arrow is enough; give the
            // section list the room instead.
            if (!cs.isCompact) SizedBox(height: cs(10)),
            if (!cs.isCompact) CsButton.secondary(
              onPressed: () => context.pop(),
              label: 'Back to Game',
              icon: Symbols.arrow_back_rounded,
              // Phones: the compact pill so the label never truncates.
              size: cs.isTablet ? CsButtonSize.regular : CsButtonSize.small,
              expand: true,
            ),
          ],
        ),
        right: AnimatedSwitcher(
          duration: CsMotion.base,
          switchInCurve: CsMotion.standard,
          child: ListView(
            key: ValueKey<int>(_selected),
            padding: EdgeInsets.only(bottom: cs(12)),
            children: [
              _SectionHeader(section: _sections[_selected], index: _selected),
              SizedBox(height: cs(16)),
              ..._buildSectionContent(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSectionContent() {
    switch (_selected) {
      case 0:
        return const [
          _Lead(
            'Fight through a 12-level campaign across 4 alien biomes. '
            'Each level is a choreographed gauntlet of enemy waves and '
            'formations that ends in a boss fight — bring the boss down '
            'to clear the level and unlock the next.',
          ),
          _RuleRow(
            'Clearing a level unlocks the next — progress is saved the '
            'moment the boss falls',
            index: 1,
            first: true,
          ),
          _RuleRow(
            'Flight modes (Settings) change the rules: Sortie, Cruise, '
            'Afterburn, Swarm, Holdout, Blitz, Overload and Knife Edge',
            index: 2,
          ),
          _RuleRow(
            'Every run pays credits: more for kills, bosses and '
            'first-time level clears',
            index: 3,
          ),
        ];
      case 1:
        return const [
          _InfoRow(
            leading: CsIconDisc(Symbols.swipe_rounded),
            title: 'Drag Anywhere',
            body: 'Steer — your ship mirrors your finger, so your thumb '
                'never covers it',
            first: true,
          ),
          _InfoRow(
            leading: CsIconDisc(Symbols.bolt_rounded),
            title: 'Auto-Fire',
            body: 'Your cannon fires by itself — focus on flying',
          ),
          _InfoRow(
            leading: CsIconDisc(Symbols.touch_double_rounded),
            title: 'Double-Tap',
            body: 'Launch a missile (or use the missile button)',
          ),
          _InfoRow(
            leading: CsIconDisc(Symbols.pause_rounded),
            title: 'Pause Button',
            body: 'Pause the run — resume or quit safely',
          ),
          _InfoRow(
            leading: CsIconDisc(Symbols.gamepad_rounded),
            title: 'D-Pad (optional)',
            body: 'Prefer old-school? Enable the on-screen D-pad in Settings',
          ),
        ];
      case 2:
        return const [
          _InfoRow(
            leading: CsIconDisc(Symbols.local_fire_department_rounded, color: CsColors.pink),
            title: 'Combo Chain',
            chip: 'up to ×4 score',
            body: 'Chain kills fast — without getting hit — to climb the score '
                'multiplier: ×2 at 5 kills, ×3 at 10, ×4 at 20. The chain '
                'decays if you stop killing, and one landed hit resets it',
            first: true,
          ),
          _InfoRow(
            leading: CsIconDisc(Symbols.near_me_rounded, color: CsColors.cyan),
            title: 'Graze',
            chip: '+15 & Overdrive',
            body: 'Let enemy bullets skim your hull: each near miss scores with '
                'your combo, keeps the chain alive and charges Overdrive',
          ),
          _InfoRow(
            leading: CsIconDisc(Symbols.bolt_rounded, color: CsColors.violet),
            title: 'Overdrive',
            chip: '5s · ×2 score',
            body: 'Tap a full meter: a piercing beam, double score and an aura '
                'that vaporises nearby bullets. Formation wipes charge it too',
          ),
          _InfoRow(
            leading: CsIconDisc(Symbols.my_location_rounded, color: CsColors.mint),
            title: 'Counter Fire',
            chip: 'laser + Overdrive',
            body: 'The basic cannon passes through enemy fire, so dodge it. '
                'Laser-tier shots and Overdrive knock bullets out of the sky '
                'for points. Boss bolts take about 3 hits',
          ),
          _InfoRow(
            leading: CsIconDisc(Symbols.grid_view_rounded, color: CsColors.gold),
            title: 'Formation Wipe',
            chip: 'bonus + orb',
            body: 'Destroy an entire formation fast for a wipe bonus, '
                'Overdrive charge and a guaranteed pickup drop',
          ),
        ];
      case 3:
        return const [
          _Lead(
            'Destroyed enemies sometimes drop pickup orbs — fly into '
            'them to collect.',
          ),
          _PowerUpGrid(items: [
            ('powerup_weapon', 'Weapon', 'tier up'),
            ('powerup_shield', 'Shield', 'blocks 1 hit'),
            ('powerup_missiles', 'Missiles', '+3 ammo'),
            ('powerup_speed', 'Speed', 'move faster'),
            ('powerup_x2', '×2 Score', '10 seconds'),
            ('powerup_slowmo', 'Slow-Mo', 'slows enemies'),
            ('powerup_magnet', 'Magnet', 'pulls orbs in'),
            ('powerup_ghost', 'Ghost', 'phase through'),
            ('powerup_bomb', 'Bomb', 'clears screen'),
            ('powerup_life', 'Extra Life', '+1 ship'),
          ]),
          _RuleRow(
            'Timed boosts (×2 Score, Speed, Slow-Mo, Ghost, Magnet) run for '
            'a few seconds; Shield and Weapon last until used or upgraded',
            index: 1,
            first: true,
          ),
          _RuleRow(
            'Arm Tactical Gear from the Armory before launch (gear chip on '
            'the home screen) for an instant head start',
            index: 2,
          ),
        ];
      case 4:
        return const [
          _RuleRow(
            'Every boss attack is telegraphed — a warning flash shows '
            'where it will hit before it fires. Watch, then move',
            index: 1,
            first: true,
          ),
          _RuleRow(
            'Boss energy bolts can be shot down — it takes about 3 hits '
            'each, so focus your fire to punch a gap in the curtain',
            index: 2,
          ),
          _RuleRow(
            'Bosses fight in phases: each phase flip clears their '
            'bullets and changes their attack pattern',
            index: 3,
          ),
          _RuleRow(
            'Terrain is a threat: clipping the floor, ceiling, or an '
            'obstacle damages your ship and bounces you away',
            index: 4,
          ),
          _RuleRow(
            'Watch for canyon squeezes — the corridor narrows during '
            'set pieces, and wall-mounted turrets pour aimed fire',
            index: 5,
          ),
          _RuleRow(
            'Hull lost? You get ONE revive per run: watch an ad or '
            'spend 200 CR to keep flying',
            index: 6,
          ),
        ];
      default:
        return const [
          _RuleRow(
            'Wipe whole formations fast — the bonus and guaranteed orb '
            'beat picking off stragglers',
            tip: true,
            first: true,
          ),
          _RuleRow(
            'Graze on purpose: skimming bullet streams is the fastest '
            'way to charge Overdrive',
            tip: true,
          ),
          _RuleRow('Save missiles for armored hulls and boss phases', tip: true),
          _RuleRow(
            'Protect your combo — backing off for a second beats '
            'breaking a ×4 chain',
            tip: true,
          ),
          _RuleRow(
            'Arm Tactical Gear before launch for a head start '
            '(gear chip on the home screen)',
            tip: true,
          ),
          _RuleRow(
            'Learn each boss\'s telegraphs — every attack has a tell',
            tip: true,
          ),
          _RuleRow(
            'When dodging gets tight, shoot the boss bolts down — 3 hits '
            'clears one and opens a lane',
            tip: true,
          ),
        ];
    }
  }
}

/// Category-list item (as on the store): 7% white fill + gold icon when
/// selected, quiet ink otherwise.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return CsPressable(
      onTap: onTap,
      scale: 0.98,
      semanticLabel: label,
      child: AnimatedContainer(
        duration: CsMotion.base,
        curve: CsMotion.standard,
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.symmetric(horizontal: cs(14), vertical: cs(10)),
        decoration: BoxDecoration(
          color: selected ? CsColors.fill07 : Colors.transparent,
          borderRadius: BorderRadius.circular(CsRadius.tile),
        ),
        child: Row(
          children: [
            Icon(icon, size: cs(20), color: selected ? CsColors.gold : CsColors.ink45),
            SizedBox(width: cs(14)),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: cs.type.display(
                  15,
                  weight: selected ? FontWeight.w700 : FontWeight.w600,
                  em: 0,
                  color: selected ? CsColors.ink : CsColors.ink60,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section, required this.index});
  final _Section section;
  final int index;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CsLabel('${(index + 1).toString().padLeft(2, '0')} · ${section.label}'),
              SizedBox(height: cs(8)),
              CsHeadline(section.headline, prismIndex: 1, style: t.section, maxLines: 2),
            ],
          ),
        ),
        if (section.sprite != null) ...[
          SizedBox(width: cs(16)),
          Image.asset(
            section.sprite!,
            height: cs(56),
            width: cs(110),
            alignment: Alignment.bottomRight,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ],
      ],
    );
  }
}

/// Lead paragraph under the headline.
class _Lead extends StatelessWidget {
  const _Lead(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: EdgeInsets.only(bottom: cs(14)),
      child: Text(text, style: cs.type.body.copyWith(fontSize: cs(15), color: CsColors.ink70, height: 1.5)),
    );
  }
}

/// Hairline row: mono index (or gold star for tips) + body copy.
class _RuleRow extends StatelessWidget {
  const _RuleRow(this.text, {this.index, this.tip = false, this.first = false});
  final String text;
  final int? index;
  final bool tip;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return Container(
      padding: EdgeInsets.symmetric(vertical: cs(12)),
      decoration: BoxDecoration(
        border: Border(
          top: first ? const BorderSide(color: CsColors.hairline) : BorderSide.none,
          bottom: const BorderSide(color: CsColors.hairline),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: cs(34),
            child: tip
                ? Icon(Symbols.star_rounded, size: cs(16), color: CsColors.gold)
                : Text(index.toString().padLeft(2, '0'), style: t.mono(11, color: CsColors.ink45)),
          ),
          Expanded(child: Text(text, style: t.body.copyWith(fontSize: cs(14), color: CsColors.ink70))),
        ],
      ),
    );
  }
}

/// Hairline row with a leading glyph, title (+ optional mono chip) and an
/// unclamped body (descriptions here run 2-3 lines).
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.leading, required this.title, required this.body, this.chip, this.first = false});
  final Widget leading;
  final String title;
  final String body;
  final String? chip;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return Container(
      padding: EdgeInsets.symmetric(vertical: cs(12)),
      decoration: BoxDecoration(
        border: Border(
          top: first ? const BorderSide(color: CsColors.hairline) : BorderSide.none,
          bottom: const BorderSide(color: CsColors.hairline),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          SizedBox(width: cs(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
                    ),
                    if (chip != null) ...[SizedBox(width: cs(8)), CsChip(chip!)],
                  ],
                ),
                SizedBox(height: cs(4)),
                Text(body, style: t.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Power-up pickups as a two-column hairline list with the real sprites.
class _PowerUpGrid extends StatelessWidget {
  const _PowerUpGrid({required this.items});

  /// (sprite file stem, name, effect)
  final List<(String, String, String)> items;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final cols = cs.isTablet ? 3 : 2;
    return Padding(
      padding: EdgeInsets.only(bottom: cs(18)),
      child: LayoutBuilder(builder: (context, c) {
        final gap = cs(16);
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          children: [
            for (final (file, name, effect) in items)
              Container(
                width: w,
                padding: EdgeInsets.symmetric(vertical: cs(9)),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: CsColors.hairline))),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/game/powerups/$file.png',
                      width: cs(28),
                      height: cs(28),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                    SizedBox(width: cs(12)),
                    Expanded(
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle.copyWith(fontSize: cs(14))),
                    ),
                    SizedBox(width: cs(8)),
                    Text(effect.toUpperCase(), maxLines: 1, style: t.mono(9, color: CsColors.ink45)),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}
