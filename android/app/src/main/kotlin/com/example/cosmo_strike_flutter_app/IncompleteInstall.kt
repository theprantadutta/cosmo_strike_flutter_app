package com.example.cosmo_strike_flutter_app

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import java.util.zip.ZipFile

/**
 * Detects an incomplete install: the engine's native library (libflutter.so,
 * shipped in the per-ABI config split of the App Bundle) is missing, which
 * crashes FlutterActivity at launch (ReLinker's MissingLibraryException).
 * Crashlytics sees it on rooted / sideloaded devices that copied only the
 * base APK of a split install.
 *
 * Google's old fix, Play Core's MissingSplitsManager, is deprecated with no
 * replacement ("the feature is now obsolete — installs with missing splits
 * are now blocked on devices with Play Protect or Android 10+"), and
 * these devices evade exactly that. So: a cheap check of our own.
 *
 * Cost on a normal install: one System.loadLibrary("flutter"), which the
 * engine performs a moment later anyway (a second load is a no-op). Only
 * when that fails are the installed APKs scanned for the library, so an
 * install the engine's own ReLinker could still repair (the .so is inside
 * an installed APK, just not linkable in place) is never flagged.
 */
object IncompleteInstall {
    @Volatile private var checked: Boolean? = null

    /** True when this install cannot run Flutter (cached per process). */
    fun isMissingEngine(context: Context): Boolean {
        checked?.let { return it }
        val missing = try {
            System.loadLibrary("flutter")
            false
        } catch (e: UnsatisfiedLinkError) {
            !engineInAnyApk(context)
        } catch (e: SecurityException) {
            false
        }
        checked = missing
        return missing
    }

    private fun engineInAnyApk(context: Context): Boolean {
        val info = context.applicationInfo
        val apks = buildList {
            info.splitSourceDirs?.let { addAll(it) }
            info.sourceDir?.let { add(it) }
        }
        for (path in apks) {
            try {
                ZipFile(path).use { zip ->
                    val entries = zip.entries()
                    while (entries.hasMoreElements()) {
                        val name = entries.nextElement().name
                        if (name.startsWith("lib/") && name.endsWith("/libflutter.so")) return true
                    }
                }
            } catch (e: Exception) {
                // Unreadable APK: keep looking; if nothing has it, it's missing.
            }
        }
        return false
    }
}

/**
 * Shown instead of the game when [IncompleteInstall] trips: a native dialog
 * asking the player to reinstall from Google Play (Play listing button), so
 * a broken install explains itself instead of crashing at launch. Plain
 * platform Activity + AlertDialog: nothing here touches Flutter.
 */
class IncompleteInstallActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AlertDialog.Builder(this)
            .setTitle(R.string.incomplete_install_title)
            .setMessage(R.string.incomplete_install_message)
            .setCancelable(false)
            .setPositiveButton(R.string.incomplete_install_open_play) { _, _ ->
                openPlayListing()
                finish()
            }
            .setNegativeButton(R.string.incomplete_install_close) { _, _ -> finish() }
            .show()
    }

    private fun openPlayListing() {
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(market)
        } catch (e: ActivityNotFoundException) {
            try {
                startActivity(
                    Intent(
                        Intent.ACTION_VIEW,
                        Uri.parse("https://play.google.com/store/apps/details?id=$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
            } catch (ignored: ActivityNotFoundException) {
            }
        }
    }
}
