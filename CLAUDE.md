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

## Workflow
- Run `flutter analyze <file>` after edits and fix until **"No issues found!"**
  before committing.
- ⚠️ **`dart run flutter_native_splash:create` rewrites AndroidManifest.xml and
  STRIPS `android:screenOrientation="sensorLandscape"` from MainActivity** —
  after every icon/splash regeneration, re-add it or the app boots in portrait.
  Icon/splash config lives in the standalone `flutter_launcher_icons.yaml` and
  `flutter_native_splash.yaml` files at the app root (these override pubspec —
  keep config ONLY there, never duplicated in pubspec.yaml).
  Brand mark = the prism rocket; icon/splash sources in `assets/branding/`
  (not bundled); in-app brand art in `assets/images/brand/`.
- Drift schema is currently collapsed to **schemaVersion 1**; changing tables may
  require an `adb shell pm clear com.pranta.cosmostrike` on dev devices.
- Keep home-screen walkthrough `GlobalKey`s (`HomeWalkthrough.*`) attached to their
  logical widgets after any re-layout.
