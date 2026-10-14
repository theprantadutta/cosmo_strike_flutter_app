import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../game/run_upgrades.dart';
import 'run_stat_tiles.dart';

/// After a level clear: pick 1 of 3 upgrades that stack for the rest of the
/// run. Three tall cards (rarity-coloured, current stacks shown) deal in on
/// a stagger; the run's build so far sits underneath. Tapping a card picks
/// it — there is no skip, the choice IS the reward.
class UpgradeDraftOverlay extends StatefulWidget {
  const UpgradeDraftOverlay({
    super.key,
    required this.options,
    required this.upgrades,
    required this.nextLevel,
    required this.onPick,
  });

  final List<UpgradeDef> options;
  final RunUpgrades upgrades;
  final int nextLevel;
  final ValueChanged<UpgradeId> onPick;

  @override
  State<UpgradeDraftOverlay> createState() => _UpgradeDraftOverlayState();
}

class _UpgradeDraftOverlayState extends State<UpgradeDraftOverlay> {
  UpgradeId? _picked;

  void _pick(UpgradeId id) {
    if (_picked != null) return;
    HapticFeedback.mediumImpact();
    setState(() => _picked = id);
    // Let the chosen card's confirm pulse land before moving on.
    Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) widget.onPick(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return GameplayOverlayFrame(
      scrim: const Color(0xF20A0A0D),
      washes: const [CsWash.violetTopRight, CsWash.cyanBottomLeft],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CsLabel('Upgrade · before level ${widget.nextLevel.toString().padLeft(2, '0')}',
              color: CsColors.violet),
          SizedBox(height: cs(6)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CsHeadline(const ['Choose your ', 'edge'], prismIndex: 1, maxLines: 1, style: t.display(40, em: -0.04, height: 1)),
          ),
          SizedBox(height: cs(18)),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.options.length; i++) ...[
                  if (i > 0) SizedBox(width: cs(14)),
                  Expanded(
                    child: _DealIn(
                      index: i,
                      child: _UpgradeCard(
                        def: widget.options[i],
                        owned: widget.upgrades.stacks(widget.options[i].id),
                        state: _picked == null
                            ? _CardState.idle
                            : (_picked == widget.options[i].id ? _CardState.picked : _CardState.dimmed),
                        onTap: () => _pick(widget.options[i].id),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: cs(14)),
          _BuildStrip(upgrades: widget.upgrades),
        ],
      ),
    );
  }
}

enum _CardState { idle, picked, dimmed }

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({required this.def, required this.owned, required this.state, required this.onTap});
  final UpgradeDef def;
  final int owned;
  final _CardState state;
  final VoidCallback onTap;

  static Color rarityColor(UpgradeRarity r) => switch (r) {
        UpgradeRarity.common => CsColors.ink60,
        UpgradeRarity.rare => CsColors.cyan,
        UpgradeRarity.epic => CsColors.gold,
      };

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final rc = rarityColor(def.rarity);
    final content = Padding(
      padding: EdgeInsets.all(cs(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(def.category.toUpperCase(), style: t.mono(9, color: CsColors.ink45)),
            const Spacer(),
            Text(def.rarity.name.toUpperCase(), style: t.mono(9, color: rc)),
          ]),
          const Spacer(),
          Icon(upgradeIcon(def.id), size: cs(34), color: def.rarity == UpgradeRarity.common ? CsColors.ink : rc),
          SizedBox(height: cs(12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(def.name, maxLines: 1, style: t.display(20, em: -0.02, height: 1.05)),
          ),
          SizedBox(height: cs(6)),
          Text(def.blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.body),
          const Spacer(),
          _StackPips(owned: owned, max: def.maxStacks),
        ],
      ),
    );
    final Widget card = switch (state) {
      _CardState.picked => CsPrismRing(radius: CsRadius.card, rotate: true, width: 2, child: content),
      _ => CsTile(
          state: def.rarity == UpgradeRarity.epic ? CsTileState.pro : CsTileState.selected,
          radius: CsRadius.card,
          padding: EdgeInsets.zero,
          child: content,
        ),
    };
    return AnimatedOpacity(
      duration: CsMotion.base,
      opacity: state == _CardState.dimmed ? 0.3 : 1,
      child: AnimatedScale(
        duration: CsMotion.base,
        curve: CsMotion.emphasis,
        scale: state == _CardState.picked ? 1.04 : 1,
        child: CsPressable(onTap: state == _CardState.idle ? onTap : null, semanticLabel: def.name, child: card),
      ),
    );
  }
}

/// Owned stacks (filled) + this pick (prism) + remaining (outline).
class _StackPips extends StatelessWidget {
  const _StackPips({required this.owned, required this.max});
  final int owned;
  final int max;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Row(children: [
      for (var i = 0; i < max; i++) ...[
        if (i > 0) SizedBox(width: cs(5)),
        Container(
          width: cs(18),
          height: 3,
          decoration: BoxDecoration(
            color: i < owned ? CsColors.ink : (i == owned ? null : CsColors.track),
            gradient: i == owned ? CsGradients.prism : null,
          ),
        ),
      ],
      SizedBox(width: cs(8)),
      Text(owned == 0 ? 'NEW' : 'LV ${owned + 1}', style: cs.type.mono(9, color: CsColors.ink45)),
    ]);
  }
}

/// The run's build so far: one chip per owned upgrade with its level.
class _BuildStrip extends StatelessWidget {
  const _BuildStrip({required this.upgrades});
  final RunUpgrades upgrades;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final owned = UpgradeCatalog.all.where((u) => upgrades.stacks(u.id) > 0).toList();
    return SizedBox(
      height: cs(30).clamp(28.0, 40.0),
      child: Row(children: [
        CsLabel('Your build', size: 10),
        SizedBox(width: cs(12)),
        Expanded(
          child: owned.isEmpty
              ? Text('Your first pick starts your build.', style: cs.type.mono(10, color: CsColors.ink30))
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: owned.length,
                  separatorBuilder: (_, _) => SizedBox(width: cs(8)),
                  itemBuilder: (_, i) => Center(
                    child: CsChip(
                      '${owned[i].name} ${upgrades.stacks(owned[i].id)}',
                      icon: upgradeIcon(owned[i].id),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}

class _DealIn extends StatelessWidget {
  const _DealIn({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = 0.12 * index;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + 120 * index),
      curve: Interval(start / (1 + start), 1, curve: CsMotion.emphasis),
      builder: (_, v, c) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, context.cs(28) * (1 - v)), child: c),
      ),
      child: child,
    );
  }
}

/// Glyph per upgrade (shared with the game-over build summary).
IconData upgradeIcon(UpgradeId id) => switch (id) {
      UpgradeId.twinCannon => Symbols.stacks_rounded,
      UpgradeId.wideSpread => Symbols.call_split_rounded,
      UpgradeId.rapidServos => Symbols.speed_rounded,
      UpgradeId.piercingRounds => Symbols.arrow_right_alt_rounded,
      UpgradeId.heavyRounds => Symbols.weight_rounded,
      UpgradeId.wingman => Symbols.flight_rounded,
      UpgradeId.shieldRegen => Symbols.shield_rounded,
      UpgradeId.hullPlating => Symbols.security_rounded,
      UpgradeId.magnetField => Symbols.attractions_rounded,
      UpgradeId.missileRack => Symbols.rocket_rounded,
      UpgradeId.grazeField => Symbols.radar_rounded,
      UpgradeId.siphon => Symbols.bolt_rounded,
      UpgradeId.overcharge => Symbols.electric_bolt_rounded,
      UpgradeId.chainLink => Symbols.link_rounded,
    };
