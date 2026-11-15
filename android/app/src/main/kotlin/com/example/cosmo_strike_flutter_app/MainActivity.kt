package com.example.cosmo_strike_flutter_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterShellArgs

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
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
