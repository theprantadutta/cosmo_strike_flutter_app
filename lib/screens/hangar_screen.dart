import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../game/game_assets.dart';
import '../game/hangar.dart';
import '../game/run_upgrades.dart';
import '../presentation/bloc/coins/coins_cubit.dart';
import '../router/routes.dart';
import '../services/hangar_service.dart';
import '../ui/cs.dart';
import '../widgets/list_entrance.dart';
import '../widgets/gameplay/upgrade_draft_overlay.dart' show upgradeIcon;

/// The Hangar: pick a ship frame (unlocked by clearing campaign levels) and
/// buy permanent upgrades with coins. Skins & trails stay in the store.
class HangarScreen extends StatefulWidget {
  const HangarScreen({super.key});

  @override
  State<HangarScreen> createState() => _HangarScreenState();
}

class _HangarScreenState extends State<HangarScreen> {
  final _hangar = HangarService.instance;
  HangarStat? _buying;

  /// Successful purchases per stat; a change pops that row's level bar.
  final Map<HangarStat, int> _bought = {};

  /// Ship frames and upgrade rows stagger in on first open only.
  final _entrance = ListEntrance();

  @override
  void initState() {
    super.initState();
    _hangar.addListener(_onChange);
    _hangar.load();
  }

  @override
  void dispose() {
    _hangar.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _buy(HangarStat stat) async {
    final def = HangarCatalog.byStat(stat);
    final next = _hangar.level(stat) + 1;
    final cost = HangarCatalog.costForNext(_hangar.level(stat));
    final coins = context.read<CoinsCubit>();
    if (!coins.canAfford(cost)) {
      await _offerCredits(def.name, cost - coins.balance);
      return;
    }
    final ok = await showCsConfirm(
      context,
      eyebrow: 'Hangar upgrade',
      title: '${def.name} · L$next',
      message: '${def.perLevel} per level, every run. Costs $cost CR.',
      confirmLabel: 'Upgrade · $cost',
    );
    if (!ok || !mounted) return;
    setState(() => _buying = stat);
    final done = await _hangar.buyNext(stat);
    if (!mounted) return;
    setState(() {
      _buying = null;
      if (done) _bought[stat] = (_bought[stat] ?? 0) + 1;
    });
    if (done) CsHaptic.success.play();
    showCsToast(
      context,
      done ? '${def.name} upgraded to L$next.' : 'Upgrade failed. Try again.',
      kind: done ? CsToastKind.success : CsToastKind.error,
    );
  }

  /// Short of credits: say exactly how many are missing and offer the
  /// Armory's Credits tab instead of a dead-end error toast.
  Future<void> _offerCredits(String upgradeName, int missing) async {
    final go = await showCsConfirm(
      context,
      eyebrow: 'Hangar upgrade',
      title: 'Need $missing more CR',
      message: 'Fly sorties or grab a Credit Cache in the Armory to afford $upgradeName.',
      confirmLabel: 'Get credits',
      cancelLabel: 'Not now',
    );
    if (go && mounted) context.push('${AppRoutes.store}?tab=1');
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return CsScaffold(
      title: 'Hangar',
      trailing: [
        CsButton.text(
          label: 'Liveries & exhausts',
          size: CsButtonSize.small,
          icon: Symbols.palette_rounded,
          onPressed: () => context.push(AppRoutes.cosmetics),
        ),
        BlocBuilder<CoinsCubit, CoinsState>(
          builder: (_, s) => CsCoins(s.total),
        ),
      ],
      washes: const [CsWash.violetTopRight],
      body: CsSplit(
        leftWidth: cs.isTablet ? 340 : 300,
        left: _ShipList(hangar: _hangar, entrance: _entrance),
        right: BlocBuilder<CoinsCubit, CoinsState>(
          builder: (_, s) => _UpgradeList(
            hangar: _hangar,
            balance: s.total,
            buying: _buying,
            bought: _bought,
            entrance: _entrance,
            onBuy: _buy,
          ),
        ),
      ),
    );
  }
}

class _ShipList extends StatelessWidget {
  const _ShipList({required this.hangar, required this.entrance});
  final HangarService hangar;
  final ListEntrance entrance;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final selected = hangar.selectedFrame;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CsLabel('Ship'),
        SizedBox(height: cs(6)),
        Row(children: [
          // Static preview of the player sprite (same art the game flies).
          Image.asset(
            '${GameAssets.prefix}${GameAssets.playerShip}',
            height: cs(40),
            width: cs(60),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
          SizedBox(width: cs(10)),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CsHeadline([selected.name], prismIndex: 0, maxLines: 1, style: t.display(36, em: -0.03, height: 1)),
            ),
          ),
        ]),
        SizedBox(height: cs(6)),
        Text(selected.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.body),
        if (selected.startingUpgrades.isNotEmpty) ...[
          SizedBox(height: cs(8)),
          Wrap(spacing: cs(6), runSpacing: cs(6), children: [
            for (final id in selected.startingUpgrades.toSet())
              CsChip(UpgradeCatalog.byId(id).name, icon: upgradeIcon(id)),
          ]),
        ],
        SizedBox(height: cs(14)),
        Expanded(
          child: ListView.separated(
            itemCount: ShipFrame.all.length,
            separatorBuilder: (_, _) => SizedBox(height: cs(8)),
            itemBuilder: (_, i) {
              final f = ShipFrame.all[i];
              final owned = f.ownedWith(hangar.highestCleared);
              final isSel = f.id == selected.id;
              return entrance.wrap(i, CsTile(
                state: isSel ? CsTileState.current : (owned ? CsTileState.done : CsTileState.locked),
                onTap: owned && !isSel ? () => hangar.selectFrame(f) : null,
                padding: EdgeInsets.symmetric(horizontal: cs(14), vertical: cs(10)),
                child: Row(children: [
                  Icon(owned ? Symbols.rocket_rounded : Symbols.lock_rounded,
                      size: cs(18), color: owned ? CsColors.ink : CsColors.ink25),
                  SizedBox(width: cs(12)),
                  Expanded(
                    child: Text(f.name,
                        maxLines: 1, style: t.rowTitle.copyWith(color: owned ? CsColors.ink : CsColors.ink30)),
                  ),
                  Text(
                    isSel ? 'FLYING' : (owned ? 'SELECT' : 'CLEAR L${f.unlockLevel.toString().padLeft(2, '0')}'),
                    style: t.mono(9, color: isSel ? CsColors.mint : (owned ? CsColors.ink55 : CsColors.ink30)),
                  ),
                ]),
              ));
            },
          ),
        ),
      ],
    );
  }
}

