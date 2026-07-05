# Cosmo Strike — Asset Status: COMPLETE ✅

This file used to be the commission list for real art/audio while the game ran
on programmatic placeholders. That work is done — **every sprite and sound the
game references now ships in the repo** (verified July 2026):

- **Sprites**: all 62 paths in `lib/game/game_assets.dart` exist under
  `assets/game/` (player / enemies / bosses / projectiles / powerups / fx /
  terrain), each directory declared in `pubspec.yaml`.
- **Audio**: all 26 SFX keys preloaded by `lib/services/audio_service.dart`
  plus `background_music.wav` exist under `assets/audio/` (all `.wav`).
- Missing-key lookups remain non-fatal by design: `playSound()` no-ops and
  sprites fall back to their programmatic placeholder renderers.

## Adding new assets

- Sprites: drop under the matching `assets/game/<category>/` folder and add
  the path to `game_assets.dart` (`GameAssets.all` drives preloading).
- Audio: drop a `.wav` under `assets/audio/` and register the key in
  `audio_service.dart` (`_soundsToPreload`) or `lib/game/game_audio.dart`.
- Palette/art direction lives in `lib/game/cosmo_palette.dart` and the
  Command-HUD design notes in `CLAUDE.md`.
