# Cosmo Strike 3.2 — Identity Rebrand Spec

**Why:** App Store rejected 3.1.1 under Guideline 4.3(a) (spam). Cosmo Strike
was forked from Snake Classic (same developer account) and still mirrors it
almost 1:1 below the visuals: identical cosmetics catalog (6 themes, 11 skins,
11 trails, same names), identical product-ID suffixes, identical game-mode enum
(classic/zen/speedChallenge/…), 114 achievements that are Snake Classic's with
renamed titles (`first_bite`, `all_food_types`, `foodie_*`, `anaconda`…), the
same meta-feature set and names (Battle Pass, Tournaments, Daily Challenges,
Power-ups, Ranks, Store tabs) and copy ("The original ship appearance",
"Every skin here is yours with your subscription").

**Goal:** after this release nothing a reviewer, player or binary diff sees
should read as Snake Classic. Every catalog item, product ID, mode, achievement,
meta-feature name and user-facing string becomes space-shooter native.

**Constraints**
- Nobody has bought anything on either store → the old product IDs are simply
  retired. New IDs everywhere (iOS + Android). No purchase migration.
- Existing Android players DO have local progress (Drift) and backend rows →
  every rename of a persisted ID (modes, achievements, cosmetics, power-up
  keys, bundle IDs) needs a **legacy alias / migration** so nobody loses
  progress or crashes on old data. Pattern: parse-with-fallback on the client
  (`fromLegacy`), an EF Core data migration on the server.
- Gameplay logic in `lib/game/` stays as is (per CLAUDE.md). Only data,
  names, colours and render paint change there.
- Prism Noir design system stays (it is already unique to Cosmo Strike).
- Version: **3.2.0+18**.

---

## 1. Vocabulary (user-facing renames)

| Old (Snake-mirrored) | New | Notes |
|---|---|---|
| Coins / Star Coins | **Credits** (`CR`) | Display only. Internal field/table names (`coins`) stay. |
| Pro / Cosmo Strike Pro | **Strike Command** | Subscription. "Command" badge instead of "PRO". |
| Battle Pass / Season Pass / Pass | **Frontline** (Season N · 50 tiers) | "Frontline track", "Command track" (premium lane). |
| Tournaments / Events | **Sector Cups** | A tournament = a "Cup". |
| Tournament tickets bronze/silver/gold | **Cup Passes: Scout / Strike / Ace** | Internal tiers bronze/silver/gold keep their wire names. |
| Daily Challenges | **Daily Directives** | (Game Over already says "Daily Directives".) |
| Weekly Quests | **Weekly Ops** | |
| Achievements / Awards / Trophies | **Commendations** | Rarity names: Service / Bronze Star / Silver Star / Gold Star / Nova (common/rare/epic/legendary/diamond). |
| Ranks / Leaderboard | **Standings** | Global / Weekly / Squadron. |
| Friends | **Squadron** (members = wingmates) | |
| Replays | **Flight Recorder** | |
| Statistics / Stats | **Service Record** | |
| Profile | **Pilot File** | |
| Store | **Armory** | Tabs below. |
| Power-ups (store) | **Tactical Gear** | Armed before a run ("loadout" already used by Hangar — use "gear"). |
| Themes | **Sectors** (gameplay colour palettes) | |
| Skins | **Liveries** | Paint schemes for the hull. |
| Trails | **Exhausts** | Engine exhaust effects. |
| Cosmetic bundles | **Fleet Kits** | |
| Coin packs | **Credit Caches** | |
| Daily bonus | **Supply Drop** (daily) | |
| Level (player XP level) | **Rank** stays "LV" in compact UI; long form "Pilot Rank". | |

Armory tabs (in order): **Command · Credits · Liveries · Exhausts · Sectors · Gear · Cup Passes**.

---

## 2. Store catalog (new product IDs)

Prefix stays `com.pranta.cosmostrike.` (bundle ID). All IDs below are the bare
suffix. Prices = USD tier.

### 2.1 Subscription — Strike Command (new subscription group "Strike Command")
| ID | Name | Price | Trial |
|---|---|---|---|
| `command_monthly` | Strike Command — Monthly | $4.99 / mo | 3 days |
| `command_annual` | Strike Command — Annual | $39.99 / yr | 7 days |

(Battle-pass IAP `battle_pass_season` was never sold — removed entirely. The
Frontline premium track is unlocked by Strike Command or by credits, see §5.)

### 2.2 Credit Caches (consumable)
| ID | Name | Credits | Price |
|---|---|---|---|
| `credits_cache` | Credit Cache | 120 | $0.99 |
| `credits_crate` | Credit Crate | 650 (600 + 50) | $4.99 |
| `credits_vault` | Credit Vault | 1,500 (1,300 + 200) | $9.99 |
| `credits_reserve` | Fleet Reserve | 3,400 (2,800 + 600) | $19.99 |

### 2.3 Liveries (non-consumable) — 8, not 11
Each livery has its own palette AND a distinct hull decal pattern (render
paint in `player_ship.dart`, not just a flat tint): `none`, `stripe`
(racing stripe), `chevron`, `split` (two-tone diagonal), `hex` (hex mesh),
`pulse` (animated sweep).

