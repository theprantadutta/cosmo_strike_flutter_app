# Cosmo Strike — Assets Needed

The game is **fully playable today on programmatic placeholders** (geometric
vector sprites + particle effects rendered in-engine, a procedural starfield,
and no audio). This document lists the real art/audio to commission so the
placeholders can be swapped in. Nothing here blocks compiling or playing.

Drop sprites under `cosmo_strike_flutter_app/assets/images/`, audio under
`cosmo_strike_flutter_app/assets/audio/`. They are already declared as asset
folders in `pubspec.yaml`. Items marked **[Pranta to provide]** are things that
can't be generated in-engine (final audio especially).

Conventions: PNG with transparency unless noted, designed for the amber-phosphor
palette (hull `#ffc14d`, energy `#5cc8ff`, highlight `#eaf6ff`, warm-dark
backgrounds `#0a0501`/`#180b03`/`#2c1707`, grid `#8a5a22`). Target density: provide
@1x dimensions below plus @2x/@3x variants (Flutter resolution-aware folders) or a
single high-res sprite Flame can downscale.

---

## 1. Player

| Asset | Spec | Notes |
|---|---|---|
| `player_ship.png` | 96×64, transparent | Hero ship, nose pointing right. Replaces the amber arrow placeholder in `player_ship.dart`. |
| `player_thruster.png` (anim) | 32×32, 4–6 frames | Engine flame loop at the ship's rear. |
| `player_shield.png` | 128×128, transparent | Soft energy bubble overlay when shield power-up is active. |

## 2. Enemies (one sprite per movement archetype)

| Asset | Spec | Movement (in `enemy.dart`) |
|---|---|---|
| `enemy_straight.png` | 64×48 | Flies straight left. |
| `enemy_sine.png` | 64×48 | Sine-wave weaver. |
| `enemy_dive.png` | 64×48 | Dives toward the player. |
| `enemy_tracker.png` | 64×48 | Slowly tracks the player's Y. |
| (optional) per-enemy 2-frame idle anim | 64×48, 2 frames | Subtle thruster/blink. |

## 3. Boss (per stage; at least one to start)

| Asset | Spec | Notes |
|---|---|---|
| `boss_stage1.png` | 256×220, transparent | End-of-stage boss hull. Replaces hexagon placeholder in `boss.dart`. |
| `boss_core.png` (anim) | 48×48, 3–4 frames | Pulsing weak-point core. |
| Additional `boss_stageN.png` | 256×220 | One per stage as stages are authored. |

## 4. Projectiles

| Asset | Spec | Notes |
|---|---|---|
| `bullet_player.png` | 24×8 | Default amber/blue shot. |
| `bullet_laser.png` | 40×8 | Laser power-up beam. |
| `bullet_enemy.png` | 12×12 | Enemy/boss shot. |

## 5. Power-ups (icon per type — 7 total)

32×32 transparent icons matching `PowerUpKind` in `power_up.dart`:
`rapid_fire`, `spread`, `laser`, `shield`, `extra_life`, `bomb`, `score_multiplier`.
Current placeholder draws a colored disc with a letter glyph.

## 6. Explosions / FX

| Asset | Spec | Notes |
|---|---|---|
| `explosion_small.png` (anim) | 64×64, 6–8 frames | Enemy death. Currently a particle burst. |
| `explosion_large.png` (anim) | 128×128, 8–12 frames | Boss death. |
| `hit_spark.png` (anim) | 32×32, 3–4 frames | Bullet impact. |

## 7. Backgrounds / parallax

Currently a procedural 3-layer star field (`starfield.dart`). For richer depth:

| Asset | Spec | Notes |
|---|---|---|
| `parallax_far.png` | 1024×512, seamless horizontally | Distant nebula/stars (slow). |
| `parallax_mid.png` | 1024×512, seamless, transparent | Mid debris/planets. |
| `parallax_near.png` | 1024×512, seamless, transparent | Foreground dust (fast). |
| Per-stage background tints/variants | — | Optional per-stage mood. |

## 8. HUD / branding

| Asset | Spec | Notes |
|---|---|---|
| `cosmo_strike_logo.png` | ≥1024 wide, transparent | Menu/title wordmark. (Icon `assets/logo/cosmo_strike_icon_512_amber.png` exists.) |
| `hud_life_icon.png` | 24×24 | Replaces the `Icons.flight` life pip. |
| Splash / store / launcher art | per store specs | Run `flutter_native_splash` + `flutter_launcher_icons` once final art lands (configs already point at the logo). |

## 9. Audio — **[Pranta to provide]** (cannot be generated in-engine)

SFX (short WAV/OGG) under `assets/audio/`:

| File | Trigger |
|---|---|
| `sfx_fire.wav` | Player shot |
| `sfx_enemy_hit.wav` | Bullet hits enemy |
| `sfx_explosion.wav` | Enemy destroyed |
| `sfx_boss_explosion.wav` | Boss destroyed |
| `sfx_powerup.wav` | Power-up collected |
| `sfx_player_hit.wav` | Player takes damage |
| `sfx_game_over.wav` | Run ends |
| `sfx_stage_clear.wav` | Stage cleared |

Music (looping OGG/MP3):

| File | Context |
|---|---|
| `music_menu.ogg` | Menus / home |
| `music_gameplay.ogg` | In-stage gameplay |
| `music_boss.ogg` | Boss fight |

> Audio is wired through `flame_audio`; until these files ship, the game runs
> silent (audio calls are guarded). See `lib/game/` for the call sites.

---

## Follow-ups (tracked separately, not assets)
- Achievement / daily-challenge / weekly-quest seed **copy** could use another
  flavor-text polish pass for shmup tone (the underlying metric is already
  "enemies destroyed").
- Per-stage boss design + stage backgrounds expand as stages are authored.
