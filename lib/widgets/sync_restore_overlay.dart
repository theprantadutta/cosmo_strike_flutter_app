import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cosmo_strike_flutter_app/services/sync/sync_engine.dart';
import 'package:cosmo_strike_flutter_app/ui/cs.dart';

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

  ({String eyebrow, String title, String body, bool spinning, IconData? icon, Color iconColor})
      _copyForState() {
    switch (_state) {
      case FirstSignInState.welcoming:
        return (
          eyebrow: 'Step 1 / 3 · Account',
          title: 'Setting up your account…',
          body:
              'Getting things ready for your first session. This only happens once.',
          spinning: true,
          icon: null,
          iconColor: CsColors.ink,
        );
      case FirstSignInState.pulling:
        return (
          eyebrow: 'Step 2 / 3 · Cloud',
          title: 'Loading your previous data…',
          body:
              'Fetching your stats, achievements, coins, and unlocks from the cloud.',
          spinning: true,
          icon: null,
          iconColor: CsColors.ink,
        );
      case FirstSignInState.applying:
        return (
          eyebrow: 'Step 3 / 3 · Device',
          title: 'Restoring your progress…',
          body: "Applying everything to this device. Don't close the app.",
          spinning: true,
          icon: null,
          iconColor: CsColors.ink,
        );
      case FirstSignInState.restored:
        return (
          eyebrow: 'Restored',
          title: 'All set!',
          body: 'Your progress has been restored.',
          spinning: false,
          icon: Symbols.check_circle_rounded,
          iconColor: CsColors.mint,
        );
      case FirstSignInState.failed:
        return (
          eyebrow: 'Restore failed',
          title: "Couldn't restore your data",
          body:
              "We couldn't reach the cloud just now. Check your internet "
              "connection and try again. You can also continue without "
              "restoring — we'll retry the next time you open the app.",
          spinning: false,
          icon: Symbols.cloud_off_rounded,
          iconColor: CsColors.pink,
        );
      case FirstSignInState.idle:
      case FirstSignInState.done:
        return (eyebrow: '', title: '', body: '', spinning: false, icon: null, iconColor: CsColors.ink);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) return const SizedBox.shrink();

    final cs = context.cs;
    final t = cs.type;
    final copy = _copyForState();
    final isFailed = _state == FirstSignInState.failed;
    final mq = MediaQuery.of(context);

    // Backdrop catches taps so they don't pass through to widgets
    // behind the overlay, but doesn't dismiss — only the explicit
    // buttons (in the failed state) can move past this screen.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Material(
        color: CsColors.scrim,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: cs(32), vertical: cs(16)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: cs(480),
                  maxHeight: mq.size.height - mq.padding.vertical - cs(32),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: CsColors.raised,
                    borderRadius: BorderRadius.circular(CsRadius.card),
                    border: Border.all(color: CsColors.lineSubtle),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(cs(26)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const CsLogoMark(size: 28),
                          const Spacer(),
                          if (copy.icon != null) Icon(copy.icon, size: cs(26), color: copy.iconColor),
                        ]),
                        SizedBox(height: cs(16)),
                        CsLabel(copy.eyebrow, color: isFailed ? CsColors.pink : CsColors.ink45),
                        SizedBox(height: cs(6)),
                        Text(copy.title, style: t.display(26, em: -0.03, height: 1.05)),
                        SizedBox(height: cs(10)),
                        Text(copy.body, style: t.body.copyWith(fontSize: cs(14))),
                        if (copy.spinning) ...[
                          SizedBox(height: cs(22)),
                          LayoutBuilder(
                            builder: (context, c) => CsLoadingLine(width: c.maxWidth / cs.s),
                          ),
                        ],
                        if (isFailed) ...[
                          SizedBox(height: cs(22)),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: cs(10),
                              runSpacing: cs(10),
                              children: [
                                CsButton.text(
                                  label: 'Continue Anyway',
                                  onPressed: () => SyncEngine().dismissFirstSignInOverlay(),
                                ),
                                CsButton.primary(
                                  label: 'Try Again',
                                  icon: Symbols.refresh_rounded,
                                  onPressed: () => SyncEngine().retryFirstSignInPull(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
