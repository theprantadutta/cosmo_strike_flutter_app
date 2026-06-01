import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/models/game_replay.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';
import 'package:cosmo_strike_flutter_app/widgets/app_background.dart';
import 'package:cosmo_strike_flutter_app/widgets/themed_loading.dart';

class ReplaysScreen extends StatefulWidget {
  const ReplaysScreen({super.key});

  @override
  State<ReplaysScreen> createState() => _ReplaysScreenState();
}

class _ReplaysScreenState extends State<ReplaysScreen>
    with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  List<GameReplay> _replays = [];
  bool _isLoading = true;
  late TabController _tabController;
  StreamSubscription<List<GameReplay>>? _replaysSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _subscribeToReplays();
  }

  @override
  void dispose() {
    _replaysSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  /// Subscribe to Drift's reactive replay stream. Every save (from the
  /// game-over flow) and every delete (from sanitize / the trash icon)
  /// emits a new list, so the screen is always live — no manual refresh
  /// needed. Previous code held an AppDataCache snapshot of replay keys
  /// taken at app launch, which is why fresh games weren't appearing.
  void _subscribeToReplays() {
    _replaysSub = _storageService.watchReplays().listen(
      (replays) {
        if (!mounted) return;
        // Sanitize empty-frame rows in the background — they shouldn't
        // exist in the fresh write path, but a historical bug let them
        // accumulate. Schedule deletes off the stream callback so the
        // delete-then-watch-re-emits loop is well-behaved.
        final bad = replays
            .where((r) => r.frames.isEmpty || r.totalFrames == 0)
            .map((r) => r.id)
            .toList();
        // Purge the bad rows in the background, but DON'T skip the render —
        // show the valid replays immediately. If a delete ever fails the
        // bad rows would re-emit forever, and the old early-return left the
        // screen stuck on the loading spinner.
        for (final id in bad) {
          unawaited(_storageService.deleteReplay(id));
        }
        final sorted = [
          for (final r in replays)
            if (r.frames.isNotEmpty && r.totalFrames != 0) r,
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        setState(() {
          _replays = sorted;
          _isLoading = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
      },
    );
  }

  // Tab views — no .take() cap because GameDao's saveReplay retention
  // already caps storage at top-10-by-score + 10-most-recent (~20 rows),
  // so a manual cap here would just hide rows the user actually has.
  List<GameReplay> get _recentReplays => _replays;

  List<GameReplay> get _highScoreReplays {
    final sorted = [..._replays];
    sorted.sort((a, b) => b.finalScore.compareTo(a.finalScore));
    return sorted;
  }

  List<GameReplay> get _crashReplays =>
      _replays.where((r) => r.crashReason != null).toList();

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final theme = themeState.currentTheme;

    return Scaffold(
      bottomNavigationBar: const SnakeBannerAd(),
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Game Replays',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
            ),
            if (!_isLoading && _replays.isNotEmpty) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.accentColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.accentColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '${_replays.length}',
                  style: TextStyle(
                    color: theme.accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.primaryColor),
          onPressed: () => context.pop(),
        ),
        // No refresh button: the screen subscribes to Drift's reactive
        // replay stream, so the list updates the instant a row changes.
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.accentColor,
          labelColor: theme.accentColor,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
          tabs: const [
            Tab(text: 'Recent'),
            Tab(text: 'Best'),
            Tab(text: 'Crashes'),
          ],
        ),
      ),
      body: AppBackground(
        theme: theme,
        child: _isLoading
            ? ThemedLoading(theme: theme, label: 'Loading replays...')
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildReplayList(_recentReplays, 'No recent replays', theme),
                  _buildReplayList(
                    _highScoreReplays,
                    'No high-score replays',
                    theme,
                  ),
                  _buildReplayList(_crashReplays, 'No crash replays', theme),
                ],
              ),
      ),
    );
  }

  Widget _buildReplayList(
    List<GameReplay> replays,
    String emptyMessage,
    GameTheme theme,
  ) {
    if (replays.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam_off,
              size: 80,
              color: theme.primaryColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Play some games to generate replays!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: replays.length,
      itemBuilder: (context, index) {
        final replay = replays[index];
        return _buildReplayCard(replay, theme);
      },
    );
  }

  Widget _buildReplayCard(GameReplay replay, GameTheme theme) {
    final summary = replay.getSummary();

    return Card(
      color: theme.primaryColor.withValues(alpha: 0.1),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: () {
          getIt<AnalyticsFacade>().trackReplayViewed();
          context.push(AppRoutes.replayViewerPath(replay.id), extra: replay);
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        replay.playerName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        _formatDate(replay.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: replay.crashReason != null
                          ? Colors.red.withValues(alpha: 0.2)
                          : Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      summary['outcome'],
                      style: TextStyle(
                        color: replay.crashReason != null
                            ? Colors.red
                            : Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Score and stats
              Row(
                children: [
                  Expanded(
                    child: _buildStatChip(
                      'Score',
                      replay.finalScore.toString(),
                      Icons.stars,
                      Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      'Duration',
                      summary['duration'],
                      Icons.timer,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      'Kills',
                      summary['foodConsumed'].toString(),
                      Icons.fastfood,
                      Colors.orange,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: _buildStatChip(
                      'Frames',
                      replay.totalFrames.toString(),
                      Icons.movie,
                      Colors.purple,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      'Best Stage',
                      summary['maxLength'].toString(),
                      Icons.straighten,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatChip(
                      'Power-ups',
                      summary['powerUpsCollected'].toString(),
                      Icons.flash_on,
                      Colors.yellow,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.push(AppRoutes.replayViewerPath(replay.id), extra: replay),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Watch'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accentColor.withValues(
                          alpha: 0.8,
                        ),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _deleteReplay(replay),
                    icon: const Icon(Icons.delete),
                    color: Colors.red,
                    iconSize: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  Future<void> _deleteReplay(GameReplay replay) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Replay'),
        content: Text('Delete replay from ${_formatDate(replay.createdAt)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Drift watch re-emits automatically — no manual reload.
        await _storageService.deleteReplay(replay.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Replay deleted')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete replay')),
          );
        }
      }
    }
  }
}
