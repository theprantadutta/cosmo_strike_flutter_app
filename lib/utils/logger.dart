import 'package:flutter/foundation.dart';
import 'package:talker_flutter/talker_flutter.dart';

/// Global logger instance for beautiful logging throughout the app
/// Only works in debug mode to avoid performance impact in production
class AppLogger {
  static final Talker _talker = TalkerFlutter.init(
    settings: TalkerSettings(
      enabled: kDebugMode, // Only enabled in debug mode
      useConsoleLogs: kDebugMode,
      maxHistoryItems: 1000,
      useHistory: true,
    ),
    logger: TalkerLogger(settings: TalkerLoggerSettings(enableColors: true)),
  );

  /// Get the Talker instance for advanced usage
  static Talker get instance => _talker;

  // Service-specific loggers with emojis for easy identification

  /// 👤 User system related logs
  static void user(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('👤 [USER] $message', error, stackTrace);
      } else {
        _talker.info('👤 [USER] $message');
      }
    }
  }

  /// 🔥 Firebase related logs
  static void firebase(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('🔥 [FIREBASE] $message', error, stackTrace);
      } else {
        _talker.info('🔥 [FIREBASE] $message');
      }
    }
  }

  /// ☁️ Sync service related logs
  static void sync(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('☁️ [SYNC] $message', error, stackTrace);
      } else {
        _talker.info('☁️ [SYNC] $message');
      }
    }
  }

  /// 🎮 Game logic related logs
  static void game(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('🎮 [GAME] $message', error, stackTrace);
      } else {
        _talker.info('🎮 [GAME] $message');
      }
    }
  }

  /// 🎨 Theme and UI related logs
  static void ui(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('🎨 [UI] $message', error, stackTrace);
      } else {
        _talker.info('🎨 [UI] $message');
      }
    }
  }

  /// 🔊 Audio related logs
  static void audio(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('🔊 [AUDIO] $message', error, stackTrace);
      } else {
        _talker.info('🔊 [AUDIO] $message');
      }
    }
  }

  /// 🏆 Achievement related logs
  static void achievement(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('🏆 [ACHIEVEMENT] $message', error, stackTrace);
      } else {
        _talker.info('🏆 [ACHIEVEMENT] $message');
      }
    }
  }

  /// 📊 Statistics related logs
  static void stats(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('📊 [STATS] $message', error, stackTrace);
      } else {
        _talker.info('📊 [STATS] $message');
      }
    }
  }

  /// ⚙️ Preferences related logs
  static void prefs(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('⚙️ [PREFS] $message', error, stackTrace);
      } else {
        _talker.info('⚙️ [PREFS] $message');
      }
    }
  }

  // General logging methods

  /// ✅ Success messages
  static void success(String message) {
    if (kDebugMode) {
      _talker.info('✅ $message');
    }
  }

  /// ⚠️ Warning messages
  static void warning(String message) {
    if (kDebugMode) {
      _talker.warning('⚠️ $message');
    }
  }

  /// ❌ Error messages
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _talker.error('❌ $message', error, stackTrace);
    }
  }

  /// ℹ️ Info messages
  static void info(String message) {
    if (kDebugMode) {
      _talker.info('ℹ️ $message');
    }
  }

  /// 🐛 Debug messages
  static void debug(String message) {
    if (kDebugMode) {
      _talker.debug('🐛 $message');
    }
  }

  /// 🔍 Verbose messages
  static void verbose(String message) {
    if (kDebugMode) {
      _talker.verbose('🔍 $message');
    }
  }

  /// 📝 Log any object with pretty formatting
  static void logObject(String title, Object? object) {
    if (kDebugMode) {
      _talker.info('📝 $title: ${object.toString()}');
    }
  }

  /// 🚀 App lifecycle events
  static void lifecycle(String event) {
    if (kDebugMode) {
      _talker.info('🚀 [LIFECYCLE] $event');
    }
  }

  /// 🌐 Network related logs
  static void network(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('🌐 [NETWORK] $message', error, stackTrace);
      } else {
        _talker.info('🌐 [NETWORK] $message');
      }
    }
  }

  /// 💾 Storage related logs
  static void storage(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      if (error != null) {
        _talker.error('💾 [STORAGE] $message', error, stackTrace);
      } else {
        _talker.info('💾 [STORAGE] $message');
      }
    }
  }
}