class _UpgradeList extends StatelessWidget {
  const _UpgradeList({
    required this.hangar,
    required this.balance,
    required this.buying,
    required this.bought,
    required this.entrance,
    required this.onBuy,
  });
  final HangarService hangar;
  final int balance;
  final HangarStat? buying;
  final Map<HangarStat, int> bought;
  final ListEntrance entrance;
  final ValueChanged<HangarStat> onBuy;

  static IconData _icon(HangarStat s) => switch (s) {
        HangarStat.hull => Symbols.shield_rounded,
        HangarStat.cannons => Symbols.speed_rounded,
        HangarStat.capacitor => Symbols.bolt_rounded,
        HangarStat.arsenal => Symbols.rocket_launch_rounded,
        HangarStat.tractor => Symbols.attractions_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CsLabel('Permanent upgrades · every run'),
        SizedBox(height: cs(4)),
        Expanded(
          child: ListView(
            children: [
              for (final (index, def) in HangarCatalog.stats.indexed)
                entrance.wrap(index, Builder(builder: (context) {
                  final lvl = hangar.level(def.stat);
                  final maxed = lvl >= HangarCatalog.maxLevel;
                  final cost = HangarCatalog.costForNext(lvl);
                  return CsListRow(
                    title: def.name,
                    subtitle: def.perLevel,
                    leading: CsIconDisc(_icon(def.stat), color: lvl > 0 ? CsColors.gold : CsColors.ink60),
                    // A purchase fills the new segment, rolls the level and
                    // pops the bar.
                    below: CsPop(
                      trigger: bought[def.stat] ?? 0,
                      peak: 1.06,
                      alignment: Alignment.centerLeft,
                      child: Row(children: [
                        for (var i = 0; i < HangarCatalog.maxLevel; i++) ...[
                          if (i > 0) SizedBox(width: cs(4)),
                          _LevelSegment(width: cs(22), filled: i < lvl),
                        ],
                        SizedBox(width: cs(8)),
                        CsOdometer(
                          value: lvl,
                          format: (v) => 'L$v / ${HangarCatalog.maxLevel}',
                          style: t.mono(9, color: CsColors.ink45),
                        ),
                      ]),
                    ),
                    trailing: maxed
                        ? const CsChip('Max', kind: CsChipKind.mint)
                        : _PriceButton(
                            cost: cost,
                            missing: cost - balance,
                            loading: buying == def.stat,
                            onPressed: buying == null ? () => onBuy(def.stat) : null,
                          ),
                  );
                })),
            ],
          ),
        ),
      ],
    );
  }
}

