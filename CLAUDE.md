# Cosmo Strike — Flutter App

The Cosmo Strike game client: a space shoot-'em-up **mobile game** in Flutter/Dart
(a Flame game wrapped in a Flutter app shell). Talks to the .NET backend in
`../cosmo-strike-dotnet-api/`.

## ⚠️ Orientation: LANDSCAPE / HORIZONTAL ONLY
Cosmo Strike is played **horizontally**. The app is locked to landscape
(`landscapeLeft` / `landscapeRight`) at both the Flutter level (`main.dart`
`setPreferredOrientations`) and the Android Activity level (`AndroidManifest.xml`
`android:screenOrientation="sensorLandscape"`), and runs **fullscreen immersive**
(status/navigation bars hidden, `SystemUiMode.immersiveSticky`).

**Design and lay out every screen for a wide, short landscape viewport** —
centered max-width dialog cards for forms, two-region (left/right) layouts
for content, never tall portrait-stacked columns that overflow below the fold.

## ⚠️ Architecture: OFFLINE-FIRST, DRIFT IS THE SOURCE OF TRUTH
This is the most important rule in the app. **Never make a screen depend on a
live network call.** The flow is always: **UI → Drift (local SQLite) → background
sync → backend.**

- **Drift is the single source of truth.** All reads come from the local Drift
  database (`lib/data/database/app_database.dart`, DAOs in `lib/data/daos/`).
  The UI reads/watches Drift, never the API directly.
- **Writes are local-first + queued.** A user action writes to Drift immediately
  and enqueues an outbox item; `SyncEngine` (`lib/services/sync/sync_engine.dart`)
  pushes the outbox to the backend in prioritized batches with retry/backoff.
  The game stays fully playable offline; queued writes flush when connectivity
  returns (`connectivity_service.dart` / `core/network/network_info.dart`).
- **Pull from the backend EXACTLY ONCE — on first sign-in.** Server data is only
  downloaded to hydrate the local DB the very first time a user signs in on a
  device, via `SyncEngine.maybeRunFirstSignInPull()` (`FirstSignInResult`), with
  the blocking "restoring your data…" modal `SyncRestoreOverlay`. After that the
  device is `done` and **never bulk-pulls again** (only re-runs on a fresh
  reinstall / brand-new first sign-in). Do **not** add code that re-pulls server
  state on every login/launch — it would clobber authoritative local progress.
  Local progress is authoritative; the backend is a backup/leaderboard/validation
  store fed by the push outbox.
- The backend has a matching `Sync` feature (`SyncController` + per-domain Sync
  commands) that accepts the pushed batches — see the API's CLAUDE.md.

When adding a new piece of user state: add a Drift table/DAO, read it in the UI,
write-through to Drift, enqueue it for push in `SyncEngine`. Don't bolt on a
one-off API call.

## ⚠️ Onboarding: NO GATES, DEFERRED ASKS
A fresh install goes loading → **Home**, as the silent local guest
`UnifiedUserService` creates (no Firebase/backend until they sign in). Never
put sign-in, privacy, notifications or setup choices in front of the first run.
- `services/first_run_service.dart` (SharedPreferences, device-only): runs
  started; `hasCompletedOnboarding` after 3 — the gate for later asks.
- **Privacy**: notice strip on Home ("By playing you agree…"); starting a run
  records acceptance (`gameplay_screen` initState). Only players who accepted
  an OLDER version hit the blocking `PrivacyConsentScreen`
  (`PrivacyPolicy.needsReconsent`). Read-only `/privacy-policy` from Settings.
- **Home prompt queue** (`home_screen._runPromptQueue`, re-runs on return via
  `appRouteObserver`): Play update offer (Android, ends the queue) →
  walkthrough (first visit, ends the queue) → daily bonus → game-mode picker
  (after run 1) → notification soft-ask (after onboarding). One at a time —
  never stack dialogs.
- **In-app updates** (Android only; `InAppUpdateService` + pure
  `UpdatePolicy`): one check per process, kicked off by Home after its first
  frame. Routine release → our `showPlayUpdateOfferDialog` ("Update now" =
  Play's immediate flow, which installs and restarts by itself; Later /
  outside tap / back / declining Play's screen = 24 h snooze). Urgent
  (`updatePriority` >= 4) → immediate flow unasked; flexible only when Play
  refuses immediate. Never offered before the install's first run (unless
  urgent). A finished flexible download installs at the next launch on Home
  while Home is on top, never on background/resume (ads and paused runs
  background the app; the install kills the process). Event `app_update`.
