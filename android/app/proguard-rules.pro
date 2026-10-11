# ---------------------------------------------------------------------------
# R8 / ProGuard keep rules for the release build.
#
# Release builds run R8 with obfuscation. Several libraries load classes by
# reflection (Class.forName) and break when their names are renamed/stripped.
# Without these rules the app crashes on launch with:
#   "Failed to create an instance of androidx.work.impl.WorkDatabase"
# (WorkManager is pulled in transitively via androidx.startup auto-init).
# ---------------------------------------------------------------------------

# --- WorkManager + androidx.startup auto-initialization ---------------------
-keep class androidx.startup.** { *; }
-keep class * implements androidx.startup.Initializer { *; }
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker {
    public <init>(...);
}

# --- Room ------------------------------------------------------------------
# Room instantiates the generated *_Impl database class via reflection, so its
# name must not be obfuscated/stripped (this is the WorkDatabase crash).
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.room.** { *; }
-keep class **_Impl { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    public static ** getInstance(...);
}
-dontwarn androidx.room.paging.**

# --- SQLite (used by Room / WorkManager and by Drift's native bindings) -----
-keep class androidx.sqlite.** { *; }

# --- Flutter / embedding (reflection-loaded) -------------------------------
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# --- Firebase / Google Play services ---------------------------------------
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# --- Play Core (in_app_update / deferred components) -----------------------
-keep class com.google.android.play.** { *; }
-dontwarn com.google.android.play.**

# Keep annotations and generic signatures used by reflection-based libs.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# OpenIAP billing stack (flutter_inapp_purchase). Billing classes are reached
# reflectively across the plugin boundary and the plugin ships no consumer
# rules, so R8 strips them in minified release builds — purchases then fail
# only in release, never in debug.
-keep class dev.hyo.** { *; }
-keep class io.github.hyochan.** { *; }
-keep class com.android.vending.billing.**
-keep class com.android.billingclient.** { *; }
-dontwarn dev.hyo.**
-dontwarn io.github.hyochan.**
