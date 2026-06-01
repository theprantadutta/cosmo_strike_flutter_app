import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/logger.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Enhanced connectivity service that checks actual internet access
/// and backend reachability, not just network connection status.
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _internetCheckTimer;

  bool _hasNetworkConnection = false;
  bool _hasInternetAccess = false;
  bool _isBackendReachable = false;
  DateTime? _lastOnlineTime;
  bool _isInitialized = false;

  // Getters
  bool get isOnline =>
      _hasNetworkConnection && _hasInternetAccess && _isBackendReachable;
  bool get hasNetworkConnection => _hasNetworkConnection;
  bool get hasInternetAccess => _hasInternetAccess;
  bool get isBackendReachable => _isBackendReachable;
  DateTime? get lastOnlineTime => _lastOnlineTime;

  static const String _prodFallbackUrl = 'https://snakeclassic.pranta.dev';

  /// Backend health endpoint URL
  static String get _healthUrl {
    final String backendUrl;
    if (kDebugMode) {
      backendUrl = dotenv.env['DEV_API_BACKEND_URL'] ?? 'http://127.0.0.1:8393';
    } else {
      backendUrl = dotenv.env['PROD_API_BACKEND_URL'] ?? _prodFallbackUrl;
    }
    return '$backendUrl/health/status';
  }

  // Stream controller for online status changes
  final StreamController<bool> _onlineStatusController =
      StreamController<bool>.broadcast();
  Stream<bool> get onlineStatusStream => _onlineStatusController.stream;

  /// Initialize the connectivity service
  Future<void> initialize() async {
    // Prevent re-initialization
    if (_isInitialized) {
      if (kDebugMode) {
        print('ConnectivityService already initialized');
      }
      return;
    }

    // Start listening to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _onConnectivityChanged(result);

    // Start periodic internet access check (every 30 seconds when online)
    _startInternetCheckTimer();

    _isInitialized = true;

    if (kDebugMode) {
      print('ConnectivityService initialized - Online: $isOnline');
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    final hadNetwork = _hasNetworkConnection;
    _hasNetworkConnection =
        !results.contains(ConnectivityResult.none) && results.isNotEmpty;

    if (_hasNetworkConnection) {
      // Network available, check backend health
      await _checkInternetAccess();
    } else {
      // No network connection
      _hasInternetAccess = false;
      _isBackendReachable = false;
      _emitOnlineStatus();
    }

    // Log state change
    if (hadNetwork != _hasNetworkConnection) {
      AppLogger.network(
        'Network connection changed: $_hasNetworkConnection, '
        'Internet: $_hasInternetAccess, Backend: $_isBackendReachable',
      );
    }
  }

  /// Check backend reachability via /health endpoint, with DNS fallback
  Future<bool> _checkInternetAccess() async {
    if (!_hasNetworkConnection) {
      _hasInternetAccess = false;
      _isBackendReachable = false;
      _emitOnlineStatus();
      return false;
    }

    final wasOnline = isOnline;

    try {
      // Try to reach the backend health endpoint
      final response = await http
          .get(Uri.parse(_healthUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        _hasInternetAccess = true;
        _isBackendReachable = true;
        _lastOnlineTime = DateTime.now();
      } else {
        // Backend responded but not healthy — still reachable internet-wise
        _hasInternetAccess = true;
        _isBackendReachable = false;
      }
    } catch (_) {
      // Health check failed — determine if it's internet or backend issue
      _isBackendReachable = false;
      await _checkInternetFallback();
    }

    // Only emit if status changed
    if (wasOnline != isOnline) {
      _emitOnlineStatus();
    }

    return isOnline;
  }

  /// DNS fallback to distinguish "no internet" from "backend down"
  Future<void> _checkInternetFallback() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));

      _hasInternetAccess = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      _hasInternetAccess = false;
    } on TimeoutException catch (_) {
      _hasInternetAccess = false;
    } catch (e) {
      _hasInternetAccess = false;
      if (kDebugMode) {
        print('Internet fallback check error: $e');
      }
    }
  }

  void _emitOnlineStatus() {
    _onlineStatusController.add(isOnline);
    notifyListeners();
  }

  void _startInternetCheckTimer() {
    _internetCheckTimer?.cancel();
    _internetCheckTimer = Timer.periodic(const Duration(seconds: 30), (
      _,
    ) async {
      // Only check if we have network connection
      if (_hasNetworkConnection) {
        await _checkInternetAccess();
      }
    });
  }

  /// Force an immediate internet access check
  Future<bool> checkNow() async {
    if (!_hasNetworkConnection) {
      final result = await _connectivity.checkConnectivity();
      _hasNetworkConnection =
          !result.contains(ConnectivityResult.none) && result.isNotEmpty;
    }

    if (_hasNetworkConnection) {
      return await _checkInternetAccess();
    }
    return false;
  }

  /// Get a human-readable description of the current status
  String getStatusDescription() {
    if (!_hasNetworkConnection) {
      return 'No network connection';
    } else if (!_hasInternetAccess) {
      return 'No internet access';
    } else if (!_isBackendReachable) {
      return 'Server unreachable';
    } else {
      return 'Online';
    }
  }

  /// Get time since last online (for UI display)
  Duration? getTimeSinceOnline() {
    if (isOnline || _lastOnlineTime == null) return null;
    return DateTime.now().difference(_lastOnlineTime!);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _internetCheckTimer?.cancel();
    _onlineStatusController.close();
    super.dispose();
  }
}
