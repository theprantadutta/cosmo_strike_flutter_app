/// Base failure class for all failures in the app
abstract class Failure {
  final String message;
  final String? code;

  const Failure(this.message, {this.code});

  @override
  String toString() =>
      'Failure: $message${code != null ? ' (code: $code)' : ''}';
}

/// Server-related failures (API errors, 500s, etc.)
class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error occurred']);

  factory ServerFailure.fromStatusCode(
    int statusCode, [
    String? customMessage,
  ]) {
    final message =
        customMessage ??
        switch (statusCode) {
          400 => 'Bad request',
          401 => 'Unauthorized',
          403 => 'Forbidden',
          404 => 'Not found',
          422 => 'Validation error',
          429 => 'Too many requests',
          500 => 'Internal server error',
          502 => 'Bad gateway',
          503 => 'Service unavailable',
          _ => 'Server error (status: $statusCode)',
        };
    return ServerFailure(message);
  }
}

/// Cache-related failures
class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error occurred']);
}

/// Network-related failures (no internet, timeout, etc.)
class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No network connection']);
}

/// Authentication-related failures
class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed']);
}

/// Validation failures (invalid input, etc.)
class ValidationFailure extends Failure {
  final Map<String, List<String>>? fieldErrors;

  const ValidationFailure(super.message, {this.fieldErrors});
}

/// Feature-specific failures
class GameFailure extends Failure {
  const GameFailure(super.message);
}

class PremiumFailure extends Failure {
  const PremiumFailure(super.message);
}

class LeaderboardFailure extends Failure {
  const LeaderboardFailure(super.message);
}

class SocialFailure extends Failure {
  const SocialFailure(super.message);
}

class MultiplayerFailure extends Failure {
  const MultiplayerFailure(super.message);
}
