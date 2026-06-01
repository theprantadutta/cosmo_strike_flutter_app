import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cosmo_strike_flutter_app/services/connectivity_service.dart';
import 'package:cosmo_strike_flutter_app/services/data_sync_service.dart';

/// A subtle sync status indicator widget that shows connectivity and sync state.
///
/// Designed to be minimal and non-intrusive - a small icon in the corner.
/// States:
/// - Online + synced: Small green dot (barely visible)
/// - Online + syncing: Small spinning sync icon
/// - Online + pending: Small cloud with number badge
/// - Offline: Small gray cloud icon
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
              return _buildIndicator(syncService);
            },
          );
        },
      ),
    );
  }

  Widget _buildIndicator(DataSyncService syncService) {
    final isOnline = _connectivityService.isOnline;
    final syncStatus = syncService.syncStatus;
    final pendingCount = syncService.pendingCount;
    final failedCount = syncService.failedCount;

    // Update spin animation
    if (syncStatus == SyncStatus.syncing) {
      _spinController.repeat();
    } else {
      _spinController.stop();
    }

    // Determine icon and color
    IconData icon;
    Color color;
    Widget? badge;

    if (!isOnline) {
      // Offline
      icon = Icons.cloud_off_outlined;
      color = widget.offlineColor ?? Colors.grey.shade500;
    } else if (syncStatus == SyncStatus.syncing) {
      // Syncing
      icon = Icons.sync;
      color = widget.syncingColor ?? Colors.blue.shade400;
    } else if (failedCount > 0) {
      // Has failures
      icon = Icons.cloud_off;
      color = Colors.orange.shade400;
      badge = _buildBadge(failedCount, Colors.orange);
    } else if (pendingCount > 0) {
      // Has pending items
      icon = Icons.cloud_upload_outlined;
      color = widget.pendingColor ?? Colors.blue.shade300;
      badge = _buildBadge(pendingCount, Colors.blue);
    } else {
      // Online and synced
      icon = Icons.cloud_done_outlined;
      color =
          widget.onlineColor ?? Colors.green.shade400.withValues(alpha: 0.7);
    }

    return Tooltip(
      message: _getTooltipMessage(
        isOnline,
        syncStatus,
        pendingCount,
        failedCount,
      ),
      child: SizedBox(
        width: widget.size + 8,
        height: widget.size + 8,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (syncStatus == SyncStatus.syncing)
              RotationTransition(
                turns: _spinController,
                child: Icon(icon, size: widget.size, color: color),
              )
            else
              Icon(icon, size: widget.size, color: color),
            if (badge != null) Positioned(top: 0, right: 0, child: badge),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
      child: Text(
        count > 9 ? '9+' : count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
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
      return 'Offline - Changes will sync when connected';
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
          color = Colors.grey.shade500;
        } else if (syncStatus == SyncStatus.syncing) {
          color = Colors.blue.shade400;
        } else if (syncStatus == SyncStatus.error) {
          color = Colors.orange.shade400;
        } else if (pendingCount > 0) {
          color = Colors.blue.shade300;
        } else {
          color = Colors.green.shade400;
        }

        return Tooltip(
          message: _getStatusMessage(isOnline, syncStatus, pendingCount),
          child: Container(
            width: size,
            height: size,
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

/// An inline text widget showing sync status
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
          text,
          style: style ?? TextStyle(fontSize: 10, color: Colors.grey.shade400),
        );
      },
    );
  }
}