| enum / ID | Name | Palette | Decal | Price |
|---|---|---|---|---|
| `standard` (free) | Standard Issue | stock | none | free |
| `livery_aurum` | Aurum | gold #FFD58A → #B8862E | stripe | $1.99 |
| `livery_vanta` | Vanta | matte black #15151A + cyan edge #7CF5FF | split | $1.99 |
| `livery_redline` | Redline | crimson #FF4D5E → #7A0F1E | chevron | $1.99 |
| `livery_glacier` | Glacier | ice #BFF3FF → #3A8DDE | hex | $2.99 |
| `livery_ionic` | Ionic | electric cyan #7CF5FF → violet #A78BFA | pulse | $2.99 |
| `livery_solstice` | Solstice | amber #FFB347 → pink #FF8AD8 | split | $2.99 |
| `livery_viridian` | Viridian | mint #9BFFC8 → teal #138A72 | chevron | $3.99 |
| `livery_prism` | Prism | full prism gradient (cyan→violet→pink→gold) | pulse | $4.99 |

### 2.4 Exhausts (non-consumable) — 8, not 11
| enum / ID | Name | Look | Price |
|---|---|---|---|
| `stock` (free) | Stock Thruster | default | free |
| `exhaust_ion` | Ion Wake | thin cyan line, flicker | $0.99 |
| `exhaust_plasma` | Plasma Plume | violet/pink fat plume | $1.99 |
| `exhaust_ember` | Ember Burn | orange sparks shedding | $1.99 |
| `exhaust_comet` | Comet Tail | long white→cyan fading tail | $2.99 |
| `exhaust_pulse` | Pulse Drive | rings emitted at intervals | $2.99 |
| `exhaust_quantum` | Quantum Echo | ghost after-images of the hull | $3.99 |
| `exhaust_nova` | Nova Stream | prism gradient particles | $3.99 |

### 2.5 Sectors (non-consumable, gameplay palette) — 5 + kit
Free sectors (not sold): **Prism Noir** (default, was classic/modern), **Monochrome**
(was retro), **High Contrast** (was accessible), **Neon Grid** (was neon).

| ID | Name | Mood | Price |
|---|---|---|---|
| `sector_aurora` | Aurora Reach | green/violet aurora sky | $1.99 |
| `sector_solar` | Solar Forge | orange/gold sun-scorched | $1.99 |
| `sector_abyss` | Abyssal Rift | deep blue/black, bioluminescent | $1.99 |
| `sector_ion` | Ion Storm | electric cyan/indigo | $1.99 |
| `sector_crimson` | Crimson Expanse | red nebula | $1.99 |
| `sector_atlas` | Star Atlas (all 5 sectors) | — | $6.99 |

### 2.6 Fleet Kits (non-consumable bundles) — 3, not 4
| ID | Name | Contents | Price |
|---|---|---|---|
| `kit_recruit` | Recruit Kit | Aurum + Vanta liveries, Ion Wake + Ember Burn exhausts | $3.99 |
| `kit_vanguard` | Vanguard Kit | Redline, Glacier, Ionic, Solstice liveries; Plasma, Comet, Pulse exhausts | $9.99 |
| `kit_flagship` | Flagship Kit | every livery + every exhaust | $19.99 |

### 2.7 Cup Passes (consumable)
| ID | Name | Grants | Price |
|---|---|---|---|
| `cup_scout` | Scout Cup Pass | 1 bronze ticket | $0.99 |
| `cup_strike` | Strike Cup Pass | 1 silver ticket | $1.99 |
| `cup_ace` | Ace Cup Pass | 1 gold ticket | $4.99 |
| `cup_ace_trio` | Ace Trio | 3 gold tickets | $9.99 |
| `cup_squadron` | Squadron Bundle | 5 gold + 5 silver tickets | $19.99 |

Total: 2 subs + 4 + 8 + 7 (Stock Thruster is free) + 6 + 3 + 5 = **35 products** (was 44).

### 2.8 Legacy mapping (client parse + server migration of OwnedCosmetics / equipped)
- skins: classic→standard; golden→aurum; shadow→vanta; dragon,fire→redline;
  ice→glacier; electric→ionic; rainbow→prism; neon→solstice; galaxy,cosmic,crystal→viridian.
- trails: none→stock; particle,glow→ion; neon,cosmic→plasma; fire,dragon→ember;
  star→comet; electric→pulse; shadow→quantum; rainbow,crystal→nova.
- themes: classic,modern→prismNoir; retro→monochrome; accessible→highContrast;
  neon→neonGrid; forest→aurora; desert→solar; ocean→abyss; cyberpunk,crystal→ion; space→crimson.
- Pro entitlement: any active legacy `pro_*` entitlement row (admin-granted, e.g.
  the screenshot account) is treated as Strike Command.

---

## 3. Game modes (enum + wire value + display)

The wire value is the enum identifier (backend parses case-insensitively,
stored as string). Rename the enum members on both sides and migrate stored
strings (`Scores.GameMode`, `Achievements.GameModeFilter`,
`DailyChallenges.RequiredGameMode`, tournaments, game sessions, any jsonb).
Client accepts legacy strings via `GameMode.fromWire` fallback.

