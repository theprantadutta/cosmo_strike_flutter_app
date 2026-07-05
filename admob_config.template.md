# AdMob configuration — LIVE (record of the shipped values)

All values below are wired in and shipping. This file is the reference for
where each one lives and how to rotate it — nothing here needs filling in.

Formats (don't mix them up):
- **App ID** uses a tilde:  `ca-app-pub-XXXXXXXXXXXXXXXX~ZZZZZZZZZZ`
- **Unit ID** uses a slash: `ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ`

Publisher: `ca-app-pub-9242904787767394`. Debug builds always use Google's
official test unit IDs (`ad_config.dart` switches on `kDebugMode`); the
production IDs below only serve in release builds.

## App IDs

| Platform | App ID | Wired in |
|---|---|---|
| Android | `ca-app-pub-9242904787767394~4346557234` | `android/app/src/main/AndroidManifest.xml` (`APPLICATION_ID` meta-data) |
| iOS | `ca-app-pub-9242904787767394~9318162400` | `ios/Runner/Info.plist` (`GADApplicationIdentifier`) |

## Production ad unit IDs (`lib/services/ads/ad_config.dart`)

| Unit | Android | iOS |
|---|---|---|
| Banner (anchored adaptive) | `…/7902658867` | `…/5606148107` |
| Interstitial | `…/3963413851` | `…/1337250516` |
| Rewarded | `…/9024168845` | `…/7711087171` |

## Remote-tunable cadence (Firebase Remote Config)

`lib/services/ads/ad_tuning.dart` — in-code defaults apply until a fetch
lands, so nothing breaks if these are never set in the Firebase console:

| Parameter | Default | Meaning |
|---|---|---|
| `ads_interstitial_every_n_games` | 3 | game-over interstitial cadence |
| `ads_interstitial_every_n_levels` | 3 | level-clear interstitial cadence |
| `ads_interstitial_min_gap_seconds` | 180 | shared min gap across placements |
| `ads_overlay_banners_enabled` | true | kill switch for the pause/level-clear/game-over overlay banners |

## Placement rules (keep these invariants)

- **No ads during active play** — banners live only on the pause /
  level-clear / game-over overlays (the steering gesture covers the whole
  screen; an in-play banner is an accidental-click / invalid-traffic risk).
- **No banner on the revive overlay** (it sells a rewarded ad + coin choice).
- Rewarded placements that mint currency are daily-capped in
  `AdService.dailyCaps` (incl. free bronze tournament entry, 2/day).

## Rotating an ID

1. Create the new unit in AdMob → Apps → Cosmo Strike → Ad units.
2. Update the matching constant in `lib/services/ads/ad_config.dart`
   (app IDs instead: AndroidManifest.xml / Info.plist).
3. Release — old units can be archived once traffic drains.
