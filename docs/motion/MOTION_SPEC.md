# Cosmo Strike — Motion Spec

Motion in Prism Noir is quick, physical and quiet: things press, settle and pop,
they never glow, blur or loop. Every number below is a token in `CsMotion`
(`lib/theme/cosmo_theme.dart`); every widget is in the `lib/ui/cs.dart` barrel.
If an interaction isn't listed, pick the closest row rather than inventing a
new duration.

## Tokens

| Token | ms | Use |
|---|---|---|
| `instant` / `fast` | 120 | press colour, reduce-motion fades |
| `quick` | 180 | press-down scale, toast exit |
| `base` | 200 | chip/segment fill crossfade, small swaps |
| `release` | 250 | press release spring |
| `screen` | 280 | route transitions |
| `slow` | 320 | dialog in, panel expand |
| `roll` | 380 | one odometer character |
| `gentle` | 400 | fade-ups, toast in, chip pops |
| `pop` | 450 | `CsPop` |
| `countUp` | 600 | big number count-ups |
| `lingering` | 900 | hero moments, story-telling progress fills |
| `staggerStep` | 55 | per list slot; capped at `staggerMaxSlots` = 8 |

| Curve | Cubic | Character | Use |
|---|---|---|---|
| `standard` | (.2, 0, 0, 1) | decelerate | colour, layout |
| `easeOutSoft` | (.2, .8, .2, 1) | settles gently | fades, fade-ups, fills, press-down |
| `springSoft` | (.3, 1.5, .5, 1) | ~8% overshoot | press release, toggles, counters |
| `springPop` | (.3, 1.8, .5, 1) | ~15% overshoot | pops: rewards, stars, chain, chips |
| `dropIn` | (.3, .9, .4, 1) | fast in, soft land | toasts, cards arriving |
| `exit` | (.4, 0, .5, 1) | accelerate away | anything leaving |
| `travel` | (.45, 0, .25, 1) | ease in-out | moving between two on-screen spots |

Spring curves leave 0..1. Use them on scale / translation / size only; clamp
before opacity (`CsBeatSheet.opacity(name)` does).

## Interactions

| Interaction | Motion | Duration · curve | Haptic | Reduce motion |
|---|---|---|---|---|
| **Screen transition** | Theme `FadeForwardsPageTransitionsBuilder` (bg `CsColors.bg`) | 280 · `standard` | none | OS-driven; keep as is |
| **Press** (`CsPressable`) | scale → 0.97 on down; spring back on release | down 180 `easeOutSoft`, up 250 `springSoft` | per widget (below) | dip 120 linear, no spring |
| **Buttons** (`CsButton`) | press | as Press | primary / secondary / premium / prism: light; text: selection | as Press |
| **Icon buttons** (`CsIconButton`) | press | as Press | selection | as Press |
| **Tabs / segments** (`CsSegmented`) | fill crossfades to the white pill; indicator travels | 200 `standard`; indicator 280 `travel` | selection (only when changing) | 120 crossfade, indicator jumps |
| **Toggles** (`CsToggleChip`, switches) | border/ink crossfade; knob slides | 200 `standard`; knob 220 `springSoft` | selection | 120 crossfade, knob jumps |
| **Dialogs** (`CsDialog`) | scrim fades; card scales 0.96 → 1 and fades | in 320 `easeOutSoft` (scale `springSoft`), out 180 `exit` | none (the action that opened it already ticked) | 120 fade, no scale |
| **Toasts** (`showCsToast`, `RewardToast`) | drop 12 px + fade in; fade + rise out | in 400 `dropIn`, out 180 `exit` | reward toast: success | 120 fade |
| **Lists / grids** (`CsFadeUp`) | fade + rise 10 px, staggered by slot | 400 `easeOutSoft`, +55/slot, cap slot 8 | none | 120 fade, no rise, no stagger |
| **Number roll** (`CsOdometer`) | changed characters roll in clipped slots; up rises, down drops | 380 `easeOutSoft` per slot | none | instant |
| **Count-up** (results totals) | tween the int, render with `CsOdometer` or tabular `number` style | 600 `easeOutSoft` | none | instant |
| **Progress fill** (`CsProgressLine`, `CsRingProgress`) | animate to the new value | 600 `easeOutSoft` (900 `lingering` on results) | none | 120 linear |
| **Reward pop** (claimed reward, star, unlock) | `CsPop`: swell to 1.12, settle on `springPop` | 450 | success (once per claim, not per star) | none; value just updates |
| **HUD pops** (score milestone, chain ×N, pickup) | `CsPop` with `peak: 1.08–1.15` | 450 | the game already fires its own; don't add UI haptics | none |
| **Results beat sheet** (level clear / game over) | `CsBeatSheet` timeline, below | ≈ 2.2 s total | success on stars / medium on new best | final frame shown at once (wrap in one 200 ms fade) |

