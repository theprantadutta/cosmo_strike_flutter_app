import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cosmo_strike_flutter_app/providers/daily_challenges_provider.dart';
import 'package:cosmo_strike_flutter_app/screens/daily_challenges_screen.dart';
import 'package:cosmo_strike_flutter_app/screens/weekly_quests_screen.dart';
import 'package:cosmo_strike_flutter_app/services/weekly_quest_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';

/// One hub for all recurring quests: DAILY | WEEKLY as a segmented control in
/// the top bar of a single CsScaffold, with the active set's reset countdown
/// and a refresh button. `/daily-challenges` opens tab 0 and `/weekly-quests`
/// tab 1 — both routes land here.
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

  /// Daily sets roll over at local midnight.
  static DateTime _nextDailyReset() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1);
  }

  /// Weekly sets roll over at local Monday 00:00.
  static DateTime _nextWeeklyReset() {
    final now = DateTime.now();
    final daysToMonday = (DateTime.monday - now.weekday) % 7;
    return DateTime(now.year, now.month, now.day + (daysToMonday == 0 ? 7 : daysToMonday));
  }

  @override
  Widget build(BuildContext context) {
    final dailyLoading = ref.watch(dailyChallengesProvider).isLoading;
    final cs = context.cs;

    return ListenableBuilder(
      listenable: WeeklyQuestService(),
      builder: (context, _) {
        final weekly = WeeklyQuestService();
        final isRefreshing = _tab == 0 ? dailyLoading : weekly.isLoading;
        final weeklyBadge = weekly.claimableCount;

        return CsScaffold(
          title: 'Challenges',
          bottomBar: const ShipBannerAd(),
          trailing: [
            CsSegmented<int>(
              segments: {
                0: 'Daily',
                1: weeklyBadge > 0 ? 'Weekly · $weeklyBadge' : 'Weekly',
              },
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            _ResetCountdown(
              key: ValueKey(_tab),
              nextReset: _tab == 0 ? _nextDailyReset : _nextWeeklyReset,
              compact: cs.isCompact,
            ),
            if (isRefreshing)
              SizedBox.square(
                dimension: 44,
                child: Center(
                  child: SizedBox.square(
                    dimension: cs(18),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: CsColors.ink60,
                    ),
                  ),
                ),
              )
            else
              CsIconButton(
                icon: Symbols.refresh_rounded,
                bordered: false,
                tooltip: 'Refresh',
                onPressed: _refreshActiveTab,
              ),
          ],
          // IndexedStack keeps both tabs alive so switching back doesn't
          // reload or lose scroll position.
          body: IndexedStack(
            index: _tab,
            children: const [DailyChallengesBody(), WeeklyQuestsBody()],
          ),
        );
      },
    );
  }
}

/// Mono "RESETS IN hh:mm:ss" that ticks every second on its own, so the rest
/// of the hub never rebuilds for the clock.
class _ResetCountdown extends StatefulWidget {
  const _ResetCountdown({super.key, required this.nextReset, this.compact = false});

  final DateTime Function() nextReset;

  /// Drop the "RESETS IN" prefix on short phones (icon only).
  final bool compact;

  @override
  State<_ResetCountdown> createState() => _ResetCountdownState();
}

class _ResetCountdownState extends State<_ResetCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final days = d.inDays;
    final hms = '${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return days > 0 ? '${days}D $hms' : hms;
  }

  @override
  Widget build(BuildContext context) {
    var left = widget.nextReset().difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    final time = _format(left);
    return widget.compact
        ? CsMeta(time, icon: Symbols.schedule_rounded)
        : CsMeta('Resets in $time');
  }
}
