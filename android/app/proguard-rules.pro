# Flutter Background Service — Prevent R8 from stripping the isolate entry point
-keep class id.flutter.flutter_background_service.** { *; }
-keep class id.flutter.flutter_background_service.BackgroundService { *; }

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# SharedPreferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Firebase Firestore (used inside background isolate)
-keep class com.google.firebase.firestore.** { *; }
-keep class io.flutter.plugins.firebase.firestore.** { *; }

# Firebase Core
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.core.** { *; }

# Flutter Local Notifications
-keep class com.dexterous.** { *; }

# Flutter plugin registrant (needed for background isolate plugin init)
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# OTA Update plugin & FileProvider
-keep class sk.fourq.otaupdate.** { *; }
-keep class androidx.core.content.FileProvider { *; }
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Preserve annotations used by Firebase / JSON serialization
-keepattributes *Annotation*
-keepattributes Signature