- **Notifications**: `NotificationService.initialize()` never shows the OS
  dialog; only `NotificationSoftAsk` → `requestPermissionFlow()` does.
  When the OS prompt is blocked, `NotificationSettingsOpener` (native
  channel in `MainActivity`) opens the app's notification settings (soft-ask
  and Settings → Notifications "Comms offline" row). Accountless pilots get
  ONE local comeback reminder ~20 h after leaving (`ComebackReminder`, quiet
  hours 22–09 skipped; armed at game over / on background, cancelled on
  resume; skipped with a backend session — the server reminder covers them).
- **Sign-in**: `DeferredSignInPrompt` on a new personal best after onboarding
  (≤3 asks, 3 days apart), plus Profile, all via `showAccountUpgradeSheet`
  (links Firebase-anonymous; signs in a local guest — is_new_user keeps local
  data).
- **⚠️ Purchases never require sign-in** (App Store guideline 5.1.1(v) — the
  first iOS submission was rejected for it). Every buy/restore path calls
  `AuthCubit.ensurePurchaseAccount()`, which silently gives a local guest a
  Firebase-anonymous account so the backend can verify the purchase. Never
  put the account sheet in front of a purchase.

## ⚠️ Identity: never drift back toward Snake Classic
3.1.1 was rejected under App Store guideline 4.3(a) (spam): the app was forked
from the developer's Snake Classic and still mirrored its catalog, modes,
achievements and copy. 3.2 rebranded everything — the source of truth is
`docs/rebrand/REBRAND_SPEC.md` (vocabulary, 35-product catalog, modes,
commendations, legacy-ID migrations). Use its vocabulary: Credits, Strike
Command, Armory, Liveries / Exhausts / Sectors / Fleet Kits / Tactical Gear /
Cup Passes, Frontline, Sector Cups, Daily Directives, Weekly Ops,
Commendations, Standings, Squadron. Never copy features, strings, IDs or
word lists from Snake Classic.
- Legacy IDs are migrated once on startup (`lib/services/rebrand/*`, wired at
  the end of `configureDependencies`) and parsed tolerantly everywhere
  (`GameMode.fromWire`, `LiveryType/ExhaustType.fromId`, `GameTheme.fromId`).
- The Store's Cup Passes tab hides `cup_ace_trio` / `cup_squadron` until the
  store returns them (`_TournamentEntryOffer.requiresStoreProduct`).

## Measurement: analytics, telemetry, test devices, ratings
- **Keep test devices out of the data.** Debug and DemoMode (autopilot /
  profiling) builds only get `LoggerAnalyticsClient` and never send
  telemetry (`AnalyticsGate`). **Mark every device you test release builds
  on as a test device:** Settings → About & Credits → tap the version chip
  **7 times** → toast "Test device: on (analytics off)" (same again turns it
  off; persisted in SharedPreferences). That sets user property
  `test_device=1`, switches Firebase Analytics collection off (re-applied
  every launch in `main.dart`), and sends backend telemetry with
  `is_test: true` (sticky server-side: the install leaves every retention
  number forever). `TestDevice` in `lib/services/analytics/test_device.dart`.
