# Prism Noir redesign

Branch `redesign/prism-noir`. A visual-only redesign of the whole app to the
Prism Noir kit: near-black canvas, iridescent prism accents used sparingly,
Syne + IBM Plex Mono type, hairlines instead of cards. Game logic, economy,
IAP/ads, backend calls, analytics events, routes and persistence are unchanged.

## What changed
- **Design system:** `lib/theme/cosmo_theme.dart` (tokens, type scale, motion,
  ThemeData) and `lib/ui/cs/` (barrel `lib/ui/cs.dart`): buttons, prism ring and
  text, progress lines and rings, tiles, stat grid, list rows, avatars, chips,
  segmented control, toggle chips, dialogs, toasts, loading/empty/error states,
  scaffold + top bar + two-region split. Text scaling is capped at 1.15×.
- **Responsive:** every size is scaled from the 960×432 design frame by
  `context.cs` (0.72–1.4, tighter axis), so the same composition fits a
  640×360 phone, iPhones, Android tablets and iPads. Verified on a Galaxy A24
  and a Galaxy Tab A9+, plus iPad 11", iPhone 15 and 640×360 proportions emulated
  on the tablet.
- **Fonts / icons:** Syne (static 400–800 cut from the variable font so weights
  are exact everywhere) and IBM Plex Mono; Material Symbols Rounded (filled).
  Orbitron, Rajdhani and flutter_animate are removed.
- **Brand:** new launcher icons (adaptive + monochrome, iOS, web), notification
  silhouette, and a seamless splash: the native splash and the first Flutter
  frame draw the same 120dp prism rocket, then the Flutter splash animates the
  wordmark, prism line and status into place (same approach as ai-persona).
- **Screens:** every route, overlay and dialog is ported (see
  `docs/redesign-checklist.md`).
- **Gameplay art:** all 62 sprites redrawn (graphite bodies, prism outlines,
  baked glow) at their original sizes and frame layouts, so hitboxes and
  animations are unchanged. 3-layer parallax starfield.
- **Themes:** purchased colour themes now tint gameplay only (ship stripe,
  thrust, shots, battlefield washes) via `CosmoPalette.applyGameTheme`; menus
  are always Prism Noir. Store and settings copy updated to say so.
- **Removed:** the old Command HUD widget library, AppBackground, the old
  particle system, GameTypography and unused helpers.

## Screenshots
`docs/redesign-screens/` — tablet, iPad, iPhone, small phone and A24 captures.
Compare against the kit's `screenshots/01–10`.

## Behaviour notes for review
- Share / About / How to play moved into the main menu's ··· overflow; the
  debug log viewer lives there too in debug builds.
- First-launch control and game-mode pickers, the loadout sheet, the daily bonus
  and the account-upgrade prompt are centred dialogs instead of bottom sheets.
- Restore purchases is now also offered on the Pro paywall and the store's Pro tab
  (same flow as Settings).
- The leaderboard FRIENDS segment opens the friends leaderboard screen; TOP %
  is computed from rank ÷ players.
- The HUD missile ring shows the graze meter (the cooldown is private game
  state); the thin bar under the score shows hull health.
- The splash waits for its 1.7s entrance before navigating.

## Not ported / follow-ups
- Battle pass and store keep the hard-coded "SAVE 33%" (mock shows 17%).
- Boss display names for the HUD are a local map; only Iron Dreadnought is
  confirmed by the mock.
- Pre-existing analyzer warnings in `coins_cubit.dart` / `sync_engine.dart`
  (unawaited returns in try blocks) were left alone — logic files.
- Seen during QA, not caused by the redesign: the daily bonus popup reappeared
  after being claimed once on a guest account.
