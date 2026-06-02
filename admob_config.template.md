# AdMob configuration — FILL ME IN

Replace every `REPLACE_ME...` below with the real value from your AdMob console,
then tell me it's done. I'll wire the values into the right places for you:

- **App IDs** → Android `AndroidManifest.xml` + iOS `Info.plist` (this is what
  fixes the current "Missing application ID" crash).
- **Production unit IDs** → `lib/services/ads/ad_config.dart` (the real ids used
  in release builds; debug builds keep using Google's test ids automatically).

Notes on the two formats (don't mix them up):
- **App ID** uses a tilde:  `ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ`
- **Unit ID** uses a slash: `ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ`

Where to find them in the AdMob console:
- App ID:  AdMob → **Apps** → (your app) → **App settings** → "App ID".
- Unit IDs: AdMob → **Apps** → (your app) → **Ad units** → each unit's id.

---

## 1. App IDs  (REQUIRED — these fix the crash)

```
ANDROID_APP_ID = ca-app-pub-9242904787767394~4346557234
IOS_APP_ID     = ca-app-pub-9242904787767394~9318162400
```

## 2. Production Ad Unit IDs

> The values below are what's CURRENTLY hardcoded in `ad_config.dart`
> (publisher `ca-app-pub-9242904787767394`). Confirm each is correct, or
> overwrite it with the right one. If a unit doesn't exist yet, write `NONE`.

### Banner
```
BANNER_ANDROID = ca-app-pub-9242904787767394/7902658867
BANNER_IOS     = ca-app-pub-9242904787767394/5606148107
```

### Interstitial
```
INTERSTITIAL_ANDROID = ca-app-pub-9242904787767394/3963413851
INTERSTITIAL_IOS     = ca-app-pub-9242904787767394/1337250516
```

### Rewarded
```
REWARDED_ANDROID = ca-app-pub-9242904787767394/9024168845
REWARDED_IOS     = ca-app-pub-9242904787767394/7711087171
```

---

### (optional) Test device IDs
If you want your physical test device(s) registered so real-ad-fill test
traffic doesn't count as invalid, paste the device id(s) here (one per line).
Leave blank to skip.
```
TEST_DEVICE_IDS =
```
