# GA4 custom definitions to register

GA4 only shows a custom event parameter or user property in reports after it
is registered (Admin → Data display → Custom definitions), and only from the
day it was registered. Register everything below once, in the Cosmo Strike
property. "Dimension" = text/categorical, "Metric" = a number GA4 should sum or
average (pick the unit shown).

GA4 limits: 50 event-scoped custom dimensions, 50 event-scoped metrics and 25
user-scoped dimensions per property. A parameter name is registered once and
then works for every event that sends it (e.g. `run_number` on `game_over`,
`game_abandoned` and `revive_offer`).

Code: `lib/services/analytics/` (`AnalyticsFacade` typed wrappers,
`AnalyticsParams`, `RunSession`, `PushOpenTracker`).

## Event-scoped dimensions

| Parameter | Description | Sent on |
|---|---|---|
| `game_mode` | Mode the run was played in (`sortie`, `cruise`, `blitz`, ...: `GameMode.wireName`). | `game_started`, `game_over`, `game_abandoned`, `first_game_started` |
| `end_trigger` | How the run ended: `death` / `time` (Blitz clock) / `victory` / `quit`. | `game_over`, `game_abandoned` |
| `run_number` | Lifetime run number on this install (1 = first run ever), from `FirstRunService.gamesStarted` at run start. Register as a dimension so funnels can split run 1 / 2 / 3. | `game_over`, `game_abandoned`, `revive_offer`, `onboarding_run_ended` |
| `onboarding` | 1 when the run was one of the install's first 3 runs, else 0. | `game_over`, `game_abandoned` |
| `victory` | 1 when the whole campaign was cleared. | `game_over` |
| `outcome` | How the revive offer ended: `ad` / `coins` / `free` / `declined` / `timeout` / `skipped_onboarding`. (Also used by `onboarding_run_ended` and `rewarded_result`.) | `revive_offer` |
| `control_scheme` | Steering scheme selected for the run: `drag` / `dpad`. | `first_input` |
| `input` | What the first touch was: `drag` / `dpad` / `tap`. | `first_input` |
| `push_type` | Tapped notification's payload `type` (e.g. `comeback_reminder`, server push types); falls back to `action`, `route`, then `fcm` / `local`. | `push_opened` |
| `source` | Notification channel: `fcm` (push) or `local` (scheduled on device). | `push_opened` |
| `cold_start` | 1 when the tap launched the app from a killed state (local notifications only for now). | `push_opened` |
| `placement` | Where a notification permission ask happened: `home_soft_ask`, `settings`, `new_best` (game-over ask, once wired). (Also used by `rewarded_result`.) | `notification_permission` |
| `result` | Step of the permission ask: `soft_shown` / `soft_declined` / `already_enabled` / `granted` / `denied` / `settings_opened`. On `app_update`: Play's `AppUpdateResult` (`success` / `userDeniedUpdate` / `inAppUpdateFailed`) or `error` for `immediate_result`, `home` for `auto_completed`. | `notification_permission`, `app_update` |
| `stage` | Step of the Play in-app update flow: `offered` (our dialog on screen) / `accepted` / `snoozed` / `urgent` (priority >= 4, blocking flow unasked) / `flexible_fallback` / `immediate_result` / `auto_completed` (finished download installed at launch on Home). | `app_update` |
| `kind` | Kind of goal on the game-over "Next up" strip (values set by that feature, e.g. `daily`, `level`, `streak`). | `next_goal_shown`, `next_goal_tapped` |
| `trigger` | Moment that requested the store review sheet: `levelCleared` / `newHighScore` / `victory` / `manual`. | `review_requested` |

## Event-scoped metrics

| Parameter | Unit | Description | Sent on |
|---|---|---|---|
| `score` | Standard | Run score. | `game_over`, `game_abandoned` |
| `duration_seconds` | Seconds | Run length. | `game_over`, `game_abandoned`, `onboarding_run_ended` |
| `stage_reached` | Standard | Furthest campaign level reached. | `game_over`, `game_abandoned` |
| `levels_cleared` | Standard | Levels cleared in the run. | `game_over`, `game_abandoned` |
| `seconds_since_run_start` | Seconds | Seconds from the run screen opening to the first steer/tap (install's first run only). | `first_input` |

## User-scoped dimensions

| User property | Description |
|---|---|
| `install_week` | ISO year-week of the install (`2026-W48`), from `FirstRunService.installedAt` (device-only). Install cohort for every report. Set on every launch. |
| `onboarding_done` | 1 once the install has started 3 runs, else 0. |
| `test_device` | 1 on our own test devices (hidden switch: About & Credits → tap the version chip 7 times). Collection is also switched off on those devices, so this mainly marks anything sent before the switch flipped. Use it as an exclusion filter. |

`auth_method` and `is_premium` already exist; register them as user-scoped
dimensions too if they are not yet.

## New events (for reference)

`revive_offer`, `first_input`, `push_opened`, `notification_permission`,
`next_goal_shown`, `next_goal_tapped`, `game_abandoned`, `app_update`. Mark none of them as
key events except, optionally, `push_opened`.
