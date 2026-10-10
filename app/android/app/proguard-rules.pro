# R8 rules for Len's release build (Flutter adds its own engine rules).
# Plugins reached from Dart through JNI (package:jni / jnigen, used by
# path_provider_android) look classes up by name at runtime; their packages
# ship consumer rules, repeated here defensively.
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