- **Events:** new ones go through `AnalyticsClient.trackEvent` with typed
  wrappers on `AnalyticsFacade` (don't add a method per client). Run
  context comes from `RunSession` (`lib/services/analytics/run_session.dart`),
  driven by one-line hooks in `gameplay_screen`: `game_over` gained
  `run_number` (lifetime, 1 = first run), `onboarding` (0/1) and
  `end_trigger` (`death`/`time`/`victory`); quits log `game_abandoned`
  (`end_trigger: quit`); `revive_offer` (`ad`/`coins`/`free`/`declined`/
  `timeout`/`skipped_onboarding`); `first_input` (install's first run);
  `push_opened` (`PushOpenTracker`, FCM + local incl. cold-start launches);
  `notification_permission` (`NotificationSettingsOpener.requestOrOpen(
  placement: ...)`); `next_goal_shown/tapped`. User properties
  `install_week` / `onboarding_done` (set from `FirstRunService`).
  **Register every new param in GA4** — list and descriptions:
  `docs/analytics/GA4_CUSTOM_DEFINITIONS.md`.
- **Backend telemetry** (`lib/services/telemetry/telemetry_service.dart`,
  contract in the API repo's `docs/TELEMETRY_CONTRACT.md`): one cumulative
  counter row per local day (sessions, runs started/finished, seconds
  played, max level) in SharedPreferences, POSTed to
  `/telemetry/heartbeat` with an install UUID (device-only, never reset on
  sign-out). A session = launch, or resume after ≥ 30 min in the background.
  Flushes on launch, background and reconnect; 400 drops, 413/429/5xx/
  network retry with backoff. Never blocks the UI.
- **Ratings:** `ReviewService.maybeAskForReview(trigger)` is the only
  automatic prompt, fired by `RunSession` at a level clear (or a new best
  reached at a level clear) and at a campaign victory that isn't a new best.
  Gate (`ReviewGate`): onboarding done AND ≥ 6 runs started, ≤ once per 60
  days, never within 90 s of a full-screen ad, purchase sheet or lost ship
  (`ReviewService.noteInterruption`), never in DemoMode. Native in-app
  review API only — **never add a "Do you like the game?" pre-dialog**
  (filtering unhappy players violates Play policy).

## Stack & conventions
- **State management:** `flutter_bloc` Cubits/Blocs in `lib/presentation/bloc/`
  plus some `provider`-based providers in `lib/providers/`.
- **Material is `package:material_ui`** (Flutter 3.50 split): import it, never
  `package:flutter/material.dart`. Every `MaterialApp` (incl. test harnesses)
  needs `localizationsDelegates: GlobalMaterialLocalizations.delegates` from
  material_ui or widgets throw "No MaterialLocalizations found";
  `MaterialUiCompatibilityBridge` in the router app's `builder` covers
  third-party packages still on flutter/material.
- **DI:** `get_it` — registrations in `lib/core/di/injection.dart` (`getIt<…>()`).
- **Routing:** `go_router` in `lib/router/app_router.dart` (`AppRoutes`, `context.push`).
- **Game:** Flame engine in `lib/game/` — gameplay LOGIC is off-limits for UI work
  (`cosmo_strike_game.dart`, state machine, `ValueNotifier`s); only colors
  (`cosmo_palette.dart`), component `render()` paint, and the Flutter HUD change.
- **Auth/users:** `unified_user_service.dart` (guest / anonymous / Google),
  Firebase Auth; guests can upgrade and keep local progress via the first-sign-in pull.

## Visual design — "Prism Noir"
Near-black canvas (#0A0A0D UI, #08080B in-game), iridescent prism gradient
(cyan #7CF5FF → violet #A78BFA → pink #FF8AD8 → gold #FFD58A, + mint #9BFFC8)
used sparingly as the only colour, big Syne 800 headlines, IBM Plex Mono
uppercase labels, 1px hairlines instead of cards. Source kit (mocks + exact
CSS): `docs/redesign/AGENT_BRIEF.md` explains where it lives and the rules.

- Tokens + ThemeData: `lib/theme/cosmo_theme.dart` (`CsColors`, `CsGradients`,
  `CsMotion`, `buildCosmoTheme()`).
- Components: `lib/ui/cs/` — import ONLY the barrel `lib/ui/cs.dart` (also
  re-exports Material Symbols; use `Symbols.*_rounded`, filled by theme).
  `CsScaffold` (canvas + SafeArea + `CsTopBar`) → `CsSplit` (summary left,
  content right) is the standard screen. Buttons: `CsButton.primary` (one white
  pill per screen) / `.secondary` / `.text` / `.premium` (gold) / `.prism`.
  Also `CsTile` (done/current/selected/future/locked/pro), `CsPrismRing`,
  `CsPrismText`, `CsProgressLine`, `CsRingProgress`, `CsStatGrid`,
  `CsListRow`, `CsAvatarRing`, `CsChip`, `CsSegmented`, `CsToggleChip`,
  `showCsDialog`/`CsDialog`, `showCsConfirm`, `showCsToast`,
  `CsLoadingState`/`CsEmptyState`.
- **Responsive:** every size goes through `context.cs` (`cs(16)` scales a value
  from the 960×432 design frame; factor clamps 0.72–1.4 by the tighter axis)
  and `context.type` (pre-scaled type scale). Must look designed on 640×360
  phones up to 13" iPads: distribute tablet height with Expanded/Spacer, side
  columns never scroll (`CsFitColumn`), lists may. No raw px font sizes.
- Prism marks only the 1–2 things that matter per screen. Semantic colours:
  mint = success, gold = coins/reward/premium, pink = danger/game over,
  violet = XP, cyan = info. No glows/shadows, no glassmorphism (pause scrim is
  the one blur), no looping shimmer.
- Purchased colour themes (`ThemeCubit` / `GameTheme`) tint **gameplay only**
  via `CosmoPalette`; menus are always Prism Noir. Don't colour UI from
  `GameTheme` getters.
- Dialogs are centred `CsDialog`s (no bottom sheets in landscape); toasts via
  `showCsToast` / `RewardToast`.

## Gameplay: choreographed sprite campaign
The Flame game is a 12-level campaign (4 biomes × 3 levels) with modes as
modifiers on top. Key pieces (all in `lib/game/`):
- **Choreographed levels**: each level is a `LevelScript` timeline
  (`levels/level_script.dart`: FormationEvent / DropEvent / SetPieceEvent /
  TelegraphEvent / BossEvent, RELATIVE delays, barrier events wait for a
  clear field) driven by `levels/script_runner.dart`. Formations
  (`levels/formation.dart` + `components/formation_unit.dart`) are the spawn
  unit — 9 shapes (stream/vWedge/serpentine/pincer/wallWithGap/columnDive/
  ambushRear/ringSpinner/escortConvoy); wiping one fast = bonus + orb.
  The 12 scripts live in `levels/level_catalog.dart`; adding a level =
  appending data + a name in `lib/utils/campaign_catalog.dart`.
- **Game-time spawning**: ScriptRunner is a plain Component — never use
  `Future.delayed` for spawns (wall-clock ignores `pauseEngine()` and breaks
  pause/revive).
- **Combo + graze + Overdrive** (`combo_graze.dart`): kill chains drive a
  ×1-×4 score multiplier (breaks on landed hits). Grazes score with the combo,
  extend the chain and fill the Overdrive meter (formation wipes charge it
  too); tapping a full meter = 5s piercing beam, ×2 score, bullet-vaporising
  aura. Kill scoring goes through `game.addKillScore`.
- **Pressure** (`intensity_director.dart`, `tuning.dart`): aimed-shot share and
  bullet speed rise per level; clean flying raises fire rate/aim (hits ease it);
  idling draws a sniper volley. The basic gun does NOT shoot bullets down (laser
  and Overdrive do). ALL feel numbers live in `lib/game/tuning.dart`.
  First runs are eased (`GameTuning.onboardingEase`: softer fire rate /
  bullet speed / aimed share over the 3 onboarding runs), never for Daily
  Run, Sector Cup or Knife Edge runs (decided in `gameplay_screen`).
- **Upgrade draft** (`run_upgrades.dart`, `widgets/gameplay/upgrade_draft_overlay.dart`):
  pick 1 of 3 after every level clear; stacks for the run only.
- **Hangar** (`hangar.dart`, `services/hangar_service.dart`, `screens/hangar_screen.dart`):
  permanent coin upgrades stored as UnlockedItems type `hangar`
  (`hangar_<stat>_<level>`, synced via the unlocked-item outbox) + ship frames
  unlocked by campaign clears; applied at run start via `HangarLoadout`.
- **Daily Run** (`services/daily_run_service.dart`): date-seeded `game.rng`
  (shake uses its own RNG) attributed to today's backend "Daily Challenge"
  tournament. Tournament runs play under the tournament's mode.
- **Bosses** (`components/bosses/`): per-type multi-phase kits (BossBrain/
  BossPhase/BossAttack) — EVERY attack telegraphs and aim is captured at
  windup start; phase flips clear boss bullets + flash + hit-stop.
- **Terrain is gameplay**: `TerrainStrip` bands animate (SetPieceEvent
  corridor squeezes; growth rate-clamped; a rising band displaces the
  player without damage). `EnemyType.turret` mounts floor/ceiling.
- **Pooling** (`pools.dart`): bullets/sparks/flashes/popups are
  always-mounted activate/deactivate pools — never construct
  PlayerBullet/EnemyBullet directly; use `game.pools.*`.
- **Sprites**: all components render from `game_assets.dart` paths preloaded
  into `Flame.images` by the pre-game loader (memoized; re-awaited in onLoad).
- **Progress**: per-level bests live in Drift (`StageProgressDao`,
  monotonic merge, stars via `CampaignCatalog.starsFor`); each level clear
  persists incrementally from `gameplay_screen.dart`; sync goes through the
  outbox to `/sync/stage-progress` (absorbing merge server-side).
- Start level rides **route extras** (`levelSelect → playLoading → game`),
  never a cubit. One revive per run (ad / 200 coins); armed store power-ups
  inject via `run_effects.dart`.

## Structure
- `lib/game/` — Flame gameplay (logic off-limits; reskin via palette/render only).
- `lib/theme/` + `lib/ui/cs/` — the Prism Noir design system (barrel `lib/ui/cs.dart`).
- `lib/screens/` — full screens. `lib/widgets/` — shared widgets/overlays.
- `lib/data/` — Drift `database/`, `daos/`, datasources (local cache / remote api).
- `lib/services/` — app services incl. `sync/sync_engine.dart`, `data_sync_service.dart`,
  `unified_user_service.dart`, audio/haptics/ads/analytics, etc.
- `lib/presentation/bloc/` + `lib/providers/` — state. `lib/core/` — DI + network.
- `lib/router/` — go_router. `lib/models/` — DTOs/models. `lib/utils/` — constants/helpers.

## ⚠️ Releasing a new version (macOS / App Store Connect sessions read this)
When you submit a new version on **App Store Connect**, set (or confirm) the
version's App Information URLs to the Cosmo Strike backend pages:
- **Marketing URL:** `https://cosmostrike.pranta.dev/marketing`
- **Support URL:** `https://cosmostrike.pranta.dev/support`
- **Privacy Policy URL:** `https://legal.pranta.dev/privacy/html?projectName=cosmo_strike`

On **Google Play**, the listing's developer website is
`https://cosmostrike.pranta.dev` (it serves the marketing page and AdMob's
`/app-ads.txt`).

**AdMob (both apps):** AdMob looks for `app-ads.txt` on the domain of the
store listing's website — the App Store **Marketing URL** for the iOS app,
the Play **developer website** for the Android app. So after the URLs above
are set (or changed), open AdMob → Apps → each Cosmo Strike app →
**app-ads.txt** and make sure it points at / finds
`https://cosmostrike.pranta.dev/app-ads.txt` (use "Check for updates";
the crawl can take up to 24h). If the backend domain ever changes, update
the store URLs and re-verify in AdMob, or ad demand drops.

The pages live in the backend repo
(`../cosmo-strike-dotnet-api/src/CosmoStrike.Api/wwwroot/`, see its
CLAUDE.md "Public pages"). If a release changes features, prices, Settings
labels or screenshots, update those pages too: they only make claims the
app really backs. The backend must be redeployed on the VPS for page
changes to go live.

### macOS: first iOS build after 3.5.0 (Nov 2026)
Android shipped 3.4.0 / 3.5.0 from Windows; iOS hasn't been built since.
- **Pods:** 3.4.0 added `gma_mediation_unity` + `gma_mediation_liftoffmonetize`
  (Unity Ads / Liftoff bidding, already mapped in AdMob's iOS mediation
  groups). Run `cd ios && pod install --repo-update` before building.
  The 171 SKAdNetwork IDs they need are already in `ios/Runner/Info.plist`.
- **60 FPS cap:** `CADisableMinimumFrameDurationOnPhone` is now `false` on
  purpose, so iPhones run at 60 Hz (the game is tuned and profiled at 60 only;
  Android does the same via `preferredRefreshRate` in `MainActivity`). Don't
  flip it back. ProMotion iPads can still run 120 Hz.
- **Paywall perks:** the shared `StrikeCommandOffer` no longer lists "Lucky
  draw: rarer pickups" or "More in-flight pickups": the game never
  implemented them. The ONLY real Strike Command perks are: no ads; every
  Livery, Exhaust and Sector; 1.5× credits; the Frontline Command lane
  (plus the Tactical Gear / Cup Pass resupply the offer lists). Nobody is
  subscribed to anything (owner, Nov 2026).
- **App Store Connect cleanup to mirror what was done on Google Play
  (2026-11-19). Use Claude in Chrome on appstoreconnect.apple.com → Cosmo
  Strike → Monetization:**
  - *Subscriptions → Strike Command group* (`command_monthly`,
    `command_annual`): check each localization's Display Name and
    Description and the group's display name. Remove any claim beyond the
    real perks above (no "Lucky draw", no "pickups", no Snake-era words:
    skins/trails/themes/coins/Battle Pass/tournament). Play's versions list
    no benefits at all.
  - *Old Pro subscriptions* (`pro_monthly` / `pro_yearly`, pre-3.2
    "Cosmo Strike Pro"): on Play their base plans are inactive, so they
    can't be bought; their benefits were cut to just "No ads" and they were
    renamed "Retired - Cosmo Strike Pro Monthly/Yearly". On App Store
    Connect, remove them from sale (or leave them unavailable) and replace
    any Snake-era description the same way. The app only uses these IDs to
    label old purchase-history rows (`settings_screen._getTypeFromProductId`),
    so retiring them is safe.
  - *In-App Purchases:* Play has 33 one-time products, all already on the
    3.2 names (Cup Passes, Fleet Kits, Sectors, Exhausts, Liveries, Credits;
    see `docs/rebrand/REBRAND_SPEC.md`). Confirm the iOS display names and
    descriptions match and none still say skins/trails/themes/coins.
  - *App Store description / promotional text:* the Play listing describes
    Strike Command as "no ads, every Livery, Exhaust and Sector, 1.5×
    credits and the Frontline Command lane" — use the same claims.
  - Don't change prices, product IDs or availability of the live
    `command_*` products.
- **Liftoff iOS app** is still "not live yet" in Liftoff (store link pending).
- **Release-test on an iPhone:** both Strike Command entry points (Home →
  Command, Armory → Command) show the same plans, trial and price line; the
  Supply Drop shows once per launch and stays closed; the HUD/pause/quit
  confirm look right.

## Workflow
- **Profiling / demo mode:** `flutter build apk --release
  --dart-define=COSMO_AUTOPILOT=true [--dart-define=COSMO_AUTOPILOT_LEVEL=N]`
  boots straight into an invincible autopilot run that loops through the
  levels and never saves progress. `lib/debug/perf_monitor.dart` logs
  `[PERF]` (fps, build/raster percentiles, frames over the 16.7 ms budget)
  and `[PERF-SLOW]` (which scene each slow frame belonged to) to logcat
  every 5 s: `adb logcat -s flutter:I | grep PERF`. Release-signed so it
  installs over the store build. Never ship with the define.
- Run `flutter analyze <file>` after edits and fix until **"No issues found!"**
  before committing.
- ⚠️ **`dart run flutter_native_splash:create` rewrites AndroidManifest.xml and
  STRIPS `android:screenOrientation="sensorLandscape"` from MainActivity** —
  after every icon/splash regeneration, re-add it or the app boots in portrait.
  It also rewrites `res/values*/styles.xml` and drops the edge-to-edge items
  (transparent `statusBarColor`/`navigationBarColor`) — re-add those too.
- **Edge-to-edge (Play Console):** `MainActivity` calls
  `WindowCompat.enableEdgeToEdge(window)` and hides the bars via
  `WindowInsetsControllerCompat`. Never pass bar colours to
  `SystemUiOverlayStyle` in Dart: they route through Android's deprecated
  `setStatusBarColor`/`setNavigationBarColor`, which Play flags.
- **R8:** keep `proguard-rules.pro` minimal — no blanket
  `-keep class <sdk>.** { *; }` (SDKs ship consumer rules; blanket keeps
  disable optimization and Play flags it). After any R8/dependency change,
  release-test sign-in, purchases, ads and notifications.
  Icon/splash config lives in the standalone `flutter_launcher_icons.yaml` and
  `flutter_native_splash.yaml` files at the app root (these override pubspec —
  keep config ONLY there, never duplicated in pubspec.yaml).
  Brand mark = the prism rocket; icon/splash sources in `assets/branding/`
  (not bundled); in-app brand art in `assets/images/brand/`.
- ⚠️ `.env` ships as a Flutter asset; AGP 9 drops dot-files from release
  APK/AABs unless `androidResources.ignoreAssetsPattern` (app
  `build.gradle.kts`) omits the dot-file rule. Keep it, and after toolchain
  bumps confirm `assets/flutter_assets/.env` is in the release APK.
- Drift schema is currently collapsed to **schemaVersion 1**; changing tables may
  require an `adb shell pm clear com.pranta.cosmostrike` on dev devices.
- Keep home-screen walkthrough `GlobalKey`s (`HomeWalkthrough.*`) attached to their
  logical widgets after any re-layout.

## Ad mediation (shared AdMob account)
This app is part of the owner's shared AdMob account with mediation (Unity Ads, Liftoff,
and Open Bidding exchanges). Read `docs/AD_MEDIATION.md` before any ads work: it lists
this app's AdMob IDs, which ad units sit in the shared mediation groups, the app-ads.txt
rule, and how to add the Unity/Liftoff adapters.
