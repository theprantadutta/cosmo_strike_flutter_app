import 'dart:async';
import 'package:cosmo_strike_flutter_app/services/connectivity_service.dart';

/// Abstract interface for network information
abstract class NetworkInfo {
  /// Check if device is connected to the internet
  Future<bool> get isConnected;

  /// Stream of connectivity changes
  Stream<bool> get onlineStatusStream;

  /// Current online status (synchronous)
  bool get isOnline;
}

/// Implementation of NetworkInfo using ConnectivityService
class NetworkInfoImpl implements NetworkInfo {
  final ConnectivityService _connectivityService;

  NetworkInfoImpl(this._connectivityService);

  @override
  Future<bool> get isConnected async {
    return _connectivityService.isOnline;
  }

  @override
  Stream<bool> get onlineStatusStream {
    return _connectivityService.onlineStatusStream;
  }

  @override
  bool get isOnline => _connectivityService.isOnline;
}
