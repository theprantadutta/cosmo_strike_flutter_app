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

**Clean/minimal direction:** favor **borderless** surfaces (no hairline strokes),
let the space background show through (transparent fills over heavy glass tints
where it reads better), and lean on glow, spacing, and the neon accents for
definition instead of outlines. Default new surfaces to no border.

Build new screens with `CommandScaffold` + these widgets. Reference screens:
`home_screen.dart` (menu hub), `leaderboard_screen.dart` (list/detail),
`username_setup_screen.dart` / `email_auth_screen.dart` (centered form card).

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
- Drift schema is currently collapsed to **schemaVersion 1**; changing tables may
  require an `adb shell pm clear com.pranta.cosmostrike` on dev devices.
- Keep home-screen walkthrough `GlobalKey`s (`HomeWalkthrough.*`) attached to their
  logical widgets after any re-layout.
