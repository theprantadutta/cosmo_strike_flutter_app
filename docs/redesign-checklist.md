# Prism Noir redesign — checklist

Branch `redesign/prism-noir`. Mocks: redesign kit `screenshots/01–10`. QA devices: Galaxy A24 (phone, ~891×411dp), Galaxy Tab A9+ (tablet), plus iPhone / iPad sizes.

Legend: [x] ported · [x] in progress · [ ] todo

## Foundation
- [x] Tokens, type scale, responsive scale (`lib/theme/cosmo_theme.dart`)
- [x] Component library (`lib/ui/cs/`, barrel `lib/ui/cs.dart`)
- [x] Fonts: Syne (static 400–800) + IBM Plex Mono; Material Symbols Rounded
- [x] App icons (Android adaptive + monochrome, iOS, web), notification icon
- [x] Native splash (Android ≤11, Android 12+ with branding, iOS), sensorLandscape preserved
- [x] Route transitions (280ms fade + 12px slide)
- [x] Remove old design system (`lib/ui/design*`, `AppBackground`, Orbitron/Rajdhani, flutter_animate)

## Screens & routes
| Route / surface | File | Mock | Status |
|---|---|---|---|
| Splash / boot | screens/loading_screen.dart | 01 | [x] |
| Main menu | screens/home_screen.dart | 02 | [x] |
| ↳ control choice, game-mode picker, loadout | home_screen.dart | — | [x] |
| ↳ overflow menu (help / share / about) | home_screen.dart | — | [x] |
| Campaign / level select | screens/level_select_screen.dart | 06 | [x] |
| Pre-game loader | screens/pre_game_loading_screen.dart | — | [x] |
| Gameplay HUD | screens/gameplay_screen.dart | 03 | [x] |
| Pause | widgets/gameplay/pause_overlay.dart | 04 | [x] |
| Game over | widgets/gameplay/game_over_overlay.dart | 05 | [x] |
| Level complete | widgets/gameplay/level_complete_overlay.dart | — | [x] |
| D-pad | widgets/game_dpad.dart | — | [x] |
| Daily challenges | screens/daily_challenges_screen.dart | 07 | [x] |
| Weekly quests / challenges hub | screens/weekly_quests_screen.dart, challenges_hub_screen.dart | — | [x] |
| Daily bonus popup | widgets/daily_bonus_popup.dart | — | [x] |
| Reward toast | widgets/reward_toast.dart | — | [x] |
| Battle pass | screens/battle_pass_screen.dart | 08 | [x] |
| Pro benefits / paywall | screens/premium_benefits_screen.dart | 10 | [x] |
| Store (Pro, Coins, Themes, Skins, Trails, Power-ups) | screens/store_screen.dart | 10 | [x] |
| Leaderboards | screens/leaderboard_screen.dart | 09 | [x] |
| Friends leaderboard | screens/friends_leaderboard_screen.dart | — | [x] |
| Friends | screens/friends_screen.dart | — | [x] |
| Events / tournaments + detail | screens/tournaments_screen.dart, tournament_detail_screen.dart | — | [x] |
| Profile | screens/profile_screen.dart | — | [x] |
| Statistics | screens/statistics_screen.dart | — | [x] |
| Awards | screens/achievements_screen.dart | — | [x] |
| Replays + viewer | screens/replays_screen.dart, replay_viewer_screen.dart | — | [x] |
| Settings | screens/settings_screen.dart | — | [x] |
| How to play | screens/instructions_screen.dart | — | [x] |
| About / credits | widgets/credits_dialog.dart | — | [x] |
| Privacy consent | screens/privacy_consent_screen.dart | — | [x] |
| First-time auth | screens/first_time_auth_screen.dart | — | [x] |
| Email auth | screens/email_auth_screen.dart | — | [x] |
| Username setup | screens/username_setup_screen.dart | — | [x] |
| Account upgrade sheet | widgets/account_upgrade_sheet.dart | — | [x] |
| Sync restore overlay / status | widgets/sync_restore_overlay.dart, sync_status_indicator.dart | — | [x] |
| Home walkthrough | widgets/walkthrough/* | — | [x] |
| Rewarded action button / banner ad strip | widgets/ads/* | — | [x] |
| Player level badges | widgets/player_progression.dart | — | [x] |

## Gameplay art
- [x] Palette + theme tint API (`lib/game/cosmo_palette.dart`)
- [x] Player ship, enemies (11), bosses (7 incl. pods), power-ups (10), projectiles, FX sheets, terrain, parallax starfield

## QA matrix (every screen)
Phone, small phone (640×360), tablet, iPad 11"/13" sizes · empty / loading / error / offline · locked/unlocked · claimed/unclaimed · free vs Pro · 0 coins vs 1,000,000+ · long usernames · font scale 1.3 · no overflow · nothing under the notch · tap targets ≥ 44dp.
