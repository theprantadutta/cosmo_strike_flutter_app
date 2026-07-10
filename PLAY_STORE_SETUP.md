# Cosmo Strike — Google Play Store Setup (Products, Subscriptions, IDs, Prices)

The complete monetization catalog to create in Play Console, extracted from the
code (client `lib/services/purchase_service.dart` `ProductIds` + server
`CosmoStrike.Domain/Catalog/ProductCatalog.cs` — the two are verified in sync).
Companion doc: `SUBSCRIPTION_SETUP.md` (subscription click-path details).

## App identity

| | |
|---|---|
| Package name | `com.pranta.cosmostrike` |
| Current version | `1.1.4` (versionCode `8`) — bump before each upload |
| Upload keystore | `C:\android-keys\cosmo-strike\upload-keystore.jks` via `android/key.properties` |
| Prod backend | `https://cosmostrike.pranta.dev` (must be deployed BEFORE release) |
| AdMob app ID | `ca-app-pub-9242904787767394~4346557234` (production, already in manifest) |

**Product ID rule:** create every ID below WITHOUT the prefix shown — enter the
full ID exactly as written. The app queries the full
`com.pranta.cosmostrike.<bare_id>` string; Play requires the full ID at creation
time. (44 store products total: 2 subscriptions + 42 in-app products.)

---

## 1. Subscriptions (Monetize → Products → Subscriptions)

| Product ID | Name | Base plan | Free trial offer | Price |
|---|---|---|---|---|
| `com.pranta.cosmostrike.pro_monthly` | Cosmo Strike Pro — Monthly | `P1M` auto-renewing | **NONE** | **$4.99 / month** |
| `com.pranta.cosmostrike.pro_yearly` | Cosmo Strike Pro — Yearly | `P1Y` auto-renewing | **NONE** | **$39.99 / year** (Save 33%) |

- ⚠️ **NO free-trial offers** — all trial logic (in-app AND store-facing copy)
  was removed from the app + backend in July 2026. Adding a trial offer in the
  Console would give away time the app never advertises.
- Both plans grant the same **Pro** entitlement: all premium themes, all 11
  skins, all 11 trails, coin-earn multiplier, tournament entry bypass,
  **Battle Pass premium track**, per-period power-up grant, no ads.

### Do NOT create
- `battle_pass_season` — retired; the premium Battle Pass track is included
  with Pro. The client deliberately doesn't query or restore it.
- Power-up bundles (`mega_pack`, `tactical_pack`, `ultimate_pack`) — those are
  **coin-priced in-game purchases**, not store products.

---

## 2. In-app products (Monetize → Products → In-app products)

Play Console has one "in-app product" type; consumable-vs-permanent is handled
by the app (coin packs + tournament entries are consumed; everything else is a
permanent unlock, delivered + acknowledged by the app and re-granted via
Restore).

### 2a. Coin packs (consumable)

| Product ID | Name | Grants | Price |
|---|---|---|---|
| `com.pranta.cosmostrike.coin_pack_small` | Starter Pack | 100 coins | **$0.99** |
| `com.pranta.cosmostrike.coin_pack_medium` | Value Pack | 550 coins (500 + 50 bonus) | **$4.99** |
| `com.pranta.cosmostrike.coin_pack_large` | Premium Pack | 1,400 coins (1,200 + 200 bonus) | **$9.99** |
| `com.pranta.cosmostrike.coin_pack_mega` | Ultimate Pack | 3,000 coins (2,500 + 500 bonus) | **$19.99** |

### 2b. Tournament entry tickets (consumable)

| Product ID | Name | Grants | Price |
|---|---|---|---|
| `com.pranta.cosmostrike.tournament_bronze` | Bronze Tournament Entry | 1 bronze ticket | **$0.99** |
| `com.pranta.cosmostrike.tournament_silver` | Silver Tournament Entry | 1 silver ticket | **$1.99** |
| `com.pranta.cosmostrike.tournament_gold` | Gold Tournament Entry | 1 gold ticket | **$4.99** |
| `com.pranta.cosmostrike.championship_entry` | Championship Entry | 1 gold-tier ticket | $4.99 *(optional — see note)* |
| `com.pranta.cosmostrike.tournament_vip_entry` | VIP Tournament Entry | 1 gold-tier ticket | $4.99 *(optional — see note)* |

> Note: `championship_entry` and `tournament_vip_entry` are registered in the
> app + backend but **no screen sells them yet** (only bronze/silver/gold have
> buy buttons). Safe to skip for now — querying a missing product is harmless —
> or create them Inactive until a UI exists.
>
> Bronze entries can also be earned via a rewarded ad, **capped at 2/day**
> (`AdService.capTournamentEntry`), so the paid bronze entry retains value.

### 2c. Premium themes (permanent unlock)

| Product ID | Name | Price |
|---|---|---|
| `com.pranta.cosmostrike.crystal_theme` | Crystal Theme | **$1.99** |
| `com.pranta.cosmostrike.cyberpunk_theme` | Cyberpunk Theme | **$1.99** |
| `com.pranta.cosmostrike.space_theme` | Space Theme | **$1.99** |
| `com.pranta.cosmostrike.ocean_theme` | Ocean Theme | **$1.99** |
| `com.pranta.cosmostrike.desert_theme` | Desert Theme | **$1.99** |
| `com.pranta.cosmostrike.forest_theme` | Forest Theme | **$1.99** |
| `com.pranta.cosmostrike.premium_themes_bundle` | All Themes Bundle (all 6) | **$7.99** |