### Results beat sheet (template)

`t0` is when the results overlay mounts. A tap anywhere calls `skipToEnd()`.

| t (ms) | Beat | Duration · curve |
|---|---|---|
| 0 | Title fades up | 400 · `easeOutSoft` |
| 200 | Score counts up (`CsOdometer` / count-up) | 600 · `easeOutSoft` |
| 700 | Stars pop one by one, 120 ms apart (haptic success on the last) | 450 · `springPop` |
| 1100 | New-best chip pops (medium haptic) | 450 · `springPop` |
| 1300 | Stat rows fade up, 55 ms stagger | 400 · `easeOutSoft` |
| 1700 | Rewards progress fills | 600 · `easeOutSoft` |
| 1800 | Buttons fade in (interactive from t0 regardless) | 320 · `easeOutSoft` |

```dart
late final sheet = CsBeatSheet(vsync: this, beats: {
  'title': const CsBeat(at: 0, duration: 400),
  'score': const CsBeat(at: 200, duration: 600),
  'star1': CsBeat(at: 700, duration: 450, curve: CsMotion.springPop),
  'star2': CsBeat(at: 820, duration: 450, curve: CsMotion.springPop),
  'star3': CsBeat(at: 940, duration: 450, curve: CsMotion.springPop, onStart: CsHaptic.success.play),
  'buttons': const CsBeat(at: 1800, duration: 320),
});
// in didChangeDependencies (once): sheet.play(reduceMotion: CsReduceMotion.of(context, listen: false));
FadeTransition(opacity: sheet.opacity('title'), child: title);
ScaleTransition(scale: sheet['star1'], child: star);
```

## Reduce motion

`CsReduceMotion.of(context)` is true when any of: a widget's own
`reduceMotion:` override, a `CsReduceMotion(reduceMotion: true)` scope, the
in-app setting (Settings → Access → Reduce motion, `PreferencesService`), or
the OS `MediaQuery.disableAnimations`. Helpers: `CsReduceMotion.duration(ctx,
full, reduced: …)` and `CsReduceMotion.curve(ctx, curve)`.

General fallback: no movement, no overshoot, no stagger; state changes become a
≤120 ms linear crossfade or are instant. The press dip stays (it's feedback,
not motion). Haptics are NOT affected: they have their own toggle.

## Haptics

`CsHaptic { none, selection, light, medium, success }` → `HapticService`, which
returns early when the player's Haptics toggle is off (hydrated from Drift at
startup, flipped live by Settings and the pause menu). Never call
`HapticFeedback.*` directly from UI: it bypasses the toggle. Fire once per user
action; when a button already has a default haptic, don't add another in its
`onPressed`.

## Performance rules (must hold 60 FPS on a Galaxy A24)

1. **FadeTransition, not Opacity.** Never rebuild an `Opacity` widget per frame
   over a subtree. `FadeTransition` / `AnimatedOpacity` update a composited
   layer and drop it entirely at 0 and 1.
2. **No blur or saveLayer in animated content.** No `BackdropFilter`,
   `ImageFiltered`, `ShaderMask` or anti-aliased clips on anything that moves
   (the pause scrim is the one static blur). Use hard-edge `ClipRect` only.
3. **RepaintBoundary around independently animating pieces** (HUD counters,
   pops, odometers, rings) so their repaint doesn't drag the screen along.
   `CsPop` and `CsOdometer` already include one.
4. **Drive per-frame motion through a Listenable**, i.e. `*Transition` widgets
   or `AnimatedBuilder` with the static subtree passed as `child`. Never
   `setState` a big subtree on every tick.
5. **One controller per choreography.** Many beats → one `CsBeatSheet`, not a
   controller per element.
6. **No looping animation in menus** (no shimmer, no breathing glows). A
   one-shot entrance or a ring turn on a real event is fine.
7. **Animate transforms and opacity, not layout.** Avoid animating
   width/height/padding of large subtrees; prefer scale/translate.
8. **Profile before shipping** a new animated screen: the autopilot build plus
   `lib/debug/perf_monitor.dart` (`[PERF]` logcat lines) must show no frames
   over 16.7 ms attributable to it.
