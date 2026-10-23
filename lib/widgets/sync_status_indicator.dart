import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cosmo_strike_flutter_app/services/connectivity_service.dart';
import 'package:cosmo_strike_flutter_app/services/data_sync_service.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

/// A subtle sync status indicator: one Material Symbol in the corner.
///
/// States (Prism Noir semantics):
/// - Online + synced: mint cloud-done glyph at reduced opacity
/// - Online + syncing: rotating cyan sync glyph
/// - Online + pending: cyan upload glyph with a count badge
/// - Failures: pink cloud-off glyph with a count badge
/// - Offline: muted cloud-off glyph
class SyncStatusIndicator extends StatefulWidget {
  final double size;
  final Color? onlineColor;
  final Color? offlineColor;
  final Color? syncingColor;
  final Color? pendingColor;

  const SyncStatusIndicator({
    super.key,
    this.size = 18,
    this.onlineColor,
    this.offlineColor,
    this.syncingColor,
    this.pendingColor,
  });

  @override
  State<SyncStatusIndicator> createState() => _SyncStatusIndicatorState();
}

class _SyncStatusIndicatorState extends State<SyncStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _spinController;
  final ConnectivityService _connectivityService = ConnectivityService();
  final DataSyncService _dataSyncService = DataSyncService();

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _dataSyncService,
      child: Consumer<DataSyncService>(
        builder: (context, syncService, child) {
          return ListenableBuilder(
            listenable: _connectivityService,
            builder: (context, child) {
              return _buildIndicator(context, syncService);
            },
          );
        },
      ),
    );
  }

  Widget _buildIndicator(BuildContext context, DataSyncService syncService) {
    final cs = context.cs;
    final isOnline = _connectivityService.isOnline;
    final syncStatus = syncService.syncStatus;
    final pendingCount = syncService.pendingCount;
    final failedCount = syncService.failedCount;

    // Spin only while a sync is actually running.
    if (syncStatus == SyncStatus.syncing) {
      _spinController.repeat();
    } else {
      _spinController.stop();
    }

    IconData icon;
    Color color;
    Widget? badge;

    if (!isOnline) {
      icon = Symbols.cloud_off_rounded;
      color = widget.offlineColor ?? CsColors.ink45;
    } else if (syncStatus == SyncStatus.syncing) {
      icon = Symbols.sync_rounded;
      color = widget.syncingColor ?? CsColors.cyan;
    } else if (failedCount > 0) {
      icon = Symbols.cloud_off_rounded;
      color = CsColors.pink;
      badge = _buildBadge(context, failedCount, CsColors.pink);
    } else if (pendingCount > 0) {
      icon = Symbols.cloud_upload_rounded;
      color = widget.pendingColor ?? CsColors.cyan;
      badge = _buildBadge(context, pendingCount, CsColors.cyan);
    } else {
      icon = Symbols.cloud_done_rounded;
      color = widget.onlineColor ?? CsColors.mint.withValues(alpha: 0.7);
    }

    final iconSize = cs(widget.size);
    return Tooltip(
      message: _getTooltipMessage(
        isOnline,
        syncStatus,
        pendingCount,
        failedCount,
      ),
      child: SizedBox(
        width: iconSize + cs(8),
        height: iconSize + cs(8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (syncStatus == SyncStatus.syncing)
              RotationTransition(
                turns: _spinController,
                child: Icon(icon, size: iconSize, color: color),
              )
            else
              Icon(icon, size: iconSize, color: color),
            if (badge != null) Positioned(top: 0, right: 0, child: badge),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context, int count, Color color) {
    final cs = context.cs;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: cs(3), vertical: cs(1)),
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      constraints: BoxConstraints(minWidth: cs(12), minHeight: cs(12)),
      alignment: Alignment.center,
      child: Text(
        count > 9 ? '9+' : count.toString(),
        style: cs.type.mono(7, color: CsColors.onLight, weight: FontWeight.w600, em: 0, height: 1.1),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _getTooltipMessage(
    bool isOnline,
    SyncStatus status,
    int pendingCount,
    int failedCount,
  ) {
    if (!isOnline) {
      return 'Offline. Changes sync on reconnect';
    }

    switch (status) {
      case SyncStatus.syncing:
        return 'Syncing...';
      case SyncStatus.synced:
        return 'All data synced';
      case SyncStatus.error:
        return '$failedCount item(s) failed to sync';
      case SyncStatus.idle:
        return '$pendingCount item(s) pending sync';
      case SyncStatus.offline:
        return 'Offline';
    }
  }
}

/// A more compact version that just shows a small dot
class SyncStatusDot extends StatelessWidget {
  final double size;

  const SyncStatusDot({super.key, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final connectivityService = ConnectivityService();
    final dataSyncService = DataSyncService();

    return ListenableBuilder(
      listenable: Listenable.merge([connectivityService, dataSyncService]),
      builder: (context, child) {
        final isOnline = connectivityService.isOnline;
        final syncStatus = dataSyncService.syncStatus;
        final pendingCount = dataSyncService.pendingCount;

        Color color;
        if (!isOnline) {
          color = CsColors.ink45;
        } else if (syncStatus == SyncStatus.syncing) {
          color = CsColors.cyan;
        } else if (syncStatus == SyncStatus.error) {
          color = CsColors.pink;
        } else if (pendingCount > 0) {
          color = CsColors.cyan.withValues(alpha: 0.7);
        } else {
          color = CsColors.mint;
        }

        final d = context.cs(size);
        return Tooltip(
          message: _getStatusMessage(isOnline, syncStatus, pendingCount),
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        );
      },
    );
  }

  String _getStatusMessage(bool isOnline, SyncStatus status, int pendingCount) {
    if (!isOnline) return 'Offline';
    if (status == SyncStatus.syncing) return 'Syncing...';
    if (status == SyncStatus.error) return 'Sync error';
    if (pendingCount > 0) return '$pendingCount pending';
    return 'Synced';
  }
}

/// An inline mono text widget showing sync status
class SyncStatusText extends StatelessWidget {
  final TextStyle? style;
  final bool showWhenSynced;

  const SyncStatusText({super.key, this.style, this.showWhenSynced = false});

  @override
  Widget build(BuildContext context) {
    final connectivityService = ConnectivityService();
    final dataSyncService = DataSyncService();

    return ListenableBuilder(
      listenable: Listenable.merge([connectivityService, dataSyncService]),
      builder: (context, child) {
        final isOnline = connectivityService.isOnline;
        final syncStatus = dataSyncService.syncStatus;
        final pendingCount = dataSyncService.pendingCount;

        String text;
        if (!isOnline) {
          text = 'Offline';
        } else if (syncStatus == SyncStatus.syncing) {
          text = 'Syncing...';
        } else if (syncStatus == SyncStatus.error) {
          text = 'Sync error';
        } else if (pendingCount > 0) {
          text = '$pendingCount pending';
        } else if (showWhenSynced) {
          text = 'Synced';
        } else {
          return const SizedBox.shrink();
        }

        return Text(
          text.toUpperCase(),
          style: style ?? context.type.micro,
        );
      },
    );
  }
}
