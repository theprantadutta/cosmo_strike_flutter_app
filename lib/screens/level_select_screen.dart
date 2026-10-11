import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../data/database/app_database.dart';
import '../router/routes.dart';
import '../services/audio_service.dart';
import '../ui/cs.dart';
import '../utils/campaign_catalog.dart';

/// Campaign level select (Prism Noir, mock 06).
///
/// Top bar: CAMPAIGN · ★ stars / total · CLEARED n / 12.
/// Upper-left: the four sectors (biomes) as big Syne type — the selected one
/// at full ink, the others fading by distance (30% / 15%). Tapping a sector
/// selects its furthest playable level. Upper-right: planet, selected level
/// name + stars + mono meta (best, time, par) and the white CONTINUE pill.
/// Bottom: all 12 level tiles in one row, grouped by sector — done = bordered
/// tile with gold stars, next = prism ring + "NEXT →", locked = lock at 25%.
///
/// Data: a single Drift watch on StageProgressDao — offline-first, always
/// live (a finished run updates the tiles the moment it persists).
class LevelSelectScreen extends StatefulWidget {
  const LevelSelectScreen({super.key});

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  int? _selected;
  bool _autoSelected = false;

  late final Stream<List<StageProgressRow>> _stream = GetIt.I<AppDatabase>()
      .stageProgressDao
      .watchAll();

  void _launch(int level) {
    AudioService().playSound('button_click');
    context.push(AppRoutes.playLoading, extra: level);
  }

