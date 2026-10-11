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

# ML Kit (handwriting recognition). Its startup provider discovers component
# registrars by class name and instantiates them reflectively; R8 otherwise
# strips their no-arg constructors (NoSuchMethodException → the plugin fails
# to register → MissingPluginException in Dart). Partial keeps of only some
# ML Kit packages are worse: kept classes then reference renamed internals
# ("Unsatisfied dependency" crash at startup). So keep ML Kit whole, plus the
# Flutter plugin bridge, which R8 cannot see is reached from Dart.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.firebase.components.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_digital_ink_recognition.** { *; }
-dontwarn com.google.mlkit.**
