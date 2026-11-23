package com.example.cosmo_strike_flutter_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** This launch found an incomplete install (see [IncompleteInstall]). */
    private var incompleteInstall = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Incomplete install (the ABI split with libflutter.so is missing):
        // FlutterActivity.onCreate would crash creating the engine. Hand off
        // to the native "reinstall from Google Play" dialog and finish; the
        // platform onCreate inside FlutterActivity's runs before the engine
        // attach throws, so the Activity contract still holds. A normal
        // install never enters this branch.
        if (IncompleteInstall.isMissingEngine(this)) {
            incompleteInstall = true
            startActivity(Intent(this, IncompleteInstallActivity::class.java))
            finish()
            try {
                super.onCreate(savedInstanceState)
            } catch (expected: Throwable) {
                // The engine's MissingLibraryException / UnsatisfiedLinkError.
            }
            return
        }
        // Explicit edge-to-edge opt-in on every Android version — the call
        // Play Console's "Edge-to-edge may not display for all users" check
        // looks for. androidx.core's Window variant, because FlutterActivity
        // is a plain Activity (androidx.activity.enableEdgeToEdge() needs a
        // ComponentActivity). Needs androidx.core 1.16+ (pinned in Gradle).
        WindowCompat.enableEdgeToEdge(window)
        super.onCreate(savedInstanceState)

        // Full-screen game: hide status + navigation bars with the
        // non-deprecated insets controller; an edge swipe peeks them and
        // they auto-hide (same as Dart's immersiveSticky, re-asserted there).
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

        createNotificationChannel()
        preferSixtyHz()
    }

    // The game is built and tuned for 60 FPS. On 90/120 Hz panels ask the
    // window for 60 Hz so frame pacing, battery and heat match what we test.
    //
    // preferredRefreshRate, NOT preferredDisplayModeId: on One UI (Galaxy
    // A24) Display.supportedModes only lists the ACTIVE mode, so a 60 Hz mode
    // id can't be found and the system kept 90 Hz. The rate hint is honoured
    // (SurfaceFlinger vsync 16.67 ms). Android drops window display
    // preferences while backgrounded, so re-apply it on every resume. It's a
    // hint: power saving or a forced-peak developer option can override it.
    override fun onResume() {
        super.onResume()
        preferSixtyHz()
    }

    // An incomplete install finished in onCreate with a half-attached
    // delegate: let the platform teardown run, ignore the engine's.
    override fun onDestroy() {
        if (!incompleteInstall) {
            super.onDestroy()
            return
        }
        try {
            super.onDestroy()
        } catch (expected: Throwable) {
        }
    }

    private fun preferSixtyHz() {
        val attrs = window.attributes
        if (attrs.preferredRefreshRate == 60f) return
        attrs.preferredRefreshRate = 60f
        window.attributes = attrs
    }

    // Android 10 (SDK 29) renders with Skia instead of Impeller.
    //
    // SDK 29 is the engine's floor for handing devices to Impeller, so budget
    // phones on it run Impeller's least-exercised OpenGL ES path on the oldest
    // GPU drivers. Snake Classic's Play vitals showed exactly that: SIGSEGVs
    // inside libIMGegl / libGLESv2_mtk / POWERVR drivers plus "GPU
    // unresponsive" ANRs, 100% on Android 10 budget handsets. Cosmo Strike is
    // a much heavier Flame renderer, so its exposure is higher. Devices that
    // can run Vulkan are unaffected (they're on SDK 30+ paths anyway).
    //
    // Shell args rather than manifest meta-data, because the manifest flag
    // would disable Impeller for every device.
    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
            args.add(FlutterShellArgs.ARG_DISABLE_IMPELLER)
        }
        return args
    }

    // NEVER let the launch Intent choose Flutter's initial route.
    //
    // FlutterActivity reads the String extra named "route" as the initial
    // route, and FCM copies every key of a push's data payload onto the
    // launch Intent — Cosmo Strike's pushes carry ["route"] = "home" /
    // "daily_challenge" / … as their deep-link discriminator. A bare word
    // like "home" matches no go_router path, so the router settles on nothing
    // and the app sits on the native splash. Returning null falls back to
    // "/" (go_router's initialLocation); the deep-link target is still read
    // from the FCM message data in NotificationService.
    override fun getInitialRoute(): String? = null

    // Deep link to THIS app's system notification settings
    // (NotificationSettingsOpener in Dart). Once POST_NOTIFICATIONS is
    // permanently denied Android never re-shows the OS prompt, so this page
    // is the only way a player can turn notifications back on.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "cosmo_strike/notification_settings",
        ).setMethodCallHandler { call, result ->
            if (call.method == "open") {
                result.success(openNotificationSettings())
            } else {
                result.notImplemented()
            }
        }
    }

    private fun openNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            // Pre-O has no per-app notification page: use App info instead.
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
        }
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            // Some OEM builds lack the notification page; fall back to App info.
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.fromParts("package", packageName, null)),
                )
                true
            } catch (fallbackError: ActivityNotFoundException) {
                false
            }
        }
    }

    // Create the FCM channel natively on every launch, before any Dart runs.
    // The Dart side (NotificationService) also creates it, but only once Home
    // mounts; until then a fresh install has NO channel and a push targeting
    // "cosmo_strike_notifications" on Android 8+ is dropped or demoted.
    // createNotificationChannel is idempotent (same id = no-op). Name and
    // description must match NotificationService's _channelName /
    // _channelDescription (strings.xml).
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                getString(R.string.default_notification_channel_id),
                getString(R.string.default_notification_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = getString(R.string.default_notification_channel_desc)
                enableVibration(true)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}
