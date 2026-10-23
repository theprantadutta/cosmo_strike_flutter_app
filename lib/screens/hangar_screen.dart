import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../game/hangar.dart';
import '../game/run_upgrades.dart';
import '../presentation/bloc/coins/coins_cubit.dart';
import '../router/routes.dart';
import '../services/hangar_service.dart';
import '../ui/cs.dart';
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
    if (!context.read<CoinsCubit>().canAfford(cost)) {
      showCsToast(context, 'Not enough credits. $cost CR needed.', kind: CsToastKind.error);
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
    setState(() => _buying = null);
    showCsToast(
      context,
      done ? '${def.name} upgraded to L$next.' : 'Upgrade failed. Try again.',
      kind: done ? CsToastKind.success : CsToastKind.error,
    );
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
        left: _ShipList(hangar: _hangar),
        right: _UpgradeList(hangar: _hangar, buying: _buying, onBuy: _buy),
      ),
    );
  }
}

class _ShipList extends StatelessWidget {
  const _ShipList({required this.hangar});
  final HangarService hangar;

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
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CsHeadline([selected.name], prismIndex: 0, maxLines: 1, style: t.display(36, em: -0.03, height: 1)),
        ),
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
              return CsTile(
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
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UpgradeList extends StatelessWidget {
  const _UpgradeList({required this.hangar, required this.buying, required this.onBuy});
  final HangarService hangar;
  final HangarStat? buying;
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
              for (final def in HangarCatalog.stats)
                Builder(builder: (context) {
                  final lvl = hangar.level(def.stat);
                  final maxed = lvl >= HangarCatalog.maxLevel;
                  final cost = HangarCatalog.costForNext(lvl);
                  return CsListRow(
                    title: def.name,
                    subtitle: def.perLevel,
                    leading: CsIconDisc(_icon(def.stat), color: lvl > 0 ? CsColors.gold : CsColors.ink60),
                    below: Row(children: [
                      for (var i = 0; i < HangarCatalog.maxLevel; i++) ...[
                        if (i > 0) SizedBox(width: cs(4)),
                        Container(
                          width: cs(22),
                          height: 3,
                          decoration: BoxDecoration(
                            color: i < lvl ? null : CsColors.track,
                            gradient: i < lvl ? CsGradients.prism : null,
                          ),
                        ),
                      ],
                      SizedBox(width: cs(8)),
                      Text('L$lvl / ${HangarCatalog.maxLevel}', style: t.mono(9, color: CsColors.ink45)),
                    ]),
                    trailing: maxed
                        ? const CsChip('Max', kind: CsChipKind.mint)
                        : CsButton.secondary(
                            label: '$cost',
                            size: CsButtonSize.small,
                            icon: Symbols.paid_rounded,
                            loading: buying == def.stat,
                            onPressed: buying == null ? () => onBuy(def.stat) : null,
                          ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}
