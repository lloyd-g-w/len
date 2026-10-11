# R8 rules for Len's release build (Flutter adds its own engine rules).
# Plugins reached from Dart through JNI (package:jni / jnigen, used by
# path_provider_android) look classes up by name at runtime; their packages
# ship consumer rules, repeated here defensively.
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }

# WorkManager (pulled in by ML Kit's model downloader) instantiates its Room
# database implementation reflectively (`WorkDatabase_Impl`); without these
# rules R8 strips/renames it and the app crashes at startup in
# androidx.startup.InitializationProvider.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-dontwarn androidx.room.paging.**
