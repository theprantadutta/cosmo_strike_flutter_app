import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/models/achievement.dart';
import 'package:cosmo_strike_flutter_app/services/achievement_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';

enum _AwardFilter { all, unlocked, locked }

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final AchievementService _achievementService = AchievementService();
  _AwardFilter _filter = _AwardFilter.all;

  @override
  void initState() {
    super.initState();
    _achievementService.addListener(_onAchievementsChanged);
  }

  @override
  void dispose() {
    _achievementService.removeListener(_onAchievementsChanged);
    super.dispose();
  }

  void _onAchievementsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<Achievement> get _visible => switch (_filter) {
        _AwardFilter.all => _achievementService.achievements,
        _AwardFilter.unlocked => _achievementService.getUnlockedAchievements(),
        _AwardFilter.locked => _achievementService.getLockedAchievements(),
      };

  @override
  Widget build(BuildContext context) {
    final all = _achievementService.achievements;
    final unlocked = all.where((a) => a.isUnlocked).length;
    return CsScaffold(
      title: 'Achievements',
      washes: const [CsWash.goldTopRight],
      trailing: [CsMeta('$unlocked / ${all.length} unlocked')],
      body: CsSplit(
        // Inline banner in the summary column (no full-width banners).
        leftFooter: ColumnBannerAd(maxHeight: context.cs.isTablet ? 100 : 60),
        left: _buildSummary(context),
        right: _buildGridColumn(context),
      ),
    );
  }

  /// LEFT: completion ring + claimed/pending readout + points.
  /// Stat counts use the same logic as the dashboard's AchievementsGrid.
  Widget _buildSummary(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final all = _achievementService.achievements;
    final total = all.length;
    final unlocked = all.where((a) => a.isUnlocked).length;
    final claimed = all.where((a) => a.rewardClaimed).length;
    final pending = all.where((a) => !a.isUnlocked).length;
    final completion = _achievementService.completionPercentage;
    final pct = (completion * 100).round();
    final points = _achievementService.totalAchievementPoints;

    return CsFitColumn(
      alignment: Alignment.centerLeft,
      children: [
        CsRingProgress(
          value: completion,
          size: cs(cs.isTablet ? 150 : 128),
          stroke: 3,
          // Scale down to fit the ring: "28/114" overflowed and was clipped
          // to "28/11" on phones.
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: cs(14)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$unlocked/$total', maxLines: 1, style: t.display(28, em: -0.03, height: 1)),
                SizedBox(height: cs(4)),
                Text('UNLOCKED', style: t.micro),
              ]),
            ),
          ),
        ),
        SizedBox(height: cs(22)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Your awards', maxLines: 1, style: t.display(36, em: -0.04, height: 1)),
        ),
        SizedBox(height: cs(10)),
        Text('$pct% COMPLETE', style: t.mono(11, color: CsColors.ink)),
        SizedBox(height: cs(6)),
        Text('$claimed CLAIMED · $pending PENDING', style: t.label),
        SizedBox(height: cs(6)),
        Text('$points PTS', style: t.mono(11, color: CsColors.gold)),
      ],
    );
  }

  Widget _buildGridColumn(BuildContext context) {
    final cs = context.cs;
    final all = _achievementService.achievements;
    final unlocked = all.where((a) => a.isUnlocked).length;
    final locked = all.where((a) => !a.isUnlocked).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: CsSegmented<_AwardFilter>(
              segments: {
                _AwardFilter.all: 'All ${all.length}',
                _AwardFilter.unlocked: 'Unlocked $unlocked',
                _AwardFilter.locked: 'Locked $locked',
              },
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
        ),
        SizedBox(height: cs(14)),
        Expanded(
          child: AnimatedSwitcher(
            duration: CsMotion.base,
            switchInCurve: CsMotion.standard,
            child: KeyedSubtree(key: ValueKey(_filter), child: _buildGrid(context, _visible)),
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(BuildContext context, List<Achievement> achievements) {
    final cs = context.cs;
    if (achievements.isEmpty) {
      return const CsEmptyState(
        icon: Symbols.workspace_premium_rounded,
        title: 'No achievements here',
        compact: true,
      );
    }
    final columns = cs.isTablet ? 4 : (cs.size.width < 700 ? 2 : 3);
    return GridView.builder(
      padding: EdgeInsets.only(bottom: cs(12)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: cs(10),
        crossAxisSpacing: cs(10),
        mainAxisExtent: cs(150),
      ),
      itemCount: achievements.length,
      itemBuilder: (context, i) => _AwardTile(
        achievement: achievements[i],
        onTap: () => _showDetail(achievements[i]),
      ),
    );
  }

  void _showDetail(Achievement a) {
    final progress = a.progressPercentage;
    showCsDialog<void>(
      context,
      builder: (ctx) {
        final cs = ctx.cs;
        final t = cs.type;
        return CsDialog(
          icon: a.icon,
          iconColor: a.isUnlocked ? CsColors.gold : CsColors.ink45,
          eyebrow: '${a.rarityName} · ${a.points} pts',
          title: a.title,
          message: a.description,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!a.isUnlocked) ...[
                CsProgressLine(value: progress),
                SizedBox(height: cs(8)),
                Text('${a.currentProgress} / ${a.targetValue}', style: t.label),
                SizedBox(height: cs(14)),
              ],
              Row(children: [
                Text('+${a.xpReward} XP', style: t.mono(12, color: CsColors.xp)),
                SizedBox(width: cs(16)),
                CsCoins('+${a.coinReward}', size: 12, suffix: ' COINS'),
              ]),
              if (a.isUnlocked) ...[
                SizedBox(height: cs(14)),
                Text(
                  [
                    if (a.unlockedAt != null) 'UNLOCKED ${_formatDate(a.unlockedAt!).toUpperCase()}' else 'UNLOCKED',
                    a.rewardClaimed ? 'REWARD CLAIMED' : 'REWARD PENDING',
                  ].join(' · '),
                  style: t.mono(11, color: a.rewardClaimed ? CsColors.mint : CsColors.gold),
                ),
              ],
            ],
          ),
          actions: [CsButton.secondary(label: 'Close', onPressed: () => Navigator.of(ctx).pop())],
        );
      },
    );
  }
}

