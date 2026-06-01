import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cosmo_strike_flutter_app/presentation/bloc/theme/theme_cubit.dart';
import 'package:cosmo_strike_flutter_app/services/sync/sync_engine.dart';
import 'package:cosmo_strike_flutter_app/utils/constants.dart';

/// Modal overlay shown during the first-sign-in flow. Subscribes to
/// [SyncEngine.firstSignInStateStream] and renders a full-screen
/// blocking sheet whenever the engine is in a non-idle, non-done state.
///
/// Hosted inside an [OverlayEntry] inserted by [SyncEngine] itself
/// (see [SyncEngine.attachNavigatorKey]). That makes it visible above
/// whatever screen the user happens to be on when sign-in fires —
/// FirstTimeAuthScreen, LoadingScreen, ProfileScreen's "Save your
/// progress" upgrade, anywhere — without putting any restore-related
/// code into the screens' widget trees. Once the engine emits `done`,
/// the OverlayEntry is removed and this widget never builds again until
/// the next first-sign-in flow (typically only on a fresh reinstall).
class SyncRestoreOverlay extends StatefulWidget {
  const SyncRestoreOverlay({super.key});

  @override
  State<SyncRestoreOverlay> createState() => _SyncRestoreOverlayState();
}

class _SyncRestoreOverlayState extends State<SyncRestoreOverlay> {
  FirstSignInState _state = SyncEngine().firstSignInState;
  StreamSubscription<FirstSignInState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = SyncEngine().firstSignInStateStream.listen((s) {
      if (!mounted) return;
      setState(() => _state = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  bool get _shouldShow {
    switch (_state) {
      case FirstSignInState.welcoming:
      case FirstSignInState.pulling:
      case FirstSignInState.applying:
      case FirstSignInState.restored:
      case FirstSignInState.failed:
        return true;
      case FirstSignInState.idle:
      case FirstSignInState.done:
        return false;
    }
  }

  ({String title, String body, bool spinning, IconData? icon, Color? iconColor})
      _copyForState() {
    switch (_state) {
      case FirstSignInState.welcoming:
        return (
          title: 'Setting up your account…',
          body:
              'Getting things ready for your first session. This only happens once.',
          spinning: true,
          icon: null,
          iconColor: null,
        );
      case FirstSignInState.pulling:
        return (
          title: 'Loading your previous data…',
          body:
              'Fetching your stats, achievements, coins, and unlocks from the cloud.',
          spinning: true,
          icon: null,
          iconColor: null,
        );
      case FirstSignInState.applying:
        return (
          title: 'Restoring your progress…',
          body: "Applying everything to this device. Don't close the app.",
          spinning: true,
          icon: null,
          iconColor: null,
        );
      case FirstSignInState.restored:
        return (
          title: 'All set!',
          body: 'Your progress has been restored.',
          spinning: false,
          icon: Icons.check_circle_outline_rounded,
          iconColor: Colors.greenAccent,
        );
      case FirstSignInState.failed:
        return (
          title: "Couldn't restore your data",
          body:
              "We couldn't reach the cloud just now. Check your internet "
              "connection and try again. You can also continue without "
              "restoring — we'll retry the next time you open the app.",
          spinning: false,
          icon: Icons.cloud_off_rounded,
          iconColor: Colors.orangeAccent,
        );
      case FirstSignInState.idle:
      case FirstSignInState.done:
        return (title: '', body: '', spinning: false, icon: null, iconColor: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) return const SizedBox.shrink();

    // Read theme via BlocBuilder so the overlay can render inside any
    // OverlayEntry context (no constructor arg needed). ThemeCubit is
    // provided at the root in main.dart, above MaterialApp.router, so
    // it's reachable from inside the Navigator's Overlay.
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final theme = themeState.currentTheme;
        final copy = _copyForState();
        final isFailed = _state == FirstSignInState.failed;

        // Backdrop catches taps so they don't pass through to widgets
        // behind the overlay, but doesn't dismiss — only the explicit
        // buttons (in the failed state) can move past this screen.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              color: Colors.black.withValues(alpha: 0.78),
              alignment: Alignment.center,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                decoration: BoxDecoration(
                  color: theme.backgroundColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.accentColor.withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.accentColor.withValues(alpha: 0.3),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (copy.spinning)
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(
                          strokeWidth: 5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              theme.accentColor),
                        ),
                      )
                    else if (copy.icon != null)
                      Icon(
                        copy.icon,
                        size: 64,
                        color: copy.iconColor ?? theme.accentColor,
                      ),
                    const SizedBox(height: 24),
                    Text(
                      copy.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.accentColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      copy.body,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.accentColor.withValues(alpha: 0.75),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    if (isFailed) ...[
                      const SizedBox(height: 24),
                      _PrimaryButton(
                        theme: theme,
                        label: 'Try Again',
                        icon: Icons.refresh_rounded,
                        onPressed: () =>
                            SyncEngine().retryFirstSignInPull(),
                      ),
                      const SizedBox(height: 10),
                      _SecondaryButton(
                        theme: theme,
                        label: 'Continue Anyway',
                        onPressed: () =>
                            SyncEngine().dismissFirstSignInOverlay(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final GameTheme theme;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.theme,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.accentColor,
          foregroundColor: theme.backgroundColor,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final GameTheme theme;
  final String label;
  final VoidCallback onPressed;

  const _SecondaryButton({
    required this.theme,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: theme.accentColor.withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(vertical: 10),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
