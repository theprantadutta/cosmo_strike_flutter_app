# Lessons from Snake Classic — improvement plan

Snake Classic is the developer's best-performing game. This list ports its
**fixes, plumbing and lessons** to Cosmo Strike — never its features, names,
copy, catalog or look (App Store 4.3(a): see CLAUDE.md "Identity"). Each item
is done and committed one at a time; tick it here when it lands.

Legend: impact H/M/L · effort S/M/L · `A` = Snake Classic, `B` = Cosmo Strike.

## Tier 1 — stability (small, high impact)
- [x] 1. **Notification taps can freeze on the splash** (H, S). FCM copies the
  push's `route` data key onto the launch Intent; FlutterActivity reads it as
  the initial route, which matches nothing. Fix: `getInitialRoute() = null` in
  `MainActivity`; deep links keep coming from the FCM message data.
- [x] 2. **Impeller off on Android 10 (SDK 29)** (H, S). A saw GPU-driver
  SIGSEGVs + "GPU unresponsive" ANRs there; B is a heavier Flame game.
  `getFlutterShellArgs()` adds `--disable-impeller` on SDK 29 only.
- [x] 3. **Create the notification channel natively at launch** (H, S) +
  manifest `default_notification_channel_id`, so pushes that arrive before
  Home first mounts aren't dropped/demoted.
- [ ] 4. **Retry failed ad loads** (H, S–M). B only logs `onAdFailedToLoad`;
  A retries with backoff so interstitial/rewarded slots refill.

## Tier 2 — retention & revenue
- [ ] 5. **Ad mediation** (Unity Ads + Liftoff) (H, M). Code is small; needs
  per-app console setup by the owner (see the global CLAUDE.md AdMob notes).
- [ ] 6. **Calmer reminder pushes** (M, S–M, backend). Daily → every 2 days →
  weekly by absence (`LastDailyReminderAt`) and a backward tick window instead
  of the exact-minute match.
- [ ] 7. **Day-1 comeback local notification** (M, S–M). ~20 h after a session,
  outside quiet hours, cancelled on return; reaches accountless guests the
  server can't. Copy written in Cosmo's own voice.
- [ ] 8. **Open the app's notification settings** (M, S) for players who denied
  permission (native MethodChannel), from the soft-ask/Settings.
- [ ] 9. **First-run funnel analytics** (M, S): onboarding steps,
  `first_game_started(seconds_since_install)`, second run.
- [ ] 10. **Startup safety net** (H, M): overall bootstrap timeout + loading
  watchdog + recovery/retry, and crash reporting that also covers early
  startup failures.
- [ ] 11. **Gentler first runs** (M, S–M): ease bullet pressure for the first
  few runs; shorten the fixed 3 s pre-game loader to "until loaded".

## Tier 3 — bigger projects
- [ ] 12. **Localized store listings**, then in-app l10n (M, S→L). Translate
  Cosmo's own copy (never A's).
- [ ] 13. **iOS subscription reconcile + refund job** (M, M, backend).
- [ ] 14. **Ad revenue/load measurement**, iOS update prompt, release scripts
  that upload crash symbols (L each, S–M).
