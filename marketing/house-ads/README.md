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

## Status: NOT live (owner's decision, 2026-11-23)

AdMob only allows house-ad campaigns once the account is linked to Google
Ads, and the owner will not link Google Ads (account-ban risk for the shared
AdMob publisher). Do not link it or ask again. Cross-promo runs through the
in-app "More games" card instead (`marketing/cross-promo/MORE_GAMES_SPEC.md`).
These images stay here for that card or any self-served promo slot in the
owner's apps, using the same platform-correct links above.
