# "More games" card — Cosmo Strike, for Snake Classic (and future apps)

Approved by the owner on 2026-11-23. Same developer, so both stores allow it,
as long as the rules below hold.

## Content
- **Name:** Cosmo Strike
- **Line (English, translate per app):** "Arcade space shooter from the makers of Snake Classic."
  - Shorter fallback: "Our arcade space shooter."
- **Icon:** `cosmo-strike-icon-512.png` (also `-192`). The rounded-square
  launcher art on a near-black background (#0A0A0D), not transparent;
  clip to the host app's own corner radius.
- **Label the block** as your own games, e.g. "More games from us" /
  "Also by the Snake Classic team", never as a reward or a system prompt.

## Links (platform-correct, never cross them)
- **Android → Google Play only:**
  `https://play.google.com/store/apps/details?id=com.pranta.cosmostrike&referrer=utm_source%3Dsnake_classic%26utm_medium%3Dmore_games`
  Open with `LaunchMode.externalApplication` (Play app handles it).
- **iOS → App Store only:**
  `https://apps.apple.com/app/id6824382793?pt=&ct=snake_classic_more_games&mt=8`
  (`ct` shows up in App Store Connect → App Analytics → Campaigns.)
  Prefer `SKStoreProductViewController` if already available; a plain App
  Store link is fine.

## Policy rules (Google Play + App Store)
- No reward of any kind for installing or opening Cosmo Strike (Play
  "incentivized install" ban; Apple 3.2.2). No credits, no unlocks.
- No deceptive UI: it must look like a normal list row or card, not an
  alert, notification, "you won", fake close or download button.
- Not interstitial and not blocking: user-initiated tap only; never on launch,
  never during gameplay, never forced.
- Not shown in a kids-category / Families context (both games are 7+ and not
  child-directed, so fine today; re-check if that ever changes).
- Keep the store name / icon exactly as the live listing.

## Placement (host app decides)
Bottom of Settings or the Home overflow menu. Not the game-over screen.