### 2d. Ship skins (permanent unlock)

| Product ID | Name | Price |
|---|---|---|
| `com.pranta.cosmostrike.skin_golden` | Golden Ship | **$1.99** |
| `com.pranta.cosmostrike.skin_fire` | Fire Ship | **$1.99** |
| `com.pranta.cosmostrike.skin_ice` | Ice Ship | **$1.99** |
| `com.pranta.cosmostrike.skin_electric` | Electric Ship | **$1.99** |
| `com.pranta.cosmostrike.skin_rainbow` | Rainbow Ship | **$2.99** |
| `com.pranta.cosmostrike.skin_neon` | Neon Ship | **$2.99** |
| `com.pranta.cosmostrike.skin_shadow` | Shadow Ship | **$2.99** |
| `com.pranta.cosmostrike.skin_galaxy` | Galaxy Ship | **$3.99** |
| `com.pranta.cosmostrike.skin_crystal` | Crystal Ship | **$3.99** |
| `com.pranta.cosmostrike.skin_cosmic` | Cosmic Ship | **$3.99** |
| `com.pranta.cosmostrike.skin_dragon` | Dragon Ship | **$4.99** |

### 2e. Trail effects (permanent unlock)

| Product ID | Name | Price |
|---|---|---|
| `com.pranta.cosmostrike.trail_particle` | Particle Trail | **$0.99** |
| `com.pranta.cosmostrike.trail_glow` | Glow Trail | **$0.99** |
| `com.pranta.cosmostrike.trail_rainbow` | Rainbow Trail | **$1.99** |
| `com.pranta.cosmostrike.trail_neon` | Neon Trail | **$1.99** |
| `com.pranta.cosmostrike.trail_shadow` | Shadow Trail | **$1.99** |
| `com.pranta.cosmostrike.trail_fire` | Fire Trail | **$2.99** |
| `com.pranta.cosmostrike.trail_electric` | Electric Trail | **$2.99** |
| `com.pranta.cosmostrike.trail_star` | Star Trail | **$2.99** |
| `com.pranta.cosmostrike.trail_cosmic` | Cosmic Trail | **$3.99** |
| `com.pranta.cosmostrike.trail_crystal` | Crystal Trail | **$3.99** |
| `com.pranta.cosmostrike.trail_dragon` | Dragon Trail | **$3.99** |

### 2f. Cosmetic bundles (permanent unlock)

| Product ID | Name | Contents | Price |
|---|---|---|---|
| `com.pranta.cosmostrike.starter_pack` | Starter Pack | Golden + Fire skins, Particle + Glow trails | **$3.99** |
| `com.pranta.cosmostrike.elemental_pack` | Elemental Pack | Fire/Ice/Electric skins, Fire/Electric trails | **$7.99** |
| `com.pranta.cosmostrike.cosmic_collection` | Cosmic Collection | Galaxy/Cosmic/Crystal skins, Cosmic/Star/Crystal trails | **$14.99** |
| `com.pranta.cosmostrike.ultimate_collection` | Ultimate Collection | ALL 11 skins + ALL 11 trails | **$29.99** |

---

## 3. Server-side wiring (already implemented — just configure)

1. **Service account**: `google-play-service-account.json` (backend repo root,
   gitignored) must be linked in Play Console → Setup → API access, with
   *Financial data* permissions — the backend verifies every purchase/sub
   server-side via the Google Play Developer API.
2. **Real-time developer notifications (RTDN)**: Play Console → Monetize →
   Monetization setup → create a Cloud Pub/Sub topic and point a push
   subscription at:
   `https://cosmostrike.pranta.dev/api/v1/purchases/webhook/google-play?token=<GOOGLE_PLAY_PUBSUB_VERIFICATION_TOKEN>`
   The token must equal the backend `.env` value (constant-time verified;
   wrong/missing token → ignored).
3. Backend env: `GOOGLE_PLAY_PACKAGE_NAME=com.pranta.cosmostrike`,
   `GOOGLE_PLAY_PUBSUB_VERIFICATION_TOKEN=<same token>`. Apple stays
   `APPLE_IAP_ENABLED=false` until iOS ships (see backend `CLAUDE.md`).

## 4. Testing checklist

1. Play Console → Setup → License testing → add tester Google accounts
   (purchases won't be charged).
2. Upload the signed `.aab` to **Internal testing** — sideloaded builds ALWAYS
   report products as not-found; install via the opt-in link.
3. Verify on-device: Pro screen shows real store prices (not the $4.99/$39.99
   fallbacks) → purchase sheet opens → after purchase `/purchases/verify`
   grants premium → Restore purchases works after reinstall.

## 5. Data-safety form — SDK inventory

Declare data collected by: Firebase (Auth, Analytics, Crashlytics, Performance,
Messaging), Google Sign-In, AdMob (+ UMP consent, already implemented),
Google Play Billing, connectivity. Privacy policy ships in-app (`PRIVACY.md`
v2.0) — host the same text at a public URL for the store listing.

## 6. iOS / App Store (later)

The same catalog applies 1:1 on the App Store (same bare IDs under the
`com.pranta.cosmostrike.` prefix; App Store Connect auto-renewables for the two
subs). BLOCKED until: `GoogleService-Info.plist` added, real Apple receipt/JWS
verification implemented, and `APPLE_IAP_ENABLED=true` — checklist in the
backend `CLAUDE.md`.
