# Vendored packages

| Package | Version | License | Why vendored |
|---|---|---|---|
| `pasteboard` | 0.5.0 | Apache-2.0 | Upstream's Android build applies the Kotlin Gradle Plugin unconditionally, which Flutter is deprecating ("Built-in Kotlin"). Patched `android/build.gradle` to apply it only when built-in Kotlin is off, via `project.pluginManager.apply(...)`. Drop this copy once upstream ships the fix. |
| `desktop_drop` | 0.8.4 | Apache-2.0 | Upstream already applies KGP only when needed, but with an `apply plugin:` line that Flutter's text-based detector flags. Patched to call `project.pluginManager.apply(...)` instead. |

`pasteboard` also has `write` (a PNG and / or text as one clipboard entry, for the lasso's copy to other apps: GTK targets in `linux/pasteboard_plugin.cc`, PNG + DIB + text in `windows/pasteboard_plugin.cpp`, a `ClipData` with a `PasteboardFileProvider` URI on Android — declared in the plugin's manifest with `res/xml/pasteboard_paths.xml` —, a `ClipboardItem` on the web), and reads HTML on Linux (`html` in `linux/pasteboard_plugin.cc`, decoded in `lib/src/pasteboard_platform_io.dart`; upstream only supports Windows, Android and the web) for rich paste into text boxes.

Otherwise only `android/build.gradle` differs from upstream (and `example/`, `test/` were removed). Upstream's Android `writeImage` still expects an app-declared `${packageName}.provider`, which Len has not: use `write`.
