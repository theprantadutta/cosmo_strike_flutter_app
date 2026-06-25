import 'package:share_plus/share_plus.dart';

import '../utils/logger.dart';

/// Opens the native OS share sheet so players can invite friends to
/// Cosmo Strike. Single entry point ([shareApp]); the message + store link
/// live here so callers stay trivial.
class ShareService {
  static final ShareService _instance = ShareService._internal();
  factory ShareService() => _instance;
  ShareService._internal();

  /// Google Play listing for the game.
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.pranta.cosmostrike';

  /// Pre-filled share message. Kept short so it reads well in messaging apps
  /// and tweets; the link carries the rest.
  static const String _shareMessage =
      'Blast through the galaxy in Cosmo Strike — a neon space shooter. '
      'Join me and see how high you can score! $playStoreUrl';

  /// Show the native share sheet. Fire-and-forget safe — swallows the
  /// platform "share dismissed" path and any errors so callers never crash.
  Future<void> shareApp() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _shareMessage,
          subject: 'Cosmo Strike',
        ),
      );
    } catch (e) {
      AppLogger.info('[ShareService] share failed or dismissed: $e');
    }
  }
}
