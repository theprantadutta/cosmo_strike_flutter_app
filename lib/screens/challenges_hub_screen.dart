import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/providers/daily_challenges_provider.dart';
import 'package:cosmo_strike_flutter_app/screens/daily_challenges_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/weekly_quests_screen.dart';
import 'package:cosmo_strike_flutter_app/services/weekly_quest_service.dart';
import 'package:cosmo_strike_flutter_app/ui/design.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';

/// One hub for all recurring quests: Daily | Weekly as borderless segmented
/// tabs inside a single CommandScaffold. `/daily-challenges` opens tab 0 and
/// `/weekly-quests` tab 1 — both routes land here.
class ChallengesHubScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const ChallengesHubScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<ChallengesHubScreen> createState() =>
      _ChallengesHubScreenState();
}

class _ChallengesHubScreenState extends ConsumerState<ChallengesHubScreen> {
  late int _tab = widget.initialTab.clamp(0, 1);

  Future<void> _refreshActiveTab() async {
    if (_tab == 0) {
      await ref.read(dailyChallengesProvider.notifier).refresh();
    } else {
      await WeeklyQuestService().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dailyLoading = ref.watch(dailyChallengesProvider).isLoading;

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;
        return ListenableBuilder(
          listenable: WeeklyQuestService(),
          builder: (context, _) {
            final isRefreshing = _tab == 0
                ? dailyLoading
                : WeeklyQuestService().isLoading;
            return CommandScaffold(
              theme: theme,
              title: 'Challenges',
              bottomBar: const ShipBannerAd(),
              bodyPadding: EdgeInsets.zero,
              actions: [
                IconButton(
                  icon: isRefreshing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(
                              theme.accentColor,
                            ),
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(Icons.refresh, color: theme.accentColor),
                  onPressed: isRefreshing ? null : _refreshActiveTab,
                ),
              ],
              body: Column(
                children: [
                  _SegmentedTabs(
                    theme: theme,
                    selected: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                    weeklyBadge: WeeklyQuestService().claimableCount,
                  ),
                  Expanded(
                    // IndexedStack keeps both tabs alive so switching back
                    // doesn't reload or lose scroll position.
                    child: IndexedStack(
                      index: _tab,
                      children: const [
                        DailyChallengesBody(),
                        WeeklyQuestsBody(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Borderless segmented tabs — no TabBar chrome; selection reads purely
/// through the neon text color + weight (pattern-matched to the settings
/// game-mode chips).
class _SegmentedTabs extends StatelessWidget {
  final GameTheme theme;
  final int selected;
  final ValueChanged<int> onChanged;
  final int weeklyBadge;

  const _SegmentedTabs({
    required this.theme,
    required this.selected,
    required this.onChanged,
    required this.weeklyBadge,
  });

  Widget _tab(String label, int index, {int badge = 0}) {
    final isSelected = selected == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? theme.neonPrimary : theme.textMuted,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                letterSpacing: 1.5,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.neonSecondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badge',
                  style: TextStyle(
                    color: theme.neonSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _tab('DAILY', 0),
        _tab('WEEKLY', 1, badge: weeklyBadge),
      ],
    );
  }
}
