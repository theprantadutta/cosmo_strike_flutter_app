import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cosmo_strike_flutter_app/models/game_replay.dart';
import 'package:cosmo_strike_flutter_app/router/routes.dart';
import 'package:cosmo_strike_flutter_app/widgets/ads/banner_ad_widget.dart';
import 'package:cosmo_strike_flutter_app/core/di/injection.dart';
import 'package:cosmo_strike_flutter_app/services/analytics/analytics_facade.dart';
import 'package:cosmo_strike_flutter_app/services/storage_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart' show GameMode;

enum _ReplayTab { recent, best, crashes }

class ReplaysScreen extends StatefulWidget {
  const ReplaysScreen({super.key});

  @override
  State<ReplaysScreen> createState() => _ReplaysScreenState();
}

class _ReplaysScreenState extends State<ReplaysScreen> {
  final StorageService _storageService = StorageService();
  List<GameReplay> _replays = [];
  bool _isLoading = true;
  _ReplayTab _tab = _ReplayTab.recent;
  StreamSubscription<List<GameReplay>>? _replaysSub;

  @override
  void initState() {
    super.initState();
    _subscribeToReplays();
  }

  @override
  void dispose() {
    _replaysSub?.cancel();
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

  List<GameReplay> get _crashReplays => _replays.where((r) => r.crashReason != null).toList();

  @override
  Widget build(BuildContext context) {
    return CsScaffold(
      title: 'Flight Recorder',
      washes: const [CsWash.violetTopRight],
      trailing: [
        if (!_isLoading && _replays.isNotEmpty) CsMeta('${_replays.length} saved'),
      ],
      // No refresh button: the screen subscribes to Drift's reactive
      // replay stream, so the list updates the instant a row changes.
      body: CsSplit(
        // Inline banner in the summary column (no full-width banners).
        leftFooter: ColumnBannerAd(maxHeight: context.cs.isTablet ? 100 : 60),
        left: _buildSummary(context),
        right: _isLoading ? const CsLoadingState(label: 'Loading recordings') : _buildList(context),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final cs = context.cs;
    final t = cs.type;
    final best = _replays.isEmpty
        ? 0
        : _replays.map((r) => r.finalScore).reduce((a, b) => a > b ? a : b);
    return CsFitColumn(
      alignment: Alignment.centerLeft,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: CsSegmented<_ReplayTab>(
            segments: const {
              _ReplayTab.recent: 'Recent',
              _ReplayTab.best: 'Best',
              _ReplayTab.crashes: 'Lost',
            },
            selected: _tab,
            onChanged: (v) => setState(() => _tab = v),
          ),
        ),
        SizedBox(height: cs(28)),
        const CsLabel('Best recording'),
        SizedBox(height: cs(8)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_formatScore(best), maxLines: 1, style: t.display(64, em: -0.04, height: 0.95)),
        ),
        SizedBox(height: cs(12)),
        Text(
          '${_replays.length} SAVED · ${_crashReplays.length} SHIPS LOST',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.label,
        ),
        SizedBox(height: cs(18)),
        Text('Tap a run to review it frame by frame.', style: t.body),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final (List<GameReplay> list, String empty) = switch (_tab) {
      _ReplayTab.recent => (_recentReplays, 'No recent recordings'),
      _ReplayTab.best => (_highScoreReplays, 'No high-score recordings'),
      _ReplayTab.crashes => (_crashReplays, 'No lost-ship recordings'),
    };
    return AnimatedSwitcher(
      duration: CsMotion.base,
      switchInCurve: CsMotion.standard,
      child: KeyedSubtree(
        key: ValueKey(_tab),
        child: list.isEmpty
            ? CsEmptyState(
                icon: Symbols.videocam_off_rounded,
                title: empty,
                message: 'Fly a run. The recorder logs it automatically.',
              )
            : ListView.builder(
                padding: EdgeInsets.only(bottom: context.cs(12)),
                itemCount: list.length,
                itemBuilder: (context, i) => _buildReplayRow(context, list[i], first: i == 0),
              ),
      ),
    );
  }

  Widget _buildReplayRow(BuildContext context, GameReplay replay, {required bool first}) {
    final cs = context.cs;
    final t = cs.type;
    final summary = replay.getSummary();
    final crashed = replay.crashReason != null;

    void open() {
      getIt<AnalyticsFacade>().trackReplayViewed();
      context.push(AppRoutes.replayViewerPath(replay.id), extra: replay);
    }

    final meta = [
      _formatDate(replay.createdAt).toUpperCase(),
      '${summary['duration']}',
      '${summary['kills']} KILLS',
      '${replay.totalFrames} FRAMES',
      '${summary['powerUpsCollected']} PWR',
    ].join(' · ');

    return CsPressable(
      onTap: open,
      scale: 0.99,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: EdgeInsets.symmetric(vertical: cs(12)),
        decoration: BoxDecoration(
          border: Border(
            top: first ? const BorderSide(color: CsColors.hairline) : BorderSide.none,
            bottom: const BorderSide(color: CsColors.hairline),
          ),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _formatScore(replay.finalScore),
                      maxLines: 1,
                      style: t.display(24, em: -0.02, height: 1),
                    ),
                  ),
                ),
                SizedBox(width: cs(10)),
                Flexible(
                  flex: 2,
                  child: Text(
                    replay.playerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.mono(10, color: CsColors.ink45),
                  ),
                ),
              ]),
              SizedBox(height: cs(6)),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.micro),
              SizedBox(height: cs(8)),
              Wrap(spacing: cs(6), runSpacing: cs(6), children: [
                CsChip('${summary['outcome']}', kind: crashed ? CsChipKind.pink : CsChipKind.mint),
                CsChip('Stage ${summary['maxLength']}'),
                if (replay.gameMode.isNotEmpty) CsChip(_prettyMode(replay.gameMode)),
              ]),
            ]),
          ),
          SizedBox(width: cs(12)),
          CsButton.secondary(
            label: 'Watch',
            icon: Symbols.play_arrow_rounded,
            size: CsButtonSize.small,
            onPressed: () => context.push(AppRoutes.replayViewerPath(replay.id), extra: replay),
          ),
          SizedBox(width: cs(4)),
          CsIconButton(
            icon: Symbols.delete_rounded,
            bordered: false,
            color: CsColors.pink,
            size: 36,
            tooltip: 'Delete recording',
            onPressed: () => _deleteReplay(replay),
          ),
        ]),
      ),
    );
  }

  String _prettyMode(String raw) => GameMode.fromWire(raw).name;

  String _formatScore(int v) {
    final s = v.abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
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
    final confirmed = await showCsConfirm(
      context,
      eyebrow: 'Flight Recorder',
      title: 'Delete recording?',
      message: 'Delete the recording from ${_formatDate(replay.createdAt)}?',
      confirmLabel: 'Delete',
      destructive: true,
    );

    if (confirmed) {
      try {
        // Drift watch re-emits automatically — no manual reload.
        await _storageService.deleteReplay(replay.id);
        if (mounted) {
          showCsToast(context, 'Recording deleted.', kind: CsToastKind.success);
        }
      } catch (e) {
        if (mounted) {
          showCsToast(context, 'Delete failed. Try again.', kind: CsToastKind.error);
        }
      }
    }
  }
}
