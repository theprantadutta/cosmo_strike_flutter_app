import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralized system-chrome control for the command-HUD shell.
///
/// Two modes:
/// - **Menu** (`enterMenu`): edge-to-edge — status + nav bars stay present but
///   transparent (Android 15 compliance), content draws under them.
/// - **Game** (`enterGame`): `immersiveSticky` — status + nav bars hidden for
///   full-screen play; a swipe temporarily reveals them.
///
/// The [inGameplay] flag exists so the app-resume handler (`main.dart`
/// `didChangeAppLifecycleState`) does NOT re-apply the menu chrome while a game
/// screen is active, which would otherwise fight the immersive mode.
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

  /// Edge-to-edge menu chrome. Safe to call on resume.
  static void enterMenu() {
    inGameplay = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(_menuOverlay);
  }

  /// Full-screen immersive gameplay (status + notification bar hidden).
  static void enterGame() {
    inGameplay = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
}
