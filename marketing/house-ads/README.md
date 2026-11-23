# Cosmo Strike house ads (AdMob)

Static creatives that promote Cosmo Strike in the owner's other apps through
AdMob **house ads** (Campaigns → House ads). They don't earn money; they fill
a share of those apps' impressions with our own game.

Regenerate from the latest raw captures:

    cd tools/marketing && python render_house_ads.py

| File | AdMob format |
| --- | --- |
| banner_320x50.png, banner_468x60.png, banner_728x90.png | Banner |
| mrec_300x250.jpg | Banner (medium rectangle) |
| interstitial_320x480.jpg, interstitial_768x1024.jpg | Interstitial, portrait |
| interstitial_480x320.jpg, interstitial_1024x768.jpg | Interstitial, landscape |

## Click-through URLs (never cross platforms)

One campaign per platform, so each only targets that platform's ad units:

- **Android campaign** → Google Play:
  `https://play.google.com/store/apps/details?id=com.pranta.cosmostrike&referrer=utm_source%3Dhouse_ads%26utm_medium%3Dadmob`
- **iOS campaign** → App Store:
  `https://apps.apple.com/app/id6824382793?pt=&ct=house_ads_admob&mt=8`

## Policy (Google Play + App Store)

- No reward for installing or opening Cosmo Strike (Play incentivized-install
  ban, Apple 3.2.2). House ads must never be served on a rewarded ad unit.
- No fake close/download buttons or system-style alerts. "Play free" is the
  real action; the game is free to play with optional purchases.
- Store name and icon match the live listings.
- Not for kids/Families-designated apps.

## Live setup (2026-11-23)

Share starts low (see the campaign's "Fill rate") so the host apps keep most
of their paid inventory; raise it in AdMob if installs justify it. Measure in
Play Console → Acquisition (utm_source=house_ads) and App Store Connect →
App Analytics → Campaigns (ct=house_ads_admob).