  static bool _isUnlocked(Map<int, StageProgressRow> byStage, int level) =>
      byStage[level]?.unlocked ?? (level == 1);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StageProgressRow>>(
      stream: _stream,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <StageProgressRow>[];
        final byStage = {for (final r in rows) r.stageId: r};

        // Furthest unlocked level — the default selection, so the CTA is
        // "continue" out of the box.
        var furthest = 1;
        for (final r in rows) {
          if (r.unlocked && r.stageId > furthest) furthest = r.stageId;
        }
        if (!_autoSelected && rows.isNotEmpty) {
          _autoSelected = true;
          _selected = furthest;
        }
        final selected = (_selected ?? 1).clamp(1, CampaignCatalog.totalLevels);
        final selectedBiome = (selected - 1) ~/ CampaignCatalog.levelsPerBiome;

        final clearedCount = rows.where((r) => r.cleared).length;
        final totalStars = rows.fold<int>(0, (sum, r) => sum + r.stars);

        final selRow = byStage[selected];
        final selUnlocked = _isUnlocked(byStage, selected);
        final selCleared = selRow?.cleared ?? false;
        final launchLabel = !selUnlocked
            ? 'Locked'
            : (selected == furthest && !selCleared ? 'Continue' : 'Launch');

        void selectBiome(int b) {
          // Show the sector's furthest playable level (or its first level
          // when the whole sector is still locked → "clear N to unlock").
          final first = b * CampaignCatalog.levelsPerBiome + 1;
          var pick = first;
          for (var l = first; l < first + CampaignCatalog.levelsPerBiome; l++) {
            if (_isUnlocked(byStage, l)) pick = l;
          }
          AudioService().playSound('button_click');
          setState(() => _selected = pick);
        }

        void onLevelTap(int level) {
          // Tap-to-play: an unlocked tile launches straight into that level.
          // A locked tile just selects, so the side panel shows the
          // "clear N to unlock" hint.
          if (_isUnlocked(byStage, level)) {
            _launch(level);
          } else {
            setState(() => _selected = level);
          }
        }

        final cs = context.cs;
        return CsScaffold(
          title: 'Campaign',
          washes: const [CsWash.violetTopRight],
          trailing: [
            CsMeta(
              '${_pad(totalStars)} / ${CampaignCatalog.totalStars}',
              icon: Symbols.star_rounded,
            ),
            CsMeta(
              'Cleared ${_pad(clearedCount)} / ${_pad(CampaignCatalog.totalLevels)}',
            ),
          ],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _SectorList(
                        selectedBiome: selectedBiome,
                        byStage: byStage,
                        onSelect: selectBiome,
                      ),
                    ),
                    SizedBox(width: cs(24)),
                    SizedBox(
                      width: cs(cs.isTablet ? 300 : 260),
                      child: _LevelPanel(
                        level: selected,
                        row: selRow,
                        unlocked: selUnlocked,
                        cta: CsButton.primary(
                          label: launchLabel,
                          trailingIcon: selUnlocked
                              ? Symbols.arrow_forward_rounded
                              : Symbols.lock_rounded,
                          onPressed: selUnlocked
                              ? () => _launch(selected)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: cs(14)),
              _LevelRow(
                byStage: byStage,
                selected: selected,
                furthest: furthest,
                selectedBiome: selectedBiome,
                onTap: onLevelTap,
                onLongPress: (l) => setState(() => _selected = l),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _pad(int n) => n.toString().padLeft(2, '0');

String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

String _time(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

String _thousands(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// The four sectors as big editorial type. Opacity fades with distance from
/// the selected sector (100 / 30 / 15%). Never scrolls — scales down to fit.
class _SectorList extends StatelessWidget {
  const _SectorList({
    required this.selectedBiome,
    required this.byStage,
    required this.onSelect,
  });

  final int selectedBiome;
  final Map<int, StageProgressRow> byStage;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final nameStyle = t.display(cs.isTablet ? 44 : 36, em: -0.03, height: 1.05);
    const per = CampaignCatalog.levelsPerBiome;

    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var b = 0; b < CampaignCatalog.biomeIds.length; b++)
              Builder(
                builder: (context) {
                  final first = b * per + 1;
                  var stars = 0;
                  for (var l = first; l < first + per; l++) {
                    stars += byStage[l]?.stars ?? 0;
                  }
                  final distance = (b - selectedBiome).abs();
                  final opacity = distance == 0
                      ? 1.0
                      : (distance == 1 ? 0.3 : 0.15);
                  final isSel = distance == 0;
                  return CsPressable(
                    onTap: () => onSelect(b),
                    semanticLabel:
                        CampaignCatalog.biomeNames[CampaignCatalog.biomeIds[b]],
                    child: AnimatedOpacity(
                      opacity: opacity,
                      duration: CsMotion.base,
                      curve: CsMotion.standard,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: cs(2)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            SizedBox(
                              width: cs(30),
                              child: Text(
                                _pad(b + 1),
                                style: t.mono(
                                  11,
                                  color: isSel ? CsColors.ink55 : CsColors.ink,
                                ),
                              ),
                            ),
                            Text(
                              _titleCase(
                                CampaignCatalog.biomeNames[CampaignCatalog
                                    .biomeIds[b]]!,
                              ),
                              maxLines: 1,
                              style: nameStyle,
                            ),
                            SizedBox(width: cs(14)),
                            Text(
                              '$stars/${per * 3}',
                              style: t.mono(
                                11,
                                em: 0.04,
                                color: isSel ? CsColors.gold : CsColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Right column: planet, selected level name/stars/meta (scales down, never
/// scrolls) and the primary pill kept at full size beneath it.
class _LevelPanel extends StatelessWidget {
  const _LevelPanel({
    required this.level,
    required this.row,
    required this.unlocked,
    required this.cta,
  });

  final int level;
  final StageProgressRow? row;
  final bool unlocked;
  final Widget cta;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final stars = row?.stars ?? 0;
    final best = row?.bestScore ?? 0;
    final bestTime = row?.bestTimeSeconds ?? 0;
    final meta = t.mono(11, color: CsColors.ink55);

    final metaLine = [
      'LEVEL ${_pad(level)}',
      if (unlocked) 'BEST ${best > 0 ? _thousands(best) : '—'}',
      if (unlocked) 'TIME ${bestTime > 0 ? _time(bestTime) : '—'}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // The planet takes whatever height the text doesn't need, so on
              // short phones the level details stay full size instead of the
              // whole column being scaled down to fit a fixed-size planet.
              final planet = (box.maxHeight - cs(118)).clamp(
                0.0,
                cs(cs.isTablet ? 132 : 100),
              );
              return CsFitColumn(
                alignment: Alignment.centerRight,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (planet >= cs(36)) ...[
                    CsPlanet(size: planet, dim: !unlocked),
                    SizedBox(height: cs(14)),
                  ],
                  Text(
                    _titleCase(CampaignCatalog.levelNameFor(level)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: t.display(
                      22,
                      em: -0.02,
                      height: 1.1,
                      color: unlocked ? CsColors.ink : CsColors.ink45,
                    ),
                  ),
                  SizedBox(height: cs(8)),
                  CsStars(stars, size: 14),
                  SizedBox(height: cs(10)),
                  Text(
                    metaLine,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta,
                  ),
                  SizedBox(height: cs(6)),
                  if (unlocked) ...[
                    Text(
                      'PAR ${_time(CampaignCatalog.parTimeSeconds(level))} · ${_thousands(CampaignCatalog.parScore(level))} PTS',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: t.mono(10, color: CsColors.ink30),
                    ),
                    if (row?.clearedNoHit ?? false) ...[
                      SizedBox(height: cs(6)),
                      Text(
                        'NO-HIT CLEAR',
                        style: t.mono(10, color: CsColors.mint),
                      ),
                    ],
                  ] else
                    Text(
                      'CLEAR LEVEL ${_pad(level - 1)} TO UNLOCK',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: t.mono(10, color: CsColors.pink),
                    ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: cs(12)),
        cta,
      ],
    );
  }
}

/// All 12 levels in one row, grouped by sector (wider gap between sectors;
/// the selected sector's group carries a brighter top rule).
class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.byStage,
    required this.selected,
    required this.furthest,
    required this.selectedBiome,
    required this.onTap,
    required this.onLongPress,
  });

  final Map<int, StageProgressRow> byStage;
  final int selected;
  final int furthest;
  final int selectedBiome;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    const per = CampaignCatalog.levelsPerBiome;
    final tileH = cs(cs.isTablet ? 100 : 84).clamp(56.0, 140.0);
    final gap = cs(8);
    final groupGap = cs(18);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var b = 0; b < CampaignCatalog.biomeIds.length; b++) ...[
          if (b > 0) SizedBox(width: groupGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: CsMotion.base,
                  curve: CsMotion.standard,
                  height: b == selectedBiome ? 2 : 1,
                  color: b == selectedBiome
                      ? CsColors.ink60
                      : CsColors.hairline,
                ),
                SizedBox(height: cs(12)),
                SizedBox(
                  height: tileH,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < per; i++) ...[
                        if (i > 0) SizedBox(width: gap),
                        Expanded(
                          child: _LevelTile(
                            level: b * per + i + 1,
                            row: byStage[b * per + i + 1],
                            isSelected: b * per + i + 1 == selected,
                            isNext: b * per + i + 1 == furthest,
                            onTap: () => onTap(b * per + i + 1),
                            onLongPress: () => onLongPress(b * per + i + 1),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.level,
    required this.row,
    required this.isSelected,
    required this.isNext,
    required this.onTap,
    required this.onLongPress,
  });

  final int level;
  final StageProgressRow? row;
  final bool isSelected;
  final bool isNext;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final unlocked = row?.unlocked ?? (level == 1);
    final cleared = row?.cleared ?? false;
    final stars = row?.stars ?? 0;
    final current = isNext && unlocked && !cleared;

    final state = current
        ? CsTileState.current
        : isSelected
        ? CsTileState.selected
        : !unlocked
        ? CsTileState.locked
        : cleared
        ? CsTileState.done
        : CsTileState.future;

    final numColor = !unlocked
        ? CsColors.ink25
        : (current || isSelected ? CsColors.ink : CsColors.ink60);

    final Widget foot;
    if (!unlocked) {
      foot = Icon(Symbols.lock_rounded, size: cs(16), color: CsColors.ink25);
    } else if (current) {
      foot = Text(
        'NEXT →',
        maxLines: 1,
        style: t.display(10, weight: FontWeight.w700, em: 0.12, height: 1),
      );
    } else if (cleared) {
      foot = CsStars(stars, size: 12);
    } else {
      foot = Icon(
        Symbols.play_arrow_rounded,
        size: cs(16),
        color: CsColors.ink45,
      );
    }

    return CsPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: 'Level $level${unlocked ? '' : ', locked'}',
      child: CsTile(
        state: state,
        rotateRing: current,
        padding: EdgeInsets.all(cs(9)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _pad(level),
              maxLines: 1,
              style: t.mono(11, em: 0.04, color: numColor),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomLeft,
              child: foot,
            ),
          ],
        ),
      ),
    );
  }
}