/// One award in the grid. done = unlocked & claimed, current (prism) =
/// unlocked with reward still pending, future = in progress, locked = 0%.
class _AwardTile extends StatelessWidget {
  const _AwardTile({required this.achievement, required this.onTap});
  final Achievement achievement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = achievement;
    final cs = context.cs;
    final t = cs.type;
    final progress = a.progressPercentage;
    final state = a.isUnlocked
        ? (a.rewardClaimed ? CsTileState.done : CsTileState.current)
        : (progress > 0 ? CsTileState.future : CsTileState.locked);
    final locked = state == CsTileState.locked;

    final Widget status;
    if (a.isUnlocked) {
      status = Text(
        a.rewardClaimed ? 'CLAIMED' : 'REWARD PENDING',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.mono(9, color: a.rewardClaimed ? CsColors.mint : CsColors.gold),
      );
    } else if (progress > 0) {
      status = Row(children: [
        Expanded(child: CsProgressLine(value: progress)),
        SizedBox(width: cs(8)),
        Text('${a.currentProgress}/${a.targetValue}', maxLines: 1, style: t.micro),
      ]);
    } else {
      status = Row(children: [
        Icon(Symbols.lock_rounded, size: cs(11), color: CsColors.ink45),
        SizedBox(width: cs(4)),
        Text('LOCKED', style: t.micro),
      ]);
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(a.icon, size: cs(22), color: a.isUnlocked ? CsColors.gold : CsColors.ink60),
          const Spacer(),
          Flexible(
            flex: 4,
            child: Text(
              a.rarityName.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: t.micro,
            ),
          ),
        ]),
        SizedBox(height: cs(10)),
        Expanded(
          child: Text(
            a.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.display(15, weight: FontWeight.w700, em: 0, height: 1.15),
          ),
        ),
        status,
        SizedBox(height: cs(8)),
        Row(children: [
          Text('+${a.xpReward} XP', maxLines: 1, style: t.mono(9, color: CsColors.xp)),
          SizedBox(width: cs(10)),
          Flexible(child: CsCoins('+${a.coinReward}', size: 9)),
        ]),
      ],
    );

    return CsTile(
      state: state,
      onTap: onTap,
      padding: EdgeInsets.all(cs(12)),
      child: locked ? Opacity(opacity: 0.4, child: content) : content,
    );
  }
}

String _formatDate(DateTime date) {
  final now = DateTime.now();
  final difference = now.difference(date);

  if (difference.inDays > 0) {
    return '${difference.inDays}d ago';
  } else if (difference.inHours > 0) {
    return '${difference.inHours}h ago';
  } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes}m ago';
  } else {
    return 'just now';
  }
}
