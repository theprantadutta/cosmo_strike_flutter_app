# Ad mediation (Cosmo Strike)

All the owner's apps share **one AdMob account** (publisher `ca-app-pub-9242904787767394`),
so mediation partners, mediation groups and app-ads.txt are shared. The master document,
with every ID, status and history, is
`G:\Personal\MyProjects\snake-classic\snake_classic\docs\AD_MEDIATION_PARTNERS.md`
(Snake Classic repo). Read its "Quick status" table before touching ads.

Last updated: 2026-11-16.

## This app in AdMob

- Android app: ca-app-pub-9242904787767394~4346557234 (com.pranta.cosmostrike, Ready)
- iOS app: ca-app-pub-9242904787767394~9318162400 (App Store 6824382793; AdMob says 'Verify app to lift limit', which the owner clicks)
- Ad units in the shared mediation groups (added 2026-11-16): Android: banner, interstitial, rewarded (no App Open unit). iOS: banner, interstitial, rewarded.
  Any new ad unit must be added to the matching group (`banner_ad`, `interestitial`,
  `rewarded_ad`, `app_open_ad`, or their `_ios` versions), or only AdMob bids on it.
- Mediation adapters in this app: `gma_mediation_unity` and `gma_mediation_liftoffmonetize` are already in pubspec, but **no Cosmo Strike app exists yet in the Unity or Liftoff dashboards and no AdMob mapping**, so they don't bid yet.

## Partners (whole account)

| Partner | Status | Needs app code? |
|---|---|---|
| AdMob Network | Live | No |
| Open Bidding exchanges: Index Exchange, Magnite, OpenX, PubMatic, Verve, Smaato, InMobi Exchange, Media.net, Equativ | Applied 2026-11-16, approvals pending; they cover this app | **No** (they bid through Google's servers) |
| Unity Ads | Live for Snake Classic only | **Yes**, see below |
| Liftoff Monetize | Live for Snake Classic only | **Yes**, see below |
| AppLovin | Closed (account disabled, not reactivated) | Don't add |
| Meta, Mintegral, Pangle | Planned after the 2026-11-20 revenue check | Yes, later |

## app-ads.txt

Lives in `cosmo-strike/cosmo-strike-dotnet-api` (`src/*/wwwroot/app-ads.txt`), served at https://cosmostrike.pranta.dev/app-ads.txt (verified live 2026-11-16). It must be an **exact copy** of `portfolio/portfolio-svelte-web/static/app-ads.txt`
(https://pranta.dev/app-ads.txt). Don't hand-edit it per app: change the portfolio copy
and sync every app.

## Adding Unity Ads and Liftoff to this app

Console side (the owner, with the Snake Classic session, in the owner's Chrome): create
this app in Unity (cloud.unity.com) and Liftoff (publisher.vungle.com) with bidding
placements, then map this app's ad units in AdMob > Mediation > Bidding sources. The owner
answers the COPPA/child-directed questions.

App side (this repo's agent):

Add the official adapters, built for this app's `google_mobile_ads` version (check each
adapter's CHANGELOG; bump them together, never one alone):

```yaml
gma_mediation_unity: <version matching google_mobile_ads>
gma_mediation_liftoffmonetize: <version matching google_mobile_ads>
```

No Dart code: the adapters register themselves and read the UMP/TCF consent the app
already collects. iOS: merge Unity's and Liftoff's SKAdNetwork IDs into
`ios/Runner/Info.plist` (copy the full list from Snake Classic's Info.plist, 171 IDs),
build on macOS so Swift Package Manager pulls the adapters, and commit `Package.resolved`.
Snake Classic's pubspec (`google_mobile_ads ^9.2.0`, `gma_mediation_unity ^1.12.0`,
`gma_mediation_liftoffmonetize ^1.5.7`) is a working reference.

Verify with AdMob Ad Inspector on a registered test device, then watch AdMob > Reports >
Mediation for a week.

## Rules

- Partner agreements, terms and COPPA declarations are signed by the **owner**, never an agent.
- The owner's Chrome runs an ad blocker that breaks partner dashboards: ask them to allow the site.
- Before ad work, check Gmail for partner emails
  (`from:(unity OR liftoff OR vungle OR magnite OR openx OR pubmatic OR verve OR smaato OR inmobi OR media.net OR equativ OR indexexchange) newer_than:14d`).