/// Credit price for an upgrade: an outlined pill with the gold coin and the
/// shared numeric style. Short of credits it dims (reads as unavailable) and
/// shows "Need N more" under it, but stays tappable so the tap can route to
/// the Credits tab.
class _PriceButton extends StatelessWidget {
  const _PriceButton({required this.cost, required this.missing, required this.loading, required this.onPressed});
  final int cost;
  final int missing;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final short = missing > 0;
    final pill = Opacity(
      opacity: short || (onPressed == null && !loading) ? 0.45 : 1,
      child: CsPressable(
        onTap: loading ? null : onPressed,
        semanticLabel: short ? '$cost credits, need $missing more' : 'Upgrade for $cost credits',
        child: Container(
          constraints: BoxConstraints(minHeight: cs(34).clamp(34.0, 44.0)),
          padding: EdgeInsets.symmetric(horizontal: cs(14)),
          decoration: const ShapeDecoration(
            shape: StadiumBorder(side: BorderSide(color: CsColors.lineStrong)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (loading)
              SizedBox.square(
                dimension: cs(14),
                child: const CircularProgressIndicator(strokeWidth: 2, color: CsColors.ink),
              )
            else
              const CsCoinGlyph(size: 16),
            SizedBox(width: cs(8)),
            // Rolls to the next level's price after a purchase.
            CsOdometer(value: cost, format: (v) => '$v', style: t.number(14, em: 0, height: 1)),
          ]),
        ),
      ),
    );
    if (!short) return pill;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        pill,
        SizedBox(height: cs(4)),
        ExcludeSemantics(
          child: Text('Need $missing more', maxLines: 1, style: t.mono(10, color: CsColors.ink70, em: 0.04)),
        ),
      ],
    );
  }
}

/// One segment of an upgrade's level bar. Filling sweeps the prism in from
/// the left (a scaleX transform, no relayout); it starts filled on first
/// build, so only real changes animate.
class _LevelSegment extends StatelessWidget {
  const _LevelSegment({required this.width, required this.filled});
  final double width;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 3,
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: CsColors.track),
        TweenAnimationBuilder<double>(
          tween: Tween(end: filled ? 1 : 0),
          duration: CsReduceMotion.duration(context, CsMotion.gentle),
          curve: CsMotion.easeOutSoft,
          child: const DecoratedBox(decoration: BoxDecoration(gradient: CsGradients.prism)),
          builder: (context, v, child) => v == 0
              ? const SizedBox.shrink()
              : Transform(
                  alignment: Alignment.centerLeft,
                  transform: Matrix4.diagonal3Values(v, 1, 1),
                  child: child,
                ),
        ),
      ]),
    );
  }
}
