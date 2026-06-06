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
centered max-width glass cards for forms/dialogs, two-region (left/right) layouts
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

## Stack & conventions
- **State management:** `flutter_bloc` Cubits/Blocs in `lib/presentation/bloc/`
  plus some `provider`-based providers in `lib/providers/`.
- **DI:** `get_it` — registrations in `lib/core/di/injection.dart` (`getIt<…>()`).
- **Routing:** `go_router` in `lib/router/app_router.dart` (`AppRoutes`, `context.push`).
- **Game:** Flame engine in `lib/game/` — gameplay LOGIC is off-limits for UI work
  (`cosmo_strike_game.dart`, state machine, `ValueNotifier`s); only colors
  (`cosmo_palette.dart`), component `render()` paint, and the Flutter HUD change.
- **Auth/users:** `unified_user_service.dart` (guest / anonymous / Google),
  Firebase Auth; guests can upgrade and keep local progress via the first-sign-in pull.

## Visual design — "Command HUD" (clean / minimal)
Sleek sci-fi neon aesthetic: deep-indigo/near-black base, neon cyan + magenta
accents, glassmorphic panels, a full custom-painted deep-space background
(`lib/ui/widgets/starfield_background.dart`: gradient + nebulae + sun/planets/moon
+ a drifting parallax starfield & comet). Design system lives in `lib/ui/`
(barrel `lib/ui/design.dart`):
- `CommandScaffold` — app shell (space bg + glass top bar + landscape SafeArea).
- `GlassPanel` / `HoloCard` — frosted-glass surfaces / tappable tiles.
- `NeonButton` — the standard button. `HudChip` — telemetry pill (`bordered` opt-out).
- `StarfieldBackground`, `HoloLogo`, `LaunchEmblem`, `GameTokens`.
- Per-skin neon getters on `GameTheme` (`lib/utils/constants.dart`): `neonPrimary`,
  `neonSecondary`, `glow`, `stroke`, `surface`, `surfaceGlass`, `textPrimary`,
  `textMuted`, `gridLine`.

**Clean/minimal direction (hard rules, learned from the home/loading/daily
redesigns — apply to every future screen):**
- **No borders, ever**: no hairline strokes on cards, buttons, chips, pills,
  app bars, or the back button.
- **Prefer FULLY transparent over glass**: list cards, nav chips, top command
  bars, and hero CTAs float straight on the starfield — no fills, no gradients,
  and no `GlassPanel`/`BackdropFilter` behind them (the blur frosts the scene
  into a visible dark box even with a transparent fill). Reserve subtle tinted
  fills for deliberate highlights only (e.g. a gold celebration card).
- **Keep tap targets**: transparent tappables need
  `behavior: HitTestBehavior.opaque` (whole area tappable, not just the paint).
- Definition comes from **neon icon discs, slim (≈6px) progress bars, glow,
  spacing, and the cyan/magenta accents** — never outlines or boxes.
- **Landscape two-region layouts** (e.g. telemetry/summary left, list right);
  side panels must **never scroll** — render at natural size inside
  `FittedBox(scaleDown)` so they use the height responsively.
- Background scenery is dimmed (bodies ~50%, stars capped) so white/grey text
  stays readable over it — don't brighten it back up under text.

Build new screens with `CommandScaffold` + these widgets. Reference screens:
`home_screen.dart` (menu hub), `leaderboard_screen.dart` (list/detail),
`username_setup_screen.dart` / `email_auth_screen.dart` (centered form card).

## Gameplay: sprite-based checkpoint campaign
The Flame game is a 12-level campaign (4 biomes × 3 levels) with modes as
modifiers on top. Key pieces (all in `lib/game/`):
- **Pure-data levels**: `levels/level_def.dart` (EnemyType/BossDef/BiomeDef/
  WaveDef schemas) + `levels/level_catalog.dart` (the 12 LevelDefs — adding a
  level = appending data + a name in `lib/utils/campaign_catalog.dart`).
- **Game-time spawning**: `levels/wave_runner.dart` — never use
  `Future.delayed` for spawns (wall-clock ignores `pauseEngine()` and breaks
  pause/revive).
- **Sprites**: all components render from `game_assets.dart` paths preloaded
  into `Flame.images` by the pre-game loader (memoized; re-awaited in onLoad).
- **Progress**: per-level bests live in Drift (`StageProgressDao`,
  monotonic merge, stars via `CampaignCatalog.starsFor`); each level clear
  persists incrementally from `gameplay_screen.dart`; sync goes through the
  outbox to `/sync/stage-progress` (absorbing merge server-side).
- Start level rides **route extras** (`levelSelect → playLoading → game`),
  never a cubit. One revive per run (ad / 200 coins); armed store power-ups
  inject via `run_effects.dart`.
- Gameplay SFX keys exist but `assets/audio/` has no files yet — hooks
  no-op silently (see `game_audio.dart` / AudioService fallback rule).

## Structure
- `lib/game/` — Flame gameplay (logic off-limits; reskin via palette/render only).
- `lib/ui/` — the command-HUD design system (widgets + tokens; barrel `design.dart`).
- `lib/screens/` — full screens. `lib/widgets/` — shared widgets/overlays.
- `lib/data/` — Drift `database/`, `daos/`, datasources (local cache / remote api).
- `lib/services/` — app services incl. `sync/sync_engine.dart`, `data_sync_service.dart`,
  `unified_user_service.dart`, audio/haptics/ads/analytics, etc.
- `lib/presentation/bloc/` + `lib/providers/` — state. `lib/core/` — DI + network.
- `lib/router/` — go_router. `lib/models/` — DTOs/models. `lib/utils/` — constants/helpers.

## Workflow
- Run `flutter analyze <file>` after edits and fix until **"No issues found!"**
  before committing.
- ⚠️ **`dart run flutter_native_splash:create` rewrites AndroidManifest.xml and
  STRIPS `android:screenOrientation="sensorLandscape"` from MainActivity** —
  after every icon/splash regeneration, re-add it or the app boots in portrait.
  Icon/splash config lives in the standalone `flutter_launcher_icons.yaml` and
  `flutter_native_splash.yaml` files at the app root (these override pubspec —
  keep config ONLY there, never duplicated in pubspec.yaml).
  Brand mark = Material `Icons.rocket_launch` in neon cyan; sources in
  `assets/icon/` (not bundled).
- Drift schema is currently collapsed to **schemaVersion 1**; changing tables may
  require an `adb shell pm clear com.pranta.cosmostrike` on dev devices.
- Keep home-screen walkthrough `GlobalKey`s (`HomeWalkthrough.*`) attached to their
  logical widgets after any re-layout.
