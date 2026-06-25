# iOS Firebase setup (Crashlytics + Performance + Analytics)

The Dart wiring and the Xcode build config are already in the repo and are
**cross-platform** — iOS will work once the one Mac-only file is in place.

## Already done (in the repo, no Mac needed)
- `firebase_crashlytics` + `firebase_performance` in `pubspec.yaml`.
- `lib/main.dart` — collection gating + `FlutterError.onError` / `PlatformDispatcher.onError`
  forwarding (cross-platform; runs on iOS too).
- `lib/firebase_options.dart` already contains the iOS app config, so
  `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` initializes
  Firebase on iOS without needing the plist for init.
- `ios/Runner.xcodeproj/project.pbxproj` — an **"Upload Crashlytics dSYMs"** Run Script
  build phase (runs the FirebaseCrashlytics `run` symbol-upload script). It is **guarded**:
  if the pod isn't installed it just prints a warning and skips, so it can never fail a build.
- iOS deployment target is already 13.0 (Crashlytics/Performance require iOS 13+).

## The one manual step (must be done on a Mac)
`GoogleService-Info.plist` can only be downloaded/generated on macOS (it's not in the repo
because this machine is Windows). On a Mac:

1. Get the plist: run `flutterfire configure` (regenerates `firebase_options.dart` + downloads
   the iOS plist), **or** download `GoogleService-Info.plist` from the Firebase console
   (Project settings → iOS app `com.pranta.cosmostrike`).
2. Place it at `ios/Runner/GoogleService-Info.plist`.
3. Open `ios/Runner.xcworkspace` in Xcode and drag the plist into the **Runner** target
   (check "Copy items if needed" and the Runner target membership) so it ships in the bundle.
4. `cd ios && pod install` (pulls the FirebaseCrashlytics/FirebasePerformance pods; this is
   what makes the dSYM-upload build phase actually run).
5. Build: `flutter build ipa --release`.

## Verify on iOS
- Crashlytics: trigger a test crash on a release/profile build, relaunch, confirm it appears
  in the Firebase console.
- Performance: launch a few times; `app_start` + network traces show up in the Performance
  dashboard (first data can take several hours).

Nothing else is required — Performance auto-instruments, and Analytics uses the same
`firebase_options.dart` config.