| Old | New enum | Display | Blurb |
|---|---|---|---|
| classic | `sortie` | Sortie | The standard run: waves, formations, a boss. |
| zen | `cruise` | Cruise | Lighter fire, no score pressure. Learn the patterns. |
| speedChallenge | `afterburn` | Afterburn | Scroll speed climbs every wave. |
| onslaught | `swarm` | Swarm | Endless dense formations. Hold the line. |
| survival | `holdout` | Holdout | Three hulls, no repairs. How long can you last? |
| timeAttack | `blitz` | Blitz | Three minutes. Score everything. |
| powerUpMadness | `overload` | Overload | Gear drops everywhere. Chaos encouraged. |
| perfectGame | `knifeEdge` | Knife Edge | One hit ends the run. |

Emoji icons are replaced by Material Symbols (no emoji in the UI).

---

## 4. Commendations (achievements) — full replacement

Replace all 114 with a new **72-commendation** set whose IDs are prefixed
`cmd_` and which only use stats the game really tracks for a shooter (kills,
bosses, elites, grazes, missiles fired, Overdrive activations, max combo
multiplier, formation wipes, campaign levels cleared, stars, perfect levels,
waves/stage reached, run time, Daily Run, Cup entries, upgrade drafts, Hangar
upgrades, revives, days streak). Categories (the `AchievementType` enum is
renamed in UI only): **Combat · Precision · Campaign · Endurance · Service ·
Modes · Feats**.

Implementing agent: read `achievement_service.dart` to see which counters
exist; add the minimal counters needed (persisted through the existing
statistics path) for grazes / missiles / overdrive / formation wipes / bosses
if not already counted. No commendation may reference snake/food concepts, or
modes by old names.

Old unlock/progress migration: map old→new where the condition is the same
(e.g. score thresholds, games played, kill counts, combo, perfect games,
day streaks); unmapped old rows are dropped. Client: one-time Drift migration
keyed by a SharedPreferences flag. Server: EF data migration + reseed.

---

## 5. Meta features

- **Frontline** (was Battle Pass): Season N, 50 tiers, free lane + "Command
  lane". Command lane unlocks with Strike Command, or for 1,200 credits per
  season (no IAP). Tier rewards reference the new catalog items and Sector
  names. Backend `BattlePassSeasonGenerator` produces themed season names
  ("Operation Glasswing", "Operation Red Tide", …) instead of generic ones.
- **Sector Cups** (was Tournaments): Daily Cup (was Daily Challenge
  tournament), Weekly Cup, Championship. Entry via Cup Passes.
- **Daily Directives** (3/day) and **Weekly Ops** (5/week): rewrite every
  directive template text to shooter verbs (destroy, graze, clear, wipe a
  formation, fire missiles, trigger Overdrive, finish a level without a hit).
- **Tactical Gear** (store power-ups) renamed:
  speed_boost→**Afterburner**, invincibility→**Aegis Shell**,
  score_multiplier→**Bounty Amp**, slow_motion→**Chrono Field**,
  teleport→**Warp Escape**, ghost_mode→**Phase Cloak**,
  magnetic_pickup→**Grav Lure**, score_shield→**Last Stand**.
  Inventory keys become `gear_afterburner`, `gear_aegis`, `gear_bounty`,
  `gear_chrono`, `gear_warp`, `gear_cloak`, `gear_lure`, `gear_laststand`
  (legacy key aliases on both sides; server migrates jsonb inventories).
  Credit-bought gear bundles: mega_pack→`gear_supply_crate` "Supply Crate",
  tactical_pack→`gear_tactical_case` "Tactical Case",
  ultimate_pack→`gear_arsenal` "Full Arsenal".
- **Supply Drop** (daily bonus): 7-day ladder copy rewritten.
- Home nav labels: DIRECTIVES · FRONTLINE · CUPS · STANDINGS · SQUADRON ·
  HANGAR · COMMENDATIONS · RECORD · COMMAND · ARMORY.

---

## 6. Copy rules
- No string may contain: snake, food, eat, bite, slither, grow/length (as
  progression), "Classic" as a mode, "Pro" as the subscription name, Zen,
  Speed Challenge, Time Attack, Power-Up Madness, Perfect Game, Battle Pass,
  Tournament(s) in UI, Trophies, Skins, Trails, Themes (UI), Coins (UI).
- Voice: terse military/space ops ("Sortie complete.", "Cup locked in.",
  "Livery applied."). No emoji anywhere in the UI.
- Notifications, toasts, empty states, dialogs, walkthrough, How-to-Play,
  store descriptions, subscription legal copy all follow this.

## 7. Store metadata (after code lands)
- App Store + Play: new description/keywords built around the shooter
  (campaign, bosses, graze/Overdrive, Sector Cups), new IAP names/descriptions
  from §2, new screenshots, review notes explaining the rebrand.
- Retire old 44 products on ASC (remove from sale / delete where allowed) and
  deactivate old Play products — only after the user confirms.
