import 'package:cosmo_strike_flutter_app/services/api_service.dart';

/// Exception thrown when an API call fails.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      'ApiException: $message${statusCode != null ? ' (status: $statusCode)' : ''}';
}

/// Thin wrapper around [ApiService] that throws [ApiException] on
/// failure so the repository layer can handle errors uniformly.
/// Post-offline-first-refactor: only auth + purchase methods remain.
class ApiDataSource {
  final ApiService _apiService;

  ApiDataSource(this._apiService);

  // ==================== Authentication ====================

  bool get isAuthenticated => _apiService.isAuthenticated;

  String? get currentUserId => _apiService.currentUserId;

  Future<Map<String, dynamic>> authenticateWithFirebase(
    String firebaseIdToken,
  ) async {
    final result = await _apiService.authenticateWithFirebase(firebaseIdToken);
    if (result == null) {
      throw ApiException('Authentication failed');
    }
    return result;
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    final result = await _apiService.getCurrentUser();
    if (result == null) {
      throw ApiException('Failed to get current user');
    }
    return result;
  }

  Future<bool> logout() async {
    return await _apiService.logout();
  }

  Future<void> clearToken() async {
    await _apiService.clearToken();
  }

  // ==================== Users ====================

  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final result = await _apiService.getUserProfile(userId);
    if (result == null) {
      throw ApiException('Failed to get user profile');
    }
    return result;
  }

  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    final result = await _apiService.updateProfile(data);
    if (result == null) {
      throw ApiException('Failed to update profile');
    }
    return result;
  }

  Future<Map<String, dynamic>> checkUsername(String username) async {
    final result = await _apiService.checkUsername(username);
    if (result == null) {
      throw ApiException('Failed to check username');
    }
    return result;
  }

  Future<Map<String, dynamic>> setUsername(String username) async {
    final result = await _apiService.setUsername(username);
    if (result == null) {
      throw ApiException('Failed to set username');
    }
    return result;
  }

  // ==================== Purchases ====================

  Future<Map<String, dynamic>> verifyPurchase({
    required String platform,
    required String receiptData,
    required String productId,
    required String transactionId,
    String? purchaseToken,
  }) async {
    final result = await _apiService.verifyPurchase(
      platform: platform,
      receiptData: receiptData,
      productId: productId,
      transactionId: transactionId,
      purchaseToken: purchaseToken,
    );
    if (result == null) {
      throw ApiException('Failed to verify purchase');
    }
    return result;
  }

  Future<Map<String, dynamic>> getPremiumContent() async {
    final result = await _apiService.getPremiumContent();
    if (result == null) {
      throw ApiException('Failed to get premium content');
    }
    return result;
  }

  // ==================== Notifications ====================

  Future<bool> registerFcmToken({
    required String fcmToken,
    String platform = 'flutter',
  }) async {
    return await _apiService.registerFcmToken(
      fcmToken: fcmToken,
      platform: platform,
    );
  }
}
