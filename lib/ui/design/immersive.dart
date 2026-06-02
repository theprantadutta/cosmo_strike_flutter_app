import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralized system-chrome control for the command-HUD shell.
///
/// Cosmo Strike is a full-screen landscape game, so the status/notification bar
/// and nav bar are hidden EVERYWHERE (immersiveSticky) — a swipe from the edge
/// reveals them briefly, then they auto-hide.
///
/// Both [enterMenu] and [enterGame] use immersiveSticky; they're kept as
/// separate calls only so the app-resume handler can re-assert the mode. The
/// [inGameplay] flag tracks which screen is active for that re-assert.
class Immersive {
  Immersive._();

  /// True while a full-screen gameplay screen is active.
  static bool inGameplay = false;

  static const SystemUiOverlayStyle _menuOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  );

  /// Full-screen menu chrome (status + nav bars hidden). Safe to call on resume.
  static void enterMenu() {
    inGameplay = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(_menuOverlay);
  }

  /// Full-screen immersive gameplay (status + notification bar hidden).
  static void enterGame() {
    inGameplay = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
}
