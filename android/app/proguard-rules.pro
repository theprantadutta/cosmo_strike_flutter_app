# R8 rules for the release build.
#
# Play Console flagged "Improve your app's memory and performance with R8
# optimization": this file used to keep whole SDK packages with blanket
# "-keep class <pkg>.** { *; }" rules (Firebase, Play services, WorkManager,
# Room, Flutter, billing), which pinned most of the DEX so R8 could not
# inline, merge, rename or drop it. Every one of those SDKs ships its own
# consumer rules inside its AAR, the Flutter engine marks its JNI entry
# points with @Keep, and the Flutter Gradle plugin keeps every FlutterPlugin.
# Only rules with a documented reason remain (same set as Snake Classic).

# Google Play Core (deferred components / split install) — referenced by the
# Flutter embedding but not shipped in this app.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Readable Crashlytics stack traces: keep line numbers and exception names.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# flutter_local_notifications — Gson (de)serializes scheduled notification
# details; R8 full mode strips the generic TypeToken signatures without these
# (the rules from the plugin's README).
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.stream.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Native methods, Parcelables and Serializables.
-keepclassmembers class * {
    native <methods>;
}
-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Play Billing + flutter_inapp_purchase (OpenIAP) ship their own consumer
# rules; only silence optional references.
-dontwarn dev.hyo.**
-dontwarn io.github.hyochan.**
