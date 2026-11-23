/// How an available Play Store update is offered.
enum UpdateFlow {
  /// Nothing this session.
  none,

  /// Play's blocking full-screen flow straight away, without asking first.
  /// Reserved for releases the publisher marked urgent.
  immediate,

  /// Our own "Update now / Later" dialog on Home (`showPlayUpdateOfferDialog`).
  /// "Update now" runs Play's blocking flow (download with progress, then Play
  /// installs and restarts the app by itself); "Later" snoozes. The default
  /// for a routine release.
  offer,

  /// Play downloads in the background; the finished download is installed at
  /// the next launch on Home. Only a fallback, for when Play will not run the
  /// blocking flow: with the flexible flow as the default, players accepted
  /// the download and then never tapped Restart, so most of them stayed on
  /// the old build.
  flexible,
}

/// The rule for which flow to run, kept pure so it can be tested.
///
/// Google Play never installs an app update silently on the app's behalf;
/// the player always accepts first. A routine release is OFFERED: Play's
/// blocking screen only appears once the player has chosen "Update now".
/// Immediate-without-asking is for emergencies, signalled by the release's
/// update priority (set when publishing through the Play Developer API; a
/// console upload is priority 0).
///
/// No gates for first-run players: in the session(s) before the player's
/// first run ([firstSession]) nothing is offered unless the release is
/// urgent.
///
/// Ported from Snake Classic (`lib/services/update_policy.dart`); cross-app
/// write-up: D:\Desktop\self-improvements\Recommendations\in-app-update-flow.md.
class UpdatePolicy {
  const UpdatePolicy._();

  /// Priority at or above which a release is treated as an emergency and
  /// gets the blocking flow without the offer. Play's scale is 0 to 5.
  static const int immediatePriorityThreshold = 4;

  /// How long a "Later" (or a declined Play dialog) is left alone before
  /// asking again.
  static const Duration snooze = Duration(hours: 24);

  static UpdateFlow decide({
    required bool updateAvailable,
    required int priority,
    required bool immediateAllowed,
    required bool flexibleAllowed,
    required Duration? sinceDeclined,
    bool firstSession = false,
  }) {
    if (!updateAvailable) return UpdateFlow.none;

    final urgent = priority >= immediatePriorityThreshold;

    // An emergency release cuts through a snooze and the first-run grace:
    // the whole point of the priority is that this one cannot wait.
    if (urgent && immediateAllowed) return UpdateFlow.immediate;

    // Never put an update ask in front of a player's first run.
    if (firstSession && !urgent) return UpdateFlow.none;

    if (sinceDeclined != null && sinceDeclined < snooze) return UpdateFlow.none;

    if (immediateAllowed) return UpdateFlow.offer;

    // Play sometimes allows only the background download (for example while
    // one is already in progress). Better than nothing; the downloaded
    // update is installed at the next launch on Home.
    if (flexibleAllowed) return UpdateFlow.flexible;

    return UpdateFlow.none;
  }
}
