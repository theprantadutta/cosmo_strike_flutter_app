# Cosmo Strike — Subscription Setup Checklist

The tester report saw **"Premium subscription not available"** when tapping
Subscribe. This is **not a code bug** — the app correctly asks Google Play for the
subscription products, but Play returns them as *not found* until they are created
and activated in the Play Console, and only on builds installed from a Play track.

The app code now degrades gracefully (clear message + Retry), but to enable
**real paid subscriptions** complete the steps below.

**NO FREE TRIALS** — do not add trial/intro offers to either base plan. All
trial logic was removed from the app and backend (July 2026); subscriptions
are live-priced from day one.

## Product IDs the app expects (exact)
Defined in `lib/services/purchase_service.dart` (`ProductIds`):

| Plan    | Store product ID                          | Price  |
|---------|-------------------------------------------|--------|
| Monthly | `com.pranta.cosmostrike.pro_monthly`      | $4.99  |
| Yearly  | `com.pranta.cosmostrike.pro_yearly`       | $39.99 |

## Steps
1. **Play Console → Monetize → Products → Subscriptions → Create subscription.**
   - Create one subscription with product ID `com.pranta.cosmostrike.pro_monthly`
     and one with `com.pranta.cosmostrike.pro_yearly` — the FULL prefixed string,
     exactly as the app queries it (same convention as the 40 in-app products).
2. **Add a base plan** to each (NO trial offers):
   - Monthly: billing period **P1M** (auto-renewing), $4.99.
   - Yearly: billing period **P1Y** (auto-renewing), $39.99.
   - Set the USD price and let Google auto-convert the regions.
3. **Activate** each subscription and base plan (status must be **Active**, not Draft).
4. **License testing:** Play Console → Setup → License testing → add the tester
   Google accounts so they can purchase without being charged.
5. **Install from a Play track.** Sideloaded debug/release APKs **always** report
   products as not-found. Upload the signed `.aab` to **Internal testing**, add the
   testers, and install via the opt-in link / Play Store.
6. **Signing:** confirm the build uses the configured upload key (see the
   release-signing notes) so Play accepts it on the track.

## How to verify it worked
- Open **Pro** screen → the price readout shows the real store price (not the
  `$4.99` / `$39.99` fallbacks).
- Tap **Subscribe** → the Google Play purchase sheet opens (no snackbar).
- After purchase, `PurchasesController` `/v1/purchases/verify` validates it and
  premium unlocks; `/v1/subscriptions/status` reflects the active subscription.

## If it still says unavailable
The app now tells you which case it is:
- *"...not available on this device"* → billing unsupported (emulator / no Play).
- *"The store is still loading... RETRY"* → query pending or network issue; tap Retry.
- *"Pro subscriptions aren't available right now"* → billing works but the products
  aren't Active on the track yet → re-check steps 3–5.
