package com.example.cosmo_strike_flutter_app

import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity

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
    }
}
